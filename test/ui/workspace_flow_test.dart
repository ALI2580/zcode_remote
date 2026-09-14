import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/command_center.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';
import 'fake_workspace.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'A to B to A keeps one shell and restores independent source state',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final a = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1',
        label: '设备 A');
    final b = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-B&hash=synthetic&t=1',
        label: '设备 B');
    final bridges = {a.id: FakeBridge(), b.id: FakeBridge()};
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridges[d.id]!));
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    late BuildContext root;
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: Builder(builder: (context) {
          root = context;
          return const Scaffold(body: Text('设备目录'));
        })));
    await openDeviceWorkspace(root, sessions, prefs, a,
        target: TaskTarget(
            deviceId: a.id,
            workspaceKey: 'workspace',
            sessionId: 'task',
            title: '任务 A'));
    await tester.pumpAndSettle();
    final shellState = tester.state(find.byType(WorkspaceShell));
    await tester.enterText(find.byType(TextField), 'A 独立草稿');
    await tester.tap(find.byTooltip('工作面板').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('辅助对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开辅助对话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'A 辅助草稿');
    await tester.tap(find.text('任务状态'));
    await tester.pumpAndSettle();
    expect(find.text('任务 A'), findsWidgets);
    await tester.tap(find.text('辅助对话'));
    await tester.pumpAndSettle();
    expect(find.text('A 辅助草稿'), findsOneWidget);
    expect(bridges[a.id]!.conversationTransport.subscriptions['task-side'], 1);
    for (final width in [344.0, 720.0, 834.0, 1180.0]) {
      tester.view.physicalSize = Size(width, 820);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(bridges[a.id]!.conversationTransport.subscriptions['task-side'], 1);
    await tester.tap(find.byTooltip('关闭面板').last);
    await tester.pumpAndSettle();
    await openDeviceWorkspace(
        tester.element(find.byType(WorkspaceShell)), sessions, prefs, b,
        target: TaskTarget(
            deviceId: b.id,
            workspaceKey: 'workspace',
            sessionId: 'task',
            title: '任务 B'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'B 独立草稿');
    await openDeviceWorkspace(
        tester.element(find.byType(WorkspaceShell)), sessions, prefs, a);
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(WorkspaceShell)), same(shellState));
    expect(find.text('A 独立草稿'), findsOneWidget);
    final aTransport = bridges[a.id]!.conversationTransport;
    final bTransport = bridges[b.id]!.conversationTransport;
    expect(
        (aTransport.subscriptions['task'] ?? 0) -
            (aTransport.disposals['task'] ?? 0),
        1);
    expect(
        (bTransport.subscriptions['task'] ?? 0) -
            (bTransport.disposals['task'] ?? 0),
        0);
    expect(sessions.drafts[jsonEncode([b.id, 'workspace', 'task'])], 'B 独立草稿');
    expect((sessions.sessionOf(a.id) as FakeDeviceSession).closes, 0);
    expect((sessions.sessionOf(b.id) as FakeDeviceSession).closes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
    prefs.dispose();
  });

  testWidgets('narrow overlay panel and terminal drawer stay independent',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(360, 760);
    addTearDown(tester.view.reset);
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1');
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    late BuildContext root;
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: Builder(builder: (context) {
          root = context;
          return const Scaffold(body: Text('设备目录'));
        })));
    await openDeviceWorkspace(root, sessions, prefs, device,
        target: TaskTarget(
            deviceId: device.id,
            workspaceKey: 'workspace',
            sessionId: 'task',
            title: '任务 A'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('工作面板').last);
    await tester.pumpAndSettle();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
    expect(find.text('任务已就绪'), findsOneWidget);
    await tester.tap(find.text('辅助对话'));
    await tester.pump();
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
    // The official remote hosts terminals in a bottom drawer toggled from the
    // top bar; switching side panel tabs must not close or move it.
    await tester.tap(find.byTooltip('切换终端').last);
    await tester.pump();
    expect(find.text('终端'), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
    await tester.tap(find.text('任务状态'));
    await tester.pumpAndSettle();
    expect(find.text('任务已就绪'), findsOneWidget);
    expect(find.byTooltip('关闭终端抽屉'), findsWidgets);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
    prefs.dispose();
  });

  testWidgets('late A connection cannot replace the more recent B selection',
      (tester) async {
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final a = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1');
    final b = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-B&hash=synthetic&t=1');
    final gate = Completer<void>();
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge(),
            gate: d.id == a.id ? gate.future : null));
    final prefs = ClientPreferences();
    late BuildContext root;
    await tester.pumpWidget(ZcodeRemoteApp(home: Builder(builder: (context) {
      root = context;
      return const Scaffold();
    })));
    final pending = openDeviceWorkspace(root, sessions, prefs, a);
    await openDeviceWorkspace(root, sessions, prefs, b);
    await tester.pumpAndSettle();
    gate.complete();
    await pending;
    await tester.pumpAndSettle();
    expect(tester.widget<WorkspaceShell>(find.byType(WorkspaceShell)).device.id,
        b.id);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
    prefs.dispose();
  });

  testWidgets('Ctrl+K opens the local command center', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1');
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    late BuildContext root;
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: Builder(builder: (context) {
          root = context;
          return const Scaffold(body: Text('设备目录'));
        })));
    await openDeviceWorkspace(root, sessions, prefs, device,
        target: TaskTarget(
            deviceId: device.id,
            workspaceKey: 'workspace',
            sessionId: 'task',
            title: '任务 A'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(CommandCenter), findsOneWidget);
    expect(find.text('全部'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandCenter), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
    prefs.dispose();
  });

  testWidgets(
      'command center does not disturb persistent main and side composers',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1');
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    late BuildContext root;
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: Builder(builder: (context) {
          root = context;
          return const Scaffold(body: Text('设备目录'));
        })));
    await openDeviceWorkspace(root, sessions, prefs, device,
        target: TaskTarget(
            deviceId: device.id,
            workspaceKey: 'workspace',
            sessionId: 'task',
            title: '任务 A'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'A 主草稿');
    await tester.tap(find.byTooltip('工作面板').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('辅助对话'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('打开辅助对话'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'A 辅助草稿');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(CommandCenter), findsOneWidget);
    expect(find.text('A 主草稿'), findsOneWidget);
    expect(find.text('A 辅助草稿'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandCenter), findsNothing);
    expect(find.text('A 主草稿'), findsOneWidget);
    expect(find.text('A 辅助草稿'), findsOneWidget);
    expect(tester.widget<IndexedStack>(find.byType(IndexedStack)).index, 0);
    expect(
        (sessions.sessionOf(device.id) as FakeDeviceSession)
            .bridge
            .conversationTransport
            .sent,
        isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
    prefs.dispose();
  });

  testWidgets('rejected send keeps the draft and does not retry automatically',
      (tester) async {
    final bridge = FakeBridge();
    bridge.conversationTransport.response = {
      'status': 'rejected',
      'reasonCode': 'notReady'
    };
    final drafts = <String, String>{};
    await tester.pumpWidget(ZcodeRemoteApp(
        home: ChatPage(
            session: bridge,
            scope: const {},
            workspaceKey: 'workspace',
            deviceId: 'A',
            sessionId: 'task',
            title: 'Test',
            drafts: drafts,
            viewStates: <String, ConversationViewState>{})));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '保留这段内容');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-submit')));
    await tester.pumpAndSettle();
    expect(find.text('保留这段内容'), findsOneWidget);
    expect(drafts[jsonEncode(['A', 'workspace', 'task'])], '保留这段内容');
    expect(bridge.conversationTransport.sent, ['保留这段内容']);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
