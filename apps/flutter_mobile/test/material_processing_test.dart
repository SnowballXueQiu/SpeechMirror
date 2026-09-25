import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:speechmirror/src/api_client.dart';
import 'package:speechmirror/src/auth_controller.dart';
import 'package:speechmirror/src/models.dart';
import 'package:speechmirror/src/screens/document_text_screen.dart';
import 'package:speechmirror/src/screens/project_detail_screen.dart';

void main() {
  testWidgets('polls processing material and saves corrected text', (
    tester,
  ) async {
    final api = _MaterialApiClient();
    final router = GoRouter(
      initialLocation: '/projects/p1',
      routes: [
        GoRoute(
          path: '/projects/:id',
          builder: (context, state) =>
              ProjectDetailScreen(projectId: state.pathParameters['id']!),
        ),
        GoRoute(
          path: '/projects/:id/documents/:documentId',
          builder: (context, state) => DocumentTextScreen(
            documentId: state.pathParameters['documentId']!,
          ),
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

    expect(api.listCalls, greaterThanOrEqualTo(2));
    expect(find.text('已完成解析'), findsOneWidget);
    await tester.tap(find.text('defense.md'));
    await tester.pumpAndSettle();

    expect(find.text('已进入知识库，可校对下方文本'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('document-text-editor')),
      '人工校正后的材料内容',
    );
    await tester.tap(find.byTooltip('保存并重建索引'));
    await tester.pumpAndSettle();

    expect(api.correctedText, '人工校正后的材料内容');
    expect(find.text('文本已保存，知识库索引已更新'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _MaterialApiClient extends ApiClient {
  int listCalls = 0;
  String? correctedText;

  ProjectDocument get document => ProjectDocument(
    id: 'd1',
    filename: 'defense.md',
    status: 'ready',
    mediaType: 'text/markdown',
    text: correctedText ?? '# SpeechMirror\n初始解析内容',
  );

  @override
  Future<Project> getProject(String id) async => const Project(
    id: 'p1',
    name: '材料处理测试',
    description: '验证解析状态与人工校正',
    durationSeconds: 300,
  );

  @override
  Future<List<ProjectDocument>> listDocuments(String projectId) async {
    listCalls += 1;
    if (listCalls == 1) {
      return const [
        ProjectDocument(
          id: 'd1',
          filename: 'defense.md',
          status: 'processing',
          mediaType: 'text/markdown',
        ),
      ];
    }
    return [document];
  }

  @override
  Future<ProjectDocument> getDocument(String documentId) async => document;

  @override
  Future<ProjectDocument> correctDocumentText(
    String documentId,
    String text,
  ) async {
    correctedText = text;
    return document;
  }
}
