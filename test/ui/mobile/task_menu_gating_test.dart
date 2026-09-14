import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/state/app_sessions.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/workspace_catalog.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';
import '../fake_workspace.dart';

/// M2-3: the compact task menu is generated from the existing usability
/// gating (conversationBuilder or a saved-device monitor match), never from
/// a hardcoded capability list. An unregistered monitor keeps the shell in
/// the "connection closed" state and the menu loses its terminal/panel
/// entries; a registered monitor brings them back with live open/closed
/// state labels.
void main() {
  testWidgets(
      'compact task menu entries follow the existing usability gating',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    SharedPreferences.setMockInitialValues({});
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1',
        label: '设备 A');
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    const workspace = WorkspaceDescriptor(
        key: 'workspace',
        title: 'ZcodeRemote',
        scope: {'workspaceIdentity': 'workspace'});

    Widget host(WorkspaceMonitor monitor) => ZcodeRemoteApp(
        preferences: prefs,
        home: WorkspaceShell(
            device: device,
            workspace: workspace,
            monitor: monitor,
            sessions: sessions,
            preferences: prefs));

    // A monitor that was never registered with the session store: the
    // saved-device/monitor match fails and the shell is not usable.
    final rogue = FakeWorkspaceMonitor(
        bridge: FakeBridge(),
        scope: workspace.scope,
        notifications: sessions.notifications,
        source: WorkspaceTaskSource(
            deviceId: device.id,
            deviceLabel: device.label,
            workspaceKey: workspace.key));
    addTearDown(rogue.dispose);
    await tester.pumpWidget(host(rogue));
    await tester.pumpAndSettle();
    expect(find.text('连接已关闭或链接已更新'), findsOneWidget);

    Future<void> openMenu() async {
      await tester.tap(find.byTooltip('更多').first);
      await tester.pumpAndSettle();
    }

    Future<void> closeMenu() async {
      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      navigator.pop();
      await tester.pumpAndSettle();
    }

    await openMenu();
    expect(find.byKey(const ValueKey('task-menu-terminal')), findsNothing);
    expect(find.byKey(const ValueKey('task-menu-panel')), findsNothing);
    await closeMenu();

    // Register the workspace on the session store; the same shell now
    // passes the usability gate and the menu gains the live entries.
    final registered =
        await sessions.openWorkspace(device, workspace.key, workspace.scope);
    addTearDown(registered.dispose);
    await tester.pumpWidget(host(registered));
    await tester.pumpAndSettle();
    expect(find.text('连接已关闭或链接已更新'), findsNothing);

    await openMenu();
    expect(find.byKey(const ValueKey('task-menu-terminal')), findsOneWidget);
    expect(find.byKey(const ValueKey('task-menu-panel')), findsOneWidget);
    // The entries are generated with their current activation state.
    expect(find.textContaining('（已关闭）'), findsOneWidget);
    expect(find.textContaining('（关闭）'), findsOneWidget);
    await closeMenu();

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
    prefs.dispose();
  });
}
