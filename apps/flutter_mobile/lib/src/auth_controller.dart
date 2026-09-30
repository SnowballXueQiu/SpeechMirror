import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';

final apiClientProvider = Provider<ApiClient>((ref) => ApiClient());
final authControllerProvider = ChangeNotifierProvider<AuthController>(
  (ref) => AuthController(ref.read(apiClientProvider)),
);

class AuthController extends ChangeNotifier {
  AuthController(this._api) {
    _api.onSessionExpired = _handleSessionExpired;
  }
  final ApiClient _api;
  bool initialized = false;
  bool authenticated = false;
  bool busy = false;
  String? error;
  UserProfile? profile;
  bool _activityRecorded = false;

  bool get needsOnboarding =>
      authenticated && profile != null && !profile!.onboardingCompleted;

  Future<void> restore() async {
    if (initialized) return;
    try {
      authenticated = await _api.restoreSession();
      if (authenticated) await _hydrateProfile();
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
      await _hydrateProfile();
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
    profile = null;
    _activityRecorded = false;
    notifyListeners();
  }

  void _handleSessionExpired() {
    authenticated = false;
    profile = null;
    busy = false;
    error = null;
    _activityRecorded = false;
    initialized = true;
    notifyListeners();
  }

  Future<UserProfile?> refreshProfile() async {
    if (!authenticated) return null;
    try {
      profile = await _api.getProfile();
      notifyListeners();
      return profile;
    } catch (_) {
      return profile;
    }
  }

  Future<UserProfile> updateProfile(UserProfileUpdate update) async {
    profile = await _api.updateProfile(update);
    notifyListeners();
    return profile!;
  }

  Future<void> _hydrateProfile() async {
    try {
      profile = await _api.getProfile();
    } catch (_) {
      profile = null;
    }
    if (!_activityRecorded) {
      _activityRecorded = true;
      try {
        await _api.recordActivity();
      } catch (_) {
        // Activity telemetry must never prevent access to the app.
      }
    }
  }
}
