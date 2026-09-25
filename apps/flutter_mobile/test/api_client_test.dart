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
