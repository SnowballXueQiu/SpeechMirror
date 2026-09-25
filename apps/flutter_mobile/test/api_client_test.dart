import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speechmirror/src/api_client.dart';

void main() {
  test('selects loopback addresses for each emulator platform', () {
    expect(
      defaultApiBaseUrl(android: true, configuredUrl: ''),
      'http://10.0.2.2:8080/api/v1',
    );
    expect(
      defaultApiBaseUrl(android: false, configuredUrl: ''),
      'http://127.0.0.1:8080/api/v1',
    );
    expect(
      defaultApiBaseUrl(android: true, configuredUrl: 'https://api.example/v1'),
      'https://api.example/v1',
    );
  });

  test(
    'shares one refresh request across concurrent unauthorized calls',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://speechmirror.test/api/v1'));
      final storage = MemoryTokenStore({
        'access_token': 'expired-access',
        'refresh_token': 'valid-refresh',
      });
      var refreshCalls = 0;

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) async {
            if (options.path.endsWith('/auth/refresh')) {
              refreshCalls += 1;
              await Future<void>.delayed(const Duration(milliseconds: 20));
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: {
                    'access_token': 'fresh-access',
                    'refresh_token': 'fresh-refresh',
                  },
                ),
              );
              return;
            }

            if (options.path.endsWith('/projects') &&
                options.headers['authorization'] == 'Bearer fresh-access') {
              handler.resolve(
                Response<List<dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const [],
                ),
              );
              return;
            }

            handler.reject(
              DioException(
                requestOptions: options,
                type: DioExceptionType.badResponse,
                response: Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 401,
                  data: const {
                    'code': 'unauthorized',
                    'message': 'authentication required',
                  },
                ),
              ),
            );
          },
        ),
      );

      final client = ApiClient(dio: dio, storage: storage);
      expect(await client.restoreSession(), isTrue);
      final results = await Future.wait([
        client.listProjects(),
        client.listProjects(),
      ]);

      expect(results, everyElement(isEmpty));
      expect(refreshCalls, 1);
      expect(await storage.read('access_token'), 'fresh-access');
      expect(await storage.read('refresh_token'), 'fresh-refresh');
    },
  );

  test(
    'updates and deletes a project with the authenticated contract',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://speechmirror.test/api/v1'));
      final storage = MemoryTokenStore({
        'access_token': 'valid-access',
        'refresh_token': 'valid-refresh',
      });
      Map<String, dynamic>? updateBody;
      var deleted = false;

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            expect(options.headers['authorization'], 'Bearer valid-access');
            if (options.method == 'PUT' &&
                options.path.endsWith('/projects/p1')) {
              updateBody = Map<String, dynamic>.from(options.data as Map);
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {
                    'id': 'p1',
                    'name': '更新后项目',
                    'description': null,
                    'defense_duration_seconds': 420,
                  },
                ),
              );
              return;
            }
            if (options.method == 'DELETE' &&
                options.path.endsWith('/projects/p1')) {
              deleted = true;
              handler.resolve(
                Response<Map<String, dynamic>>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const {'ok': true},
                ),
              );
              return;
            }
            handler.reject(
              DioException(
                requestOptions: options,
                message: 'unexpected request',
              ),
            );
          },
        ),
      );

      final client = ApiClient(dio: dio, storage: storage);
      expect(await client.restoreSession(), isTrue);
      final project = await client.updateProject('p1', '更新后项目', null, 420);
      await client.deleteProject('p1');

      expect(project.name, '更新后项目');
      expect(updateBody, {
        'name': '更新后项目',
        'description': '',
        'defense_duration_seconds': 420,
      });
      expect(deleted, isTrue);
    },
  );

  test('submits a follow-up answer with its parent turn', () async {
    final dio = Dio(BaseOptions(baseUrl: 'https://speechmirror.test/api/v1'));
    final storage = MemoryTokenStore({
      'access_token': 'valid-access',
      'refresh_token': 'valid-refresh',
    });
    Map<String, dynamic>? requestBody;

    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          requestBody = Map<String, dynamic>.from(options.data as Map);
          handler.resolve(
            Response<Map<String, dynamic>>(
              requestOptions: options,
              statusCode: 200,
              data: const {
                'id': 'answer-2',
                'question_id': 'question-1',
                'session_id': 'session-1',
                'asked_question': '如何验证隐私设计？',
                'parent_answer_id': 'answer-1',
                'answer_text': '通过检查服务端不保存原始视频。',
                'evaluation': {'score': 88, 'follow_up': '临时音频如何清理？'},
                'created_at': '2026-09-26T00:00:00Z',
              },
            ),
          );
        },
      ),
    );

    final client = ApiClient(dio: dio, storage: storage);
    expect(await client.restoreSession(), isTrue);
    final answer = await client.submitAnswer(
      'question-1',
      'session-1',
      '通过检查服务端不保存原始视频。',
      parentAnswerId: 'answer-1',
    );

    expect(requestBody, {
      'session_id': 'session-1',
      'answer_text': '通过检查服务端不保存原始视频。',
      'parent_answer_id': 'answer-1',
    });
    expect(answer.askedQuestion, '如何验证隐私设计？');
    expect(answer.parentAnswerId, 'answer-1');
    expect(answer.followUp, '临时音频如何清理？');
  });
}

class MemoryTokenStore implements TokenStore {
  MemoryTokenStore([Map<String, String>? values])
    : _values = Map.of(values ?? const {});

  final Map<String, String> _values;

  @override
  Future<void> delete(String key) async => _values.remove(key);

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async => _values[key] = value;
}
