import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/workspace_catalog.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/command_center.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';

import 'fake_workspace.dart';

class _SearchTransport extends FakeConversationTransport {
  _SearchTransport(super.session);

  @override
  Future<Map<String, dynamic>> listTaskList({
    required List<Map<String, dynamic>> workspaceScopes,
    String? search,
    int limit = 80,
  }) async {
    return {
      'items': [
        {
          'workspaceIdentity': 'workspace',
          'taskId': 'task-search',
          'title': 'Needle task',
          'searchSnippet': '检查第 1 项布局和状态恢复',
        }
      ],
    };
  }
}

class _SearchBridge extends FakeBridge {
  late final _SearchTransport searchTransport = _SearchTransport(this);

  @override
  ConversationTransport conversation(Map<String, dynamic> scope,
          {void Function(String line)? onLog}) =>
      searchTransport;
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('sidebar search opens remote result and locates ChatPage text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-search&hash=synthetic&t=1');
    final bridge = _SearchBridge();
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (value) => FakeDeviceSession(value.params!, bridge));
    final preferences = ClientPreferences();
    await preferences.setLanguage('zh');
    final workspace = const WorkspaceDescriptor(
        key: 'workspace',
        title: 'ZcodeRemote',
        scope: {'workspaceIdentity': 'workspace'});
    await sessions.openWorkspace(device, workspace.key, workspace.scope);
    seedConversation(
        bridge.searchTransport.states
            .putIfAbsent('task-search', ConversationState.new),
        count: 1);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled
          .timeout(const Duration(seconds: 1), onTimeout: () {});
      preferences.dispose();
    });
    late BuildContext root;
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: Builder(builder: (context) {
          root = context;
          return const Scaffold(body: Text('Root'));
        })));
    await openDeviceWorkspace(root, sessions, preferences, device,
        target: const TaskTarget(
            deviceId: 'pending',
            workspaceKey: 'workspace',
            sessionId: 'initial',
            title: 'Initial'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.byType(CommandCenter), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, '#needle');
    await tester.pumpAndSettle();
    expect(find.text('Needle task'), findsOneWidget);
    await tester.tap(find.text('Needle task'));
    await tester.pumpAndSettle();
    expect(tester.widget<WorkspaceShell>(find.byType(WorkspaceShell)).sessionId,
        'task-search');
    expect(find.text('检查第 1 项布局和状态恢复'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
