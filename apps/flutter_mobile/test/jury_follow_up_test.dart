import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:speechmirror/src/api_client.dart';
import 'package:speechmirror/src/auth_controller.dart';
import 'package:speechmirror/src/models.dart';
import 'package:speechmirror/src/screens/jury_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const ttsChannel = MethodChannel('flutter_tts');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, (_) async => 1);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(ttsChannel, null);
  });

  testWidgets('automatically follows up and then changes topic', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _JuryApiClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: JuryScreen(projectId: 'project-1', sessionId: 'session-1'),
        ),
      ),
    );
    await _pumpAsync(tester);
    expect(find.text('为什么选择端云协同架构？'), findsOneWidget);
    await tester.tap(find.byTooltip('输入文字回答'));
    await _pumpAsync(tester);
    await tester.enterText(find.byType(TextField), '原始视频只保存在手机本地。');
    await tester.tap(find.text('提交回答'));
    await _pumpAsync(tester);

    expect(find.text('如何证明服务端没有原始视频？'), findsOneWidget);
    expect(find.textContaining('本轮反馈'), findsNothing);
    await tester.tap(find.byTooltip('输入文字回答'));
    await _pumpAsync(tester);
    await tester.enterText(find.byType(TextField), '通过服务端存储目录审计。');
    await tester.tap(find.text('提交回答'));
    await _pumpAsync(tester);

    expect(find.text('你们如何验证目标用户确实需要这项功能？'), findsOneWidget);
    expect(find.textContaining('/ 03'), findsNothing);
    expect(api.sessionIds, ['session-1', 'session-1']);
    expect(api.parentAnswerIds, [null, 'answer-1']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('automatically retries question generation', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _RetryingJuryApiClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: JuryScreen(
            projectId: 'project-1',
            sessionId: 'session-1',
            autoStart: true,
          ),
        ),
      ),
    );
    await _pumpAsync(tester, cycles: 60);

    expect(find.text('为什么选择端云协同架构？'), findsOneWidget);
    expect(api.generationAttempts, 2);
    expect(find.text('重试'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('shows manual retry only after five automatic retries fail', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _FailingJuryApiClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: JuryScreen(projectId: 'project-1', sessionId: 'session-1'),
        ),
      ),
    );
    await _pumpAsync(tester, cycles: 220);

    expect(api.generationAttempts, 6);
    expect(find.text('AI服务暂时未完成请求，请稍后重试'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    final endButton = tester.widget<IconButton>(
      find.descendant(
        of: find.byTooltip('结束答辩'),
        matching: find.byType(IconButton),
      ),
    );
    expect(endButton.onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('answer failure does not lock answer or end controls', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _FailingAnswerJuryApiClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: JuryScreen(projectId: 'project-1', sessionId: 'session-1'),
        ),
      ),
    );
    await _pumpAsync(tester);
    await tester.tap(find.byTooltip('输入文字回答'));
    await _pumpAsync(tester);
    await tester.enterText(find.byType(TextField), '测试回答');
    await tester.tap(find.text('提交回答'));
    await _pumpAsync(tester, cycles: 220);

    expect(find.text('AI服务暂时未完成请求，请稍后重试'), findsOneWidget);
    for (final tooltip in ['输入文字回答', '开始回答', '结束答辩']) {
      final button = tester.widget<IconButton>(
        find.descendant(
          of: find.byTooltip(tooltip),
          matching: find.byType(IconButton),
        ),
      );
      expect(
        button.onPressed,
        isNotNull,
        reason: '$tooltip should stay enabled',
      );
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('ending a defense leaves the call before report generation', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _JuryApiClient();
    final router = GoRouter(
      initialLocation: '/projects/project-1/jury',
      routes: [
        GoRoute(
          path: '/projects/:id/jury',
          builder: (context, state) =>
              const JuryScreen(projectId: 'project-1', sessionId: 'session-1'),
        ),
        GoRoute(
          path: '/reports/:sessionId',
          builder: (context, state) =>
              Scaffold(body: Text('生成报告 ${state.pathParameters['sessionId']}')),
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
    await _pumpAsync(tester);
    await tester.tap(find.byTooltip('结束答辩'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '结束答辩'));
    await tester.pumpAndSettle();

    expect(find.text('生成报告 session-1'), findsOneWidget);
    expect(find.byType(JuryScreen), findsNothing);
    expect(
      router.routeInformationProvider.value.uri.queryParameters['generate'],
      '1',
    );
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpAsync(WidgetTester tester, {int cycles = 24}) async {
  for (var index = 0; index < cycles; index += 1) {
    await tester.pump(const Duration(milliseconds: 20));
  }
}

class _JuryApiClient extends ApiClient {
  final List<String> sessionIds = [];
  final List<String?> parentAnswerIds = [];

  @override
  Future<Project> getProject(String id) async =>
      const Project(id: 'project-1', name: '言镜', durationSeconds: 300);

  @override
  Future<List<JuryQuestion>> listQuestions(String projectId) async => const [
    JuryQuestion(
      id: 'question-1',
      sessionId: 'session-1',
      category: '技术架构',
      question: '为什么选择端云协同架构？',
    ),
  ];

  @override
  Future<List<JuryQuestion>> generateQuestions(
    String projectId, {
    String? sessionId,
    int count = 5,
    bool regenerate = false,
  }) async => [
    ...await listQuestions(projectId),
    if (count > 1)
      const JuryQuestion(
        id: 'question-2',
        sessionId: 'session-1',
        category: '用户与场景',
        question: '你们如何验证目标用户确实需要这项功能？',
      ),
  ];

  @override
  Future<JuryAnswer> submitAnswer(
    String questionId,
    String sessionId,
    String text, {
    String? parentAnswerId,
    String? requestId,
    int? elapsedSeconds,
  }) async {
    sessionIds.add(sessionId);
    parentAnswerIds.add(parentAnswerId);
    final secondTurn = parentAnswerId != null;
    return JuryAnswer(
      id: secondTurn ? 'answer-2' : 'answer-1',
      questionId: questionId,
      sessionId: sessionId,
      askedQuestion: secondTurn ? '如何证明服务端没有原始视频？' : '如何保护原始视频？',
      parentAnswerId: parentAnswerId,
      answerText: text,
      evaluation: {
        'score': secondTurn ? 90 : 85,
        'follow_up': secondTurn ? null : '如何证明服务端没有原始视频？',
        'decision': secondTurn ? 'next_question' : 'follow_up',
      },
    );
  }
}

class _RetryingJuryApiClient extends _JuryApiClient {
  int generationAttempts = 0;

  @override
  Future<List<JuryQuestion>> generateQuestions(
    String projectId, {
    String? sessionId,
    int count = 5,
    bool regenerate = false,
  }) async {
    generationAttempts += 1;
    if (generationAttempts == 1) {
      throw const ApiException('AI服务暂时未完成请求，请稍后重试');
    }
    return super.generateQuestions(
      projectId,
      sessionId: sessionId,
      count: count,
      regenerate: regenerate,
    );
  }
}

class _FailingJuryApiClient extends _JuryApiClient {
  int generationAttempts = 0;

  @override
  Future<List<JuryQuestion>> generateQuestions(
    String projectId, {
    String? sessionId,
    int count = 5,
    bool regenerate = false,
  }) async {
    generationAttempts += 1;
    throw const ApiException('AI服务暂时未完成请求，请稍后重试');
  }
}

class _FailingAnswerJuryApiClient extends _JuryApiClient {
  @override
  Future<JuryAnswer> submitAnswer(
    String questionId,
    String sessionId,
    String text, {
    String? parentAnswerId,
    String? requestId,
    int? elapsedSeconds,
  }) async {
    throw const ApiException('AI服务暂时未完成请求，请稍后重试');
  }
}
