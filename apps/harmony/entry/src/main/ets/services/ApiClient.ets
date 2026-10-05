import { http } from '@kit.NetworkKit';
import { common } from '@kit.AbilityKit';
import preferences from '@ohos.data.preferences';
import {
  ActivitySummary,
  DocumentItem,
  JuryAnswer,
  JuryQuestion,
  Project,
  ReportPayload,
  SessionItem,
  Trends,
  UserProfile,
  UserProfileUpdate
} from '../models/Models';

interface TokenPair { access_token: string; refresh_token: string; }
interface ReportEnvelope { report: ReportPayload; }
interface LoginRequest { username: string; password: string; }
interface RefreshRequest { refresh_token: string; }
interface CreateProjectRequest { name: string; description: string; defense_duration_seconds: number; }
interface CreateSessionRequest { target_seconds: number; local_date: string; }
interface CompleteSessionRequest { actual_seconds: number; transcript: string; }
interface GenerateQuestionsRequest { session_id: string; count: number; regenerate: boolean; }
interface SubmitAnswerRequest {
  session_id: string;
  answer_text: string;
  parent_answer_id?: string;
  request_id?: string;
  elapsed_seconds?: number;
}
interface TextCorrectionRequest { text: string; }
interface LocalDateRequest { local_date: string; }
interface ApiErrorPayload { message?: string; code?: string; }

export class ApiError extends Error {
  statusCode: number;
  constructor(message: string, statusCode: number = 0) {
    super(message);
    this.statusCode = statusCode;
  }
}

class ApiClient {
  private accessToken: string = '';
  private refreshToken: string = '';
  private context?: common.UIAbilityContext;
  private initialized: boolean = false;
  private refreshTask?: Promise<boolean> = undefined;

  initialize(context: common.UIAbilityContext): void {
    this.context = context;
  }

  private baseUrl(): string {
    return AppStorage.get<string>('apiBaseUrl') ?? 'http://main.vastsea.cc:48180/api/v1';
  }

  private async tokenPreferences(): Promise<preferences.Preferences> {
    if (this.context === undefined) throw new ApiError('应用存储尚未初始化');
    return preferences.getPreferences(this.context, 'speechmirror_session');
  }

  async restoreSession(): Promise<boolean> {
    if (this.initialized) return this.accessToken.length > 0 && this.refreshToken.length > 0;
    try {
      const store = await this.tokenPreferences();
      this.accessToken = `${await store.get('access_token', '')}`;
      this.refreshToken = `${await store.get('refresh_token', '')}`;
    } catch (_) {
      this.accessToken = '';
      this.refreshToken = '';
    }
    this.initialized = true;
    return this.accessToken.length > 0 && this.refreshToken.length > 0;
  }

  private async saveTokens(tokens: TokenPair): Promise<void> {
    this.accessToken = tokens.access_token;
    this.refreshToken = tokens.refresh_token;
    this.initialized = true;
    const store = await this.tokenPreferences();
    await store.put('access_token', tokens.access_token);
    await store.put('refresh_token', tokens.refresh_token);
    await store.flush();
  }

  private async clearTokens(): Promise<void> {
    this.accessToken = '';
    this.refreshToken = '';
    this.initialized = true;
    try {
      const store = await this.tokenPreferences();
      await store.delete('access_token');
      await store.delete('refresh_token');
      await store.flush();
    } catch (_) {}
  }

  private messageFor(statusCode: number, result: string): string {
    try {
      const payload = JSON.parse(result) as ApiErrorPayload;
      if (payload.message !== undefined && payload.message.trim().length > 0) return payload.message;
    } catch (_) {}
    if (statusCode === 401) return '登录状态已失效，请重新登录';
    if (statusCode === 404) return '请求的内容不存在';
    if (statusCode >= 500) return '服务暂时未完成请求，请稍后重试';
    return `请求失败（${statusCode}）`;
  }

  private async perform<T>(method: http.RequestMethod, path: string, body?: object,
    authorized: boolean = true): Promise<T> {
    const client = http.createHttp();
    const headers: Record<string, string> = { 'Content-Type': 'application/json' };
    if (authorized && this.accessToken.length > 0) headers['Authorization'] = `Bearer ${this.accessToken}`;
    try {
      const response = await client.request(`${this.baseUrl()}${path}`, {
        method,
        header: headers,
        extraData: body === undefined ? undefined : JSON.stringify(body),
        connectTimeout: 15000,
        readTimeout: 120000
      });
      const result = response.result as string;
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new ApiError(this.messageFor(response.responseCode, result), response.responseCode);
      }
      return JSON.parse(result) as T;
    } finally {
      client.destroy();
    }
  }

  private async executeRefresh(): Promise<boolean> {
    if (this.refreshToken.length === 0) return false;
    const attemptedToken = this.refreshToken;
    try {
      const body: RefreshRequest = { refresh_token: attemptedToken };
      const tokens = await this.perform<TokenPair>(http.RequestMethod.POST, '/auth/refresh', body, false);
      await this.saveTokens(tokens);
      return true;
    } catch (_) {
      if (this.refreshToken.length > 0 && this.refreshToken !== attemptedToken) return true;
      await this.clearTokens();
      return false;
    }
  }

  private async refresh(): Promise<boolean> {
    if (this.refreshTask !== undefined) return this.refreshTask;
    this.refreshTask = this.executeRefresh();
    try {
      return await this.refreshTask;
    } finally {
      this.refreshTask = undefined;
    }
  }

  private async request<T>(method: http.RequestMethod, path: string, body?: object): Promise<T> {
    await this.restoreSession();
    try {
      return await this.perform<T>(method, path, body);
    } catch (reason) {
      if (reason instanceof ApiError && reason.statusCode === 401 && await this.refresh()) {
        return this.perform<T>(method, path, body);
      }
      if (reason instanceof Error) throw reason;
      throw new ApiError(`${reason}`);
    }
  }

  private localDate(): string {
    const date = new Date();
    const month = `${date.getMonth() + 1}`.padStart(2, '0');
    const day = `${date.getDate()}`.padStart(2, '0');
    return `${date.getFullYear()}-${month}-${day}`;
  }

  async login(username: string, password: string, register: boolean): Promise<UserProfile> {
    const body: LoginRequest = { username, password };
    const tokens = await this.perform<TokenPair>(http.RequestMethod.POST,
      register ? '/auth/register' : '/auth/login', body, false);
    await this.saveTokens(tokens);
    await this.recordActivity();
    return this.getProfile();
  }

  async logout(): Promise<void> {
    if (this.refreshToken.length > 0) {
      const body: RefreshRequest = { refresh_token: this.refreshToken };
      try { await this.request<object>(http.RequestMethod.POST, '/auth/logout', body); } catch (_) {}
    }
    await this.clearTokens();
  }

  getProfile(): Promise<UserProfile> { return this.request<UserProfile>(http.RequestMethod.GET, '/me'); }
  updateProfile(update: UserProfileUpdate): Promise<UserProfile> {
    return this.request<UserProfile>(http.RequestMethod.PUT, '/me', update);
  }
  recordActivity(): Promise<object> {
    const body: LocalDateRequest = { local_date: this.localDate() };
    return this.request<object>(http.RequestMethod.POST, '/me/activity', body);
  }
  getActivity(): Promise<ActivitySummary> {
    return this.request<ActivitySummary>(http.RequestMethod.GET, `/me/activity?through=${this.localDate()}`);
  }

  listProjects(): Promise<Project[]> { return this.request<Project[]>(http.RequestMethod.GET, '/projects'); }
  getProject(id: string): Promise<Project> { return this.request<Project>(http.RequestMethod.GET, `/projects/${id}`); }
  createProject(name: string, description: string, seconds: number): Promise<Project> {
    const body: CreateProjectRequest = { name, description, defense_duration_seconds: seconds };
    return this.request<Project>(http.RequestMethod.POST, '/projects', body);
  }
  updateProject(id: string, name: string, description: string, seconds: number): Promise<Project> {
    const body: CreateProjectRequest = { name, description, defense_duration_seconds: seconds };
    return this.request<Project>(http.RequestMethod.PUT, `/projects/${id}`, body);
  }
  deleteProject(id: string): Promise<object> {
    return this.request<object>(http.RequestMethod.DELETE, `/projects/${id}`);
  }

  listDocuments(projectId: string): Promise<DocumentItem[]> {
    return this.request<DocumentItem[]>(http.RequestMethod.GET, `/projects/${projectId}/documents`);
  }
  getDocument(documentId: string): Promise<DocumentItem> {
    return this.request<DocumentItem>(http.RequestMethod.GET, `/documents/${documentId}`);
  }
  correctDocumentText(documentId: string, text: string): Promise<DocumentItem> {
    const body: TextCorrectionRequest = { text };
    return this.request<DocumentItem>(http.RequestMethod.PUT, `/documents/${documentId}/text`, body);
  }

  async uploadDocument(projectId: string, fileUri: string): Promise<DocumentItem> {
    await this.restoreSession();
    const client = http.createHttp();
    const name = decodeURIComponent(fileUri.split('/').pop() ?? 'document');
    const extension = name.split('.').pop()?.toLowerCase() ?? '';
    const contentTypes: Record<string, string> = {
      'pdf': 'application/pdf', 'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document', 'txt': 'text/plain',
      'md': 'text/markdown', 'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg'
    };
    try {
      const response = await client.request(`${this.baseUrl()}/projects/${projectId}/documents`, {
        method: http.RequestMethod.POST,
        header: { 'Authorization': `Bearer ${this.accessToken}` },
        multiFormDataList: [{
          name: 'file',
          contentType: contentTypes[extension] ?? 'application/octet-stream',
          remoteFileName: name,
          filePath: fileUri
        }],
        connectTimeout: 15000,
        readTimeout: 120000
      });
      const result = response.result as string;
      if (response.responseCode < 200 || response.responseCode >= 300) {
        throw new ApiError(this.messageFor(response.responseCode, result), response.responseCode);
      }
      return JSON.parse(result) as DocumentItem;
    } finally {
      client.destroy();
    }
  }

  createSession(projectId: string, seconds: number): Promise<SessionItem> {
    const body: CreateSessionRequest = { target_seconds: seconds, local_date: this.localDate() };
    return this.request<SessionItem>(http.RequestMethod.POST, `/projects/${projectId}/sessions`, body);
  }
  listSessions(projectId: string): Promise<SessionItem[]> {
    return this.request<SessionItem[]>(http.RequestMethod.GET, `/projects/${projectId}/sessions`);
  }
  completeSession(sessionId: string, seconds: number, transcript: string): Promise<SessionItem> {
    const body: CompleteSessionRequest = { actual_seconds: Math.max(1, seconds), transcript };
    return this.request<SessionItem>(http.RequestMethod.POST, `/sessions/${sessionId}/complete`, body);
  }
  async analyzeSession(sessionId: string): Promise<ReportPayload> {
    const envelope = await this.request<ReportEnvelope>(http.RequestMethod.POST, `/sessions/${sessionId}/analyze`);
    return envelope.report;
  }
  async getReport(sessionId: string): Promise<ReportPayload> {
    const envelope = await this.request<ReportEnvelope>(http.RequestMethod.GET, `/sessions/${sessionId}/report`);
    return envelope.report;
  }
  getTrends(projectId: string): Promise<Trends> {
    return this.request<Trends>(http.RequestMethod.GET, `/projects/${projectId}/trends`);
  }

  listQuestions(projectId: string): Promise<JuryQuestion[]> {
    return this.request<JuryQuestion[]>(http.RequestMethod.GET, `/projects/${projectId}/questions`);
  }
  generateQuestions(projectId: string, sessionId: string, count: number = 1,
    regenerate: boolean = false): Promise<JuryQuestion[]> {
    const body: GenerateQuestionsRequest = { session_id: sessionId, count, regenerate };
    return this.request<JuryQuestion[]>(http.RequestMethod.POST, `/projects/${projectId}/questions`, body);
  }
  submitAnswer(questionId: string, sessionId: string, answerText: string, parentAnswerId?: string,
    requestId?: string, elapsedSeconds?: number): Promise<JuryAnswer> {
    const body: SubmitAnswerRequest = {
      session_id: sessionId,
      answer_text: answerText,
      parent_answer_id: parentAnswerId,
      request_id: requestId,
      elapsed_seconds: elapsedSeconds
    };
    return this.request<JuryAnswer>(http.RequestMethod.POST, `/questions/${questionId}/answers`, body);
  }
}

export const apiClient = new ApiClient();
