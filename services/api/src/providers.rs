use std::path::Path;

use base64::{Engine, engine::general_purpose::STANDARD};
use reqwest::multipart::{Form, Part};
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
        let provider = &self.config.llm;
        let response = self
            .http
            .post(self.endpoint(provider, "chat/completions"))
            .bearer_auth(self.api_key(provider)?)
            .json(&json!({
                "model": provider.model,
                "temperature": 0.2,
                "response_format": {"type": "json_object"},
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": user}
                ]
            }))
            .send()
            .await
            .map_err(internal)?;
        let body = checked_json(response).await?;
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
        let part = Part::bytes(bytes).file_name(filename.to_owned());
        let form = Form::new()
            .text("model", provider.model.clone())
            .text("language", "zh")
            .part("file", part);
        let response = self
            .http
            .post(self.endpoint(provider, "audio/transcriptions"))
            .bearer_auth(self.api_key(provider)?)
            .multipart(form)
            .send()
            .await
            .map_err(internal)?;
        let body = checked_json(response).await?;
        body.get("text")
            .and_then(Value::as_str)
            .map(str::to_owned)
            .ok_or_else(|| ApiError::Internal("ASR response did not contain text".into()))
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
            .map(str::to_owned)
            .ok_or_else(|| ApiError::Internal("OCR response did not contain text".into()))
    }
}

fn internal(error: reqwest::Error) -> ApiError {
    ApiError::Internal(format!("AI provider request failed: {error}"))
}

async fn checked_json(response: reqwest::Response) -> ApiResult<Value> {
    let status = response.status();
    let text = response.text().await.map_err(internal)?;
    if !status.is_success() {
        return Err(ApiError::Internal(format!(
            "AI provider returned {status}: {text}"
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
