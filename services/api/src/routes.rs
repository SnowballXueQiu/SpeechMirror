use std::{collections::HashSet, io::Cursor, path::PathBuf};

use axum::{
    Extension, Json, Router,
    extract::{DefaultBodyLimit, Multipart, Path, State},
    middleware,
    routing::{get, post, put},
};
use chrono::Utc;
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, EntityTrait, ModelTrait, QueryFilter,
    QueryOrder, TransactionTrait, sea_query::Expr,
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
        ai_configured: state.ai.is_fully_configured(),
        providers: AiProviderStatus {
            llm: state.ai.is_llm_configured(),
            embedding: state.ai.is_embedding_configured(),
            asr: state.ai.is_asr_configured(),
            ocr: state.ai.is_ocr_configured(),
        },
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
    let transaction = state.db.begin().await?;
    session_metric::Entity::delete_many()
        .filter(session_metric::Column::SessionId.eq(&session_id))
        .exec(&transaction)
        .await?;
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
        .insert(&transaction)
        .await?;
    }
    transaction.commit().await?;
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
    if !state.ai.is_asr_configured() {
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
    if data.is_empty() {
        return Err(ApiError::BadRequest("uploaded audio is empty".into()));
    }
    if data.len() > MAX_AUDIO_BYTES {
        return Err(ApiError::BadRequest(
            "audio exceeds the 30 MiB upload limit".into(),
        ));
    }
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
    if !state.ai.is_llm_configured() {
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
    let presentation = if let Some(ref session_id) = body.session_id {
        let session = owned_session(&state, &user.id, session_id).await?;
        session
            .transcript
            .unwrap_or_default()
            .chars()
            .take(2_400)
            .collect::<String>()
    } else {
        String::new()
    };
    if let Some(ref session_id) = body.session_id {
        let existing = jury_question::Entity::find()
            .filter(jury_question::Column::ProjectId.eq(&project_id))
            .filter(jury_question::Column::SessionId.eq(session_id))
            .order_by_asc(jury_question::Column::CreatedAt)
            .all(&state.db)
            .await?;
        if existing.len() >= count && !body.regenerate {
            return existing
                .into_iter()
                .take(count)
                .map(question_response)
                .collect::<ApiResult<Vec<_>>>()
                .map(Json);
        }
        if body.regenerate && !existing.is_empty() {
            jury_question::Entity::delete_many()
                .filter(jury_question::Column::ProjectId.eq(&project_id))
                .filter(jury_question::Column::SessionId.eq(session_id))
                .exec(&state.db)
                .await?;
        }
    }
    let chunks = retrieve_chunks(
        &state,
        &project_id,
        &format!("项目背景 技术方案 创新点 实验结果 局限性 风险 {presentation}"),
        8,
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
    let category_plan = question_category_plan(count);
    let mut candidates = Vec::with_capacity(count);
    for _ in 0..QUESTION_GENERATION_MAX_ATTEMPTS {
        let missing = missing_question_categories(&category_plan, &candidates);
        if missing.is_empty() {
            break;
        }
        let prompt = question_generation_prompt(&material, &presentation, &missing);
        let value = match state
            .ai
            .chat_json_fast("你是严格但建设性的计算机应用大赛评委。", &prompt)
            .await
        {
            Ok(value) => value,
            Err(error) => {
                tracing::warn!(error = %error, "question generation fell back to material prompts");
                break;
            }
        };
        accept_question_candidates(&value, &chunks, &category_plan, &mut candidates);
    }
    fill_fallback_question_candidates(
        &category_plan,
        &chunks,
        &mut candidates,
        body.session_id.as_deref().unwrap_or(&project_id),
    );
    let candidates = order_question_candidates(&category_plan, candidates);
    if candidates.len() != count {
        let missing = missing_question_categories(&category_plan, &candidates).join("、");
        return Err(ApiError::Internal(format!(
            "AI question response did not provide valid questions for: {missing}"
        )));
    }

    let transaction = state.db.begin().await?;
    let mut responses = Vec::with_capacity(count);
    for candidate in candidates {
        let model = jury_question::ActiveModel {
            id: Set(Uuid::new_v4().to_string()),
            project_id: Set(project_id.clone()),
            session_id: Set(body.session_id.clone()),
            category: Set(candidate.category),
            question: Set(candidate.question),
            evidence_json: Set(serde_json::to_value(&candidate.evidence)?),
            created_at: Set(Utc::now()),
        }
        .insert(&transaction)
        .await?;
        responses.push(question_response(model)?);
    }
    transaction.commit().await?;
    Ok(Json(responses))
}

const CORE_QUESTION_CATEGORIES: [&str; 5] = ["技术", "应用", "创新", "风险", "质疑"];
const QUESTION_GENERATION_MAX_ATTEMPTS: usize = 3;

#[derive(Debug)]
struct QuestionCandidate {
    category: String,
    question: String,
    evidence: Vec<EvidenceRef>,
}

fn question_category_plan(count: usize) -> Vec<&'static str> {
    CORE_QUESTION_CATEGORIES
        .into_iter()
        .cycle()
        .take(count)
        .collect()
}

fn missing_question_categories<'a>(
    category_plan: &'a [&'static str],
    candidates: &[QuestionCandidate],
) -> Vec<&'a str> {
    let mut available = candidates
        .iter()
        .map(|candidate| candidate.category.as_str())
        .collect::<Vec<_>>();
    category_plan
        .iter()
        .filter_map(|category| {
            available
                .iter()
                .position(|accepted| accepted == category)
                .map(|position| available.remove(position))
                .is_none()
                .then_some(*category)
        })
        .collect()
}

fn question_generation_prompt(material: &str, presentation: &str, missing: &[&str]) -> String {
    let presentation = if presentation.trim().is_empty() {
        "（没有可用的现场陈述转写）"
    } else {
        presentation
    };
    format!(
        "请结合项目材料和学生刚才的现场陈述，生成{}个关键、适度的中文答辩问题。优先追问陈述中含糊、遗漏、与材料不一致或缺少验证的部分，不要复制现场陈述原句。类别必须依次为：{}。每个问题只能问一件事，必须是一个简短直接的问题，80字以内，不得使用引号、括号、分号或连续多个问号。question只写问题本身，不要写背景、评价或多个小问。每个问题的category必须逐字使用对应类别；evidence至少包含一项；chunk_id必须复制材料方括号中的编号；quote必须是对应材料中的连续原文，不得改写或概括。只返回JSON：{{\"questions\":[{{\"category\":\"技术\",\"question\":\"...\",\"evidence\":[{{\"chunk_id\":\"...\",\"quote\":\"材料原文\"}}]}}]}}。questions数组必须恰好包含{}项。\n\n现场陈述转写：\n{presentation}\n\n项目材料：\n{material}",
        missing.len(),
        missing.join("、"),
        missing.len(),
    )
}

fn fill_fallback_question_candidates(
    category_plan: &[&'static str],
    chunks: &[crate::entities::document_chunk::Model],
    candidates: &mut Vec<QuestionCandidate>,
    variation_key: &str,
) {
    if chunks.is_empty() {
        return;
    }
    let offset = variation_key
        .bytes()
        .fold(0usize, |total, byte| total.wrapping_add(byte as usize))
        % chunks.len();
    let missing = missing_question_categories(category_plan, candidates);
    for (index, category) in missing.into_iter().enumerate() {
        let chunk = &chunks[(offset + index) % chunks.len()];
        let anchor = chunk
            .content
            .split_whitespace()
            .collect::<Vec<_>>()
            .join("")
            .chars()
            .take(38)
            .collect::<String>();
        let question = match category {
            "技术" => format!("材料提到“{anchor}”，请说明它在系统中如何实现？"),
            "应用" => format!("材料提到“{anchor}”，请说明这一点如何服务目标用户？"),
            "创新" => format!("材料提到“{anchor}”，请说明它相比常见方案的具体差异？"),
            "风险" => format!("材料提到“{anchor}”，请说明这一点目前如何验证？"),
            "质疑" => format!("材料提到“{anchor}”，请说明该方案的边界或局限是什么？"),
            _ => format!("材料提到“{anchor}”，请说明这一点的依据是什么？"),
        };
        candidates.push(QuestionCandidate {
            category: category.to_owned(),
            question,
            evidence: vec![EvidenceRef {
                chunk_id: chunk.id.clone(),
                quote: chunk.content.chars().take(100).collect(),
            }],
        });
    }
}

fn accept_question_candidates(
    value: &Value,
    chunks: &[crate::entities::document_chunk::Model],
    category_plan: &[&'static str],
    candidates: &mut Vec<QuestionCandidate>,
) {
    let Some(items) = value.get("questions").and_then(Value::as_array) else {
        return;
    };
    let mut missing = missing_question_categories(category_plan, candidates);
    for item in items {
        let Some(category) = item.get("category").and_then(Value::as_str).map(str::trim) else {
            continue;
        };
        let Some(category_position) = missing.iter().position(|expected| *expected == category)
        else {
            continue;
        };
        let Some(question) = item
            .get("question")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|question| !question.is_empty())
        else {
            continue;
        };
        if question.chars().count() > 100
            || question.matches('？').count() > 1
            || question.matches('?').count() > 1
            || question.chars().any(|character| {
                matches!(
                    character,
                    '\n' | '\r' | '"' | '“' | '”' | '(' | ')' | '（' | '）' | ';' | '；'
                )
            })
        {
            continue;
        }
        if candidates
            .iter()
            .any(|candidate| candidate.question == question)
        {
            continue;
        }
        let evidence = verified_evidence(item.get("evidence"), chunks);
        if evidence.is_empty() {
            continue;
        }
        candidates.push(QuestionCandidate {
            category: category.to_owned(),
            question: question.to_owned(),
            evidence,
        });
        missing.remove(category_position);
        if missing.is_empty() {
            break;
        }
    }
}

fn order_question_candidates(
    category_plan: &[&'static str],
    mut candidates: Vec<QuestionCandidate>,
) -> Vec<QuestionCandidate> {
    category_plan
        .iter()
        .filter_map(|category| {
            let position = candidates
                .iter()
                .position(|candidate| candidate.category == *category)?;
            Some(candidates.remove(position))
        })
        .collect()
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
    let (asked_question, previous_turn) = if let Some(parent_answer_id) =
        body.parent_answer_id.as_deref()
    {
        let parent = jury_answer::Entity::find_by_id(parent_answer_id)
            .one(&state.db)
            .await?
            .ok_or(ApiError::NotFound)?;
        if parent.question_id != question_id || parent.session_id != body.session_id {
            return Err(ApiError::BadRequest(
                "follow-up must continue the same question and session".into(),
            ));
        }
        let follow_up = normalized_follow_up(&parent.evaluation_json).ok_or_else(|| {
            ApiError::BadRequest("the referenced answer does not contain a valid follow-up".into())
        })?;
        let previous_question = parent
            .evaluation_json
            .get("asked_question")
            .and_then(Value::as_str)
            .unwrap_or(&question.question);
        (
            follow_up,
            format!(
                "上一轮问题：{previous_question}\n上一轮回答：{}\n",
                parent.answer_text
            ),
        )
    } else {
        (question.question.clone(), String::new())
    };
    let chunks = retrieve_chunks(
        &state,
        &question.project_id,
        &format!("{} {}", asked_question, body.answer_text),
        4,
    )
    .await?;
    let material = chunks
        .iter()
        .map(|c| format!("[{}] {}", c.id, c.content))
        .collect::<Vec<_>>()
        .join("\n");
    let prompt = format!(
        "原始问题：{}\n{}本轮问题：{}\n本轮回答：{}\n项目材料：\n{}\n只返回JSON，字段为score(0-100整数)、expression_score(0-100整数)、adaptability_score(0-100整数)、familiarity_score(0-100整数)、completeness_score(0-100整数)、relevance、accuracy、evidence数组、suggestions数组、follow_up。评分必须严格以本轮问题和材料证据为准，不能因为回答字数多就给高分：完全跑题、胡编或没有回答要点时不超过40分；回答没有任何材料依据时不超过55分；只有明确回答问题、引用材料中的具体方案或数据，并说明边界时才能超过75分。evidence每项必须含chunk_id和对应材料中的连续原文quote。suggestions必须至少给出3条针对本轮回答的改进，每条指出一个具体缺口和对应改法，禁止使用‘继续努力’‘补充材料’等空泛表述。首轮回答存在关键缺口、矛盾或不确定时必须给出一个简短中文follow_up，第二轮follow_up必须为null。",
        question.question, previous_turn, asked_question, body.answer_text, material
    );
    let mut evaluation = match state
        .ai
        .chat_json_fast("你是答辩评委，评价要简洁、可解释并引用项目材料。", &prompt)
        .await
    {
        Ok(value) => value,
        Err(error) => {
            tracing::warn!(error = %error, "answer evaluation fell back to material feedback");
            fallback_answer_evaluation(
                &asked_question,
                &body.answer_text,
                &chunks,
                body.parent_answer_id.is_none(),
            )
        }
    };
    let mut evidence = verified_evidence(evaluation.get("evidence"), &chunks);
    if evidence.is_empty() {
        evaluation = fallback_answer_evaluation(
            &asked_question,
            &body.answer_text,
            &chunks,
            body.parent_answer_id.is_none(),
        );
        evidence = verified_evidence(evaluation.get("evidence"), &chunks);
    }
    if evidence.is_empty() {
        return Err(ApiError::Internal(
            "answer evaluation could not establish material evidence".into(),
        ));
    }
    if evaluation.get("score").and_then(Value::as_i64).is_none() {
        evaluation = fallback_answer_evaluation(
            &asked_question,
            &body.answer_text,
            &chunks,
            body.parent_answer_id.is_none(),
        );
        evidence = verified_evidence(evaluation.get("evidence"), &chunks);
    }
    {
        let evaluation_object = evaluation
            .as_object_mut()
            .ok_or_else(|| ApiError::Internal("AI answer evaluation is malformed".into()))?;
        evaluation_object.insert("evidence".into(), serde_json::to_value(&evidence)?);
    }
    enrich_answer_feedback(
        &mut evaluation,
        &asked_question,
        &body.answer_text,
        &evidence,
        body.parent_answer_id.is_none(),
    );
    let raw_score = evaluation
        .as_object()
        .and_then(|object| object.get("score"))
        .and_then(Value::as_i64)
        .ok_or_else(|| ApiError::Internal("AI answer evaluation did not contain a score".into()))?
        .clamp(0, 100);
    let score = calibrate_answer_score(raw_score, &body.answer_text, &evidence);
    let evaluation_object = evaluation
        .as_object_mut()
        .ok_or_else(|| ApiError::Internal("AI answer evaluation is malformed".into()))?;
    evaluation_object.insert("score".into(), json!(score));
    let follow_up = normalized_follow_up(&evaluation);
    let evaluation_object = evaluation
        .as_object_mut()
        .ok_or_else(|| ApiError::Internal("AI answer evaluation is malformed".into()))?;
    evaluation_object.insert("follow_up".into(), json!(follow_up));
    evaluation_object.insert("asked_question".into(), json!(&asked_question));
    evaluation_object.insert(
        "parent_answer_id".into(),
        serde_json::to_value(&body.parent_answer_id)?,
    );
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
        asked_question,
        parent_answer_id: body.parent_answer_id,
        answer_text: model.answer_text,
        evaluation,
        created_at: model.created_at,
    }))
}

fn fallback_answer_evaluation(
    asked_question: &str,
    answer_text: &str,
    chunks: &[crate::entities::document_chunk::Model],
    allow_follow_up: bool,
) -> Value {
    let answer_length = answer_text
        .chars()
        .filter(|character| !character.is_whitespace())
        .count();
    let score = if answer_length >= 80 {
        48
    } else if answer_length >= 40 {
        38
    } else if answer_length >= 15 {
        28
    } else {
        18
    };
    let evidence = chunks
        .first()
        .map(|chunk| {
            json!([{
                "chunk_id": chunk.id,
                "quote": chunk.content.chars().take(80).collect::<String>()
            }])
        })
        .unwrap_or_else(|| json!([]));
    let follow_up = if allow_follow_up && answer_length < 80 {
        format!(
            "请结合材料补充“{}”的一个具体依据或结果？",
            asked_question.chars().take(30).collect::<String>()
        )
    } else {
        String::new()
    };
    json!({
        "score": score,
        "expression_score": score,
        "adaptability_score": score,
        "familiarity_score": score,
        "completeness_score": score,
        "relevance": if answer_length < 40 { "回答只触及问题表面，尚未形成可核验的完整回答。" } else { "回答包含部分相关信息，但与材料证据的对应关系不足。" },
        "accuracy": "当前回答缺少足够的材料依据，不能据此确认方案或结论准确。",
        "evidence": evidence,
        "suggestions": [
            "先用一句话直接回答问题，再补充一项材料依据。",
            "补充一个可验证的技术细节、数据结果或实际使用场景。",
            "避免连续使用口头填充词，回答结构可按结论、依据、边界展开。"
        ],
        "follow_up": if follow_up.is_empty() { Value::Null } else { Value::String(follow_up) },
        "evaluation_source": "material_recovery"
    })
}

fn enrich_answer_feedback(
    evaluation: &mut Value,
    asked_question: &str,
    answer_text: &str,
    evidence: &[EvidenceRef],
    allow_follow_up: bool,
) {
    let answer_length = answer_text
        .chars()
        .filter(|character| !character.is_whitespace())
        .count();
    let needs_follow_up =
        allow_follow_up && answer_length < 80 && normalized_follow_up(evaluation).is_none();
    let Some(object) = evaluation.as_object_mut() else {
        return;
    };
    let question_excerpt = asked_question.chars().take(32).collect::<String>();
    let evidence_excerpt = evidence
        .first()
        .map(|item| item.quote.chars().take(38).collect::<String>())
        .unwrap_or_else(|| "当前材料证据".into());
    let targeted_suggestion = format!(
        "针对“{question_excerpt}”，请明确说明回答与材料片段“{evidence_excerpt}”的对应关系。"
    );
    let suggestions = object.entry("suggestions").or_insert_with(|| json!([]));
    if let Some(items) = suggestions.as_array_mut() {
        if items.len() < 3 {
            items.push(Value::String(targeted_suggestion));
        }
    } else {
        *suggestions = json!([
            "先用一句话直接回答问题，再补充一项材料依据。",
            "补充一个可验证的技术细节、数据结果或实际使用场景。",
            targeted_suggestion
        ]);
    }
    if needs_follow_up {
        object.insert(
            "follow_up".into(),
            json!(format!(
                "请结合材料补充“{}”的一个具体依据或结果？",
                asked_question.chars().take(30).collect::<String>()
            )),
        );
    }
}

fn calibrate_answer_score(raw_score: i64, answer_text: &str, evidence: &[EvidenceRef]) -> i64 {
    let answer_length = answer_text
        .chars()
        .filter(|character| !character.is_whitespace())
        .count();
    let overlap = material_overlap_count(answer_text, evidence);
    let upper_bound = if answer_length < 15 {
        25
    } else if answer_length < 40 {
        42
    } else if overlap == 0 {
        48
    } else if overlap < 2 {
        60
    } else if overlap < 4 {
        75
    } else {
        100
    };
    raw_score.min(upper_bound)
}

fn material_overlap_count(answer_text: &str, evidence: &[EvidenceRef]) -> usize {
    let answer_chars = answer_text
        .chars()
        .filter(|character| character.is_alphanumeric())
        .collect::<Vec<_>>();
    if answer_chars.len() < 2 {
        return 0;
    }
    let evidence_text = evidence
        .iter()
        .map(|item| item.quote.as_str())
        .collect::<Vec<_>>()
        .join("");
    let mut seen = HashSet::new();
    answer_chars
        .windows(2)
        .filter_map(|pair| {
            let token = pair.iter().collect::<String>();
            evidence_text.contains(&token).then_some(token)
        })
        .filter(|token| seen.insert(token.clone()))
        .count()
}

fn normalized_follow_up(evaluation: &Value) -> Option<String> {
    let follow_up = evaluation.get("follow_up")?.as_str()?.trim();
    (!follow_up.is_empty() && follow_up.chars().count() <= 500).then(|| follow_up.to_owned())
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
            && let Ok(payload) = serde_json::from_value::<ReportPayload>(model.report_json)
        {
            points.push(build_trend_point(
                session.id,
                session.target_seconds,
                model.created_at,
                payload,
            ));
        }
    }
    Ok(Json(TrendsResponse { project_id, points }))
}

fn build_trend_point(
    session_id: String,
    target_seconds: i32,
    created_at: chrono::DateTime<Utc>,
    payload: ReportPayload,
) -> TrendPoint {
    let actual_seconds = payload.actual_seconds.max(0);
    let filler_count = payload.filler_counts.values().sum();
    let filler_per_minute = if actual_seconds == 0 {
        0.0
    } else {
        filler_count as f64 * 60.0 / actual_seconds as f64
    };
    TrendPoint {
        session_id,
        created_at,
        target_seconds,
        actual_seconds,
        duration_deviation_seconds: actual_seconds - target_seconds,
        characters_per_minute: payload.characters_per_minute,
        filler_count,
        filler_per_minute,
        delivery_score: payload.delivery.score,
        timing_score: payload.timing.score,
        visual_score: payload.visual.score,
        content_score: payload.content.score,
        qa_score: payload.qa.score,
    }
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
const MAX_AUDIO_BYTES: usize = 30 * 1024 * 1024;

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
mod route_tests {
    use std::collections::BTreeMap;

    use super::*;

    fn dimension(score: Option<i32>) -> DimensionReport {
        DimensionReport {
            score,
            summary: String::new(),
            evidence: vec![],
        }
    }

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

    fn question_test_chunk() -> crate::entities::document_chunk::Model {
        crate::entities::document_chunk::Model {
            id: "chunk-1".into(),
            document_id: "document-1".into(),
            project_id: "project-1".into(),
            ordinal: 0,
            content: "系统采用端云协同架构，原始视频只保存在手机本地。".into(),
            embedding: None,
        }
    }

    #[test]
    fn question_candidates_require_exact_category_question_and_evidence() {
        let chunks = vec![question_test_chunk()];
        let plan = question_category_plan(5);
        let value = json!({"questions": [
            {"category":"技术", "question":"系统如何实现端云协同？", "evidence":[{"chunk_id":"chunk-1", "quote":"端云协同架构"}]},
            {"category":"应用", "question":" ", "evidence":[{"chunk_id":"chunk-1", "quote":"原始视频"}]},
            {"category":"创新", "question":"创新点是什么？", "evidence":[{"chunk_id":"chunk-1", "quote":"不存在的原文"}]},
            {"category":"风险类", "question":"有什么风险？", "evidence":[{"chunk_id":"chunk-1", "quote":"手机本地"}]},
            {"category":"质疑", "question":"为什么不上传视频？", "evidence":[{"chunk_id":"chunk-1", "quote":"原始视频只保存在手机本地"}]},
            {"category":"应用", "question":"系统如何实现端云协同？", "evidence":[{"chunk_id":"chunk-1", "quote":"端云协同架构"}]}
        ]});
        let mut candidates = Vec::new();

        accept_question_candidates(&value, &chunks, &plan, &mut candidates);

        assert_eq!(candidates.len(), 2);
        assert_eq!(candidates[0].category, "技术");
        assert_eq!(candidates[1].category, "质疑");
        assert_eq!(
            missing_question_categories(&plan, &candidates),
            vec!["应用", "创新", "风险"]
        );
    }

    #[test]
    fn question_retry_fills_only_missing_categories_and_restores_plan_order() {
        let chunks = vec![question_test_chunk()];
        let plan = question_category_plan(5);
        let first = json!({"questions": [
            {"category":"技术", "question":"技术问题", "evidence":[{"chunk_id":"chunk-1", "quote":"端云协同架构"}]},
            {"category":"质疑", "question":"质疑问题", "evidence":[{"chunk_id":"chunk-1", "quote":"原始视频"}]}
        ]});
        let retry = json!({"questions": [
            {"category":"风险", "question":"风险问题", "evidence":[{"chunk_id":"chunk-1", "quote":"手机本地"}]},
            {"category":"创新", "question":"创新问题", "evidence":[{"chunk_id":"chunk-1", "quote":"端云协同架构"}]},
            {"category":"应用", "question":"应用问题", "evidence":[{"chunk_id":"chunk-1", "quote":"原始视频只保存在手机本地"}]},
            {"category":"技术", "question":"不应重复补充的技术问题", "evidence":[{"chunk_id":"chunk-1", "quote":"端云协同架构"}]}
        ]});
        let mut candidates = Vec::new();

        accept_question_candidates(&first, &chunks, &plan, &mut candidates);
        accept_question_candidates(&retry, &chunks, &plan, &mut candidates);
        let ordered = order_question_candidates(&plan, candidates);

        assert_eq!(ordered.len(), 5);
        assert_eq!(
            ordered
                .iter()
                .map(|candidate| candidate.category.as_str())
                .collect::<Vec<_>>(),
            CORE_QUESTION_CATEGORIES
        );
        assert!(missing_question_categories(&plan, &ordered).is_empty());
    }

    #[test]
    fn question_candidates_reject_ambiguous_or_overlong_questions() {
        let chunks = vec![question_test_chunk()];
        let plan = question_category_plan(1);
        let value = json!({"questions": [
            {"category":"技术", "question":"请说明技术方案如何实现、如何验证，以及后续如何扩展？还可以补充哪些细节？", "evidence":[{"chunk_id":"chunk-1", "quote":"端云协同架构"}]}
        ]});
        let mut candidates = Vec::new();

        accept_question_candidates(&value, &chunks, &plan, &mut candidates);

        assert!(candidates.is_empty());
    }

    #[test]
    fn recovered_answer_feedback_keeps_suggestions_and_follow_up() {
        let value = fallback_answer_evaluation(
            "请说明项目面向的主要用户？",
            "主要面向学生。",
            &[question_test_chunk()],
            true,
        );

        assert!(
            value["suggestions"]
                .as_array()
                .is_some_and(|items| items.len() >= 2)
        );
        assert!(normalized_follow_up(&value).is_some());
        assert_eq!(
            verified_evidence(value.get("evidence"), &[question_test_chunk()]).len(),
            1
        );
    }

    #[test]
    fn answer_score_is_capped_without_material_overlap() {
        let evidence = vec![EvidenceRef {
            chunk_id: "chunk-1".into(),
            quote: "系统采用端云协同架构".into(),
        }];

        assert_eq!(
            calibrate_answer_score(96, "我觉得这个项目特别好，大家都会喜欢。", &evidence),
            42
        );
        assert_eq!(
            calibrate_answer_score(
                96,
                "系统采用端云协同架构，并通过材料中的流程和测试结果支撑这一方案，同时说明了适用边界和后续验证计划。",
                &evidence,
            ),
            96
        );
    }

    #[test]
    fn follow_up_requires_a_non_empty_bounded_question() {
        assert_eq!(
            normalized_follow_up(&json!({"follow_up":"  如何验证端侧数据没有泄露？  "})),
            Some("如何验证端侧数据没有泄露？".into())
        );
        assert_eq!(normalized_follow_up(&json!({"follow_up":"  "})), None);
        assert_eq!(normalized_follow_up(&json!({"follow_up":7})), None);
        assert_eq!(
            normalized_follow_up(&json!({"follow_up":"问".repeat(501)})),
            None
        );
    }

    #[test]
    fn derives_trend_metrics_from_a_persisted_report() {
        let payload = ReportPayload {
            session_id: "session-1".into(),
            overall_score: Some(80),
            actual_seconds: 330,
            character_count: 900,
            characters_per_minute: 163.6,
            filler_counts: BTreeMap::from([("然后".into(), 2), ("嗯".into(), 1)]),
            long_pause_count: Some(1),
            audio_waveform: vec![],
            content: dimension(Some(84)),
            delivery: dimension(Some(78)),
            timing: dimension(Some(90)),
            visual: dimension(None),
            qa: dimension(Some(76)),
            timeline: vec![],
            suggestions: vec![],
            model_confidence: Some(0.8),
        };
        let point = build_trend_point("session-1".into(), 300, Utc::now(), payload);

        assert_eq!(point.actual_seconds, 330);
        assert_eq!(point.duration_deviation_seconds, 30);
        assert_eq!(point.filler_count, 3);
        assert!((point.filler_per_minute - 0.5454).abs() < 0.001);
        assert_eq!(point.content_score, Some(84));
        assert_eq!(point.qa_score, Some(76));
        assert_eq!(point.visual_score, None);
    }

    #[test]
    fn keeps_zero_duration_trend_finite() {
        let payload = ReportPayload {
            session_id: "session-2".into(),
            overall_score: None,
            actual_seconds: 0,
            character_count: 0,
            characters_per_minute: 0.0,
            filler_counts: BTreeMap::from([("嗯".into(), 1)]),
            long_pause_count: None,
            audio_waveform: vec![],
            content: dimension(None),
            delivery: dimension(None),
            timing: dimension(None),
            visual: dimension(None),
            qa: dimension(None),
            timeline: vec![],
            suggestions: vec![],
            model_confidence: None,
        };
        let point = build_trend_point("session-2".into(), 300, Utc::now(), payload);

        assert_eq!(point.actual_seconds, 0);
        assert_eq!(point.duration_deviation_seconds, -300);
        assert_eq!(point.filler_per_minute, 0.0);
        assert!(point.filler_per_minute.is_finite());
    }
}
