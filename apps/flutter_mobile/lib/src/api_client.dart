import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class TokenStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureTokenStore implements TokenStore {
  const SecureTokenStore([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

String defaultApiBaseUrl({bool? android, String? configuredUrl}) {
  final configured =
      configuredUrl ??
      const String.fromEnvironment('API_BASE_URL', defaultValue: '');
  if (configured.trim().isNotEmpty) return configured.trim();
  return (android ?? Platform.isAndroid)
      ? 'http://10.0.2.2:8080/api/v1'
      : 'http://127.0.0.1:8080/api/v1';
}

class ApiClient {
  ApiClient({Dio? dio, TokenStore? storage})
    : _dio =
          dio ??
          Dio(
            BaseOptions(
              baseUrl: defaultApiBaseUrl(),
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 120),
            ),
          ),
      _storage = storage ?? const SecureTokenStore();

  final Dio _dio;
  final TokenStore _storage;
  String? _accessToken;
  String? _refreshToken;
  Future<bool>? _refreshInFlight;

  Future<bool> restoreSession() async {
    try {
      _accessToken = await _storage.read('access_token');
      _refreshToken = await _storage.read('refresh_token');
      return _accessToken != null && _refreshToken != null;
    } catch (_) {
      _accessToken = null;
      _refreshToken = null;
      return false;
    }
  }

  Future<void> login(
    String username,
    String password, {
    bool register = false,
  }) async {
    final response = await _call(
      () => _dio.post<Map<String, dynamic>>(
        register ? '/auth/register' : '/auth/login',
        data: {'username': username, 'password': password},
      ),
      retryAuth: false,
    );
    await _storeTokens(response.data!);
  }

  Future<void> logout() async {
    final refresh = _refreshToken;
    if (refresh != null) {
      try {
        await _authorized(
          () => _dio.post('/auth/logout', data: {'refresh_token': refresh}),
        );
      } catch (_) {}
    }
    await _clearTokens();
  }

  Future<List<Project>> listProjects() async {
    final response = await _authorized(
      () => _dio.get<List<dynamic>>('/projects'),
    );
    return response.data!
        .map((item) => Project.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Project> createProject(
    String name,
    String? description,
    int seconds,
  ) async {
    final response = await _authorized(
      () => _dio.post<Map<String, dynamic>>(
        '/projects',
        data: {
          'name': name,
          'description': description,
          'defense_duration_seconds': seconds,
        },
      ),
    );
    return Project.fromJson(response.data!);
  }

  Future<Project> getProject(String id) async {
    final response = await _authorized(
      () => _dio.get<Map<String, dynamic>>('/projects/$id'),
    );
    return Project.fromJson(response.data!);
  }

  Future<Project> updateProject(
    String id,
    String name,
    String? description,
    int seconds,
  ) async {
    final response = await _authorized(
      () => _dio.put<Map<String, dynamic>>(
        '/projects/$id',
        data: {
          'name': name,
          'description': description ?? '',
          'defense_duration_seconds': seconds,
        },
      ),
    );
    return Project.fromJson(response.data!);
  }

  Future<void> deleteProject(String id) async {
    await _authorized(() => _dio.delete('/projects/$id'));
  }

  Future<List<ProjectDocument>> listDocuments(String projectId) async {
    final response = await _authorized(
      () => _dio.get<List<dynamic>>('/projects/$projectId/documents'),
    );
    return response.data!
        .map((item) => ProjectDocument.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<ProjectDocument> getDocument(String documentId) async {
    final response = await _authorized(
      () => _dio.get<Map<String, dynamic>>('/documents/$documentId'),
    );
    return ProjectDocument.fromJson(response.data!);
  }

  Future<ProjectDocument> uploadDocument(
    String projectId,
    PlatformFile file,
  ) async {
    if (file.path == null) throw const ApiException('无法读取所选文件');
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        file.path!,
        filename: file.name,
        contentType: _mediaType(file.extension),
      ),
    });
    final response = await _authorized(
      () => _dio.post<Map<String, dynamic>>(
        '/projects/$projectId/documents',
        data: form,
      ),
    );
    return ProjectDocument.fromJson(response.data!);
  }

  Future<ProjectDocument> correctDocumentText(
    String documentId,
    String text,
  ) async {
    final response = await _authorized(
      () => _dio.put<Map<String, dynamic>>(
        '/documents/$documentId/text',
        data: {'text': text},
      ),
    );
    return ProjectDocument.fromJson(response.data!);
  }

  Future<RehearsalSession> createSession(
    String projectId,
    int seconds,
    String? localVideoRef,
  ) async {
    final response = await _authorized(
      () => _dio.post<Map<String, dynamic>>(
        '/projects/$projectId/sessions',
        data: {'target_seconds': seconds, 'local_video_ref': localVideoRef},
      ),
    );
    return RehearsalSession.fromJson(response.data!);
  }

  Future<List<RehearsalSession>> listSessions(String projectId) async {
    final response = await _authorized(
      () => _dio.get<List<dynamic>>('/projects/$projectId/sessions'),
    );
    return response.data!
        .map((item) => RehearsalSession.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<TrainingTrends> getTrends(String projectId) async {
    final response = await _authorized(
      () => _dio.get<Map<String, dynamic>>('/projects/$projectId/trends'),
    );
    return TrainingTrends.fromJson(response.data!);
  }

  Future<String> uploadAudio(
    String sessionId,
    String path, {
    bool answerOnly = false,
  }) async {
    final form = FormData.fromMap({
      'file': await MultipartFile.fromFile(
        path,
        filename: path.split(Platform.pathSeparator).last,
      ),
    });
    final response = await _authorized(
      () => _dio.post<Map<String, dynamic>>(
        '/sessions/$sessionId/${answerOnly ? 'answer-audio' : 'audio'}',
        data: form,
      ),
    );
    return response.data!['transcript'] as String;
  }

  Future<void> uploadMetrics(
    String sessionId,
    List<Map<String, dynamic>> samples,
  ) async {
    await _authorized(
      () =>
          _dio.post('/sessions/$sessionId/metrics', data: {'samples': samples}),
    );
  }

  Future<void> completeSession(
    String sessionId,
    int seconds,
    String transcript,
  ) async {
    await _authorized(
      () => _dio.post(
        '/sessions/$sessionId/complete',
        data: {'actual_seconds': seconds, 'transcript': transcript},
      ),
    );
  }

  Future<RehearsalReport> analyzeSession(String sessionId) async {
    final response = await _authorized(
      () => _dio.post<Map<String, dynamic>>('/sessions/$sessionId/analyze'),
    );
    return RehearsalReport.fromJson(response.data!);
  }

  Future<RehearsalReport> getReport(String sessionId) async {
    final response = await _authorized(
      () => _dio.get<Map<String, dynamic>>('/sessions/$sessionId/report'),
    );
    return RehearsalReport.fromJson(response.data!);
  }

  Future<List<JuryQuestion>> listQuestions(String projectId) async {
    final response = await _authorized(
      () => _dio.get<List<dynamic>>('/projects/$projectId/questions'),
    );
    return response.data!
        .map((item) => JuryQuestion.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<List<JuryQuestion>> generateQuestions(
    String projectId, {
    String? sessionId,
  }) async {
    final response = await _authorized(
      () => _dio.post<List<dynamic>>(
        '/projects/$projectId/questions',
        data: {'session_id': sessionId, 'count': 5},
      ),
    );
    return response.data!
        .map((item) => JuryQuestion.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<Map<String, dynamic>> submitAnswer(
    String questionId,
    String sessionId,
    String text,
  ) async {
    final response = await _authorized(
      () => _dio.post<Map<String, dynamic>>(
        '/questions/$questionId/answers',
        data: {'session_id': sessionId, 'answer_text': text},
      ),
    );
    return response.data!['evaluation'] as Map<String, dynamic>;
  }

  Future<Response<T>> _authorized<T>(
    Future<Response<T>> Function() action,
  ) async {
    _dio.options.headers['authorization'] = 'Bearer $_accessToken';
    return _call(action, retryAuth: true);
  }

  Future<Response<T>> _call<T>(
    Future<Response<T>> Function() action, {
    required bool retryAuth,
  }) async {
    try {
      return await action();
    } on DioException catch (error) {
      if (retryAuth && error.response?.statusCode == 401 && await _refresh()) {
        _dio.options.headers['authorization'] = 'Bearer $_accessToken';
        return _call(action, retryAuth: false);
      }
      throw ApiException(_errorMessage(error));
    }
  }

  Future<bool> _refresh() async {
    final inFlight = _refreshInFlight;
    if (inFlight != null) return inFlight;
    final operation = _performRefresh();
    _refreshInFlight = operation;
    try {
      return await operation;
    } finally {
      if (identical(_refreshInFlight, operation)) {
        _refreshInFlight = null;
      }
    }
  }

  Future<bool> _performRefresh() async {
    final refresh = _refreshToken;
    if (refresh == null) return false;
    try {
      final response = await _dio.post<Map<String, dynamic>>(
        '/auth/refresh',
        data: {'refresh_token': refresh},
      );
      await _storeTokens(response.data!);
      return true;
    } catch (_) {
      await _clearTokens();
      return false;
    }
  }

  Future<void> _storeTokens(Map<String, dynamic> data) async {
    _accessToken = data['access_token'] as String;
    _refreshToken = data['refresh_token'] as String;
    await _storage.write('access_token', _accessToken!);
    await _storage.write('refresh_token', _refreshToken!);
  }

  Future<void> _clearTokens() async {
    _accessToken = null;
    _refreshToken = null;
    _dio.options.headers.remove('authorization');
    await Future.wait([
      _storage.delete('access_token'),
      _storage.delete('refresh_token'),
    ]);
  }

  String _errorMessage(DioException error) {
    final data = error.response?.data;
    final body = data is Map ? data : const <String, dynamic>{};
    return switch (body['code']) {
      'unauthorized' => '用户名或密码错误，或登录已过期',
      'conflict' => '该用户名已被使用',
      'bad_request' => body['message']?.toString() ?? '请检查输入内容',
      _ => body['message']?.toString() ?? error.message ?? '网络请求失败',
    };
  }

  DioMediaType _mediaType(String? extension) => switch (extension
      ?.toLowerCase()) {
    'pdf' => DioMediaType.parse('application/pdf'),
    'docx' => DioMediaType.parse(
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    ),
    'pptx' => DioMediaType.parse(
      'application/vnd.openxmlformats-officedocument.presentationml.presentation',
    ),
    'txt' => DioMediaType.parse('text/plain'),
    'md' => DioMediaType.parse('text/markdown'),
    'png' => DioMediaType.parse('image/png'),
    'jpg' || 'jpeg' => DioMediaType.parse('image/jpeg'),
    _ => DioMediaType.parse('application/octet-stream'),
  };
}

class PlatformFile {
  PlatformFile({
    required this.name,
    required this.path,
    required this.extension,
  });
  final String name;
  final String? path;
  final String? extension;
}
