export interface Project {
  id: string;
  name: string;
  description?: string;
  defense_duration_seconds: number;
}

export interface DocumentItem {
  id: string;
  filename: string;
  media_type: string;
  status: string;
  error?: string;
}

export interface SessionItem {
  id: string;
  project_id: string;
  title: string;
  status: string;
  target_seconds: number;
}

export interface EvidenceRef { chunk_id: string; quote: string; }
export interface JuryQuestion { id: string; session_id?: string; category: string; question: string; evidence: EvidenceRef[]; }
export interface JuryEvaluation {
  score: number;
  relevance?: string;
  accuracy?: string;
  suggestions?: string[];
  follow_up: string;
  evidence: EvidenceRef[];
}
export interface JuryAnswer {
  id: string;
  question_id: string;
  session_id: string;
  asked_question: string;
  parent_answer_id?: string;
  answer_text: string;
  evaluation: JuryEvaluation;
}
export interface DimensionReport { score: number | null; summary: string; evidence: EvidenceRef[]; }
export interface AudioWavePoint { timestamp_ms: number; level: number; }
export interface ReportPayload {
  session_id: string;
  overall_score?: number | null;
  actual_seconds: number;
  characters_per_minute: number;
  long_pause_count?: number | null;
  audio_waveform?: AudioWavePoint[];
  content: DimensionReport;
  delivery: DimensionReport;
  timing: DimensionReport;
  visual: DimensionReport;
  qa: DimensionReport;
  suggestions: string[];
}
