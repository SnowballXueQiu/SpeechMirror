use argon2::{Argon2, PasswordHash, PasswordHasher, PasswordVerifier, password_hash::SaltString};
use axum::{
    extract::{Request, State},
    http::header::AUTHORIZATION,
    middleware::Next,
    response::Response,
};
use chrono::{Duration, Utc};
use jsonwebtoken::{DecodingKey, EncodingKey, Header, Validation, decode, encode};
use rand::rngs::OsRng;
use sea_orm::{ActiveModelTrait, ActiveValue::Set};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use uuid::Uuid;

use crate::{
    AppState,
    entities::refresh_token,
    error::{ApiError, ApiResult},
    models::TokenPair,
};

pub const ACCESS_TOKEN_SECONDS: i64 = 15 * 60;
pub const REFRESH_TOKEN_DAYS: i64 = 30;

#[derive(Clone, Debug)]
pub struct CurrentUser {
    pub id: String,
}

#[derive(Debug, Serialize, Deserialize)]
struct Claims {
    sub: String,
    exp: usize,
    kind: String,
}

pub fn hash_password(password: &str) -> ApiResult<String> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|hash| hash.to_string())
        .map_err(|error| ApiError::Internal(error.to_string()))
}

pub fn verify_password(password: &str, password_hash: &str) -> bool {
    let Ok(parsed) = PasswordHash::new(password_hash) else {
        return false;
    };
    Argon2::default()
        .verify_password(password.as_bytes(), &parsed)
        .is_ok()
}

pub fn validate_credentials(username: &str, password: &str) -> ApiResult<()> {
    let username_len = username.chars().count();
    if !(3..=32).contains(&username_len)
        || !username
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || matches!(c, '_' | '-'))
    {
        return Err(ApiError::BadRequest(
            "username must be 3-32 ASCII letters, numbers, underscores or hyphens".into(),
        ));
    }
    if password.chars().count() < 8 {
        return Err(ApiError::BadRequest(
            "password must contain at least 8 characters".into(),
        ));
    }
    Ok(())
}

pub async fn issue_tokens(state: &AppState, user_id: &str) -> ApiResult<TokenPair> {
    let now = Utc::now();
    let access_claims = Claims {
        sub: user_id.to_owned(),
        exp: (now + Duration::seconds(ACCESS_TOKEN_SECONDS)).timestamp() as usize,
        kind: "access".into(),
    };
    let access_token = encode(
        &Header::default(),
        &access_claims,
        &EncodingKey::from_secret(state.config.jwt_secret.as_bytes()),
    )
    .map_err(|error| ApiError::Internal(error.to_string()))?;

    let refresh_token_value = format!("{}.{}", Uuid::new_v4(), Uuid::new_v4());
    refresh_token::ActiveModel {
        id: Set(Uuid::new_v4().to_string()),
        user_id: Set(user_id.to_owned()),
        token_hash: Set(hash_token(&refresh_token_value)),
        expires_at: Set(now + Duration::days(REFRESH_TOKEN_DAYS)),
        revoked: Set(false),
        created_at: Set(now),
    }
    .insert(&state.db)
    .await?;

    Ok(TokenPair {
        access_token,
        refresh_token: refresh_token_value,
        token_type: "Bearer",
        expires_in: ACCESS_TOKEN_SECONDS,
    })
}

pub fn hash_token(value: &str) -> String {
    let digest = Sha256::digest(value.as_bytes());
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

pub async fn require_auth(
    State(state): State<AppState>,
    mut request: Request,
    next: Next,
) -> ApiResult<Response> {
    let header = request
        .headers()
        .get(AUTHORIZATION)
        .and_then(|value| value.to_str().ok())
        .ok_or(ApiError::Unauthorized)?;
    let token = header
        .strip_prefix("Bearer ")
        .ok_or(ApiError::Unauthorized)?;
    let token_data = decode::<Claims>(
        token,
        &DecodingKey::from_secret(state.config.jwt_secret.as_bytes()),
        &Validation::default(),
    )
    .map_err(|_| ApiError::Unauthorized)?;
    if token_data.claims.kind != "access" {
        return Err(ApiError::Unauthorized);
    }
    request.extensions_mut().insert(CurrentUser {
        id: token_data.claims.sub,
    });
    Ok(next.run(request).await)
}
