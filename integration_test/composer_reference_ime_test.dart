import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_input.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import '../test/ui/fake_features.dart';

/// Manual Trime QA harness. It is not part of CI: the operator completes the
/// candidate click and @/$ keyboard checks, then taps “结束输入检查”.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      r'real Trime soft keyboard drives candidate click, @/$ and atomic refs',
      (tester) async {
    final environment = await const MethodChannel('zcode_remote/attachments')
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa',
        reason:
            'Run only with ZCODE_ANDROID_QA=true; never use production data.');
    final bridge = FeatureBridge();
    final store = ComposerStore();
    final controller = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'synthetic-ime',
        workspaceKey: 'ime',
        sessionId: 'task');
    await controller.loadOptions();
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    await prefs.setTheme(ThemeMode.light);
    await prefs.setTextScale(1);
    final finished = Completer<void>();
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ZcodeRemoteApp(
            preferences: prefs,
            home: Scaffold(
                appBar: AppBar(title: const Text('B1.1 IME QA · 合成数据')),
                body: Column(children: [
                  const SizedBox(height: 8),
                  TextButton(
                      onPressed: () {
                        if (!finished.isCompleted) finished.complete();
                      },
                      child: const Text('结束输入检查')),
                  TextButton(
                      onPressed: () {
                        FocusManager.instance.primaryFocus?.unfocus();
                      },
                      child: const Text('暂收焦点')),
                  const Spacer(),
                  ComposerBar(controller: controller),
                ])))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-input')));
    await tester.pumpAndSettle();

    final deadline = DateTime.now().add(const Duration(minutes: 4));
    while (!finished.isCompleted) {
      final text = controller.input.text;
      if (text.contains('\u4f60\u597d') &&
          text.contains('@') &&
          text.contains(r'$')) {
        finished.complete();
      }
      if (DateTime.now().isAfter(deadline)) {
        fail(
            r'Complete Trime candidate click, @ and $ checks, then tap finish.');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(controller.input.text, contains('你好'));
    expect(controller.input.text, contains('@'));
    expect(controller.input.text, contains(r'$'));
    expect(bridge.conversationTransport.sent, isEmpty);
    expect(bridge.conversationTransport.commands, isEmpty);

    controller.input.clear();
    controller.input.insertReference(
        const TextRange(start: 0, end: 0),
        const ComposerReference(
            id: 'ime-file',
            category: 'files',
            label: 'ime.txt',
            value: 'notes/ime.txt'));
    await tester.pumpAndSettle();
    expect(controller.input.text, '@ime.txt ');
    expect(controller.input.referenceCount, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(controller.input.text, isEmpty);
    expect(controller.input.referenceCount, 0);
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    prefs.dispose();
    debugPrint(
        r'B1.1 IME QA: Trime candidate click, @/$, atomic reference deletion, focus and no send passed.');
  }, timeout: const Timeout(Duration(minutes: 6)));
}
