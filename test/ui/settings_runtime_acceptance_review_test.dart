import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/conversation_work_rows.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';

import 'fake_features.dart';
import 'fake_workspace.dart';

void main() {
  testWidgets('review: saved reasoning preference changes the existing chat',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);
    final preferences = ClientPreferences();
    await preferences.setLanguage('en');
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    await store.load();
    final device = await store.addUrl(
      'https://zcode.z.ai/remote/v4?sid=synthetic-runtime-review&hash=synthetic&t=1',
      label: 'Review device',
    );
    final bridge = FeatureBridge();
    final sessions = FakeAppSessions(
      store: store,
      sessionFactory: (d) => FakeDeviceSession(d.params!, bridge),
    );
    final settings = <String, dynamic>{'messageStreamShowReasoning': true};
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.setting) {
        if (method == 'update') {
          settings.addAll((args.single as Map).cast<String, dynamic>());
        }
        return Map<String, dynamic>.from(settings);
      }
      return <String, dynamic>{};
    };
    final rows = <Map<String, dynamic>>[
      {'rowId': 1, 'kind': 'turnHeader', 'state': 'complete'},
      {
        'rowId': 2,
        'kind': 'reasoning',
        'state': 'complete',
        'text': 'First reasoning'
      },
      {
        'rowId': 3,
        'kind': 'reasoning',
        'state': 'complete',
        'text': 'Later reasoning'
      },
    ];
    bridge.conversationTransport.states['runtime-review'] = ConversationState()
      ..applyFrame({
        'toSeq': 1,
        'payload': {
          'kind': 'snapshot',
          'snapshot': {
            ...composerSnapshotFixture,
            'rows': {
              'totalCount': rows.length,
              'firstRowId': 1,
              'window': rows
            },
          },
        },
      }, onGap: () => fail('unexpected gap'));
    late BuildContext root;
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: Builder(builder: (context) {
          root = context;
          return const Scaffold();
        }),
      ));
      await openDeviceWorkspace(root, sessions, preferences, device,
          target: TaskTarget(
              deviceId: device.id,
              workspaceKey: 'workspace',
              sessionId: 'runtime-review',
              title: 'Runtime settings'));
      await tester.pumpAndSettle();
      expect(find.byType(ReasoningRow), findsNWidgets(2));
      final shell = tester.widget<WorkspaceShell>(find.byType(WorkspaceShell));
      showSettingsCenter(
          tester.element(find.byType(WorkspaceShell)), sessions, preferences,
          remoteMonitor: shell.monitor);
      await tester.pumpAndSettle();
      final toggle = find
          .byKey(const ValueKey('remote-toggle-messageStreamShowReasoning'));
      await tester.ensureVisible(toggle);
      await tester.pump();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(settings['messageStreamShowReasoning'], isFalse);
      expect(tester.widget<Switch>(toggle).value, isFalse);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(ReasoningRow), findsOneWidget,
          reason:
              'Official VY keeps the first reasoning only when the saved toggle is off.');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled;
      preferences.dispose();
    }
  });
}
