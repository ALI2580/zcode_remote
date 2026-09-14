import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';

import 'fake_workspace.dart';

/// P4-shell measurement (references/optimization/performance-todolist.md):
/// the per-source Offstage chat page cache must stay bounded — every
/// complete source switch clears the retained pages, so across N switch
/// cycles the retained maximum stays 1 and ChatPage constructions stay
/// linear (one per source entry).
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('metric: source switch cycles keep page retention bounded',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
      'https://zcode.z.ai/remote/v4?sid=synthetic-source-metrics&hash=synthetic&t=1',
      label: 'Metrics device',
    );
    final bridge = FakeBridge();
    final sessions = FakeAppSessions(
      store: store,
      sessionFactory: (d) => FakeDeviceSession(d.params!, bridge),
    );
    final preferences = ClientPreferences();
    late BuildContext rootContext;
    await tester.pumpWidget(ZcodeRemoteApp(
      preferences: preferences,
      home: Builder(builder: (context) {
        rootContext = context;
        return const Scaffold(body: Text('Root directory'));
      }),
    ));

    Future<void> open(String workspaceKey) => openDeviceWorkspace(
          tester.element(find.byType(WorkspaceShell)),
          sessions,
          preferences,
          device,
          target: TaskTarget(
              deviceId: device.id,
              workspaceKey: workspaceKey,
              sessionId: 'task',
              title: 'Metrics $workspaceKey'),
        );

    try {
      await openDeviceWorkspace(
        rootContext,
        sessions,
        preferences,
        device,
        target: TaskTarget(
            deviceId: device.id,
            workspaceKey: 'ws-a',
            sessionId: 'task',
            title: 'Metrics ws-a'),
      );
      await tester.pumpAndSettle();
      workspaceShellChatPagesBuilt = 0;
      workspaceShellRetainedPagesMax = 0;

      for (var cycle = 0; cycle < 6; cycle++) {
        await open('ws-b');
        await tester.pumpAndSettle();
        await open('ws-a');
        await tester.pumpAndSettle();
      }

      // ignore: avoid_print
      print('P4SHELL switches=12 chatPagesBuilt=$workspaceShellChatPagesBuilt '
          'retainedMax=$workspaceShellRetainedPagesMax');
      expect(workspaceShellRetainedPagesMax, 1,
          reason: 'retention is cleared on every complete source switch');
      expect(workspaceShellChatPagesBuilt, lessThanOrEqualTo(24),
          reason: 'one page build per source entry, not per rebuild');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled;
      await sessions.notifications.settled;
    }
  });
}
