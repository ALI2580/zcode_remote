import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import 'package:zcode_remote/ui/shell/shell_layout.dart';
import '../test/ui/fake_features.dart';
import '../test/ui/fake_workspace.dart';

Future<void> _waitForOrientation(
  WidgetTester tester, {
  required bool landscape,
}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (true) {
    final size = tester.view.physicalSize / tester.view.devicePixelRatio;
    final matches =
        landscape ? size.width > size.height : size.height > size.width;
    if (matches) {
      await tester.pumpAndSettle();
      return;
    }
    if (DateTime.now().isAfter(deadline)) {
      fail(
          'system orientation did not change to ${landscape ? 'landscape' : 'portrait'}');
    }
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _snapState(ConversationState state, Map<String, dynamic> patch) {
  state.applyFrame({
    'toSeq': state.seq + 1,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {...composerSnapshotFixture, ...patch},
    },
  }, onGap: () => fail('unexpected snapshot gap'));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native rotation keeps main and side panel state isolated',
      (tester) async {
    final environment = await const MethodChannel('zcode_remote/attachments')
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa',
        reason: 'Run only with ZCODE_ANDROID_QA=true; never .dev data.');

    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    final bridge = FeatureBridge();
    final store = ComposerStore();
    final main = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace');
    final side = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace',
        sessionId: 'side');
    await main.loadOptions();
    await side.loadOptions();
    addTearDown(() async {
      await SystemChrome.setPreferredOrientations(
          [DeviceOrientation.portraitUp]);
      store.dispose();
      prefs.dispose();
    });

    main.input.text = 'rotation main draft';
    final sideState = ConversationState();
    _snapState(sideState, {
      'availability': {
        'switchModelConfig': {'allowed': true},
        'queueEdit': {'allowed': true},
      },
      'queue': {
        'autoDrain': false,
        'items': [
          {
            'queueItemId': 'q1',
            'text': 'rotation side queue',
            'dispatch': {'state': 'queued'},
          },
        ],
      },
    });
    side.bind(sideState);
    final sideModelSelected =
        await side.selectModel('custom:provider-b:second-model');
    expect(sideModelSelected, isTrue, reason: 'side model selection accepted');
    final setupCommands = bridge.conversationTransport.commands.length;

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: WorkspaceShellLayout(
            title: 'D2.4 旋转隔离',
            project: 'Synthetic',
            sidebar: const Text('sidebar'),
            sidebarCollapsed: false,
            onSidebarCollapsed: (_) {},
            conversation: ComposerBar(controller: main),
            panel: ComposerBar(controller: side))));
    await tester.pumpAndSettle();
    expect(find.text('rotation main draft'), findsOneWidget);
    expect(find.textContaining('rotation side queue'), findsOneWidget);
    expect(main.queue, isEmpty);
    expect(side.queue, hasLength(1));

    await SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft]);
    await _waitForOrientation(tester, landscape: true);
    expect(find.text('rotation main draft'), findsOneWidget);
    expect(find.textContaining('rotation side queue'), findsOneWidget);
    expect(main.input.text, 'rotation main draft');
    expect(side.config['model'], 'second-model');
    expect(main.queue, isEmpty);
    expect(side.queue.single['text'], 'rotation side queue');

    await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
    await _waitForOrientation(tester, landscape: false);
    expect(find.text('rotation main draft'), findsOneWidget);
    expect(find.textContaining('rotation side queue'), findsOneWidget);
    expect(side.queue.single['text'], 'rotation side queue');
    expect(main.queue, isEmpty);
    expect(bridge.conversationTransport.sent, isEmpty);
    expect(bridge.conversationTransport.commands.length, setupCommands,
        reason: 'rotation must not introduce new conversation commands');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
