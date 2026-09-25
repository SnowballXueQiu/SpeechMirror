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
export interface JuryQuestion { id: string; category: string; question: string; evidence: EvidenceRef[]; }
export interface DimensionReport { score: number | null; summary: string; evidence: EvidenceRef[]; }
export interface ReportPayload {
  session_id: string;
  actual_seconds: number;
  characters_per_minute: number;
  long_pause_count?: number | null;
  content: DimensionReport;
  delivery: DimensionReport;
  timing: DimensionReport;
  visual: DimensionReport;
  qa: DimensionReport;
  suggestions: string[];
}
