import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speechmirror/src/project_editor.dart';

void main() {
  testWidgets('project editor scrolls above the keyboard on a small screen', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 780);
    tester.view.devicePixelRatio = 1;
    tester.view.viewInsets = const FakeViewPadding(bottom: 320);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetViewInsets);

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showProjectEditor(context),
                child: const Text('新建项目'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('新建项目'));
    await tester.pumpAndSettle();

    expect(find.text('新建答辩项目'), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.drag(
      find.byType(SingleChildScrollView),
      const Offset(0, -180),
    );
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '创建项目'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
