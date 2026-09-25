import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speechmirror/src/api_client.dart';
import 'package:speechmirror/src/auth_controller.dart';
import 'package:speechmirror/src/models.dart';
import 'package:speechmirror/src/screens/projects_screen.dart';

void main() {
  testWidgets('project list loads without returning a Future from setState', (
    tester,
  ) async {
    final api = _ScreenApiClient();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [apiClientProvider.overrideWithValue(api)],
        child: const MaterialApp(home: ProjectsScreen()),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('0 个项目'), findsOneWidget);
    expect(find.text('从一份真实材料开始'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

class _ScreenApiClient extends ApiClient {
  @override
  Future<List<Project>> listProjects() async => const [];
}
