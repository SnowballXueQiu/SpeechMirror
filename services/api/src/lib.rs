pub mod analysis;
pub mod auth;
pub mod config;
pub mod entities;
pub mod error;
pub mod migration;
pub mod models;
pub mod providers;
pub mod routes;
pub mod workers;

use std::time::Duration;

use axum::{
    Router,
    http::{
        HeaderValue, Method, StatusCode,
        header::{AUTHORIZATION, CONTENT_TYPE},
    },
    response::IntoResponse,
    routing::get,
};
use config::Config;
use migration::Migrator;
use providers::AiClient;
use sea_orm::{ConnectOptions, ConnectionTrait, Database, DatabaseConnection};
use sea_orm_migration::MigratorTrait;
use tower_http::{cors::CorsLayer, trace::TraceLayer};

#[derive(Clone)]
pub struct AppState {
    pub db: DatabaseConnection,
    pub config: Config,
    pub ai: AiClient,
}

pub async fn app(config: Config) -> anyhow::Result<Router> {
    tokio::fs::create_dir_all(config.storage_dir.join("documents")).await?;
    tokio::fs::create_dir_all(config.storage_dir.join("tmp")).await?;
    if let Some(path) = config
        .database_url
        .strip_prefix("sqlite://")
        .and_then(|value| value.split('?').next())
    {
        if path != ":memory:" {
            if let Some(parent) = std::path::Path::new(path).parent() {
                tokio::fs::create_dir_all(parent).await?;
            }
        }
    }
    let mut options = ConnectOptions::new(config.database_url.clone());
    options
        .max_connections(if config.database_url.contains(":memory:") {
            1
        } else {
            5
        })
        .min_connections(1)
        .connect_timeout(Duration::from_secs(10))
        .sqlx_logging(false);
    let db = Database::connect(options).await?;
    db.execute_unprepared("PRAGMA foreign_keys = ON").await?;
    if !config.database_url.contains(":memory:") {
        db.execute_unprepared("PRAGMA journal_mode = WAL").await?;
    }
    let cors_allowed_origins = config.cors_allowed_origins.clone();
    Migrator::up(&db, None).await?;
    let state = AppState {
        db,
        ai: AiClient::new(config.ai.clone()),
        config,
    };
    workers::spawn(state.clone());
    let mut router = Router::new()
        .route("/api-docs/openapi.yaml", get(openapi_spec))
        .nest("/api/v1", routes::api_router(state))
        .layer(TraceLayer::new_for_http());
    if !cors_allowed_origins.is_empty() {
        let origins = cors_allowed_origins
            .iter()
            .map(|origin| origin.parse::<HeaderValue>())
            .collect::<Result<Vec<_>, _>>()?;
        let cors = CorsLayer::new()
            .allow_origin(origins)
            .allow_methods([Method::GET, Method::POST, Method::PUT, Method::DELETE])
            .allow_headers([AUTHORIZATION, CONTENT_TYPE])
            .expose_headers([CONTENT_TYPE]);
        router = router.layer(cors);
    }
    Ok(router)
}

async fn openapi_spec() -> impl IntoResponse {
    (
        StatusCode::OK,
        [(CONTENT_TYPE, "application/yaml; charset=utf-8")],
        include_str!("../../../openapi/openapi.yaml"),
    )
}

#[cfg(test)]
mod tests {
    use axum::{
        body::Body,
        http::{Method, Request, StatusCode},
    };
    use http_body_util::BodyExt;
    use serde_json::{Value, json};
    use tempfile::tempdir;
    use tower::ServiceExt;

    use super::*;

    #[tokio::test]
    async fn registration_and_project_flow() {
        let temp = tempdir().unwrap();
        let router = app(Config::test(temp.path().to_owned())).await.unwrap();
        let response = router
            .clone()
            .oneshot(json_request(
                "/api/v1/auth/register",
                json!({"username":"yanjing","password":"correct-horse"}),
                None,
            ))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body: Value =
            serde_json::from_slice(&response.into_body().collect().await.unwrap().to_bytes())
                .unwrap();
        let token = body["access_token"].as_str().unwrap();

        let response = router
            .clone()
            .oneshot(json_request(
                "/api/v1/projects",
                json!({"name":"毕业答辩","defense_duration_seconds":300}),
                Some(token),
            ))
            .await
            .unwrap();
        assert_eq!(response.status(), StatusCode::OK);

        let request = Request::builder()
            .uri("/api/v1/projects")
            .header("authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap();
        let response = router.oneshot(request).await.unwrap();
        assert_eq!(response.status(), StatusCode::OK);
        let body: Value =
            serde_json::from_slice(&response.into_body().collect().await.unwrap().to_bytes())
                .unwrap();
        assert_eq!(body.as_array().unwrap().len(), 1);
    }

    #[tokio::test]
    async fn cors_only_allows_configured_origin() {
        let temp = tempdir().unwrap();
        let mut config = Config::test(temp.path().to_owned());
        config.cors_allowed_origins = vec!["https://speechmirror.example".into()];
        let router = app(config).await.unwrap();

        let allowed = Request::builder()
            .method("OPTIONS")
            .uri("/api/v1/health")
            .header("origin", "https://speechmirror.example")
            .header("access-control-request-method", "GET")
            .body(Body::empty())
            .unwrap();
        let allowed = router.clone().oneshot(allowed).await.unwrap();
        assert_eq!(
            allowed
                .headers()
                .get("access-control-allow-origin")
                .unwrap(),
            "https://speechmirror.example"
        );

        let denied = Request::builder()
            .method("OPTIONS")
            .uri("/api/v1/health")
            .header("origin", "https://attacker.example")
            .header("access-control-request-method", "GET")
            .body(Body::empty())
            .unwrap();
        let denied = router.oneshot(denied).await.unwrap();
        assert!(
            denied
                .headers()
                .get("access-control-allow-origin")
                .is_none()
        );
    }

    #[tokio::test]
    async fn refresh_token_is_single_use() {
        let temp = tempdir().unwrap();
        let router = app(Config::test(temp.path().to_owned())).await.unwrap();
        let response = router
            .clone()
            .oneshot(json_request(
                "/api/v1/auth/register",
                json!({"username":"rotation","password":"correct-horse"}),
                None,
            ))
            .await
            .unwrap();
        let body: Value =
            serde_json::from_slice(&response.into_body().collect().await.unwrap().to_bytes())
                .unwrap();
        let refresh_token = body["refresh_token"].as_str().unwrap();

        let first = router
            .clone()
            .oneshot(json_request(
                "/api/v1/auth/refresh",
                json!({"refresh_token":refresh_token}),
                None,
            ))
            .await
            .unwrap();
        assert_eq!(first.status(), StatusCode::OK);

        let replay = router
            .oneshot(json_request(
                "/api/v1/auth/refresh",
                json!({"refresh_token":refresh_token}),
                None,
            ))
            .await
            .unwrap();
        assert_eq!(replay.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn authentication_validates_credentials_and_revokes_logout_token() {
        let temp = tempdir().unwrap();
        let router = app(Config::test(temp.path().to_owned())).await.unwrap();

        let invalid_username = router
            .clone()
            .oneshot(json_request(
                "/api/v1/auth/register",
                json!({"username":"王彦翔","password":"correct-horse"}),
                None,
            ))
            .await
            .unwrap();
        assert_eq!(invalid_username.status(), StatusCode::BAD_REQUEST);

        let oversized_password = router
            .clone()
            .oneshot(json_request(
                "/api/v1/auth/register",
                json!({"username":"valid_user","password":"x".repeat(129)}),
                None,
            ))
            .await
            .unwrap();
        assert_eq!(oversized_password.status(), StatusCode::BAD_REQUEST);

        let registered = router
            .clone()
            .oneshot(json_request(
                "/api/v1/auth/register",
                json!({"username":"valid_user","password":"correct-horse"}),
                None,
            ))
            .await
            .unwrap();
        assert_eq!(registered.status(), StatusCode::OK);
        let body: Value =
            serde_json::from_slice(&registered.into_body().collect().await.unwrap().to_bytes())
                .unwrap();
        let access_token = body["access_token"].as_str().unwrap();
        let refresh_token = body["refresh_token"].as_str().unwrap();

        let duplicate = router
            .clone()
            .oneshot(json_request(
                "/api/v1/auth/register",
                json!({"username":"valid_user","password":"correct-horse"}),
                None,
            ))
            .await
            .unwrap();
        assert_eq!(duplicate.status(), StatusCode::CONFLICT);

        let wrong_password = router
            .clone()
            .oneshot(json_request(
                "/api/v1/auth/login",
                json!({"username":"valid_user","password":"wrong-password"}),
                None,
            ))
            .await
            .unwrap();
        assert_eq!(wrong_password.status(), StatusCode::UNAUTHORIZED);

        let logout = router
            .clone()
            .oneshot(json_request(
                "/api/v1/auth/logout",
                json!({"refresh_token":refresh_token}),
                Some(access_token),
            ))
            .await
            .unwrap();
        assert_eq!(logout.status(), StatusCode::OK);

        let revoked = router
            .oneshot(json_request(
                "/api/v1/auth/refresh",
                json!({"refresh_token":refresh_token}),
                None,
            ))
            .await
            .unwrap();
        assert_eq!(revoked.status(), StatusCode::UNAUTHORIZED);
    }

    #[tokio::test]
    async fn project_crud_normalizes_fields_and_enforces_ownership() {
        let temp = tempdir().unwrap();
        let router = app(Config::test(temp.path().to_owned())).await.unwrap();

        let owner = router
            .clone()
            .oneshot(json_request(
                "/api/v1/auth/register",
                json!({"username":"project_owner","password":"correct-horse"}),
                None,
            ))
            .await
            .unwrap();
        let owner: Value =
            serde_json::from_slice(&owner.into_body().collect().await.unwrap().to_bytes()).unwrap();
        let owner_token = owner["access_token"].as_str().unwrap();

        let intruder = router
            .clone()
            .oneshot(json_request(
                "/api/v1/auth/register",
                json!({"username":"project_intruder","password":"correct-horse"}),
                None,
            ))
            .await
            .unwrap();
        let intruder: Value =
            serde_json::from_slice(&intruder.into_body().collect().await.unwrap().to_bytes())
                .unwrap();
        let intruder_token = intruder["access_token"].as_str().unwrap();

        let created = router
            .clone()
            .oneshot(json_request(
                "/api/v1/projects",
                json!({
                    "name":"  论文答辩  ",
                    "description":"  多端协同训练  ",
                    "defense_duration_seconds":300
                }),
                Some(owner_token),
            ))
            .await
            .unwrap();
        assert_eq!(created.status(), StatusCode::OK);
        let created: Value =
            serde_json::from_slice(&created.into_body().collect().await.unwrap().to_bytes())
                .unwrap();
        assert_eq!(created["name"], "论文答辩");
        assert_eq!(created["description"], "多端协同训练");
        let project_id = created["id"].as_str().unwrap();

        let denied = router
            .clone()
            .oneshot(json_request_with_method(
                Method::PUT,
                &format!("/api/v1/projects/{project_id}"),
                json!({"name":"非法修改"}),
                Some(intruder_token),
            ))
            .await
            .unwrap();
        assert_eq!(denied.status(), StatusCode::NOT_FOUND);

        let oversized = router
            .clone()
            .oneshot(json_request_with_method(
                Method::PUT,
                &format!("/api/v1/projects/{project_id}"),
                json!({"description":"x".repeat(501)}),
                Some(owner_token),
            ))
            .await
            .unwrap();
        assert_eq!(oversized.status(), StatusCode::BAD_REQUEST);

        let updated = router
            .clone()
            .oneshot(json_request_with_method(
                Method::PUT,
                &format!("/api/v1/projects/{project_id}"),
                json!({
                    "name":"  更新后项目  ",
                    "description":"   ",
                    "defense_duration_seconds":420
                }),
                Some(owner_token),
            ))
            .await
            .unwrap();
        assert_eq!(updated.status(), StatusCode::OK);
        let updated: Value =
            serde_json::from_slice(&updated.into_body().collect().await.unwrap().to_bytes())
                .unwrap();
        assert_eq!(updated["name"], "更新后项目");
        assert!(updated["description"].is_null());
        assert_eq!(updated["defense_duration_seconds"], 420);

        let denied_delete = router
            .clone()
            .oneshot(json_request_with_method(
                Method::DELETE,
                &format!("/api/v1/projects/{project_id}"),
                json!({}),
                Some(intruder_token),
            ))
            .await
            .unwrap();
        assert_eq!(denied_delete.status(), StatusCode::NOT_FOUND);

        let deleted = router
            .clone()
            .oneshot(json_request_with_method(
                Method::DELETE,
                &format!("/api/v1/projects/{project_id}"),
                json!({}),
                Some(owner_token),
            ))
            .await
            .unwrap();
        assert_eq!(deleted.status(), StatusCode::OK);

        let missing = router
            .oneshot(
                Request::builder()
                    .uri(format!("/api/v1/projects/{project_id}"))
                    .header("authorization", format!("Bearer {owner_token}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        assert_eq!(missing.status(), StatusCode::NOT_FOUND);
    }

    #[tokio::test]
    async fn text_document_upload_processing_and_correction_flow() {
        let temp = tempdir().unwrap();
        let router = app(Config::test(temp.path().to_owned())).await.unwrap();
        let registered = router
            .clone()
            .oneshot(json_request(
                "/api/v1/auth/register",
                json!({"username":"material_owner","password":"correct-horse"}),
                None,
            ))
            .await
            .unwrap();
        let registered: Value =
            serde_json::from_slice(&registered.into_body().collect().await.unwrap().to_bytes())
                .unwrap();
        let token = registered["access_token"].as_str().unwrap();

        let project = router
            .clone()
            .oneshot(json_request(
                "/api/v1/projects",
                json!({"name":"材料解析测试","defense_duration_seconds":300}),
                Some(token),
            ))
            .await
            .unwrap();
        let project: Value =
            serde_json::from_slice(&project.into_body().collect().await.unwrap().to_bytes())
                .unwrap();
        let project_id = project["id"].as_str().unwrap();

        let uploaded = router
            .clone()
            .oneshot(multipart_request(
                &format!("/api/v1/projects/{project_id}/documents"),
                "defense.md",
                "text/markdown",
                b"# SpeechMirror\n\nMaterial-grounded defense rehearsal.",
                token,
            ))
            .await
            .unwrap();
        assert_eq!(uploaded.status(), StatusCode::OK);
        let uploaded: Value =
            serde_json::from_slice(&uploaded.into_body().collect().await.unwrap().to_bytes())
                .unwrap();
        let document_id = uploaded["id"].as_str().unwrap();
        assert_eq!(uploaded["status"], "processing");
        assert_eq!(uploaded["media_type"], "text/markdown");

        let mut ready = None;
        for _ in 0..30 {
            let response = router
                .clone()
                .oneshot(
                    Request::builder()
                        .uri(format!("/api/v1/documents/{document_id}"))
                        .header("authorization", format!("Bearer {token}"))
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            assert_eq!(response.status(), StatusCode::OK);
            let body: Value =
                serde_json::from_slice(&response.into_body().collect().await.unwrap().to_bytes())
                    .unwrap();
            if body["status"] == "ready" {
                ready = Some(body);
                break;
            }
            tokio::time::sleep(Duration::from_millis(100)).await;
        }
        let ready = ready.expect("document ingestion did not finish");
        assert!(
            ready["extracted_text"]
                .as_str()
                .unwrap()
                .contains("Material-grounded")
        );

        let corrected = router
            .oneshot(json_request_with_method(
                Method::PUT,
                &format!("/api/v1/documents/{document_id}/text"),
                json!({"text":"已校正的答辩材料文本"}),
                Some(token),
            ))
            .await
            .unwrap();
        assert_eq!(corrected.status(), StatusCode::OK);
        let corrected: Value =
            serde_json::from_slice(&corrected.into_body().collect().await.unwrap().to_bytes())
                .unwrap();
        assert_eq!(corrected["status"], "ready");
        assert_eq!(corrected["extracted_text"], "已校正的答辩材料文本");
    }

    fn json_request(uri: &str, body: Value, token: Option<&str>) -> Request<Body> {
        json_request_with_method(Method::POST, uri, body, token)
    }

    fn json_request_with_method(
        method: Method,
        uri: &str,
        body: Value,
        token: Option<&str>,
    ) -> Request<Body> {
        let mut builder = Request::builder()
            .method(method)
            .uri(uri)
            .header("content-type", "application/json");
        if let Some(token) = token {
            builder = builder.header("authorization", format!("Bearer {token}"));
        }
        builder.body(Body::from(body.to_string())).unwrap()
    }

    fn multipart_request(
        uri: &str,
        filename: &str,
        media_type: &str,
        contents: &[u8],
        token: &str,
    ) -> Request<Body> {
        const BOUNDARY: &str = "speechmirror-test-boundary";
        let mut body = format!(
            "--{BOUNDARY}\r\nContent-Disposition: form-data; name=\"file\"; filename=\"{filename}\"\r\nContent-Type: {media_type}\r\n\r\n"
        )
        .into_bytes();
        body.extend_from_slice(contents);
        body.extend_from_slice(format!("\r\n--{BOUNDARY}--\r\n").as_bytes());
        Request::builder()
            .method(Method::POST)
            .uri(uri)
            .header("authorization", format!("Bearer {token}"))
            .header(
                "content-type",
                format!("multipart/form-data; boundary={BOUNDARY}"),
            )
            .body(Body::from(body))
            .unwrap()
    }
}
