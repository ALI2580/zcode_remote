import 'dart:async';
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
  testWidgets('real .qa reference menus recover and refresh runtime catalogs',
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
        deviceId: 'synthetic-runtime',
        workspaceKey: 'runtime');
    await controller.loadOptions();
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    await prefs.setTheme(ThemeMode.light);
    await prefs.setTextScale(1);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: Scaffold(
            body: Column(children: [
          const Text('B1.3 引用状态 QA · 仅使用合成远端'),
          const Spacer(),
          ComposerBar(controller: controller),
        ]))));
    await tester.pumpAndSettle();

    Future<void> openAction(String action) async {
      await tester.tap(find.byKey(const ValueKey('composer-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(ValueKey('composer-action-$action')));
      await tester.pumpAndSettle();
    }

    // A failed catalog keeps other categories usable and retry replaces it.
    var fileAttempts = 0;
    bridge.conversationTransport.filesHandler = () {
      fileAttempts++;
      if (fileAttempts == 1) {
        return Future.error(TimeoutException('synthetic file timeout'));
      }
      return Future.value([
        {
          'name': 'retry.dart',
          'relativePath': 'lib/retry.dart',
          'path': 'D:/Synthetic/lib/retry.dart',
          'type': 'file'
        }
      ]);
    };
    await openAction('@');
    expect(find.text('部分引用加载失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('reference-plugin:demo@official')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('reference-session:other-task')),
        findsOneWidget);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('部分引用加载失败'), findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('reference-file:lib/retry.dart')));
    await tester.pumpAndSettle();
    expect(controller.input.text, '@retry.dart ');
    expect(controller.input.markdown, '[retry.dart](./lib/retry.dart) ');

    // Runtime catalog changes must not leave stale plugin/skill candidates.
    bridge.conversationTransport.plugins = const [
      {
        'pluginId': 'fresh@official',
        'name': 'Fresh plugin',
        'enabled': true,
        'description': 'Runtime refresh',
        'conflictingPluginIds': []
      }
    ];
    bridge.conversationTransport.skillItems = const [
      {
        'id': 'runtime-skill',
        'name': 'fresh-skill',
        'path': 'skills/fresh.md',
        'scope': 'workspace',
        'description': 'Runtime refresh'
      }
    ];
    controller.references.invalidate();

    await openAction('@');
    expect(find.byKey(const ValueKey('reference-plugin:demo@official')),
        findsNothing);
    await tester
        .tap(find.byKey(const ValueKey('reference-plugin:fresh@official')));
    await tester.pumpAndSettle();

    await openAction(r'$');
    expect(find.byKey(const ValueKey('reference-skill:workspace-skill')),
        findsNothing);
    expect(find.byKey(const ValueKey('reference-skill:runtime-skill')),
        findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('reference-skill:runtime-skill')));
    await tester.pumpAndSettle();

    expect(
        controller.input.text,
        '@retry.dart @Fresh plugin '
        '\$fresh-skill ');
    expect(
        controller.input.markdown,
        '[retry.dart](./lib/retry.dart) '
        '[@Fresh plugin](plugin://fresh@official) '
        r'[$fresh-skill](./skills/fresh.md) ');
    expect(controller.input.referenceCount, 3);
    expect(controller.input.contextReferenceCount, 3);
    expect(bridge.conversationTransport.sent, isEmpty);
    expect(bridge.conversationTransport.commands, isEmpty);

    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    prefs.dispose();
    debugPrint(
        'B1.3 QA: retry, runtime catalogs, visible labels and serialization passed.');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
