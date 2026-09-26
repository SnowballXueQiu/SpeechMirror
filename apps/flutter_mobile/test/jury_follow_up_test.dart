import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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

  testWidgets('continues a jury conversation from the previous answer', (
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
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('如何保护原始视频？'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '原始视频只保存在手机本地。');
    await tester.tap(find.text('提交回答'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('回答这一项关键追问'), findsOneWidget);
    await tester.tap(find.text('回答这一项关键追问'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('如何证明服务端没有原始视频？'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '通过服务端存储目录审计。');
    await tester.tap(find.text('提交回答'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.textContaining('90'), findsOneWidget);
    expect(find.text('结束答辩并生成报告'), findsOneWidget);
    expect(api.sessionIds, ['session-1', 'session-1']);
    expect(api.parentAnswerIds, [null, 'answer-1']);
    expect(tester.takeException(), isNull);
  });
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
      category: '风险',
      question: '如何保护原始视频？',
    ),
  ];

  @override
  Future<JuryAnswer> submitAnswer(
    String questionId,
    String sessionId,
    String text, {
    String? parentAnswerId,
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
      },
    );
  }
}
