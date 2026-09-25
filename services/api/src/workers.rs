use std::{
    path::Path,
    time::{Duration, SystemTime},
};

use chrono::Utc;
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, EntityTrait, QueryFilter, QueryOrder,
};
use serde_json::{Value, json};
use tokio::time::sleep;
use uuid::Uuid;

use crate::{
    AppState,
    analysis::{generate_report, ingest_document, mark_document_failed},
    entities::{analysis_job, rehearsal_session},
    error::{ApiError, ApiResult},
};

pub async fn enqueue_document_ingestion(state: &AppState, document_id: &str) -> ApiResult<()> {
    let now = Utc::now();
    analysis_job::ActiveModel {
        id: Set(Uuid::new_v4().to_string()),
        kind: Set("document_ingestion".into()),
        resource_id: Set(document_id.to_owned()),
        status: Set("queued".into()),
        error: Set(None),
        result_json: Set(None),
        created_at: Set(now),
        updated_at: Set(now),
    }
    .insert(&state.db)
    .await?;
    Ok(())
}

pub async fn enqueue_session_asr(
    state: &AppState,
    job_id: &str,
    session_id: &str,
    answer_only: bool,
) -> ApiResult<()> {
    insert_job(
        state,
        job_id,
        if answer_only {
            "answer_asr"
        } else {
            "session_asr"
        },
        session_id,
    )
    .await
}

pub async fn enqueue_report_generation(state: &AppState, session_id: &str) -> ApiResult<String> {
    let job_id = Uuid::new_v4().to_string();
    insert_job(state, &job_id, "report_generation", session_id).await?;
    Ok(job_id)
}

async fn insert_job(state: &AppState, id: &str, kind: &str, resource_id: &str) -> ApiResult<()> {
    let now = Utc::now();
    analysis_job::ActiveModel {
        id: Set(id.to_owned()),
        kind: Set(kind.to_owned()),
        resource_id: Set(resource_id.to_owned()),
        status: Set("queued".into()),
        error: Set(None),
        result_json: Set(None),
        created_at: Set(now),
        updated_at: Set(now),
    }
    .insert(&state.db)
    .await?;
    Ok(())
}

pub async fn wait_for_job(state: &AppState, job_id: &str) -> ApiResult<Value> {
    let deadline = tokio::time::Instant::now() + Duration::from_secs(100);
    loop {
        let job = analysis_job::Entity::find_by_id(job_id)
            .one(&state.db)
            .await?
            .ok_or(ApiError::NotFound)?;
        match job.status.as_str() {
            "completed" => return Ok(job.result_json.unwrap_or_else(|| json!({}))),
            "failed" => {
                return Err(ApiError::Internal(
                    job.error.unwrap_or_else(|| "background job failed".into()),
                ));
            }
            _ if tokio::time::Instant::now() >= deadline => {
                return Err(ApiError::Internal(
                    "background job is still running; retry the request later".into(),
                ));
            }
            _ => sleep(Duration::from_millis(200)).await,
        }
    }
}

pub fn spawn(state: AppState) {
    let job_state = state.clone();
    tokio::spawn(async move {
        if let Err(error) = recover_interrupted_jobs(&job_state).await {
            tracing::error!(%error, "failed to recover background jobs");
        }
        loop {
            match claim_next_job(&job_state).await {
                Ok(Some(job)) => run_job(&job_state, job).await,
                Ok(None) => sleep(Duration::from_millis(500)).await,
                Err(error) => {
                    tracing::error!(%error, "background job poll failed");
                    sleep(Duration::from_secs(5)).await;
                }
            }
        }
    });

    tokio::spawn(async move {
        loop {
            if let Err(error) =
                cleanup_expired_temp_files(&state.config.storage_dir.join("tmp")).await
            {
                tracing::warn!(%error, "temporary file cleanup failed");
            }
            sleep(Duration::from_secs(5 * 60)).await;
        }
    });
}

async fn recover_interrupted_jobs(state: &AppState) -> ApiResult<()> {
    let jobs = analysis_job::Entity::find()
        .filter(analysis_job::Column::Status.eq("running"))
        .all(&state.db)
        .await?;
    for job in jobs {
        let mut active: analysis_job::ActiveModel = job.into();
        active.status = Set("queued".into());
        active.error = Set(Some("服务重启后自动恢复".into()));
        active.updated_at = Set(Utc::now());
        active.update(&state.db).await?;
    }
    Ok(())
}

async fn claim_next_job(state: &AppState) -> ApiResult<Option<analysis_job::Model>> {
    let Some(job) = analysis_job::Entity::find()
        .filter(analysis_job::Column::Status.eq("queued"))
        .order_by_asc(analysis_job::Column::CreatedAt)
        .one(&state.db)
        .await?
    else {
        return Ok(None);
    };
    let mut active: analysis_job::ActiveModel = job.into();
    active.status = Set("running".into());
    active.error = Set(None);
    active.result_json = Set(None);
    active.updated_at = Set(Utc::now());
    Ok(Some(active.update(&state.db).await?))
}

async fn run_job(state: &AppState, job: analysis_job::Model) {
    let result = match job.kind.as_str() {
        "document_ingestion" => ingest_document(state, &job.resource_id).await.map(|_| None),
        "session_asr" => transcribe_audio_job(state, &job, true).await.map(Some),
        "answer_asr" => transcribe_audio_job(state, &job, false).await.map(Some),
        "report_generation" => generate_report(state, &job.resource_id)
            .await
            .map(|report| Some(json!({"report_id": report.id}))),
        other => Err(crate::error::ApiError::Internal(format!(
            "unknown job kind: {other}"
        ))),
    };
    let mut active: analysis_job::ActiveModel = job.clone().into();
    active.updated_at = Set(Utc::now());
    match result {
        Ok(result_json) => {
            active.status = Set("completed".into());
            active.error = Set(None);
            active.result_json = Set(result_json);
        }
        Err(error) => {
            let message: String = error.to_string().chars().take(1000).collect();
            tracing::error!(job_id = %job.id, resource_id = %job.resource_id, %message, "background job failed");
            if job.kind == "document_ingestion" {
                let _ = mark_document_failed(state, &job.resource_id, &message).await;
            }
            active.status = Set("failed".into());
            active.error = Set(Some(message));
            active.result_json = Set(None);
        }
    }
    if let Err(error) = active.update(&state.db).await {
        tracing::error!(job_id = %job.id, %error, "failed to persist background job result");
    }
}

async fn transcribe_audio_job(
    state: &AppState,
    job: &analysis_job::Model,
    persist_session_transcript: bool,
) -> ApiResult<Value> {
    let path = state
        .config
        .storage_dir
        .join("tmp")
        .join(format!("asr-{}.m4a", job.id));
    let transcription = state.ai.transcribe_audio(&path, "training.m4a").await;
    let _ = tokio::fs::remove_file(&path).await;
    let transcript = transcription?;
    if persist_session_transcript {
        let model = rehearsal_session::Entity::find_by_id(&job.resource_id)
            .one(&state.db)
            .await?
            .ok_or(ApiError::NotFound)?;
        let mut active: rehearsal_session::ActiveModel = model.into();
        active.transcript = Set(Some(transcript.clone()));
        active.update(&state.db).await?;
    }
    Ok(json!({"transcript": transcript}))
}

async fn cleanup_expired_temp_files(root: &Path) -> std::io::Result<()> {
    let cutoff = SystemTime::now() - Duration::from_secs(30 * 60);
    let mut entries = match tokio::fs::read_dir(root).await {
        Ok(entries) => entries,
        Err(error) if error.kind() == std::io::ErrorKind::NotFound => return Ok(()),
        Err(error) => return Err(error),
    };
    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        let metadata = entry.metadata().await?;
        let modified = metadata.modified().unwrap_or(SystemTime::UNIX_EPOCH);
        if modified > cutoff {
            continue;
        }
        if metadata.is_dir() {
            let _ = tokio::fs::remove_dir_all(path).await;
        } else {
            let _ = tokio::fs::remove_file(path).await;
        }
    }
    Ok(())
}
