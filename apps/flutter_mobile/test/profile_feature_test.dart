import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:speechmirror/src/api_client.dart';
import 'package:speechmirror/src/auth_controller.dart';
import 'package:speechmirror/src/cache_service.dart';
import 'package:speechmirror/src/models.dart';
import 'package:speechmirror/src/screens/onboarding_screen.dart';

void main() {
  test('parses profile and activity summaries from the API contract', () {
    final profile = UserProfile.fromJson({
      'id': 'user-1',
      'username': 'yanjing',
      'bio': '答辩训练',
      'identity': '其他',
      'identity_other': '独立开发者',
      'scenario': '学科竞赛',
      'scenarios': ['学科竞赛', '项目路演'],
      'scenario_other': null,
      'purposes': ['提升表达', '其他'],
      'purpose_other': '验证架构',
      'onboarding_completed': true,
      'research_consent': false,
      'has_avatar': true,
      'created_at': '2026-09-01T00:00:00Z',
      'updated_at': '2026-09-29T00:00:00Z',
    });
    final activity = ActivitySummary.fromJson({
      'through': '2026-09-29',
      'active_days': 2,
      'total_uses': 4,
      'total_practices': 2,
      'current_streak': 2,
      'longest_streak': 2,
      'days': [
        {'date': '2026-09-29', 'use_count': 1, 'practice_count': 1},
      ],
    });

    expect(profile.displayIdentity, '独立开发者');
    expect(profile.displayScenarios, ['学科竞赛', '项目路演']);
    expect(profile.displayPurposes, ['提升表达', '验证架构']);
    expect(activity.totalPractices, 2);
    expect(activity.days.single.practiceCount, 1);
  });

  test(
    'cache cleanup only removes the configured temporary directory',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'speechmirror-cache-test',
      );
      addTearDown(() => root.delete(recursive: true));
      final cache = Directory('${root.path}/cache')..createSync();
      final documents = Directory('${root.path}/documents')..createSync();
      File('${cache.path}/temporary.m4a').writeAsBytesSync([1, 2, 3]);
      File('${documents.path}/pending.m4a').writeAsBytesSync([4, 5, 6]);
      final service = CacheService(directoryProvider: () async => cache);

      expect(await service.sizeBytes(), 3);
      await service.clear();

      expect(cache.listSync(), isEmpty);
      expect(File('${documents.path}/pending.m4a').existsSync(), isTrue);
    },
  );

  testWidgets('onboarding can be skipped without research consent', (
    tester,
  ) async {
    final api = _ProfileApiClient();
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/projects',
          builder: (context, state) => const Scaffold(body: Text('项目列表')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text('跳过'));
    await tester.pumpAndSettle();

    expect(find.text('项目列表'), findsOneWidget);
    expect(api.update?.onboardingCompleted, isTrue);
    expect(api.update?.researchConsent, isFalse);
    expect(api.update?.identity, isNull);
    expect(api.update?.purposes, isEmpty);
  });

  testWidgets('onboarding stores more than one training scenario', (
    tester,
  ) async {
    final api = _ProfileApiClient();
    final router = GoRouter(
      initialLocation: '/onboarding',
      routes: [
        GoRoute(
          path: '/onboarding',
          builder: (context, state) => const OnboardingScreen(),
        ),
        GoRoute(
          path: '/projects',
          builder: (context, state) => const Scaffold(body: Text('项目列表')),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: MaterialApp.router(routerConfig: router),
      ),
    );

    await tester.tap(find.text('本科生'));
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('毕业答辩'));
    await tester.tap(find.text('学科竞赛'));
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('完成设置'));
    await tester.pumpAndSettle();

    expect(api.update?.scenarios, ['毕业答辩', '学科竞赛']);
    expect(find.text('项目列表'), findsOneWidget);
  });
}

class _ProfileApiClient extends ApiClient {
  UserProfileUpdate? update;

  @override
  Future<UserProfile> updateProfile(UserProfileUpdate update) async {
    this.update = update;
    return UserProfile(
      id: 'user-1',
      username: 'yanjing',
      purposes: update.purposes,
      onboardingCompleted: update.onboardingCompleted,
      researchConsent: update.researchConsent,
      hasAvatar: false,
      createdAt: DateTime(2026, 9, 29),
      updatedAt: DateTime(2026, 9, 29),
      identity: update.identity,
      scenarios: update.scenarios,
    );
  }
}
