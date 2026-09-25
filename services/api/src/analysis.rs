use std::{
    collections::{BTreeMap, HashSet},
    path::{Path, PathBuf},
    process::Stdio,
};

use chrono::Utc;
use sea_orm::{
    ActiveModelTrait, ActiveValue::Set, ColumnTrait, DatabaseConnection, EntityTrait, ModelTrait,
    QueryFilter, QueryOrder,
};
use serde_json::{Value, json};
use tokio::process::Command;
use uuid::Uuid;

use crate::{
    AppState,
    entities::{document, document_chunk, jury_answer, rehearsal_session, report, session_metric},
    error::{ApiError, ApiResult},
    models::{DimensionReport, EvidenceRef, ReportPayload, TimelineIssue},
};

pub async fn ingest_document(state: &AppState, document_id: &str) -> ApiResult<()> {
    let model = document::Entity::find_by_id(document_id)
        .one(&state.db)
        .await?
        .ok_or(ApiError::NotFound)?;
    let path = PathBuf::from(&model.storage_path);
    let extracted = extract_text(state, &path, &model.media_type).await;
    match extracted {
        Ok(text) if !text.trim().is_empty() => {
            match index_document_text(state, model.clone(), text).await {
                Ok(()) => Ok(()),
                Err(error) => {
                    set_document_error(&state.db, model, &error.to_string()).await?;
                    Err(error)
                }
            }
        }
        Ok(_) => set_document_error(&state.db, model, "未提取到可用文字").await,
        Err(error) => set_document_error(&state.db, model, &error.to_string()).await,
    }
}

pub async fn mark_document_failed(
    state: &AppState,
    document_id: &str,
    message: &str,
) -> ApiResult<()> {
    if let Some(model) = document::Entity::find_by_id(document_id)
        .one(&state.db)
        .await?
    {
        set_document_error(&state.db, model, message).await?;
    }
    Ok(())
}

pub async fn reindex_document_text(
    state: &AppState,
    document_id: &str,
    text: String,
) -> ApiResult<()> {
    let model = document::Entity::find_by_id(document_id)
        .one(&state.db)
        .await?
        .ok_or(ApiError::NotFound)?;
    index_document_text(state, model, text).await
}

async fn index_document_text(
    state: &AppState,
    model: document::Model,
    text: String,
) -> ApiResult<()> {
    let text = text.trim().to_owned();
    if text.is_empty() {
        return Err(ApiError::BadRequest(
            "document contains no extractable text".into(),
        ));
    }
    let chunks = chunk_text(&text, 800, 100);
    let embeddings = if state.ai.is_embedding_configured() {
        state.ai.embeddings(&chunks).await?
    } else {
        vec![Vec::new(); chunks.len()]
    };
    document_chunk::Entity::delete_many()
        .filter(document_chunk::Column::DocumentId.eq(&model.id))
        .exec(&state.db)
        .await?;
    for (ordinal, (content, embedding)) in chunks.into_iter().zip(embeddings).enumerate() {
        document_chunk::ActiveModel {
            id: Set(Uuid::new_v4().to_string()),
            document_id: Set(model.id.clone()),
            project_id: Set(model.project_id.clone()),
            ordinal: Set(ordinal as i32),
            content: Set(content),
            embedding: Set((!embedding.is_empty()).then(|| json!(embedding))),
        }
        .insert(&state.db)
        .await?;
    }
    let mut active: document::ActiveModel = model.into();
    active.status = Set("ready".into());
    active.extracted_text = Set(Some(text));
    active.error = Set(None);
    active.update(&state.db).await?;
    Ok(())
}

async fn set_document_error(
    db: &DatabaseConnection,
    model: document::Model,
    message: &str,
) -> ApiResult<()> {
    let mut active: document::ActiveModel = model.into();
    active.status = Set("failed".into());
    active.error = Set(Some(message.chars().take(1000).collect()));
    active.update(db).await?;
    Ok(())
}

async fn extract_text(state: &AppState, path: &Path, media_type: &str) -> ApiResult<String> {
    if media_type.starts_with("text/") {
        return Ok(tokio::fs::read_to_string(path).await?);
    }
    if media_type.starts_with("image/") {
        return extract_image_text(state, path, media_type).await;
    }
    if media_type == "application/pdf" {
        return extract_pdf_with_ocr_fallback(state, path).await;
    }
    if matches!(
        media_type,
        "application/vnd.openxmlformats-officedocument.wordprocessingml.document"
            | "application/vnd.openxmlformats-officedocument.presentationml.presentation"
    ) {
        let temp_dir = state
            .config
            .storage_dir
            .join("tmp")
            .join(Uuid::new_v4().to_string());
        tokio::fs::create_dir_all(&temp_dir).await?;
        let libreoffice = std::env::var("LIBREOFFICE_BIN").unwrap_or_else(|_| "libreoffice".into());
        let output = Command::new(libreoffice)
            .args(["--headless", "--convert-to", "pdf", "--outdir"])
            .arg(&temp_dir)
            .arg(path)
            .stdout(Stdio::null())
            .stderr(Stdio::piped())
            .output()
            .await?;
        if !output.status.success() {
            let _ = tokio::fs::remove_dir_all(&temp_dir).await;
            return Err(ApiError::Internal(format!(
                "document conversion failed: {}",
                String::from_utf8_lossy(&output.stderr)
            )));
        }
        let pdf = match first_file_with_extension(&temp_dir, "pdf").await {
            Ok(Some(pdf)) => pdf,
            Ok(None) => {
                let _ = tokio::fs::remove_dir_all(&temp_dir).await;
                return Err(ApiError::Internal(
                    "document conversion produced no PDF".into(),
                ));
            }
            Err(error) => {
                let _ = tokio::fs::remove_dir_all(&temp_dir).await;
                return Err(error);
            }
        };
        let result = extract_pdf_with_ocr_fallback(state, &pdf).await;
        let _ = tokio::fs::remove_dir_all(temp_dir).await;
        return result;
    }
    Err(ApiError::BadRequest(format!(
        "unsupported media type: {media_type}"
    )))
}

async fn extract_pdf_with_ocr_fallback(state: &AppState, path: &Path) -> ApiResult<String> {
    let pdftotext = std::env::var("PDFTOTEXT_BIN").unwrap_or_else(|_| "pdftotext".into());
    let output = Command::new(pdftotext)
        .args(["-layout"])
        .arg(path)
        .arg("-")
        .output()
        .await;
    if let Ok(output) = output {
        let text = String::from_utf8_lossy(&output.stdout).trim().to_owned();
        if output.status.success() && text.chars().count() >= 20 {
            return Ok(text);
        }
    }
    let temp_dir = state
        .config
        .storage_dir
        .join("tmp")
        .join(Uuid::new_v4().to_string());
    tokio::fs::create_dir_all(&temp_dir).await?;
    let prefix = temp_dir.join("page");
    let pdftoppm = std::env::var("PDFTOPPM_BIN").unwrap_or_else(|_| "pdftoppm".into());
    let status = Command::new(pdftoppm)
        .args(["-png", "-r", "160"])
        .arg(path)
        .arg(&prefix)
        .status()
        .await;
    let status = match status {
        Ok(status) => status,
        Err(error) => {
            let _ = tokio::fs::remove_dir_all(&temp_dir).await;
            return Err(error.into());
        }
    };
    if !status.success() {
        let _ = tokio::fs::remove_dir_all(&temp_dir).await;
        return Err(ApiError::Internal("PDF rendering for OCR failed".into()));
    }
    let mut pages = Vec::new();
    let mut entries = tokio::fs::read_dir(&temp_dir).await?;
    while let Some(entry) = entries.next_entry().await? {
        if entry.path().extension().and_then(|v| v.to_str()) == Some("png") {
            pages.push(entry.path());
        }
    }
    pages.sort();
    let mut result = String::new();
    for page in pages {
        let page_text = extract_image_text(state, &page, "image/png").await;
        let page_text = match page_text {
            Ok(text) => text,
            Err(error) => {
                let _ = tokio::fs::remove_dir_all(&temp_dir).await;
                return Err(error);
            }
        };
        result.push_str(&page_text);
        result.push_str("\n\n");
    }
    let _ = tokio::fs::remove_dir_all(temp_dir).await;
    Ok(result)
}

async fn extract_image_text(state: &AppState, path: &Path, media_type: &str) -> ApiResult<String> {
    if state.ai.is_ocr_configured() {
        return state.ai.ocr_image(path, media_type).await;
    }
    let tesseract = std::env::var("TESSERACT_BIN").unwrap_or_else(|_| "tesseract".into());
    let languages = std::env::var("TESSERACT_LANG").unwrap_or_else(|_| "chi_sim+eng".into());
    // Leptonica on macOS cannot open paths through the /tmp -> /private/tmp symlink.
    let canonical_path = tokio::fs::canonicalize(path).await?;
    let output = Command::new(tesseract)
        .arg(canonical_path)
        .arg("stdout")
        .args(["-l", &languages])
        .output()
        .await
        .map_err(|error| {
            ApiError::Internal(format!(
                "OCR is not configured and local Tesseract could not start: {error}"
            ))
        })?;
    if !output.status.success() {
        return Err(ApiError::Internal(format!(
            "local OCR failed: {}",
            String::from_utf8_lossy(&output.stderr).trim()
        )));
    }
    Ok(String::from_utf8_lossy(&output.stdout).trim().to_owned())
}

async fn first_file_with_extension(root: &Path, extension: &str) -> ApiResult<Option<PathBuf>> {
    let mut entries = tokio::fs::read_dir(root).await?;
    while let Some(entry) = entries.next_entry().await? {
        let path = entry.path();
        if path
            .extension()
            .and_then(|value| value.to_str())
            .is_some_and(|value| value.eq_ignore_ascii_case(extension))
        {
            return Ok(Some(path));
        }
    }
    Ok(None)
}

pub fn chunk_text(text: &str, max_chars: usize, overlap: usize) -> Vec<String> {
    let chars: Vec<char> = text.chars().collect();
    if chars.is_empty() {
        return Vec::new();
    }
    let mut chunks = Vec::new();
    let mut start = 0;
    while start < chars.len() {
        let mut end = (start + max_chars).min(chars.len());
        if end < chars.len() {
            if let Some(relative) = chars[start..end]
                .iter()
                .rposition(|c| matches!(c, '。' | '！' | '？' | '\n'))
            {
                end = start + relative + 1;
            }
        }
        if end <= start {
            end = (start + max_chars).min(chars.len());
        }
        chunks.push(
            chars[start..end]
                .iter()
                .collect::<String>()
                .trim()
                .to_owned(),
        );
        if end == chars.len() {
            break;
        }
        start = end.saturating_sub(overlap).max(start + 1);
    }
    chunks
        .into_iter()
        .filter(|chunk| !chunk.is_empty())
        .collect()
}

pub async fn retrieve_chunks(
    state: &AppState,
    project_id: &str,
    query: &str,
    limit: usize,
) -> ApiResult<Vec<document_chunk::Model>> {
    let chunks = document_chunk::Entity::find()
        .filter(document_chunk::Column::ProjectId.eq(project_id))
        .order_by_asc(document_chunk::Column::Ordinal)
        .all(&state.db)
        .await?;
    if chunks.is_empty() {
        return Ok(Vec::new());
    }
    if !state.ai.is_embedding_configured() {
        return Ok(chunks.into_iter().take(limit).collect());
    }
    let query_embedding = state
        .ai
        .embeddings(&[query.to_owned()])
        .await?
        .into_iter()
        .next()
        .unwrap_or_default();
    let mut scored: Vec<(f32, document_chunk::Model)> = chunks
        .into_iter()
        .map(|chunk| {
            let embedding: Vec<f32> = chunk
                .embedding
                .as_ref()
                .and_then(|value| serde_json::from_value(value.clone()).ok())
                .unwrap_or_default();
            (cosine_similarity(&query_embedding, &embedding), chunk)
        })
        .collect();
    scored.sort_by(|a, b| b.0.total_cmp(&a.0));
    Ok(scored
        .into_iter()
        .take(limit)
        .map(|(_, chunk)| chunk)
        .collect())
}

pub fn verified_evidence(
    value: Option<&Value>,
    chunks: &[document_chunk::Model],
) -> Vec<EvidenceRef> {
    let Some(items) = value.and_then(Value::as_array) else {
        return Vec::new();
    };
    let mut seen = HashSet::new();
    items
        .iter()
        .filter_map(|item| serde_json::from_value::<EvidenceRef>(item.clone()).ok())
        .filter_map(|evidence| {
            let quote = evidence.quote.trim();
            let chunk = chunks.iter().find(|chunk| chunk.id == evidence.chunk_id)?;
            if quote.is_empty() || !chunk.content.contains(quote) {
                return None;
            }
            let key = (evidence.chunk_id.clone(), quote.to_owned());
            seen.insert(key.clone()).then(|| EvidenceRef {
                chunk_id: key.0,
                quote: key.1,
            })
        })
        .collect()
}

async fn qa_dimension(state: &AppState, session_id: &str) -> ApiResult<DimensionReport> {
    let answers = jury_answer::Entity::find()
        .filter(jury_answer::Column::SessionId.eq(session_id))
        .all(&state.db)
        .await?;
    let mut scores = Vec::new();
    let mut evidence = Vec::new();
    for answer in &answers {
        if let Some(score) = answer.evaluation_json.get("score").and_then(Value::as_i64) {
            scores.push(score.clamp(0, 100) as i32);
        }
        if let Some(items) = answer
            .evaluation_json
            .get("evidence")
            .and_then(Value::as_array)
        {
            evidence.extend(
                items
                    .iter()
                    .filter_map(|item| serde_json::from_value(item.clone()).ok()),
            );
        }
    }
    let score = (!scores.is_empty())
        .then(|| scores.iter().sum::<i32>() / i32::try_from(scores.len()).unwrap_or(1));
    Ok(DimensionReport {
        score,
        summary: score.map_or_else(
            || "尚未完成AI评委问答，本维度不评分。".into(),
            |value| format!("已评价{}个回答，平均得分{}。", scores.len(), value),
        ),
        evidence,
    })
}

pub async fn refresh_report_qa(state: &AppState, session_id: &str) -> ApiResult<()> {
    let Some(model) = report::Entity::find()
        .filter(report::Column::SessionId.eq(session_id))
        .one(&state.db)
        .await?
    else {
        return Ok(());
    };
    let mut payload: ReportPayload = serde_json::from_value(model.report_json.clone())?;
    payload.qa = qa_dimension(state, session_id).await?;
    let mut active: report::ActiveModel = model.into();
    active.report_json = Set(serde_json::to_value(payload)?);
    active.update(&state.db).await?;
    Ok(())
}

fn cosine_similarity(left: &[f32], right: &[f32]) -> f32 {
    if left.is_empty() || left.len() != right.len() {
        return 0.0;
    }
    let dot: f32 = left.iter().zip(right).map(|(a, b)| a * b).sum();
    let left_norm = left.iter().map(|v| v * v).sum::<f32>().sqrt();
    let right_norm = right.iter().map(|v| v * v).sum::<f32>().sqrt();
    if left_norm == 0.0 || right_norm == 0.0 {
        0.0
    } else {
        dot / (left_norm * right_norm)
    }
}

pub async fn generate_report(state: &AppState, session_id: &str) -> ApiResult<report::Model> {
    let session = rehearsal_session::Entity::find_by_id(session_id)
        .one(&state.db)
        .await?
        .ok_or(ApiError::NotFound)?;
    let transcript = session
        .transcript
        .clone()
        .filter(|v| !v.trim().is_empty())
        .ok_or_else(|| ApiError::BadRequest("session does not contain a transcript".into()))?;
    let actual_seconds = session
        .actual_seconds
        .unwrap_or(session.target_seconds)
        .max(1);
    let character_count = transcript.chars().filter(|c| !c.is_whitespace()).count();
    let characters_per_minute = character_count as f64 * 60.0 / actual_seconds as f64;
    let filler_counts = count_fillers(&transcript);
    let metrics = session_metric::Entity::find()
        .filter(session_metric::Column::SessionId.eq(session_id))
        .order_by_asc(session_metric::Column::TimestampMs)
        .all(&state.db)
        .await?;
    let visible: Vec<_> = metrics.iter().filter(|m| m.face_detected).collect();
    let gaze = average(visible.iter().map(|m| m.gaze_centered));
    let posture = average(visible.iter().map(|m| m.posture_score));
    let face_ratio = if metrics.is_empty() {
        0.0
    } else {
        visible.len() as f64 / metrics.len() as f64
    };

    let chunks = retrieve_chunks(state, &session.project_id, &transcript, 10).await?;
    let material = chunks
        .iter()
        .map(|chunk| format!("[{}] {}", chunk.id, chunk.content))
        .collect::<Vec<_>>()
        .join("\n");
    let prompt = format!(
        "项目材料：\n{material}\n\n答辩转写：\n{transcript}\n\n请只返回JSON，字段为score(0-100整数)、summary、evidence数组（每项含chunk_id和quote）、suggestions数组、confidence(0-1)。评价答辩是否准确覆盖项目背景、方案、创新点、验证与局限；证据必须引用给出的材料编号，不能编造。"
    );
    let content_json = state
        .ai
        .chat_json(
            "你是严谨的大学生计算机应用大赛答辩评委，只评价可由材料验证的内容。",
            &prompt,
        )
        .await?;
    let evidence = verified_evidence(content_json.get("evidence"), &chunks);
    if evidence.is_empty() {
        return Err(ApiError::Internal(
            "AI content evaluation did not contain verifiable material evidence".into(),
        ));
    }
    let content = DimensionReport {
        score: Some(
            content_json
                .get("score")
                .and_then(Value::as_i64)
                .unwrap_or(0)
                .clamp(0, 100) as i32,
        ),
        summary: content_json
            .get("summary")
            .and_then(Value::as_str)
            .unwrap_or("未生成内容总结")
            .to_owned(),
        evidence,
    };

    let filler_total: usize = filler_counts.values().sum();
    let delivery_score = (100.0 - filler_total as f64 * 3.0 - speed_penalty(characters_per_minute))
        .round()
        .clamp(0.0, 100.0) as i32;
    let duration_delta = (actual_seconds - session.target_seconds).unsigned_abs() as f64;
    let timing_score = (100.0 - duration_delta / session.target_seconds.max(1) as f64 * 100.0)
        .round()
        .clamp(0.0, 100.0) as i32;
    let visual_score = ((gaze * 0.45 + posture * 0.35 + face_ratio * 0.2) * 100.0)
        .round()
        .clamp(0.0, 100.0) as i32;
    let mut timeline = Vec::new();
    for metric in &metrics {
        if !metric.face_detected {
            timeline.push(TimelineIssue {
                timestamp_ms: metric.timestamp_ms,
                kind: "framing".into(),
                message: "人物短暂离开画面".into(),
            });
        } else if metric.gaze_centered < 0.45 {
            timeline.push(TimelineIssue {
                timestamp_ms: metric.timestamp_ms,
                kind: "gaze".into(),
                message: "视线明显偏离镜头".into(),
            });
        } else if metric.posture_score < 0.5 {
            timeline.push(TimelineIssue {
                timestamp_ms: metric.timestamp_ms,
                kind: "posture".into(),
                message: "姿态稳定性下降".into(),
            });
        }
    }
    timeline.truncate(20);
    let mut suggestions: Vec<String> = content_json
        .get("suggestions")
        .cloned()
        .and_then(|value| serde_json::from_value(value).ok())
        .unwrap_or_default();
    if characters_per_minute < 180.0 {
        suggestions.push("语速偏慢，可缩短铺垫并提高信息密度。".into());
    }
    if characters_per_minute > 260.0 {
        suggestions.push("语速偏快，应在技术要点和数据结论后留出停顿。".into());
    }
    if filler_total > 5 {
        suggestions.push("口头禅较多，可用短暂停顿替代重复连接词。".into());
    }

    let payload = ReportPayload {
        session_id: session.id.clone(),
        actual_seconds,
        character_count,
        characters_per_minute,
        filler_counts,
        long_pause_count: None,
        content,
        delivery: DimensionReport {
            score: Some(delivery_score),
            summary: format!(
                "平均语速{characters_per_minute:.0}字/分钟，检测到{filler_total}次口头禅。"
            ),
            evidence: Vec::new(),
        },
        timing: DimensionReport {
            score: Some(timing_score),
            summary: format!(
                "目标{}秒，实际{}秒。",
                session.target_seconds, actual_seconds
            ),
            evidence: Vec::new(),
        },
        visual: DimensionReport {
            score: (!metrics.is_empty()).then_some(visual_score),
            summary: if metrics.is_empty() {
                "未采集端侧视觉样本，本维度不评分。".into()
            } else {
                format!(
                    "居中视线比例{:.0}%，姿态稳定度{:.0}%，有效出镜率{:.0}%。",
                    gaze * 100.0,
                    posture * 100.0,
                    face_ratio * 100.0
                )
            },
            evidence: Vec::new(),
        },
        qa: qa_dimension(state, session_id).await?,
        timeline,
        suggestions,
        model_confidence: content_json.get("confidence").and_then(Value::as_f64),
    };
    if let Some(existing) = report::Entity::find()
        .filter(report::Column::SessionId.eq(session_id))
        .one(&state.db)
        .await?
    {
        existing.delete(&state.db).await?;
    }
    let created = report::ActiveModel {
        id: Set(Uuid::new_v4().to_string()),
        session_id: Set(session.id),
        report_json: Set(serde_json::to_value(payload)?),
        created_at: Set(Utc::now()),
    }
    .insert(&state.db)
    .await?;
    Ok(created)
}

fn count_fillers(transcript: &str) -> BTreeMap<String, usize> {
    ["然后", "就是", "那个", "其实", "嗯", "啊"]
        .into_iter()
        .filter_map(|word| {
            let count = transcript.matches(word).count();
            (count > 0).then(|| (word.to_owned(), count))
        })
        .collect()
}

fn speed_penalty(cpm: f64) -> f64 {
    if cpm < 180.0 {
        (180.0 - cpm) * 0.25
    } else if cpm > 260.0 {
        (cpm - 260.0) * 0.25
    } else {
        0.0
    }
}

fn average(values: impl Iterator<Item = f64>) -> f64 {
    let values: Vec<f64> = values.collect();
    if values.is_empty() {
        0.0
    } else {
        values.iter().sum::<f64>() / values.len() as f64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chunks_keep_overlap_and_content() {
        let input = "第一段。第二段很长。第三段。".repeat(100);
        let chunks = chunk_text(&input, 80, 10);
        assert!(chunks.len() > 2);
        assert!(chunks.iter().all(|chunk| chunk.chars().count() <= 80));
        assert!(chunks.iter().all(|chunk| !chunk.is_empty()));
    }

    #[test]
    fn filler_count_is_explainable() {
        let counts = count_fillers("嗯，然后就是这样，然后结束");
        assert_eq!(counts.get("然后"), Some(&2));
        assert_eq!(counts.get("就是"), Some(&1));
    }

    #[test]
    fn evidence_must_match_the_current_chunk_verbatim() {
        let chunks = vec![document_chunk::Model {
            id: "chunk-1".into(),
            document_id: "document-1".into(),
            project_id: "project-1".into(),
            ordinal: 0,
            content: "系统采用端云协同架构，原始视频不上传。".into(),
            embedding: None,
        }];
        let raw = json!([
            {"chunk_id":"chunk-1","quote":"端云协同架构"},
            {"chunk_id":"chunk-1","quote":"并不存在的结论"},
            {"chunk_id":"other-project","quote":"端云协同架构"}
        ]);

        let evidence = verified_evidence(Some(&raw), &chunks);
        assert_eq!(evidence.len(), 1);
        assert_eq!(evidence[0].chunk_id, "chunk-1");
        assert_eq!(evidence[0].quote, "端云协同架构");
    }
}
