import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';
import 'fake_workspace.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'A to B to A restores the same task route without duplicate subscriptions',
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
    final firstState = tester.state(find.byType(ChatPage));
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
    expect(tester.state(find.byType(ChatPage)), same(firstState));
    expect(find.text('A 独立草稿'), findsOneWidget);
    expect(bridges[a.id]!.conversationTransport.subscriptions['task'], 1);
    expect(sessions.drafts[jsonEncode([b.id, 'workspace', 'task'])], 'B 独立草稿');
    expect((sessions.sessionOf(a.id) as FakeDeviceSession).closes, 0);
    expect((sessions.sessionOf(b.id) as FakeDeviceSession).closes, 0);
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
