import { http } from '@kit.NetworkKit';
import { Project, DocumentItem, SessionItem, JuryQuestion, ReportPayload } from '../models/Models';

interface TokenPair { access_token: string; refresh_token: string; }
interface ReportEnvelope { report: ReportPayload; }
interface LoginRequest { username: string; password: string; }
interface CreateProjectRequest { name: string; description: string; defense_duration_seconds: number; }
interface CreateSessionRequest { target_seconds: number; }
interface CompleteSessionRequest { actual_seconds: number; transcript: string; }
interface GenerateQuestionsRequest { session_id: string; count: number; }

class ApiClient {
  private accessToken: string = '';
  private refreshToken: string = '';

  private baseUrl(): string { return AppStorage.get<string>('apiBaseUrl') ?? 'http://127.0.0.1:8080/api/v1'; }

  private async request<T>(method: http.RequestMethod, path: string, body?: object): Promise<T> {
    const client = http.createHttp();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.accessToken.length > 0) headers['Authorization'] = `Bearer ${this.accessToken}`;
    try {
      const response = await client.request(`${this.baseUrl()}${path}`, {
        method,
        header: headers,
        extraData: body === undefined ? undefined : JSON.stringify(body),
        connectTimeout: 15000,
        readTimeout: 90000
      });
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new Error(`请求失败（${response.responseCode}）`);
      }
      return JSON.parse(response.result as string) as T;
    } finally {
      client.destroy();
    }
  }

  async login(username: string, password: string, register: boolean): Promise<void> {
    const body: LoginRequest = { username, password };
    const tokens = await this.request<TokenPair>(http.RequestMethod.POST, register ? '/auth/register' : '/auth/login', body);
    this.accessToken = tokens.access_token;
    this.refreshToken = tokens.refresh_token;
  }

  listProjects(): Promise<Project[]> { return this.request<Project[]>(http.RequestMethod.GET, '/projects'); }
  getProject(id: string): Promise<Project> { return this.request<Project>(http.RequestMethod.GET, `/projects/${id}`); }
  createProject(name: string, description: string, seconds: number): Promise<Project> {
    const body: CreateProjectRequest = { name, description, defense_duration_seconds: seconds };
    return this.request<Project>(http.RequestMethod.POST, '/projects', body);
  }
  listDocuments(projectId: string): Promise<DocumentItem[]> { return this.request<DocumentItem[]>(http.RequestMethod.GET, `/projects/${projectId}/documents`); }
  createSession(projectId: string, seconds: number): Promise<SessionItem> {
    const body: CreateSessionRequest = { target_seconds: seconds };
    return this.request<SessionItem>(http.RequestMethod.POST, `/projects/${projectId}/sessions`, body);
  }
  completeSession(sessionId: string, seconds: number, transcript: string): Promise<SessionItem> {
    const body: CompleteSessionRequest = { actual_seconds: seconds, transcript };
    return this.request<SessionItem>(http.RequestMethod.POST, `/sessions/${sessionId}/complete`, body);
  }
  async analyzeSession(sessionId: string): Promise<ReportPayload> {
    const envelope = await this.request<ReportEnvelope>(http.RequestMethod.POST, `/sessions/${sessionId}/analyze`);
    return envelope.report;
  }
  listQuestions(projectId: string): Promise<JuryQuestion[]> { return this.request<JuryQuestion[]>(http.RequestMethod.GET, `/projects/${projectId}/questions`); }
  generateQuestions(projectId: string, sessionId: string): Promise<JuryQuestion[]> {
    const body: GenerateQuestionsRequest = { session_id: sessionId, count: 5 };
    return this.request<JuryQuestion[]>(http.RequestMethod.POST, `/projects/${projectId}/questions`, body);
  }
}

export const apiClient = new ApiClient();
