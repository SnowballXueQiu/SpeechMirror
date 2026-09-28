use std::collections::HashSet;

use axum::{
    Extension, Json, Router,
    body::Bytes,
    extract::{Multipart, Query, State},
    http::{HeaderMap, HeaderValue, StatusCode, header},
    response::{IntoResponse, Response},
    routing::get,
};
use chrono::{Duration, NaiveDate, Utc};
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, EntityTrait, QueryFilter, QueryOrder,
};
use serde_json::{Value, json};

use crate::{
    AppState,
    auth::CurrentUser,
    entities::{user, user_activity_day, user_profile},
    error::{ApiError, ApiResult},
    models::{
        ActivityDayResponse, ActivityQuery, ActivitySummaryResponse, RecordActivityRequest,
        UpdateUserProfileRequest, UserProfileResponse,
    },
};

const IDENTITIES: &[&str] = &[
    "本科生",
    "硕士研究生",
    "博士研究生",
    "高职学生",
    "教师或指导老师",
    "创业团队成员",
    "职场人士",
    "其他",
];
const SCENARIOS: &[&str] = &[
    "毕业答辩",
    "课程答辩",
    "创新创业大赛",
    "学科竞赛",
    "项目路演",
    "技术面试",
    "其他",
];
const PURPOSES: &[&str] = &[
    "提升表达",
    "熟悉项目",
    "准备评委提问",
    "发现材料漏洞",
    "控制答辩时间",
    "复盘长期进步",
    "其他",
];

pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/me", get(get_profile).put(update_profile))
        .route(
            "/me/avatar",
            get(get_avatar).post(upload_avatar).delete(delete_avatar),
        )
        .route("/me/activity", get(get_activity).post(record_activity))
}

async fn get_profile(
    State(state): State<AppState>,
    Extension(current): Extension<CurrentUser>,
) -> ApiResult<Json<UserProfileResponse>> {
    Ok(Json(load_profile(&state, &current.id).await?))
}

async fn update_profile(
    State(state): State<AppState>,
    Extension(current): Extension<CurrentUser>,
    Json(body): Json<UpdateUserProfileRequest>,
) -> ApiResult<Json<UserProfileResponse>> {
    let bio = normalize_optional(body.bio, 200, "bio")?;
    let identity = normalize_choice(body.identity, IDENTITIES, "identity")?;
    let identity_other = normalize_other(body.identity_other, identity.as_deref(), "identity")?;
    let legacy_scenario = normalize_choice(body.scenario, SCENARIOS, "scenario")?;
    let scenario_values = if body.scenarios.is_empty() {
        legacy_scenario.into_iter().collect()
    } else {
        body.scenarios
    };
    let scenarios = normalize_choices(scenario_values, SCENARIOS, "scenario")?;
    let scenario_other = normalize_other(
        body.scenario_other,
        scenarios
            .iter()
            .any(|item| item == "其他")
            .then_some("其他"),
        "scenario",
    )?;
    let scenario = scenarios.first().cloned();
    if body.purposes.len() > 7 {
        return Err(ApiError::BadRequest(
            "no more than 7 purposes may be selected".into(),
        ));
    }
    let mut purposes = Vec::new();
    for purpose in body.purposes {
        let purpose = purpose.trim();
        if !PURPOSES.contains(&purpose) {
            return Err(ApiError::BadRequest("unknown purpose option".into()));
        }
        if !purposes.iter().any(|item| item == purpose) {
            purposes.push(purpose.to_owned());
        }
    }
    let purpose_other = normalize_other(
        body.purpose_other,
        purposes.iter().any(|item| item == "其他").then_some("其他"),
        "purpose",
    )?;
    let now = Utc::now();
    let purposes_json = json!(purposes);
    if let Some(model) = user_profile::Entity::find_by_id(&current.id)
        .one(&state.db)
        .await?
    {
        let mut active: user_profile::ActiveModel = model.into();
        active.bio = Set(bio);
        active.identity = Set(identity);
        active.identity_other = Set(identity_other);
        active.scenario = Set(scenario);
        active.scenarios_json = Set(json!(scenarios));
        active.scenario_other = Set(scenario_other);
        active.purposes_json = Set(purposes_json);
        active.purpose_other = Set(purpose_other);
        active.onboarding_completed = Set(body.onboarding_completed);
        active.research_consent = Set(body.research_consent);
        active.updated_at = Set(now);
        active.update(&state.db).await?;
    } else {
        user_profile::ActiveModel {
            user_id: Set(current.id.clone()),
            bio: Set(bio),
            identity: Set(identity),
            identity_other: Set(identity_other),
            scenario: Set(scenario),
            scenarios_json: Set(json!(scenarios)),
            scenario_other: Set(scenario_other),
            purposes_json: Set(purposes_json),
            purpose_other: Set(purpose_other),
            onboarding_completed: Set(body.onboarding_completed),
            research_consent: Set(body.research_consent),
            avatar_bytes: Set(None),
            avatar_media_type: Set(None),
            updated_at: Set(now),
        }
        .insert(&state.db)
        .await?;
    }
    Ok(Json(load_profile(&state, &current.id).await?))
}

async fn upload_avatar(
    State(state): State<AppState>,
    Extension(current): Extension<CurrentUser>,
    mut multipart: Multipart,
) -> ApiResult<Json<Value>> {
    let field = multipart
        .next_field()
        .await
        .map_err(|error| ApiError::BadRequest(error.to_string()))?
        .ok_or_else(|| ApiError::BadRequest("avatar file is required".into()))?;
    let declared_type = field.content_type().unwrap_or_default().to_owned();
    let bytes = field
        .bytes()
        .await
        .map_err(|error| ApiError::BadRequest(error.to_string()))?;
    if bytes.is_empty() || bytes.len() > 2 * 1024 * 1024 {
        return Err(ApiError::BadRequest(
            "avatar must contain 1 byte to 2 MiB".into(),
        ));
    }
    let media_type = detect_avatar_type(&bytes)
        .ok_or_else(|| ApiError::BadRequest("avatar must be a PNG or JPEG image".into()))?;
    if !declared_type.is_empty() && declared_type != media_type {
        return Err(ApiError::BadRequest(
            "avatar media type does not match its content".into(),
        ));
    }
    let now = Utc::now();
    if let Some(model) = user_profile::Entity::find_by_id(&current.id)
        .one(&state.db)
        .await?
    {
        let mut active: user_profile::ActiveModel = model.into();
        active.avatar_bytes = Set(Some(bytes.to_vec()));
        active.avatar_media_type = Set(Some(media_type.into()));
        active.updated_at = Set(now);
        active.update(&state.db).await?;
    } else {
        user_profile::ActiveModel {
            user_id: Set(current.id),
            bio: Set(None),
            identity: Set(None),
            identity_other: Set(None),
            scenario: Set(None),
            scenarios_json: Set(json!([])),
            scenario_other: Set(None),
            purposes_json: Set(json!([])),
            purpose_other: Set(None),
            onboarding_completed: Set(false),
            research_consent: Set(false),
            avatar_bytes: Set(Some(bytes.to_vec())),
            avatar_media_type: Set(Some(media_type.into())),
            updated_at: Set(now),
        }
        .insert(&state.db)
        .await?;
    }
    Ok(Json(json!({"ok": true})))
}

async fn get_avatar(
    State(state): State<AppState>,
    Extension(current): Extension<CurrentUser>,
) -> ApiResult<Response> {
    let profile = user_profile::Entity::find_by_id(current.id)
        .one(&state.db)
        .await?
        .ok_or(ApiError::NotFound)?;
    let bytes = profile.avatar_bytes.ok_or(ApiError::NotFound)?;
    let media_type = profile.avatar_media_type.ok_or(ApiError::NotFound)?;
    let mut headers = HeaderMap::new();
    headers.insert(
        header::CONTENT_TYPE,
        HeaderValue::from_str(&media_type)
            .map_err(|error| ApiError::Internal(error.to_string()))?,
    );
    headers.insert(
        header::CACHE_CONTROL,
        HeaderValue::from_static("private, max-age=300"),
    );
    Ok((StatusCode::OK, headers, Bytes::from(bytes)).into_response())
}

async fn delete_avatar(
    State(state): State<AppState>,
    Extension(current): Extension<CurrentUser>,
) -> ApiResult<Json<Value>> {
    if let Some(model) = user_profile::Entity::find_by_id(current.id)
        .one(&state.db)
        .await?
    {
        let mut active: user_profile::ActiveModel = model.into();
        active.avatar_bytes = Set(None);
        active.avatar_media_type = Set(None);
        active.updated_at = Set(Utc::now());
        active.update(&state.db).await?;
    }
    Ok(Json(json!({"ok": true})))
}

async fn record_activity(
    State(state): State<AppState>,
    Extension(current): Extension<CurrentUser>,
    Json(body): Json<RecordActivityRequest>,
) -> ApiResult<Json<Value>> {
    let date = validate_local_date(&body.local_date)?;
    increment_activity(&state, &current.id, &date, 1, 0).await?;
    Ok(Json(json!({"ok": true})))
}

async fn get_activity(
    State(state): State<AppState>,
    Extension(current): Extension<CurrentUser>,
    Query(query): Query<ActivityQuery>,
) -> ApiResult<Json<ActivitySummaryResponse>> {
    let through = query
        .through
        .as_deref()
        .map(validate_local_date)
        .transpose()?
        .unwrap_or_else(|| Utc::now().date_naive());
    let start = through - Duration::days(364);
    let rows = user_activity_day::Entity::find()
        .filter(user_activity_day::Column::UserId.eq(&current.id))
        .filter(user_activity_day::Column::ActivityDate.gte(start.format("%Y-%m-%d").to_string()))
        .filter(user_activity_day::Column::ActivityDate.lte(through.format("%Y-%m-%d").to_string()))
        .order_by_asc(user_activity_day::Column::ActivityDate)
        .all(&state.db)
        .await?;
    let active_dates = rows
        .iter()
        .filter(|row| row.use_count > 0 || row.practice_count > 0)
        .map(|row| row.activity_date.as_str())
        .collect::<HashSet<_>>();
    let mut current_streak = 0;
    for offset in 0..365 {
        let date = through - Duration::days(offset);
        let date = date.format("%Y-%m-%d").to_string();
        if active_dates.contains(date.as_str()) {
            current_streak += 1;
        } else {
            break;
        }
    }
    let mut longest_streak = 0;
    let mut running_streak = 0;
    for offset in 0..365 {
        let date = start + Duration::days(offset);
        let date = date.format("%Y-%m-%d").to_string();
        if active_dates.contains(date.as_str()) {
            running_streak += 1;
            longest_streak = longest_streak.max(running_streak);
        } else {
            running_streak = 0;
        }
    }
    Ok(Json(ActivitySummaryResponse {
        through: through.format("%Y-%m-%d").to_string(),
        active_days: active_dates.len(),
        total_uses: rows.iter().map(|row| row.use_count).sum(),
        total_practices: rows.iter().map(|row| row.practice_count).sum(),
        current_streak,
        longest_streak,
        days: rows
            .into_iter()
            .map(|row| ActivityDayResponse {
                date: row.activity_date,
                use_count: row.use_count,
                practice_count: row.practice_count,
            })
            .collect(),
    }))
}

pub async fn increment_activity(
    state: &AppState,
    user_id: &str,
    date: &NaiveDate,
    use_delta: i32,
    practice_delta: i32,
) -> Result<(), sea_orm::DbErr> {
    let date = date.format("%Y-%m-%d").to_string();
    if let Some(model) = user_activity_day::Entity::find_by_id((user_id.to_owned(), date.clone()))
        .one(&state.db)
        .await?
    {
        let use_count = model.use_count;
        let practice_count = model.practice_count;
        let mut active: user_activity_day::ActiveModel = model.into();
        active.use_count = Set(use_count.saturating_add(use_delta));
        active.practice_count = Set(practice_count.saturating_add(practice_delta));
        active.updated_at = Set(Utc::now());
        active.update(&state.db).await?;
    } else {
        user_activity_day::ActiveModel {
            user_id: Set(user_id.to_owned()),
            activity_date: Set(date),
            use_count: Set(use_delta),
            practice_count: Set(practice_delta),
            updated_at: Set(Utc::now()),
        }
        .insert(&state.db)
        .await?;
    }
    Ok(())
}

pub fn validate_local_date(value: &str) -> ApiResult<NaiveDate> {
    let date = NaiveDate::parse_from_str(value, "%Y-%m-%d")
        .map_err(|_| ApiError::BadRequest("local_date must use YYYY-MM-DD".into()))?;
    let today = Utc::now().date_naive();
    if date < today - Duration::days(1) || date > today + Duration::days(1) {
        return Err(ApiError::BadRequest(
            "local_date must be the device's current date".into(),
        ));
    }
    Ok(date)
}

async fn load_profile(state: &AppState, user_id: &str) -> ApiResult<UserProfileResponse> {
    let account = user::Entity::find_by_id(user_id)
        .one(&state.db)
        .await?
        .ok_or(ApiError::Unauthorized)?;
    let profile = user_profile::Entity::find_by_id(user_id)
        .one(&state.db)
        .await?;
    let purposes = profile
        .as_ref()
        .and_then(|item| serde_json::from_value::<Vec<String>>(item.purposes_json.clone()).ok())
        .unwrap_or_default();
    let scenarios = profile
        .as_ref()
        .and_then(|item| serde_json::from_value::<Vec<String>>(item.scenarios_json.clone()).ok())
        .filter(|items| !items.is_empty())
        .or_else(|| {
            profile
                .as_ref()
                .and_then(|item| item.scenario.clone())
                .map(|item| vec![item])
        })
        .unwrap_or_default();
    Ok(UserProfileResponse {
        id: account.id,
        username: account.username,
        bio: profile.as_ref().and_then(|item| item.bio.clone()),
        identity: profile.as_ref().and_then(|item| item.identity.clone()),
        identity_other: profile
            .as_ref()
            .and_then(|item| item.identity_other.clone()),
        scenario: profile.as_ref().and_then(|item| item.scenario.clone()),
        scenarios,
        scenario_other: profile
            .as_ref()
            .and_then(|item| item.scenario_other.clone()),
        purposes,
        purpose_other: profile.as_ref().and_then(|item| item.purpose_other.clone()),
        onboarding_completed: profile
            .as_ref()
            .is_some_and(|item| item.onboarding_completed),
        research_consent: profile.as_ref().is_some_and(|item| item.research_consent),
        has_avatar: profile
            .as_ref()
            .is_some_and(|item| item.avatar_bytes.is_some()),
        created_at: account.created_at,
        updated_at: profile
            .map(|item| item.updated_at)
            .unwrap_or(account.created_at),
    })
}

fn normalize_optional(value: Option<String>, max: usize, field: &str) -> ApiResult<Option<String>> {
    let Some(value) = value else {
        return Ok(None);
    };
    let value = value.trim();
    if value.is_empty() {
        return Ok(None);
    }
    if value.chars().count() > max {
        return Err(ApiError::BadRequest(format!(
            "{field} must contain no more than {max} characters"
        )));
    }
    Ok(Some(value.to_owned()))
}

fn normalize_choice(
    value: Option<String>,
    options: &[&str],
    field: &str,
) -> ApiResult<Option<String>> {
    let value = normalize_optional(value, 30, field)?;
    if let Some(value) = &value
        && !options.contains(&value.as_str())
    {
        return Err(ApiError::BadRequest(format!("unknown {field} option")));
    }
    Ok(value)
}

fn normalize_choices(values: Vec<String>, options: &[&str], field: &str) -> ApiResult<Vec<String>> {
    if values.len() > options.len() {
        return Err(ApiError::BadRequest(format!(
            "too many {field} options were selected"
        )));
    }
    let mut normalized = Vec::new();
    for value in values {
        let value = value.trim();
        if !options.contains(&value) {
            return Err(ApiError::BadRequest(format!("unknown {field} option")));
        }
        if !normalized.iter().any(|item| item == value) {
            normalized.push(value.to_owned());
        }
    }
    Ok(normalized)
}

fn normalize_other(
    value: Option<String>,
    selected: Option<&str>,
    field: &str,
) -> ApiResult<Option<String>> {
    if selected != Some("其他") {
        return Ok(None);
    }
    normalize_optional(value, 50, &format!("{field}_other"))
}

fn detect_avatar_type(bytes: &[u8]) -> Option<&'static str> {
    if bytes.starts_with(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]) {
        Some("image/png")
    } else if bytes.starts_with(&[0xFF, 0xD8, 0xFF]) {
        Some("image/jpeg")
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_supported_avatar_images() {
        assert_eq!(
            detect_avatar_type(&[0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A]),
            Some("image/png")
        );
        assert_eq!(
            detect_avatar_type(&[0xFF, 0xD8, 0xFF, 0xE0]),
            Some("image/jpeg")
        );
        assert_eq!(detect_avatar_type(b"not an image"), None);
    }
}
