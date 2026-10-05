export interface UserProfile {
  id: string;
  username: string;
  bio?: string;
  identity?: string;
  identity_other?: string;
  scenario?: string;
  scenarios: string[];
  scenario_other?: string;
  purposes: string[];
  purpose_other?: string;
  onboarding_completed: boolean;
  research_consent: boolean;
  has_avatar: boolean;
  created_at: string;
  updated_at: string;
}

export interface UserProfileUpdate {
  bio?: string;
  identity?: string;
  identity_other?: string;
  scenario?: string;
  scenarios: string[];
  scenario_other?: string;
  purposes: string[];
  purpose_other?: string;
  onboarding_completed: boolean;
  research_consent: boolean;
}

export interface ActivityDay {
  date: string;
  use_count: number;
  practice_count: number;
}

export interface ActivitySummary {
  through: string;
  active_days: number;
  total_uses: number;
  total_practices: number;
  current_streak: number;
  longest_streak: number;
  days: ActivityDay[];
}

export interface Project {
  id: string;
  name: string;
  description?: string;
  defense_duration_seconds: number;
  created_at?: string;
  updated_at?: string;
}

export interface DocumentItem {
  id: string;
  project_id?: string;
  filename: string;
  media_type: string;
  status: string;
  extracted_text?: string;
  error?: string;
  created_at?: string;
}

export interface SessionItem {
  id: string;
  project_id: string;
  title: string;
  status: string;
  target_seconds: number;
  actual_seconds?: number;
  transcript?: string;
  created_at?: string;
  completed_at?: string;
}

export interface EvidenceRef {
  chunk_id: string;
  quote: string;
}

export interface JuryQuestion {
  id: string;
  project_id?: string;
  session_id?: string;
  category: string;
  question: string;
  evidence: EvidenceRef[];
  created_at?: string;
}

export interface JuryEvaluation {
  score?: number;
  relevance?: string;
  accuracy?: string;
  suggestions?: string[];
  follow_up?: string;
  decision?: string;
  evidence?: EvidenceRef[];
}

export interface JuryAnswer {
  id: string;
  question_id: string;
  session_id: string;
  asked_question: string;
  parent_answer_id?: string;
  answer_text: string;
  evaluation: JuryEvaluation;
  created_at?: string;
}

export interface DimensionReport {
  score: number | null;
  summary: string;
  evidence: EvidenceRef[];
}

export interface AudioWavePoint {
  timestamp_ms: number;
  level: number;
}

export interface TimelineIssue {
  timestamp_ms: number;
  kind: string;
  message: string;
}

export interface DefenseScoreItem {
  label: string;
  score: number;
  max_score: number;
  summary: string;
}

export interface ReportPayload {
  session_id: string;
  overall_score?: number | null;
  actual_seconds: number;
  character_count?: number;
  characters_per_minute: number;
  filler_counts?: Record<string, number>;
  long_pause_count?: number | null;
  audio_waveform?: AudioWavePoint[];
  content: DimensionReport;
  delivery: DimensionReport;
  timing: DimensionReport;
  visual: DimensionReport;
  qa: DimensionReport;
  defense_scores?: DefenseScoreItem[];
  timeline?: TimelineIssue[];
  suggestions: string[];
  model_confidence?: number | null;
}

export interface TrendPoint {
  session_id: string;
  created_at: string;
  target_seconds: number;
  actual_seconds: number;
  duration_deviation_seconds: number;
  characters_per_minute: number;
  filler_count: number;
  filler_per_minute: number;
  delivery_score?: number;
  timing_score?: number;
  visual_score?: number;
  content_score?: number;
  qa_score?: number;
}

export interface Trends {
  project_id: string;
  points: TrendPoint[];
}
