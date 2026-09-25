use std::{env, net::SocketAddr, path::PathBuf};

#[derive(Clone, Debug)]
pub struct AiConfig {
    pub base_url: String,
    pub api_key: Option<String>,
    pub llm_model: String,
    pub embedding_model: String,
    pub asr_model: String,
    pub ocr_model: String,
}

#[derive(Clone, Debug)]
pub struct Config {
    pub bind_addr: SocketAddr,
    pub database_url: String,
    pub jwt_secret: String,
    pub storage_dir: PathBuf,
    pub cors_allowed_origins: Vec<String>,
    pub ai: AiConfig,
}

impl Config {
    pub fn from_env() -> anyhow::Result<Self> {
        let bind_addr = env::var("BIND_ADDR")
            .unwrap_or_else(|_| "0.0.0.0:8080".into())
            .parse()?;
        let database_url = env::var("DATABASE_URL")
            .unwrap_or_else(|_| "sqlite://data/speechmirror.sqlite3?mode=rwc".into());
        let jwt_secret = env::var("JWT_SECRET").map_err(|_| {
            anyhow::anyhow!("JWT_SECRET must be set and contain at least 32 characters")
        })?;
        if jwt_secret.chars().count() < 32 {
            anyhow::bail!("JWT_SECRET must be set and contain at least 32 characters");
        }
        let storage_dir = env::var("STORAGE_DIR")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("data"));
        let cors_allowed_origins = env::var("CORS_ALLOWED_ORIGINS")
            .unwrap_or_default()
            .split(',')
            .map(str::trim)
            .filter(|origin| !origin.is_empty())
            .map(str::to_owned)
            .collect();

        Ok(Self {
            bind_addr,
            database_url,
            jwt_secret,
            storage_dir,
            cors_allowed_origins,
            ai: AiConfig {
                base_url: env::var("AI_BASE_URL")
                    .unwrap_or_else(|_| "https://dashscope.aliyuncs.com/compatible-mode/v1".into()),
                api_key: env::var("AI_API_KEY").ok().filter(|v| !v.trim().is_empty()),
                llm_model: env::var("LLM_MODEL").unwrap_or_else(|_| "qwen-plus".into()),
                embedding_model: env::var("EMBEDDING_MODEL")
                    .unwrap_or_else(|_| "text-embedding-v3".into()),
                asr_model: env::var("ASR_MODEL").unwrap_or_else(|_| "paraformer-v2".into()),
                ocr_model: env::var("OCR_MODEL").unwrap_or_else(|_| "qwen-vl-plus".into()),
            },
        })
    }

    #[cfg(test)]
    pub fn test(storage_dir: PathBuf) -> Self {
        Self {
            bind_addr: "127.0.0.1:0".parse().expect("test bind address"),
            database_url: "sqlite::memory:".into(),
            jwt_secret: "test-secret-with-enough-entropy".into(),
            storage_dir,
            cors_allowed_origins: Vec::new(),
            ai: AiConfig {
                base_url: "http://127.0.0.1:9/v1".into(),
                api_key: None,
                llm_model: "test".into(),
                embedding_model: "test".into(),
                asr_model: "test".into(),
                ocr_model: "test".into(),
            },
        }
    }
}
