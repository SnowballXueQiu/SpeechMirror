import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final authControllerProvider = ChangeNotifierProvider<AuthController>(
  (ref) => AuthController(ref.read(apiClientProvider)),
);

class AuthController extends ChangeNotifier {
  AuthController(this._api);
  final ApiClient _api;
  bool initialized = false;
  bool authenticated = false;
  bool busy = false;
  String? error;

  Future<void> restore() async {
    if (initialized) return;
    try {
      authenticated = await _api.restoreSession();
    } finally {
      initialized = true;
      notifyListeners();
    }
  }

  Future<bool> submit(
    String username,
    String password, {
    required bool register,
  }) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      await _api.login(username.trim(), password, register: register);
      authenticated = true;
      return true;
    } catch (exception) {
      error = exception.toString();
      return false;
    } finally {
      busy = false;
      initialized = true;
      notifyListeners();
    }
  }

  Future<void> logout() async {
    await _api.logout();
    authenticated = false;
    notifyListeners();
  }
}
