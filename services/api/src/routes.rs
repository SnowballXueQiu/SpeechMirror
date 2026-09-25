use std::{io::Cursor, path::PathBuf};

use axum::{
    Extension, Json, Router,
    extract::{DefaultBodyLimit, Multipart, Path, State},
    middleware,
    routing::{get, post, put},
};
use chrono::Utc;
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, EntityTrait, ModelTrait, QueryFilter,
    QueryOrder, sea_query::Expr,
};
use serde_json::{Value, json};
use uuid::Uuid;

use crate::{
    AppState,
    analysis::{refresh_report_qa, reindex_document_text, retrieve_chunks, verified_evidence},
    auth::{
        CurrentUser, hash_password, hash_token, issue_tokens, require_auth, validate_credentials,
        verify_password,
    },
    entities::{
        analysis_job, document, jury_answer, jury_question, project, refresh_token,
        rehearsal_session, report, session_metric, user,
    },
    error::{ApiError, ApiResult},
    models::*,
    workers::{
        enqueue_document_ingestion, enqueue_report_generation, enqueue_session_asr, wait_for_job,
    },
};

pub fn api_router(state: AppState) -> Router {
    let public = Router::new()
        .route("/health", get(health))
        .route("/auth/register", post(register))
        .route("/auth/login", post(login))
        .route("/auth/refresh", post(refresh));
    let protected = Router::new()
        .route("/auth/logout", post(logout))
        .route("/projects", get(list_projects).post(create_project))
        .route(
            "/projects/{project_id}",
            get(get_project).put(update_project).delete(delete_project),
        )
        .route(
            "/projects/{project_id}/documents",
            get(list_documents).post(upload_document),
        )
        .route("/documents/{document_id}", get(get_document))
        .route("/documents/{document_id}/text", put(correct_document_text))
        .route(
            "/projects/{project_id}/sessions",
            get(list_sessions).post(create_session),
        )
        .route("/sessions/{session_id}", get(get_session))
        .route("/sessions/{session_id}/metrics", post(upload_metrics))
        .route("/sessions/{session_id}/audio", post(upload_audio))
        .route(
            "/sessions/{session_id}/answer-audio",
            post(upload_answer_audio),
        )
        .route("/sessions/{session_id}/complete", post(complete_session))
        .route("/sessions/{session_id}/analyze", post(analyze_session))
        .route("/sessions/{session_id}/report", get(get_report))
        .route(
            "/projects/{project_id}/questions",
            get(list_questions).post(generate_questions),
        )
        .route("/questions/{question_id}/answers", post(submit_answer))
        .route("/projects/{project_id}/trends", get(get_trends))
        .route_layer(middleware::from_fn_with_state(state.clone(), require_auth));
    public
        .merge(protected)
        .layer(DefaultBodyLimit::max(60 * 1024 * 1024))
        .with_state(state)
}

async fn health(State(state): State<AppState>) -> Json<HealthResponse> {
    Json(HealthResponse {
        status: "ok",
        ai_configured: state.ai.is_configured(),
    })
}

async fn register(
    State(state): State<AppState>,
    Json(body): Json<RegisterRequest>,
) -> ApiResult<Json<TokenPair>> {
    validate_credentials(&body.username, &body.password)?;
    if user::Entity::find()
        .filter(user::Column::Username.eq(&body.username))
        .one(&state.db)
        .await?
        .is_some()
    {
        return Err(ApiError::Conflict("username already exists".into()));
    }
    let id = Uuid::new_v4().to_string();
    user::ActiveModel {
        id: Set(id.clone()),
        username: Set(body.username),
        password_hash: Set(hash_password(&body.password)?),
        created_at: Set(Utc::now()),
    }
    .insert(&state.db)
    .await?;
    Ok(Json(issue_tokens(&state, &id).await?))
}

async fn login(
    State(state): State<AppState>,
    Json(body): Json<LoginRequest>,
) -> ApiResult<Json<TokenPair>> {
    let model = user::Entity::find()
        .filter(user::Column::Username.eq(&body.username))
        .one(&state.db)
        .await?
        .ok_or(ApiError::Unauthorized)?;
    if !verify_password(&body.password, &model.password_hash) {
        return Err(ApiError::Unauthorized);
    }
    Ok(Json(issue_tokens(&state, &model.id).await?))
}

async fn refresh(
    State(state): State<AppState>,
    Json(body): Json<RefreshRequest>,
) -> ApiResult<Json<TokenPair>> {
    let token_hash = hash_token(&body.refresh_token);
    let model = refresh_token::Entity::find()
        .filter(refresh_token::Column::TokenHash.eq(token_hash))
        .one(&state.db)
        .await?
        .ok_or(ApiError::Unauthorized)?;
    if model.revoked || model.expires_at <= Utc::now() {
        return Err(ApiError::Unauthorized);
    }
    let user_id = model.user_id.clone();
    let result = refresh_token::Entity::update_many()
        .col_expr(refresh_token::Column::Revoked, Expr::value(true))
        .filter(refresh_token::Column::Id.eq(model.id))
        .filter(refresh_token::Column::Revoked.eq(false))
        .filter(refresh_token::Column::ExpiresAt.gt(Utc::now()))
        .exec(&state.db)
        .await?;
    if result.rows_affected != 1 {
        return Err(ApiError::Unauthorized);
    }
    Ok(Json(issue_tokens(&state, &user_id).await?))
}

async fn logout(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Json(body): Json<LogoutRequest>,
) -> ApiResult<Json<Value>> {
    if let Some(model) = refresh_token::Entity::find()
        .filter(refresh_token::Column::TokenHash.eq(hash_token(&body.refresh_token)))
        .filter(refresh_token::Column::UserId.eq(user.id))
        .one(&state.db)
        .await?
    {
        let mut active: refresh_token::ActiveModel = model.into();
        active.revoked = Set(true);
        active.update(&state.db).await?;
    }
    Ok(Json(json!({"ok": true})))
}

async fn create_project(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Json(body): Json<CreateProjectRequest>,
) -> ApiResult<Json<ProjectResponse>> {
    let name = body.name.trim();
    if name.is_empty() || name.chars().count() > 80 {
        return Err(ApiError::BadRequest(
            "project name must contain 1-80 characters".into(),
        ));
    }
    if !(60..=1800).contains(&body.defense_duration_seconds) {
        return Err(ApiError::BadRequest(
            "defense duration must be 60-1800 seconds".into(),
        ));
    }
    let description = match body.description {
        Some(description) => normalize_project_description(description)?,
        None => None,
    };
    let now = Utc::now();
    let model = project::ActiveModel {
        id: Set(Uuid::new_v4().to_string()),
        user_id: Set(user.id),
        name: Set(name.into()),
        description: Set(description),
        defense_duration_seconds: Set(body.defense_duration_seconds),
        created_at: Set(now),
        updated_at: Set(now),
    }
    .insert(&state.db)
    .await?;
    Ok(Json(project_response(model)))
}

async fn list_projects(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
) -> ApiResult<Json<Vec<ProjectResponse>>> {
    let models = project::Entity::find()
        .filter(project::Column::UserId.eq(user.id))
        .order_by_desc(project::Column::UpdatedAt)
        .all(&state.db)
        .await?;
    Ok(Json(models.into_iter().map(project_response).collect()))
}

async fn get_project(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(project_id): Path<String>,
) -> ApiResult<Json<ProjectResponse>> {
    Ok(Json(project_response(
        owned_project(&state, &user.id, &project_id).await?,
    )))
}

async fn update_project(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(project_id): Path<String>,
    Json(body): Json<UpdateProjectRequest>,
) -> ApiResult<Json<ProjectResponse>> {
    let model = owned_project(&state, &user.id, &project_id).await?;
    let mut active: project::ActiveModel = model.into();
    if let Some(name) = body.name {
        let name = name.trim();
        if name.is_empty() || name.chars().count() > 80 {
            return Err(ApiError::BadRequest(
                "project name must contain 1-80 characters".into(),
            ));
        }
        active.name = Set(name.to_owned());
    }
    if let Some(seconds) = body.defense_duration_seconds {
        if !(60..=1800).contains(&seconds) {
            return Err(ApiError::BadRequest(
                "defense duration must be 60-1800 seconds".into(),
            ));
        }
        active.defense_duration_seconds = Set(seconds);
    }
    if let Some(description) = body.description {
        active.description = Set(normalize_project_description(description)?);
    }
    active.updated_at = Set(Utc::now());
    Ok(Json(project_response(active.update(&state.db).await?)))
}

async fn delete_project(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(project_id): Path<String>,
) -> ApiResult<Json<Value>> {
    let model = owned_project(&state, &user.id, &project_id).await?;
    let documents = document::Entity::find()
        .filter(document::Column::ProjectId.eq(&project_id))
        .all(&state.db)
        .await?;
    let sessions = rehearsal_session::Entity::find()
        .filter(rehearsal_session::Column::ProjectId.eq(&project_id))
        .all(&state.db)
        .await?;
    let resource_ids = documents
        .iter()
        .map(|document| document.id.clone())
        .chain(sessions.iter().map(|session| session.id.clone()))
        .collect::<Vec<_>>();
    let jobs = if resource_ids.is_empty() {
        Vec::new()
    } else {
        analysis_job::Entity::find()
            .filter(analysis_job::Column::ResourceId.is_in(resource_ids))
            .all(&state.db)
            .await?
    };
    if !jobs.is_empty() {
        analysis_job::Entity::delete_many()
            .filter(analysis_job::Column::Id.is_in(jobs.iter().map(|job| job.id.clone())))
            .exec(&state.db)
            .await?;
    }
    model.delete(&state.db).await?;
    for document in documents {
        let _ = tokio::fs::remove_file(document.storage_path).await;
    }
    for job in jobs {
        let _ = tokio::fs::remove_file(
            state
                .config
                .storage_dir
                .join("tmp")
                .join(format!("asr-{}.m4a", job.id)),
        )
        .await;
    }
    Ok(Json(json!({"ok": true})))
}

fn normalize_project_description(description: String) -> ApiResult<Option<String>> {
    let description = description.trim();
    if description.chars().count() > 500 {
        return Err(ApiError::BadRequest(
            "project description must contain at most 500 characters".into(),
        ));
    }
    Ok((!description.is_empty()).then(|| description.to_owned()))
}

async fn upload_document(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(project_id): Path<String>,
    mut multipart: Multipart,
) -> ApiResult<Json<DocumentResponse>> {
    owned_project(&state, &user.id, &project_id).await?;
    let mut upload: Option<(String, String, bytes::Bytes)> = None;
    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|error| ApiError::BadRequest(error.to_string()))?
    {
        if field.name() == Some("file") {
            let filename = safe_filename(field.file_name().unwrap_or("document"));
            let media_type = field
                .content_type()
                .unwrap_or("application/octet-stream")
                .to_owned();
            let data = field
                .bytes()
                .await
                .map_err(|error| ApiError::BadRequest(error.to_string()))?;
            upload = Some((filename, media_type, data));
            break;
        }
    }
    let (filename, declared_media_type, data) =
        upload.ok_or_else(|| ApiError::BadRequest("multipart field 'file' is required".into()))?;
    let media_type = validate_document_upload(&filename, &declared_media_type, &data)?.to_owned();
    let id = Uuid::new_v4().to_string();
    let directory = state
        .config
        .storage_dir
        .join("documents")
        .join(&user.id)
        .join(&project_id);
    tokio::fs::create_dir_all(&directory).await?;
    let path = directory.join(format!("{id}-{filename}"));
    tokio::fs::write(&path, data).await?;
    let model = match (document::ActiveModel {
        id: Set(id.clone()),
        project_id: Set(project_id),
        filename: Set(filename),
        media_type: Set(media_type),
        storage_path: Set(path.to_string_lossy().into_owned()),
        status: Set("processing".into()),
        extracted_text: Set(None),
        error: Set(None),
        created_at: Set(Utc::now()),
    })
    .insert(&state.db)
    .await
    {
        Ok(model) => model,
        Err(error) => {
            let _ = tokio::fs::remove_file(&path).await;
            return Err(error.into());
        }
    };
    if let Err(error) = enqueue_document_ingestion(&state, &id).await {
        let _ = document::Entity::delete_by_id(&id).exec(&state.db).await;
        let _ = tokio::fs::remove_file(&path).await;
        return Err(error);
    }
    Ok(Json(document_response(model)))
}

async fn list_documents(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(project_id): Path<String>,
) -> ApiResult<Json<Vec<DocumentResponse>>> {
    owned_project(&state, &user.id, &project_id).await?;
    let models = document::Entity::find()
        .filter(document::Column::ProjectId.eq(project_id))
        .order_by_desc(document::Column::CreatedAt)
        .all(&state.db)
        .await?;
    Ok(Json(models.into_iter().map(document_response).collect()))
}

async fn get_document(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(document_id): Path<String>,
) -> ApiResult<Json<DocumentResponse>> {
    let model = document::Entity::find_by_id(document_id)
        .one(&state.db)
        .await?
        .ok_or(ApiError::NotFound)?;
    owned_project(&state, &user.id, &model.project_id).await?;
    Ok(Json(document_response(model)))
}

async fn correct_document_text(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(document_id): Path<String>,
    Json(body): Json<CorrectDocumentRequest>,
) -> ApiResult<Json<DocumentResponse>> {
    let model = document::Entity::find_by_id(&document_id)
        .one(&state.db)
        .await?
        .ok_or(ApiError::NotFound)?;
    owned_project(&state, &user.id, &model.project_id).await?;
    if body.text.trim().is_empty() {
        return Err(ApiError::BadRequest(
            "corrected text cannot be empty".into(),
        ));
    }
    reindex_document_text(&state, &document_id, body.text).await?;
    let updated = document::Entity::find_by_id(document_id)
        .one(&state.db)
        .await?
        .ok_or(ApiError::NotFound)?;
    Ok(Json(document_response(updated)))
}

async fn create_session(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(project_id): Path<String>,
    Json(body): Json<CreateSessionRequest>,
) -> ApiResult<Json<SessionResponse>> {
    let project = owned_project(&state, &user.id, &project_id).await?;
    let target = body
        .target_seconds
        .unwrap_or(project.defense_duration_seconds);
    if !(30..=1800).contains(&target) {
        return Err(ApiError::BadRequest(
            "target duration must be 30-1800 seconds".into(),
        ));
    }
    let model = rehearsal_session::ActiveModel {
        id: Set(Uuid::new_v4().to_string()),
        project_id: Set(project_id),
        user_id: Set(user.id),
        title: Set(body
            .title
            .unwrap_or_else(|| format!("第{}次训练", Utc::now().format("%m%d-%H%M")))),
        status: Set("recording".into()),
        target_seconds: Set(target),
        actual_seconds: Set(None),
        transcript: Set(None),
        local_video_ref: Set(body.local_video_ref),
        created_at: Set(Utc::now()),
        completed_at: Set(None),
    }
    .insert(&state.db)
    .await?;
    Ok(Json(session_response(model)))
}

async fn list_sessions(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(project_id): Path<String>,
) -> ApiResult<Json<Vec<SessionResponse>>> {
    owned_project(&state, &user.id, &project_id).await?;
    let models = rehearsal_session::Entity::find()
        .filter(rehearsal_session::Column::ProjectId.eq(project_id))
        .order_by_desc(rehearsal_session::Column::CreatedAt)
        .all(&state.db)
        .await?;
    Ok(Json(models.into_iter().map(session_response).collect()))
}

async fn get_session(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(session_id): Path<String>,
) -> ApiResult<Json<SessionResponse>> {
    Ok(Json(session_response(
        owned_session(&state, &user.id, &session_id).await?,
    )))
}

async fn upload_metrics(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(session_id): Path<String>,
    Json(body): Json<MetricsRequest>,
) -> ApiResult<Json<Value>> {
    owned_session(&state, &user.id, &session_id).await?;
    if body.samples.len() > 20_000 {
        return Err(ApiError::BadRequest("too many metric samples".into()));
    }
    for sample in body.samples {
        for value in [
            sample.gaze_centered,
            sample.posture_score,
            sample.audio_level,
        ] {
            if !(0.0..=1.0).contains(&value) {
                return Err(ApiError::BadRequest(
                    "metric values must be in the 0-1 range".into(),
                ));
            }
        }
        session_metric::ActiveModel {
            id: Set(Uuid::new_v4().to_string()),
            session_id: Set(session_id.clone()),
            timestamp_ms: Set(sample.timestamp_ms),
            face_detected: Set(sample.face_detected),
            gaze_centered: Set(sample.gaze_centered),
            posture_score: Set(sample.posture_score),
            audio_level: Set(sample.audio_level),
        }
        .insert(&state.db)
        .await?;
    }
    Ok(Json(json!({"ok": true})))
}

async fn upload_audio(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(session_id): Path<String>,
    multipart: Multipart,
) -> ApiResult<Json<Value>> {
    transcribe_uploaded_audio(state, user, session_id, multipart, false).await
}

async fn upload_answer_audio(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(session_id): Path<String>,
    multipart: Multipart,
) -> ApiResult<Json<Value>> {
    transcribe_uploaded_audio(state, user, session_id, multipart, true).await
}

async fn transcribe_uploaded_audio(
    state: AppState,
    user: CurrentUser,
    session_id: String,
    mut multipart: Multipart,
    answer_only: bool,
) -> ApiResult<Json<Value>> {
    owned_session(&state, &user.id, &session_id).await?;
    if !state.ai.is_configured() {
        return Err(ApiError::AiNotConfigured);
    }
    let mut upload: Option<(String, bytes::Bytes)> = None;
    while let Some(field) = multipart
        .next_field()
        .await
        .map_err(|error| ApiError::BadRequest(error.to_string()))?
    {
        if field.name() == Some("file") {
            let filename = safe_filename(field.file_name().unwrap_or("training.m4a"));
            let data = field
                .bytes()
                .await
                .map_err(|error| ApiError::BadRequest(error.to_string()))?;
            upload = Some((filename, data));
            break;
        }
    }
    let (_filename, data) =
        upload.ok_or_else(|| ApiError::BadRequest("multipart field 'file' is required".into()))?;
    let temp_dir = state.config.storage_dir.join("tmp");
    tokio::fs::create_dir_all(&temp_dir).await?;
    let job_id = Uuid::new_v4().to_string();
    let path = temp_dir.join(format!("asr-{job_id}.m4a"));
    tokio::fs::write(&path, data).await?;
    if let Err(error) = enqueue_session_asr(&state, &job_id, &session_id, answer_only).await {
        let _ = tokio::fs::remove_file(path).await;
        return Err(error);
    }
    Ok(Json(wait_for_job(&state, &job_id).await?))
}

async fn complete_session(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(session_id): Path<String>,
    Json(body): Json<CompleteSessionRequest>,
) -> ApiResult<Json<SessionResponse>> {
    if !(1..=3600).contains(&body.actual_seconds) {
        return Err(ApiError::BadRequest(
            "actual duration must be 1-3600 seconds".into(),
        ));
    }
    let model = owned_session(&state, &user.id, &session_id).await?;
    let mut active: rehearsal_session::ActiveModel = model.into();
    active.status = Set("ready_for_analysis".into());
    active.actual_seconds = Set(Some(body.actual_seconds));
    if let Some(transcript) = body.transcript {
        active.transcript = Set(Some(transcript));
    }
    active.completed_at = Set(Some(Utc::now()));
    Ok(Json(session_response(active.update(&state.db).await?)))
}

async fn analyze_session(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(session_id): Path<String>,
) -> ApiResult<Json<ReportResponse>> {
    owned_session(&state, &user.id, &session_id).await?;
    if !state.ai.is_configured() {
        return Err(ApiError::AiNotConfigured);
    }
    let job_id = enqueue_report_generation(&state, &session_id).await?;
    wait_for_job(&state, &job_id).await?;
    let report = report::Entity::find()
        .filter(report::Column::SessionId.eq(&session_id))
        .one(&state.db)
        .await?
        .ok_or(ApiError::NotFound)?;
    Ok(Json(report_response(report)?))
}

async fn get_report(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(session_id): Path<String>,
) -> ApiResult<Json<ReportResponse>> {
    owned_session(&state, &user.id, &session_id).await?;
    let report = report::Entity::find()
        .filter(report::Column::SessionId.eq(session_id))
        .one(&state.db)
        .await?
        .ok_or(ApiError::NotFound)?;
    Ok(Json(report_response(report)?))
}

async fn generate_questions(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(project_id): Path<String>,
    Json(body): Json<GenerateQuestionsRequest>,
) -> ApiResult<Json<Vec<QuestionResponse>>> {
    owned_project(&state, &user.id, &project_id).await?;
    let count = body.count.clamp(1, 10);
    if let Some(ref session_id) = body.session_id {
        owned_session(&state, &user.id, session_id).await?;
    }
    let chunks = retrieve_chunks(
        &state,
        &project_id,
        "项目背景 技术方案 创新点 实验结果 局限性 风险",
        16,
    )
    .await?;
    if chunks.is_empty() {
        return Err(ApiError::BadRequest(
            "project does not contain ready material".into(),
        ));
    }
    let material = chunks
        .iter()
        .map(|c| format!("[{}] {}", c.id, c.content))
        .collect::<Vec<_>>()
        .join("\n");
    let prompt = format!(
        "请根据以下材料生成{count}个中文答辩问题，覆盖技术、应用、创新、风险和质疑。只返回JSON：{{\"questions\":[{{\"category\":\"技术\",\"question\":\"...\",\"evidence\":[{{\"chunk_id\":\"...\",\"quote\":\"...\"}}]}}]}}。证据必须来自材料。\n\n{material}"
    );
    let value = state
        .ai
        .chat_json("你是严格但建设性的计算机应用大赛评委。", &prompt)
        .await?;
    let items = value
        .get("questions")
        .and_then(Value::as_array)
        .ok_or_else(|| ApiError::Internal("question response is malformed".into()))?;
    let mut responses = Vec::new();
    for item in items.iter().take(count) {
        let question_text = item
            .get("question")
            .and_then(Value::as_str)
            .unwrap_or_default()
            .trim();
        if question_text.is_empty() {
            continue;
        }
        let evidence = verified_evidence(item.get("evidence"), &chunks);
        if evidence.is_empty() {
            continue;
        }
        let model = jury_question::ActiveModel {
            id: Set(Uuid::new_v4().to_string()),
            project_id: Set(project_id.clone()),
            session_id: Set(body.session_id.clone()),
            category: Set(item
                .get("category")
                .and_then(Value::as_str)
                .unwrap_or("综合")
                .to_owned()),
            question: Set(question_text.to_owned()),
            evidence_json: Set(serde_json::to_value(&evidence)?),
            created_at: Set(Utc::now()),
        }
        .insert(&state.db)
        .await?;
        responses.push(question_response(model)?);
    }
    if responses.is_empty() {
        return Err(ApiError::Internal(
            "AI question response did not contain verifiable material evidence".into(),
        ));
    }
    Ok(Json(responses))
}

async fn list_questions(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(project_id): Path<String>,
) -> ApiResult<Json<Vec<QuestionResponse>>> {
    owned_project(&state, &user.id, &project_id).await?;
    let models = jury_question::Entity::find()
        .filter(jury_question::Column::ProjectId.eq(project_id))
        .order_by_desc(jury_question::Column::CreatedAt)
        .all(&state.db)
        .await?;
    Ok(Json(
        models
            .into_iter()
            .map(question_response)
            .collect::<ApiResult<Vec<_>>>()?,
    ))
}

async fn submit_answer(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(question_id): Path<String>,
    Json(body): Json<SubmitAnswerRequest>,
) -> ApiResult<Json<AnswerResponse>> {
    let question = jury_question::Entity::find_by_id(&question_id)
        .one(&state.db)
        .await?
        .ok_or(ApiError::NotFound)?;
    owned_project(&state, &user.id, &question.project_id).await?;
    let session = owned_session(&state, &user.id, &body.session_id).await?;
    if session.project_id != question.project_id
        || question
            .session_id
            .as_ref()
            .is_some_and(|session_id| session_id != &body.session_id)
    {
        return Err(ApiError::BadRequest(
            "question and answer session must belong to the same project and session".into(),
        ));
    }
    if body.answer_text.trim().is_empty() {
        return Err(ApiError::BadRequest("answer cannot be empty".into()));
    }
    let chunks = retrieve_chunks(
        &state,
        &question.project_id,
        &format!("{} {}", question.question, body.answer_text),
        8,
    )
    .await?;
    let material = chunks
        .iter()
        .map(|c| format!("[{}] {}", c.id, c.content))
        .collect::<Vec<_>>()
        .join("\n");
    let prompt = format!(
        "问题：{}\n回答：{}\n项目材料：\n{}\n只返回JSON，字段为score(0-100)、relevance、accuracy、evidence、suggestions、follow_up。评价必须以材料为准，并指出没有依据的表述。",
        question.question, body.answer_text, material
    );
    let mut evaluation = state
        .ai
        .chat_json("你是答辩评委，评价要简洁、可解释并引用项目材料。", &prompt)
        .await?;
    let evidence = verified_evidence(evaluation.get("evidence"), &chunks);
    if evidence.is_empty() {
        return Err(ApiError::Internal(
            "AI answer evaluation did not contain verifiable material evidence".into(),
        ));
    }
    let evaluation_object = evaluation
        .as_object_mut()
        .ok_or_else(|| ApiError::Internal("AI answer evaluation is malformed".into()))?;
    evaluation_object.insert("evidence".into(), serde_json::to_value(evidence)?);
    let score = evaluation_object
        .get("score")
        .and_then(Value::as_i64)
        .ok_or_else(|| ApiError::Internal("AI answer evaluation did not contain a score".into()))?
        .clamp(0, 100);
    evaluation_object.insert("score".into(), json!(score));
    let model = jury_answer::ActiveModel {
        id: Set(Uuid::new_v4().to_string()),
        question_id: Set(question_id),
        session_id: Set(body.session_id),
        answer_text: Set(body.answer_text),
        evaluation_json: Set(evaluation.clone()),
        created_at: Set(Utc::now()),
    }
    .insert(&state.db)
    .await?;
    refresh_report_qa(&state, &model.session_id).await?;
    Ok(Json(AnswerResponse {
        id: model.id,
        question_id: model.question_id,
        session_id: model.session_id,
        answer_text: model.answer_text,
        evaluation,
        created_at: model.created_at,
    }))
}

async fn get_trends(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(project_id): Path<String>,
) -> ApiResult<Json<TrendsResponse>> {
    owned_project(&state, &user.id, &project_id).await?;
    let sessions = rehearsal_session::Entity::find()
        .filter(rehearsal_session::Column::ProjectId.eq(&project_id))
        .order_by_asc(rehearsal_session::Column::CreatedAt)
        .all(&state.db)
        .await?;
    let mut points = Vec::new();
    for session in sessions {
        if let Some(model) = report::Entity::find()
            .filter(report::Column::SessionId.eq(&session.id))
            .one(&state.db)
            .await?
        {
            if let Ok(payload) = serde_json::from_value::<ReportPayload>(model.report_json) {
                points.push(TrendPoint {
                    session_id: session.id,
                    created_at: model.created_at,
                    characters_per_minute: payload.characters_per_minute,
                    delivery_score: payload.delivery.score,
                    timing_score: payload.timing.score,
                    visual_score: payload.visual.score,
                    content_score: payload.content.score,
                });
            }
        }
    }
    Ok(Json(TrendsResponse { project_id, points }))
}

async fn owned_project(
    state: &AppState,
    user_id: &str,
    project_id: &str,
) -> ApiResult<project::Model> {
    project::Entity::find_by_id(project_id)
        .filter(project::Column::UserId.eq(user_id))
        .one(&state.db)
        .await?
        .ok_or(ApiError::NotFound)
}

async fn owned_session(
    state: &AppState,
    user_id: &str,
    session_id: &str,
) -> ApiResult<rehearsal_session::Model> {
    rehearsal_session::Entity::find_by_id(session_id)
        .filter(rehearsal_session::Column::UserId.eq(user_id))
        .one(&state.db)
        .await?
        .ok_or(ApiError::NotFound)
}

fn project_response(model: project::Model) -> ProjectResponse {
    ProjectResponse {
        id: model.id,
        name: model.name,
        description: model.description,
        defense_duration_seconds: model.defense_duration_seconds,
        created_at: model.created_at,
        updated_at: model.updated_at,
    }
}
fn document_response(model: document::Model) -> DocumentResponse {
    DocumentResponse {
        id: model.id,
        project_id: model.project_id,
        filename: model.filename,
        media_type: model.media_type,
        status: model.status,
        extracted_text: model.extracted_text,
        error: model.error,
        created_at: model.created_at,
    }
}
fn session_response(model: rehearsal_session::Model) -> SessionResponse {
    SessionResponse {
        id: model.id,
        project_id: model.project_id,
        title: model.title,
        status: model.status,
        target_seconds: model.target_seconds,
        actual_seconds: model.actual_seconds,
        transcript: model.transcript,
        local_video_ref: model.local_video_ref,
        created_at: model.created_at,
        completed_at: model.completed_at,
    }
}
fn report_response(model: report::Model) -> ApiResult<ReportResponse> {
    Ok(ReportResponse {
        id: model.id,
        session_id: model.session_id,
        report: serde_json::from_value(model.report_json)?,
        created_at: model.created_at,
    })
}
fn question_response(model: jury_question::Model) -> ApiResult<QuestionResponse> {
    Ok(QuestionResponse {
        id: model.id,
        project_id: model.project_id,
        session_id: model.session_id,
        category: model.category,
        question: model.question,
        evidence: serde_json::from_value(model.evidence_json)?,
        created_at: model.created_at,
    })
}

fn safe_filename(input: &str) -> String {
    let input_path = PathBuf::from(input);
    let filename = input_path
        .file_name()
        .and_then(|v| v.to_str())
        .unwrap_or("file");
    let cleaned: String = filename
        .chars()
        .map(|c| {
            if c.is_ascii_alphanumeric()
                || matches!(c, '.' | '-' | '_')
                || ('\u{4e00}'..='\u{9fff}').contains(&c)
            {
                c
            } else {
                '_'
            }
        })
        .collect();
    if cleaned.is_empty() {
        "file".into()
    } else {
        cleaned.chars().take(120).collect()
    }
}

const MAX_DOCUMENT_BYTES: usize = 25 * 1024 * 1024;

fn validate_document_upload(
    filename: &str,
    declared_media_type: &str,
    data: &[u8],
) -> ApiResult<&'static str> {
    if data.is_empty() {
        return Err(ApiError::BadRequest("uploaded document is empty".into()));
    }
    if data.len() > MAX_DOCUMENT_BYTES {
        return Err(ApiError::BadRequest(
            "document exceeds the 25 MiB upload limit".into(),
        ));
    }
    let extension = PathBuf::from(filename)
        .extension()
        .and_then(|value| value.to_str())
        .map(str::to_ascii_lowercase)
        .ok_or_else(|| {
            ApiError::BadRequest("document filename needs a supported extension".into())
        })?;
    let expected = match extension.as_str() {
        "pdf" => "application/pdf",
        "txt" => "text/plain",
        "md" => "text/markdown",
        "png" => "image/png",
        "jpg" | "jpeg" => "image/jpeg",
        "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
        "pptx" => "application/vnd.openxmlformats-officedocument.presentationml.presentation",
        _ => {
            return Err(ApiError::BadRequest(format!(
                "unsupported document extension: {extension}"
            )));
        }
    };
    if declared_media_type != "application/octet-stream" && declared_media_type != expected {
        return Err(ApiError::BadRequest(format!(
            "file extension and media type do not match: {extension} / {declared_media_type}"
        )));
    }

    let valid_content = match extension.as_str() {
        "pdf" => data.starts_with(b"%PDF-"),
        "png" => data.starts_with(b"\x89PNG\r\n\x1a\n"),
        "jpg" | "jpeg" => data.starts_with(&[0xff, 0xd8, 0xff]),
        "txt" | "md" => std::str::from_utf8(data).is_ok() && !data.contains(&0),
        "docx" => office_archive_contains(data, "word/document.xml"),
        "pptx" => office_archive_contains(data, "ppt/presentation.xml"),
        _ => false,
    };
    if !valid_content {
        return Err(ApiError::BadRequest(format!(
            "file content is not a valid {extension} document"
        )));
    }
    Ok(expected)
}

fn office_archive_contains(data: &[u8], required_entry: &str) -> bool {
    let Ok(mut archive) = zip::ZipArchive::new(Cursor::new(data)) else {
        return false;
    };
    archive.by_name(required_entry).is_ok()
}

#[cfg(test)]
mod document_upload_tests {
    use super::*;

    #[test]
    fn validates_extension_media_type_content_and_size() {
        assert_eq!(
            validate_document_upload("notes.md", "text/markdown", b"# SpeechMirror").unwrap(),
            "text/markdown"
        );
        assert!(validate_document_upload("fake.pdf", "application/pdf", b"plain text").is_err());
        assert!(validate_document_upload("image.png", "image/jpeg", b"\x89PNG\r\n\x1a\n").is_err());
        assert!(
            validate_document_upload(
                "large.txt",
                "text/plain",
                &vec![b'a'; MAX_DOCUMENT_BYTES + 1],
            )
            .is_err()
        );
    }
}
