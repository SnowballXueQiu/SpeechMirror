use sea_orm_migration::{prelude::*, sea_orm::ConnectionTrait};

pub struct Migrator;

#[async_trait::async_trait]
impl MigratorTrait for Migrator {
    fn migrations() -> Vec<Box<dyn MigrationTrait>> {
        vec![Box::new(InitialSchema)]
    }
}

struct InitialSchema;

#[async_trait::async_trait]
impl MigrationName for InitialSchema {
    fn name(&self) -> &str {
        "m20260925_000001_initial_schema"
    }
}

#[async_trait::async_trait]
impl MigrationTrait for InitialSchema {
    async fn up(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        let statements = [
            "CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY NOT NULL, username TEXT NOT NULL UNIQUE, password_hash TEXT NOT NULL, created_at TEXT NOT NULL)",
            "CREATE TABLE IF NOT EXISTS refresh_tokens (id TEXT PRIMARY KEY NOT NULL, user_id TEXT NOT NULL, token_hash TEXT NOT NULL UNIQUE, expires_at TEXT NOT NULL, revoked INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE)",
            "CREATE TABLE IF NOT EXISTS projects (id TEXT PRIMARY KEY NOT NULL, user_id TEXT NOT NULL, name TEXT NOT NULL, description TEXT, defense_duration_seconds INTEGER NOT NULL DEFAULT 300, created_at TEXT NOT NULL, updated_at TEXT NOT NULL, FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE)",
            "CREATE TABLE IF NOT EXISTS documents (id TEXT PRIMARY KEY NOT NULL, project_id TEXT NOT NULL, filename TEXT NOT NULL, media_type TEXT NOT NULL, storage_path TEXT NOT NULL, status TEXT NOT NULL, extracted_text TEXT, error TEXT, created_at TEXT NOT NULL, FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE)",
            "CREATE TABLE IF NOT EXISTS document_chunks (id TEXT PRIMARY KEY NOT NULL, document_id TEXT NOT NULL, project_id TEXT NOT NULL, ordinal INTEGER NOT NULL, content TEXT NOT NULL, embedding JSON, FOREIGN KEY(document_id) REFERENCES documents(id) ON DELETE CASCADE, FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE)",
            "CREATE TABLE IF NOT EXISTS rehearsal_sessions (id TEXT PRIMARY KEY NOT NULL, project_id TEXT NOT NULL, user_id TEXT NOT NULL, title TEXT NOT NULL, status TEXT NOT NULL, target_seconds INTEGER NOT NULL, actual_seconds INTEGER, transcript TEXT, local_video_ref TEXT, created_at TEXT NOT NULL, completed_at TEXT, FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE, FOREIGN KEY(user_id) REFERENCES users(id) ON DELETE CASCADE)",
            "CREATE TABLE IF NOT EXISTS transcript_segments (id TEXT PRIMARY KEY NOT NULL, session_id TEXT NOT NULL, start_ms INTEGER NOT NULL, end_ms INTEGER NOT NULL, text TEXT NOT NULL, FOREIGN KEY(session_id) REFERENCES rehearsal_sessions(id) ON DELETE CASCADE)",
            "CREATE TABLE IF NOT EXISTS session_metrics (id TEXT PRIMARY KEY NOT NULL, session_id TEXT NOT NULL, timestamp_ms INTEGER NOT NULL, face_detected INTEGER NOT NULL, gaze_centered REAL NOT NULL, posture_score REAL NOT NULL, audio_level REAL NOT NULL, FOREIGN KEY(session_id) REFERENCES rehearsal_sessions(id) ON DELETE CASCADE)",
            "CREATE TABLE IF NOT EXISTS reports (id TEXT PRIMARY KEY NOT NULL, session_id TEXT NOT NULL UNIQUE, report_json JSON NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(session_id) REFERENCES rehearsal_sessions(id) ON DELETE CASCADE)",
            "CREATE TABLE IF NOT EXISTS jury_questions (id TEXT PRIMARY KEY NOT NULL, project_id TEXT NOT NULL, session_id TEXT, category TEXT NOT NULL, question TEXT NOT NULL, evidence_json JSON NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(project_id) REFERENCES projects(id) ON DELETE CASCADE, FOREIGN KEY(session_id) REFERENCES rehearsal_sessions(id) ON DELETE CASCADE)",
            "CREATE TABLE IF NOT EXISTS jury_answers (id TEXT PRIMARY KEY NOT NULL, question_id TEXT NOT NULL, session_id TEXT NOT NULL, answer_text TEXT NOT NULL, evaluation_json JSON NOT NULL, created_at TEXT NOT NULL, FOREIGN KEY(question_id) REFERENCES jury_questions(id) ON DELETE CASCADE, FOREIGN KEY(session_id) REFERENCES rehearsal_sessions(id) ON DELETE CASCADE)",
            "CREATE TABLE IF NOT EXISTS analysis_jobs (id TEXT PRIMARY KEY NOT NULL, kind TEXT NOT NULL, resource_id TEXT NOT NULL, status TEXT NOT NULL, error TEXT, result_json JSON, created_at TEXT NOT NULL, updated_at TEXT NOT NULL)",
            "CREATE INDEX IF NOT EXISTS idx_projects_user ON projects(user_id)",
            "CREATE INDEX IF NOT EXISTS idx_documents_project ON documents(project_id)",
            "CREATE INDEX IF NOT EXISTS idx_chunks_project ON document_chunks(project_id)",
            "CREATE INDEX IF NOT EXISTS idx_sessions_project ON rehearsal_sessions(project_id)",
            "CREATE INDEX IF NOT EXISTS idx_metrics_session ON session_metrics(session_id, timestamp_ms)",
            "CREATE INDEX IF NOT EXISTS idx_questions_project ON jury_questions(project_id)",
            "CREATE INDEX IF NOT EXISTS idx_jobs_status ON analysis_jobs(status, created_at)",
        ];
        manager
            .get_connection()
            .execute_unprepared("PRAGMA foreign_keys = ON")
            .await?;
        for statement in statements {
            manager
                .get_connection()
                .execute_unprepared(statement)
                .await?;
        }
        if !manager.has_column("analysis_jobs", "result_json").await? {
            manager
                .get_connection()
                .execute_unprepared("ALTER TABLE analysis_jobs ADD COLUMN result_json JSON")
                .await?;
        }
        Ok(())
    }

    async fn down(&self, manager: &SchemaManager) -> Result<(), DbErr> {
        for table in [
            "analysis_jobs",
            "jury_answers",
            "jury_questions",
            "reports",
            "session_metrics",
            "transcript_segments",
            "rehearsal_sessions",
            "document_chunks",
            "documents",
            "projects",
            "refresh_tokens",
            "users",
        ] {
            manager
                .get_connection()
                .execute_unprepared(&format!("DROP TABLE IF EXISTS {table}"))
                .await?;
        }
        Ok(())
    }
}
