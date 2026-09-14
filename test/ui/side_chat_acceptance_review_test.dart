import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';

import 'fake_workspace.dart';

void main() {
  testWidgets('review: shell side chat excludes main-only message actions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final store = DeviceStore(
        requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
      'https://zcode.z.ai/remote/v4?sid=synthetic-side-review&hash=synthetic&t=1',
      label: 'Review device',
    );
    final bridge = FakeBridge();
    for (final id in ['task', 'task-side']) {
      bridge.conversationTransport.states[id] = ConversationState()
        ..applyFrame({
          'toSeq': 1,
          'payload': {
            'kind': 'snapshot',
            'snapshot': {
              ...composerSnapshotFixture,
              'rows': {
                'totalCount': 1,
                'firstRowId': 1,
                'window': [
                  {
                    'rowId': 1,
                    'kind': 'userInput',
                    'entityId': 'entity-$id',
                    'text': 'Input for $id',
                  },
                ],
              },
            },
          },
        }, onGap: () => fail('unexpected gap'));
    }
    final sessions = FakeAppSessions(
      store: store,
      sessionFactory: (d) => FakeDeviceSession(d.params!, bridge),
    );
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    late BuildContext root;
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: Builder(builder: (context) {
          root = context;
          return const Scaffold();
        }),
      ));
      await openDeviceWorkspace(root, sessions, prefs, device,
          target: TaskTarget(
              deviceId: device.id,
              workspaceKey: 'workspace',
              sessionId: 'task',
              title: 'Main task'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('工作面板').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('辅助对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开辅助对话'));
      await tester.pumpAndSettle();
      final main = find.byWidgetPredicate(
          (widget) => widget is ChatPage && widget.sessionId == 'task');
      final side = find.byWidgetPredicate(
          (widget) => widget is ChatPage && widget.sessionId == 'task-side');
      expect(find.byType(WorkspaceShell), findsOneWidget);
      expect(side, findsOneWidget);
      expect(find.descendant(of: main, matching: find.byIcon(Icons.edit_outlined)),
          findsOneWidget);
      expect(find.descendant(of: side, matching: find.byIcon(Icons.edit_outlined)),
          findsNothing,
          reason: 'Official selectionSideChat excludes edit/retry/fork/feedback.');
      expect(find.descendant(of: side, matching: find.byType(TextField)),
          findsOneWidget,
          reason: 'The side composer remains usable.');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled;
      prefs.dispose();
    }
  });
}
