import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';

import 'fake_workspace.dart';

void main() {
  testWidgets('review: repeat search on the current task restarts its visible highlight', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final preferences = ClientPreferences();
    await preferences.setLanguage('zh');
    final store = DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-repeat&hash=synthetic&t=1');
    final bridge = FakeBridge();
    final state = ConversationState();
    state.applyFrame({'toSeq': 1, 'payload': {'kind': 'snapshot', 'snapshot': {
      ...composerSnapshotFixture,
      'rows': {'totalCount': 1, 'firstRowId': 1, 'window': [
        {'kind': 'assistantText', 'rowId': 1, 'state': 'complete', 'text': 'needle target'},
      ]},
    }}}, onGap: () => fail('unexpected gap'));
    bridge.conversationTransport.states['task'] = state;
    final sessions = FakeAppSessions(store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
    late BuildContext root;
    await tester.pumpWidget(ZcodeRemoteApp(preferences: preferences,
        home: Builder(builder: (context) { root = context; return const Scaffold(); })));
    Future<void> select(BuildContext context) => openDeviceWorkspace(context,
        sessions, preferences, device,
        target: TaskTarget(deviceId: device.id, workspaceKey: 'workspace', sessionId: 'task', title: 'Repeat search'),
        searchQuery: 'needle', searchSnippet: 'needle target');
    try {
      await select(root);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byKey(const ValueKey('search-highlight-overlay')), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.byKey(const ValueKey('search-highlight-overlay')), findsNothing);
      final shell = tester.state(find.byType(WorkspaceShell));
      await select(tester.element(find.byType(WorkspaceShell)));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.state(find.byType(WorkspaceShell)), same(shell));
      expect(find.byKey(const ValueKey('search-highlight-overlay')), findsOneWidget,
          reason: 'An identical search selection is still a new user request.');
      await tester.pump(const Duration(seconds: 3));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled;
      preferences.dispose();
    }
  });
}
