import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:speechmirror/src/api_client.dart';
import 'package:speechmirror/src/app.dart';
import 'package:speechmirror/src/auth_controller.dart';
import 'package:speechmirror/src/screens/auth_screen.dart';

void main() {
  testWidgets('validates username and password before sending a request', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AuthScreen())),
    );

    await tester.tap(find.widgetWithText(FilledButton, '进入训练台'));
    await tester.pump();

    expect(find.text('请输入 3–32 位字母、数字、下划线或连字符'), findsOneWidget);
    expect(find.text('密码长度需为 8–128 个字符'), findsOneWidget);

    await tester.enterText(find.byType(TextFormField).first, 'valid_user');
    await tester.enterText(find.byType(TextFormField).last, 'short');
    await tester.tap(find.widgetWithText(FilledButton, '进入训练台'));
    await tester.pump();

    expect(find.text('请输入 3–32 位字母、数字、下划线或连字符'), findsNothing);
    expect(find.text('密码长度需为 8–128 个字符'), findsOneWidget);
  });

  testWidgets('toggles password visibility with an accessible control', (
    tester,
  ) async {
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: AuthScreen())),
    );

    EditableText password = tester.widget(find.byType(EditableText).last);
    expect(password.obscureText, isTrue);

    await tester.tap(find.byTooltip('显示密码'));
    await tester.pump();

    password = tester.widget(find.byType(EditableText).last);
    expect(password.obscureText, isFalse);
    expect(find.byTooltip('隐藏密码'), findsOneWidget);
  });

  testWidgets('keeps credentials visible after a rejected login', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiClientProvider.overrideWithValue(_RejectingAuthApiClient()),
        ],
        child: const SpeechMirrorApp(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'valid_user');
    await tester.enterText(find.byType(TextFormField).last, 'correct-horse');
    await tester.tap(find.widgetWithText(FilledButton, '进入训练台'));
    await tester.pumpAndSettle();

    final username = tester.widget<EditableText>(
      find.byType(EditableText).first,
    );
    final password = tester.widget<EditableText>(
      find.byType(EditableText).last,
    );
    expect(username.controller.text, 'valid_user');
    expect(password.controller.text, 'correct-horse');
    expect(find.text('用户名或密码错误'), findsOneWidget);
  });
}

class _RejectingAuthApiClient extends ApiClient {
  @override
  Future<bool> restoreSession() async => false;

  @override
  Future<void> login(
    String username,
    String password, {
    bool register = false,
  }) async {
    throw const ApiException('用户名或密码错误');
  }
}
