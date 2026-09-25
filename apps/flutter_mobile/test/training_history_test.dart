import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:speechmirror/src/api_client.dart';
import 'package:speechmirror/src/auth_controller.dart';
import 'package:speechmirror/src/models.dart';
import 'package:speechmirror/src/screens/training_history_screen.dart';

void main() {
  testWidgets('shows real sessions and an explicit no-report state', (
    tester,
  ) async {
    final api = _HistoryApiClient(withReport: false);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: TrainingHistoryScreen(projectId: 'p1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('暂无可比较报告'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('本地录制待分析'),
      300,
      scrollable: find.byType(Scrollable),
    );
    expect(find.text('本地录制待分析'), findsOneWidget);
    expect(find.textContaining('录制待完成'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('switches trend metrics and opens a persisted report', (
    tester,
  ) async {
    final api = _HistoryApiClient(withReport: true);
    final router = GoRouter(
      initialLocation: '/projects/p1/history',
      routes: [
        GoRoute(
          path: '/projects/:id/history',
          builder: (context, state) =>
              TrainingHistoryScreen(projectId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/reports/:sessionId',
          builder: (context, state) =>
              Scaffold(body: Text('报告 ${state.pathParameters['sessionId']}')),
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
    await tester.pumpAndSettle();

    expect(find.text('1 份'), findsOneWidget);
    expect(find.text('18 秒'), findsOneWidget);
    await tester.tap(find.text('口头禅'));
    await tester.pumpAndSettle();
    expect(find.text('0.6 次/分'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('第1次训练'),
      300,
      scrollable: find.byType(Scrollable),
    );
    await tester.tap(find.text('第1次训练'));
    await tester.pumpAndSettle();
    expect(find.text('报告 s1'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _HistoryApiClient extends ApiClient {
  _HistoryApiClient({required this.withReport});

  final bool withReport;

  @override
  Future<Project> getProject(String id) async =>
      const Project(id: 'p1', name: '毕业答辩', durationSeconds: 300);

  @override
  Future<List<RehearsalSession>> listSessions(String projectId) async => [
    RehearsalSession(
      id: 's1',
      projectId: 'p1',
      title: withReport ? '第1次训练' : '本地录制待分析',
      status: withReport ? 'completed' : 'recording',
      targetSeconds: 300,
      actualSeconds: withReport ? 318 : 28,
      createdAt: DateTime.utc(2026, 9, 25, 2, 30),
    ),
  ];

  @override
  Future<TrainingTrends> getTrends(String projectId) async => TrainingTrends(
    projectId: 'p1',
    points: withReport
        ? [
            TrainingTrendPoint(
              sessionId: 's1',
              createdAt: DateTime.utc(2026, 9, 25, 2, 36),
              targetSeconds: 300,
              actualSeconds: 318,
              durationDeviationSeconds: 18,
              charactersPerMinute: 178.5,
              fillerCount: 3,
              fillerPerMinute: 0.566,
              deliveryScore: 81,
              timingScore: 92,
              contentScore: 84,
            ),
          ]
        : const [],
  );
}
