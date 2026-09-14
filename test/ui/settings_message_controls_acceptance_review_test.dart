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
  testWidgets(
      'review: saved todo and all three grouping controls affect the existing chat',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 1100);
    addTearDown(tester.view.reset);
    final preferences = ClientPreferences();
    await preferences.setLanguage('en');
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-controls&hash=synthetic&t=1',
        label: 'Synthetic controls');
    final bridge = FeatureBridge();
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
    final values = <String, dynamic>{};
    final patches = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.setting) {
        if (method == 'update') {
          final patch = (args.single as Map).cast<String, dynamic>();
          patches.add(patch);
          values.addAll(patch);
        }
        return {...values};
      }
      return <String, dynamic>{};
    };
    final rows = <Map<String, dynamic>>[
      {'rowId': 1, 'kind': 'turnHeader', 'state': 'complete'},
      {
        'rowId': 2,
        'kind': 'toolCall',
        'toolName': 'TodoWrite',
        'state': 'complete',
        'status': 'success',
        'input': {'todos': []}
      },
      for (final id in [3, 4])
        {
          'rowId': id,
          'kind': 'toolCall',
          'toolName': 'Read',
          'state': 'complete',
          'status': 'success',
          'input': {'file_path': 'lib/read_$id.dart'}
        },
      for (final id in [5, 6])
        {
          'rowId': id,
          'kind': 'toolCall',
          'toolName': 'Bash',
          'state': 'complete',
          'status': 'success',
          'input': {'command': 'npm test'}
        },
      for (final id in [7, 8])
        {
          'rowId': id,
          'kind': 'toolCall',
          'toolName': 'Edit',
          'state': 'complete',
          'status': 'success',
          'input': {
            'file_path': 'lib/edit_$id.dart',
            'oldText': 'before',
            'newText': 'after'
          }
        },
    ];
    final state = ConversationState()
      ..applyFrame({
        'toSeq': 1,
        'payload': {
          'kind': 'snapshot',
          'snapshot': {
            ...composerSnapshotFixture,
            'rows': {'totalCount': rows.length, 'firstRowId': 1, 'window': rows}
          }
        }
      }, onGap: () => fail('unexpected gap'));
    bridge.conversationTransport.states['message-controls'] = state;
    late BuildContext root;
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: preferences,
          home: Builder(builder: (context) {
            root = context;
            return const Scaffold();
          })));
      await openDeviceWorkspace(root, sessions, preferences, device,
          target: TaskTarget(
              deviceId: device.id,
              workspaceKey: 'workspace',
              sessionId: 'message-controls',
              title: 'Message controls'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widgetList<ToolGroupRow>(find.byType(ToolGroupRow))
              .map((widget) => widget.family),
          ['explore', 'terminal']);
      expect(find.byKey(const ValueKey('tool-row-2')), findsNothing);
      final shell = tester.widget<WorkspaceShell>(find.byType(WorkspaceShell));
      showSettingsCenter(
          tester.element(find.byType(WorkspaceShell)), sessions, preferences,
          remoteMonitor: shell.monitor);
      await tester.pumpAndSettle();
      for (final key in [
        'messageStreamShowTodos',
        'toolGroupingExploreEnabled',
        'toolGroupingTerminalEnabled',
        'toolGroupingChangesEnabled'
      ]) {
        final toggle = find.byKey(ValueKey('remote-toggle-$key'));
        await tester.ensureVisible(toggle);
        await tester.pump();
        await tester.tap(toggle);
        await tester.pumpAndSettle();
      }
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(patches, hasLength(4));
      expect(
          tester
              .widgetList<ToolGroupRow>(find.byType(ToolGroupRow))
              .map((widget) => widget.family),
          ['changes']);
      expect(find.byKey(const ValueKey('tool-row-2')), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-row-3')), findsOneWidget);
      expect(find.byKey(const ValueKey('tool-row-5')), findsOneWidget);
      expect(state.rows, hasLength(rows.length),
          reason:
              'Visibility settings must retain the original protocol rows.');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled;
      preferences.dispose();
    }
  });
}
