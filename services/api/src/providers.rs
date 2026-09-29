use std::path::Path;

use base64::{Engine, engine::general_purpose::STANDARD};
use reqwest::StatusCode;
use serde_json::{Value, json};

use crate::{
    config::{AiConfig, ProviderConfig},
    error::{ApiError, ApiResult},
};

#[derive(Clone)]
pub struct AiClient {
    http: reqwest::Client,
    config: AiConfig,
}

impl AiClient {
    pub fn new(config: AiConfig) -> Self {
        Self {
            http: reqwest::Client::builder()
                .timeout(std::time::Duration::from_secs(90))
                .build()
                .expect("HTTP client configuration"),
            config,
        }
    }

    pub fn is_llm_configured(&self) -> bool {
        self.config.llm.is_configured()
    }

    pub fn is_embedding_configured(&self) -> bool {
        self.config.embedding.is_configured()
    }

    pub fn is_asr_configured(&self) -> bool {
        self.config.asr.is_configured()
    }

    pub fn is_ocr_configured(&self) -> bool {
        self.config.ocr.is_configured()
    }

    pub fn is_fully_configured(&self) -> bool {
        self.is_llm_configured()
            && self.is_embedding_configured()
            && self.is_asr_configured()
            && self.is_ocr_configured()
    }

    fn api_key<'a>(&self, provider: &'a ProviderConfig) -> ApiResult<&'a str> {
        provider.api_key.as_deref().ok_or(ApiError::AiNotConfigured)
    }

    fn endpoint(&self, provider: &ProviderConfig, suffix: &str) -> String {
        format!("{}/{}", provider.base_url.trim_end_matches('/'), suffix)
    }

    pub async fn chat_json(&self, system: &str, user: &str) -> ApiResult<Value> {
        self.chat_json_with_budget(system, user, std::time::Duration::from_secs(22), 2)
            .await
    }

    pub async fn chat_json_fast(&self, system: &str, user: &str) -> ApiResult<Value> {
        self.chat_json_with_budget(system, user, std::time::Duration::from_secs(12), 1)
            .await
    }

    async fn chat_json_with_budget(
        &self,
        system: &str,
        user: &str,
        timeout: std::time::Duration,
        attempts: u32,
    ) -> ApiResult<Value> {
        let provider = &self.config.llm;
        let request_body = json!({
            "model": provider.model,
            "temperature": 0.2,
            "response_format": {"type": "json_object"},
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user}
            ]
        });
        let mut attempt = 0_u32;
        let body = loop {
            attempt += 1;
            let response = self
                .http
                .post(self.endpoint(provider, "chat/completions"))
                .timeout(timeout)
                .bearer_auth(self.api_key(provider)?)
                .json(&request_body)
                .send()
                .await;
            match response {
                Ok(response) if retryable_status(response.status()) && attempt < attempts => {
                    tracing::warn!(attempt, status = %response.status(), "retrying AI chat request");
                }
                Ok(response) => break checked_json(response).await?,
                Err(error) if attempt < attempts => {
                    tracing::warn!(attempt, error = %error, "retrying AI chat request");
                }
                Err(error) => return Err(internal(error)),
            }
            tokio::time::sleep(std::time::Duration::from_millis(350 * u64::from(attempt))).await;
        };
        let content = body
            .pointer("/choices/0/message/content")
            .and_then(Value::as_str)
            .ok_or_else(|| {
                ApiError::Internal("AI response did not contain message content".into())
            })?;
        parse_json_content(content)
    }

    pub async fn embeddings(&self, inputs: &[String]) -> ApiResult<Vec<Vec<f32>>> {
        if inputs.is_empty() {
            return Ok(Vec::new());
        }
        let provider = &self.config.embedding;
        let response = self
            .http
            .post(self.endpoint(provider, "embeddings"))
            .bearer_auth(self.api_key(provider)?)
            .json(&json!({"model": provider.model, "input": inputs}))
            .send()
            .await
            .map_err(internal)?;
        let body = checked_json(response).await?;
        let data = body
            .get("data")
            .and_then(Value::as_array)
            .ok_or_else(|| ApiError::Internal("embedding response did not contain data".into()))?;
        let mut embeddings = Vec::with_capacity(data.len());
        for item in data {
            let values = item
                .get("embedding")
                .and_then(Value::as_array)
                .ok_or_else(|| ApiError::Internal("embedding item is malformed".into()))?;
            embeddings.push(
                values
                    .iter()
                    .map(|v| v.as_f64().unwrap_or_default() as f32)
                    .collect(),
            );
        }
        Ok(embeddings)
    }

    pub async fn transcribe_audio(&self, path: &Path, filename: &str) -> ApiResult<String> {
        let provider = &self.config.asr;
        let bytes = tokio::fs::read(path).await?;
        let (media_type, format) = audio_input_metadata(&bytes, filename)?;
        let data_url = format!("data:{media_type};base64,{}", STANDARD.encode(bytes));
        let response = self
            .http
            .post(self.endpoint(provider, "chat/completions"))
            .bearer_auth(self.api_key(provider)?)
            .json(&json!({
                "model": provider.model,
                "messages": [{
                    "role": "user",
                    "content": [{
                        "type": "input_audio",
                        "input_audio": {"data": data_url, "format": format}
                    }]
                }]
            }))
            .send()
            .await
            .map_err(internal)?;
        let body = checked_json(response).await?;
        extract_transcript(&body).ok_or_else(|| {
            tracing::warn!(
                response_shape = %json_shape(&body, 0),
                "ASR response did not contain transcript text"
            );
            ApiError::BadRequest("未识别到有效语音，请重新录制并确认麦克风权限正常".into())
        })
    }

    pub async fn ocr_image(&self, path: &Path, media_type: &str) -> ApiResult<String> {
        let provider = &self.config.ocr;
        let bytes = tokio::fs::read(path).await?;
        let data_url = format!("data:{media_type};base64,{}", STANDARD.encode(bytes));
        let response = self.http
            .post(self.endpoint(provider, "chat/completions"))
            .bearer_auth(self.api_key(provider)?)
            .json(&json!({
                "model": provider.model,
                "temperature": 0,
                "messages": [{
                    "role": "user",
                    "content": [
                        {"type": "text", "text": "请逐行提取图片中的全部文字，只返回纯文本，不要解释。"},
                        {"type": "image_url", "image_url": {"url": data_url}}
                    ]
                }]
            }))
            .send().await.map_err(internal)?;
        let body = checked_json(response).await?;
        body.pointer("/choices/0/message/content")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|text| !text.is_empty())
            .map(str::to_owned)
            .ok_or_else(|| ApiError::Internal("OCR response did not contain text".into()))
    }
}

fn retryable_status(status: StatusCode) -> bool {
    matches!(
        status,
        StatusCode::REQUEST_TIMEOUT
            | StatusCode::TOO_EARLY
            | StatusCode::TOO_MANY_REQUESTS
            | StatusCode::INTERNAL_SERVER_ERROR
            | StatusCode::BAD_GATEWAY
            | StatusCode::SERVICE_UNAVAILABLE
            | StatusCode::GATEWAY_TIMEOUT
    )
}

fn audio_input_metadata(bytes: &[u8], filename: &str) -> ApiResult<(&'static str, &'static str)> {
    if bytes.len() >= 12 && bytes.starts_with(b"RIFF") && &bytes[8..12] == b"WAVE" {
        return Ok(("audio/wav", "wav"));
    }
    if bytes.len() >= 8 && &bytes[4..8] == b"ftyp" {
        return Ok(("audio/mp4", "m4a"));
    }
    if bytes.starts_with(b"ID3")
        || (bytes.len() >= 2 && bytes[0] == 0xff && bytes[1] & 0xe0 == 0xe0)
    {
        let extension = Path::new(filename)
            .extension()
            .and_then(|value| value.to_str())
            .unwrap_or_default();
        return if extension.eq_ignore_ascii_case("aac") {
            Ok(("audio/aac", "aac"))
        } else {
            Ok(("audio/mpeg", "mp3"))
        };
    }
    if bytes.starts_with(b"fLaC") {
        return Ok(("audio/flac", "flac"));
    }
    if bytes.starts_with(b"OggS") {
        return Ok(("audio/ogg", "ogg"));
    }
    Err(ApiError::BadRequest(
        "audio must be a WAV, M4A, MP3, AAC, FLAC, or OGG file".into(),
    ))
}

fn internal(error: reqwest::Error) -> ApiError {
    ApiError::Internal(format!("AI provider request failed: {error}"))
}

async fn checked_json(response: reqwest::Response) -> ApiResult<Value> {
    let status = response.status();
    let bytes = response.bytes().await.map_err(internal)?;
    // Some compatible OpenAI endpoints occasionally include an invalid byte in
    // reasoning_content. Lossy decoding still preserves the JSON envelope and
    // lets the caller use the structured answer instead of falling back.
    let text = String::from_utf8_lossy(&bytes);
    if !status.is_success() {
        return Err(ApiError::Internal(format!(
            "AI provider returned {status}: {}",
            text.chars().take(2000).collect::<String>()
        )));
    }
    serde_json::from_str(&text).map_err(ApiError::from)
}

fn parse_json_content(content: &str) -> ApiResult<Value> {
    let trimmed = content.trim();
    let without_fence = trimmed
        .strip_prefix("```json")
        .or_else(|| trimmed.strip_prefix("```"))
        .unwrap_or(trimmed)
        .strip_suffix("```")
        .unwrap_or(trimmed)
        .trim();
    serde_json::from_str(without_fence).map_err(ApiError::from)
}

fn extract_transcript(body: &Value) -> Option<String> {
    const PATHS: [&str; 8] = [
        "/choices/0/message/audio/transcript",
        "/choices/0/message/transcript",
        "/choices/0/message/content",
        "/choices/0/text",
        "/output/transcript",
        "/output/text",
        "/transcript",
        "/text",
    ];

    PATHS
        .iter()
        .filter_map(|path| body.pointer(path))
        .find_map(transcript_from_value)
}

fn transcript_from_value(value: &Value) -> Option<String> {
    match value {
        Value::String(text) => non_empty_text(text),
        Value::Array(items) => {
            let text = items
                .iter()
                .filter_map(transcript_from_content_item)
                .collect::<Vec<_>>()
                .join("\n");
            non_empty_text(&text)
        }
        Value::Object(_) => transcript_from_content_item(value),
        _ => None,
    }
}

fn transcript_from_content_item(value: &Value) -> Option<String> {
    if let Some(text) = value.as_str() {
        return non_empty_text(text);
    }
    ["transcript", "text", "content"]
        .iter()
        .filter_map(|key| value.get(key))
        .find_map(transcript_from_value)
}

fn non_empty_text(text: &str) -> Option<String> {
    let text = text.trim();
    (!text.is_empty()).then(|| text.to_owned())
}

fn json_shape(value: &Value, depth: usize) -> Value {
    if depth >= 5 {
        return Value::String("...".into());
    }
    match value {
        Value::Object(object) => Value::Object(
            object
                .iter()
                .map(|(key, value)| (key.clone(), json_shape(value, depth + 1)))
                .collect(),
        ),
        Value::Array(items) => json!({
            "type": "array",
            "length": items.len(),
            "item": items.first().map(|item| json_shape(item, depth + 1))
        }),
        Value::Null => Value::String("null".into()),
        Value::Bool(_) => Value::String("boolean".into()),
        Value::Number(_) => Value::String("number".into()),
        Value::String(_) => Value::String("string".into()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn detects_audio_container_from_bytes() {
        let wav = b"RIFF\x00\x00\x00\x00WAVEfmt ";
        let m4a = b"\x00\x00\x00\x18ftypM4A \x00\x00\x00\x00";
        let mp3 = b"ID3\x04\x00\x00";

        assert_eq!(
            audio_input_metadata(wav, "wrong.m4a").unwrap(),
            ("audio/wav", "wav")
        );
        assert_eq!(
            audio_input_metadata(m4a, "audio.m4a").unwrap(),
            ("audio/mp4", "m4a")
        );
        assert_eq!(
            audio_input_metadata(mp3, "audio.mp3").unwrap(),
            ("audio/mpeg", "mp3")
        );
        assert!(audio_input_metadata(b"plain text", "audio.m4a").is_err());
    }

    #[test]
    fn parses_json_with_or_without_markdown_fence() {
        assert_eq!(
            parse_json_content("{\"ok\":true}").unwrap(),
            json!({"ok": true})
        );
        assert_eq!(
            parse_json_content("```json\n{\"ok\":true}\n```").unwrap(),
            json!({"ok": true})
        );
    }

    #[test]
    fn retries_only_transient_provider_statuses() {
        assert!(retryable_status(StatusCode::BAD_GATEWAY));
        assert!(retryable_status(StatusCode::TOO_MANY_REQUESTS));
        assert!(!retryable_status(StatusCode::BAD_REQUEST));
        assert!(!retryable_status(StatusCode::UNAUTHORIZED));
    }

    #[test]
    fn extracts_transcript_from_string_content() {
        let body = json!({
            "choices": [{"message": {"content": "  这是转写文本。  "}}]
        });

        assert_eq!(extract_transcript(&body).as_deref(), Some("这是转写文本。"));
    }

    #[test]
    fn extracts_transcript_from_content_items() {
        let body = json!({
            "choices": [{
                "message": {
                    "content": [
                        {"type": "text", "text": "第一段"},
                        {"type": "transcript", "transcript": "第二段"}
                    ]
                }
            }]
        });

        assert_eq!(extract_transcript(&body).as_deref(), Some("第一段\n第二段"));
    }

    #[test]
    fn extracts_transcript_from_audio_object() {
        let body = json!({
            "choices": [{
                "message": {
                    "content": null,
                    "audio": {"id": "audio-1", "transcript": "语音对象中的转写"}
                }
            }]
        });

        assert_eq!(
            extract_transcript(&body).as_deref(),
            Some("语音对象中的转写")
        );
    }

    #[test]
    fn extracts_transcript_from_top_level_output() {
        assert_eq!(
            extract_transcript(&json!({"output": {"text": "输出文本"}})).as_deref(),
            Some("输出文本")
        );
        assert!(extract_transcript(&json!({"choices": []})).is_none());
    }
}
