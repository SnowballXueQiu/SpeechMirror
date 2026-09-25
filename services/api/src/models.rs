use std::collections::BTreeMap;

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use utoipa::ToSchema;

#[derive(Debug, Serialize, ToSchema)]
pub struct HealthResponse {
    pub status: &'static str,
    pub ai_configured: bool,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RegisterRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct LoginRequest {
    pub username: String,
    pub password: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct RefreshRequest {
    pub refresh_token: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct LogoutRequest {
    pub refresh_token: String,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct TokenPair {
    pub access_token: String,
    pub refresh_token: String,
    pub token_type: &'static str,
    pub expires_in: i64,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateProjectRequest {
    pub name: String,
    pub description: Option<String>,
    #[serde(default = "default_duration")]
    pub defense_duration_seconds: i32,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct UpdateProjectRequest {
    pub name: Option<String>,
    pub description: Option<String>,
    pub defense_duration_seconds: Option<i32>,
}

fn default_duration() -> i32 {
    300
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct ProjectResponse {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub defense_duration_seconds: i32,
    pub created_at: DateTime<Utc>,
    pub updated_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct DocumentResponse {
    pub id: String,
    pub project_id: String,
    pub filename: String,
    pub media_type: String,
    pub status: String,
    pub extracted_text: Option<String>,
    pub error: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CorrectDocumentRequest {
    pub text: String,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CreateSessionRequest {
    pub title: Option<String>,
    pub target_seconds: Option<i32>,
    pub local_video_ref: Option<String>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct SessionResponse {
    pub id: String,
    pub project_id: String,
    pub title: String,
    pub status: String,
    pub target_seconds: i32,
    pub actual_seconds: Option<i32>,
    pub transcript: Option<String>,
    pub local_video_ref: Option<String>,
    pub created_at: DateTime<Utc>,
    pub completed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Deserialize, Serialize, ToSchema)]
pub struct MetricInput {
    pub timestamp_ms: i64,
    pub face_detected: bool,
    #[schema(minimum = 0, maximum = 1)]
    pub gaze_centered: f64,
    #[schema(minimum = 0, maximum = 1)]
    pub posture_score: f64,
    #[schema(minimum = 0, maximum = 1)]
    pub audio_level: f64,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct MetricsRequest {
    pub samples: Vec<MetricInput>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct CompleteSessionRequest {
    pub actual_seconds: i32,
    pub transcript: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct EvidenceRef {
    pub chunk_id: String,
    pub quote: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct DimensionReport {
    #[schema(minimum = 0, maximum = 100)]
    pub score: Option<i32>,
    pub summary: String,
    #[serde(default)]
    pub evidence: Vec<EvidenceRef>,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct TimelineIssue {
    pub timestamp_ms: i64,
    pub kind: String,
    pub message: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, ToSchema)]
pub struct ReportPayload {
    pub session_id: String,
    pub actual_seconds: i32,
    pub character_count: usize,
    pub characters_per_minute: f64,
    pub filler_counts: BTreeMap<String, usize>,
    pub long_pause_count: usize,
    pub content: DimensionReport,
    pub delivery: DimensionReport,
    pub timing: DimensionReport,
    pub visual: DimensionReport,
    pub qa: DimensionReport,
    pub timeline: Vec<TimelineIssue>,
    pub suggestions: Vec<String>,
    pub model_confidence: Option<f64>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct ReportResponse {
    pub id: String,
    pub session_id: String,
    pub report: ReportPayload,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct GenerateQuestionsRequest {
    pub session_id: Option<String>,
    #[serde(default = "default_question_count")]
    pub count: usize,
}

fn default_question_count() -> usize {
    5
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct QuestionResponse {
    pub id: String,
    pub project_id: String,
    pub session_id: Option<String>,
    pub category: String,
    pub question: String,
    pub evidence: Vec<EvidenceRef>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Deserialize, ToSchema)]
pub struct SubmitAnswerRequest {
    pub session_id: String,
    pub answer_text: String,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct AnswerResponse {
    pub id: String,
    pub question_id: String,
    pub session_id: String,
    pub answer_text: String,
    pub evaluation: Value,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct TrendPoint {
    pub session_id: String,
    pub created_at: DateTime<Utc>,
    pub characters_per_minute: f64,
    pub delivery_score: Option<i32>,
    pub timing_score: Option<i32>,
    pub visual_score: Option<i32>,
    pub content_score: Option<i32>,
}

#[derive(Debug, Serialize, Deserialize, ToSchema)]
pub struct TrendsResponse {
    pub project_id: String,
    pub points: Vec<TrendPoint>,
}
