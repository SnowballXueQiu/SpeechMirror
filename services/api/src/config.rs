use std::{env, net::SocketAddr, path::PathBuf};

#[derive(Clone, Debug)]
pub struct ProviderConfig {
    pub base_url: String,
    pub api_key: Option<String>,
    pub model: String,
}

impl ProviderConfig {
    pub fn is_configured(&self) -> bool {
        self.api_key.is_some()
    }
}

#[derive(Clone, Debug)]
pub struct AiConfig {
    pub llm: ProviderConfig,
    pub embedding: ProviderConfig,
    pub asr: ProviderConfig,
    pub ocr: ProviderConfig,
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
                llm: provider_from_env("LLM", "https://api.deepseek.com", "deepseek-chat"),
                embedding: provider_from_env(
                    "EMBEDDING",
                    "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    "qwen3.7-text-embedding-flash",
                ),
                asr: provider_from_env(
                    "ASR",
                    "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    "qwen3-asr-flash-2026-02-10",
                ),
                ocr: provider_from_env(
                    "OCR",
                    "https://dashscope.aliyuncs.com/compatible-mode/v1",
                    "qwen3.8-omni-flash",
                ),
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
                llm: test_provider(),
                embedding: test_provider(),
                asr: test_provider(),
                ocr: test_provider(),
            },
        }
    }
}

fn provider_from_env(prefix: &str, default_base_url: &str, default_model: &str) -> ProviderConfig {
    ProviderConfig {
        base_url: env::var(format!("{prefix}_BASE_URL"))
            .unwrap_or_else(|_| default_base_url.to_owned()),
        api_key: env::var(format!("{prefix}_API_KEY"))
            .ok()
            .filter(|value| !value.trim().is_empty()),
        model: env::var(format!("{prefix}_MODEL")).unwrap_or_else(|_| default_model.to_owned()),
    }
}

#[cfg(test)]
fn test_provider() -> ProviderConfig {
    ProviderConfig {
        base_url: "http://127.0.0.1:9/v1".into(),
        api_key: None,
        model: "test".into(),
    }
}
