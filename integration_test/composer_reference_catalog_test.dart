import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import '../test/ui/fake_features.dart';

const channel = MethodChannel('zcode_remote/attachments');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real .qa composer menus expose and pick every reference scope',
      (tester) async {
    final environment =
        await channel.invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa',
        reason:
            'Run only with ZCODE_ANDROID_QA=true; never use production data.');

    final bridge = FeatureBridge();
    final store = ComposerStore();
    final controller = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'synthetic-catalog',
        workspaceKey: 'catalog');
    await controller.loadOptions();
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    await prefs.setTheme(ThemeMode.light);
    await prefs.setTextScale(1);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: Scaffold(
            body: Column(children: [
          const Text('B1.2 引用作用域 QA · 仅使用合成远端'),
          const Spacer(),
          ComposerBar(controller: controller),
        ]))));
    await tester.pumpAndSettle();

    Future<void> pick(String action, String entry) async {
      await tester.tap(find.byKey(const ValueKey('composer-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('composer-action-$action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey(entry)));
      await tester.pumpAndSettle();
    }

    // @ contains files, directories, plugins and session references.
    await tester.tap(find.byKey(const ValueKey('composer-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-action-@')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reference-file:lib/main.dart')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reference-plugin:demo@official')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reference-session:other-task')),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('reference-file:lib/main.dart')));
    await tester.pumpAndSettle();
    expect(controller.input.text, '@main.dart ');
    expect(controller.input.markdown, '[main.dart](./lib/main.dart) ');

    await pick('@', 'reference-plugin:demo@official');
    expect(controller.input.text, '@main.dart @Demo plugin ');
    expect(
        controller.input.markdown,
        '[main.dart](./lib/main.dart) '
        '[@Demo plugin](plugin://demo@official) ');

    await pick('@', 'reference-session:other-task');
    expect(controller.input.text, '@main.dart @Demo plugin #Other task ');
    expect(
        controller.input.markdown,
        '[main.dart](./lib/main.dart) '
        '[@Demo plugin](plugin://demo@official) '
        '[#Other task](#other-task) ');

    // $ distinguishes user and workspace skill scopes.
    await tester.tap(find.byKey(const ValueKey('composer-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey(r'composer-action-$')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reference-skill:user-skill')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reference-skill:workspace-skill')),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('reference-skill:workspace-skill')));
    await tester.pumpAndSettle();
    expect(
        controller.input.text,
        '@main.dart @Demo plugin #Other task '
        '\$review-code ');

    // / exposes the prepared capability commands and stays non-contextual.
    await tester.tap(find.byKey(const ValueKey('composer-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-action-/')));
    await tester.pumpAndSettle();
    expect(find.text('goal'), findsOneWidget);
    expect(find.text('compact'), findsOneWidget);
    expect(find.text('plan'), findsOneWidget);
    expect(find.text('review'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reference-command:plan')));
    await tester.pumpAndSettle();
    expect(
        controller.input.text,
        '@main.dart @Demo plugin #Other task '
        '\$review-code /plan ');
    expect(
        controller.input.markdown,
        '[main.dart](./lib/main.dart) '
        '[@Demo plugin](plugin://demo@official) '
        '[#Other task](#other-task) '
        r'[$review-code](./skills/review.md) /plan ');
    expect(controller.input.referenceCount, 5);
    expect(controller.input.contextReferenceCount, 4);
    expect(bridge.conversationTransport.sent, isEmpty);
    expect(bridge.conversationTransport.commands, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    prefs.dispose();
    debugPrint('B1.2 QA: real menus exposed and picked all candidate scopes.');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
