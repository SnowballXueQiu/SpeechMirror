import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:speechmirror/src/api_client.dart';
import 'package:speechmirror/src/auth_controller.dart';
import 'package:speechmirror/src/models.dart';
import 'package:speechmirror/src/screens/project_detail_screen.dart';
import 'package:speechmirror/src/screens/projects_screen.dart';

void main() {
  testWidgets('edits and permanently deletes a project', (tester) async {
    final api = _ProjectApiClient();
    final router = GoRouter(
      initialLocation: '/projects',
      routes: [
        GoRoute(
          path: '/projects',
          builder: (context, state) => const ProjectsScreen(),
        ),
        GoRoute(
          path: '/projects/:id',
          builder: (context, state) =>
              ProjectDetailScreen(projectId: state.pathParameters['id']!),
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

    expect(find.text('原项目'), findsOneWidget);
    await tester.tap(find.text('原项目'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('编辑项目'));
    await tester.pumpAndSettle();
    expect(find.text('编辑答辩项目'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, '更新后项目');
    await tester.enterText(find.byType(TextFormField).last, '  新说明  ');
    await tester.tap(find.byTooltip('增加一分钟'));
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(api.project.name, '更新后项目');
    expect(api.project.description, '新说明');
    expect(api.project.durationSeconds, 360);
    expect(find.text('更新后项目'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('更新后项目'), findsOneWidget);

    await tester.tap(find.text('更新后项目'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('删除项目'));
    await tester.pumpAndSettle();
    expect(find.text('彻底删除项目？'), findsOneWidget);
    expect(find.textContaining('无法撤销'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('confirm-project-deletion')));
    await tester.pumpAndSettle();

    expect(api.deletedProjectId, 'p1');
    expect(find.text('0 个项目'), findsOneWidget);
    expect(find.text('从一份真实材料开始'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ProjectApiClient extends ApiClient {
  Project project = const Project(
    id: 'p1',
    name: '原项目',
    description: '原说明',
    durationSeconds: 300,
  );
  String? deletedProjectId;

  @override
  Future<List<Project>> listProjects() async =>
      deletedProjectId == null ? [project] : const [];

  @override
  Future<Project> getProject(String id) async => project;

  @override
  Future<List<ProjectDocument>> listDocuments(String projectId) async =>
      const [];

  @override
  Future<Project> updateProject(
    String id,
    String name,
    String? description,
    int seconds,
  ) async {
    project = Project(
      id: id,
      name: name,
      description: description,
      durationSeconds: seconds,
    );
    return project;
  }

  @override
  Future<void> deleteProject(String id) async {
    deletedProjectId = id;
  }
}
