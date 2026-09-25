import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speechmirror/src/api_client.dart';
import 'package:speechmirror/src/auth_controller.dart';
import 'package:speechmirror/src/models.dart';
import 'package:speechmirror/src/screens/jury_screen.dart';

void main() {
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
        child: const MaterialApp(home: JuryScreen(projectId: 'project-1')),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('如何保护原始视频？'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '原始视频只保存在手机本地。');
    await tester.tap(find.text('提交评议'));
    await tester.pumpAndSettle();

    expect(find.text('当前追问：如何证明服务端没有原始视频？'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '通过服务端存储目录审计。');
    await tester.tap(find.text('回答追问'));
    await tester.pumpAndSettle();

    expect(find.textContaining('第2轮'), findsOneWidget);
    expect(find.text('当前追问：临时音频如何清理？'), findsOneWidget);
    expect(api.sessionIds, ['session-1', 'session-1']);
    expect(api.parentAnswerIds, [null, 'answer-1']);
    expect(tester.takeException(), isNull);
  });
}

class _JuryApiClient extends ApiClient {
  final List<String> sessionIds = [];
  final List<String?> parentAnswerIds = [];

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
        'follow_up': secondTurn ? '临时音频如何清理？' : '如何证明服务端没有原始视频？',
      },
    );
  }
}
