import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';

import 'fake_workspace.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final width in [720.0, 1180.0]) {
    testWidgets('review: wide $width task switch keeps the current shell',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = Size(width, 820);
      addTearDown(tester.view.reset);
      final store = DeviceStore(requireEncryption: false, encrypt: (_) async => null);
      final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-shell-review&hash=synthetic&t=1',
        label: 'Review device',
      );
      final bridge = FakeBridge();
      final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge),
      );
      final preferences = ClientPreferences();
      await preferences.setLanguage('zh');
      late BuildContext rootContext;
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: Builder(builder: (context) {
          rootContext = context;
          return const Scaffold(body: Text('Root directory'));
        }),
      ));
      Future<void> open(BuildContext context, String id) => openDeviceWorkspace(
        context, sessions, preferences, device,
        target: TaskTarget(deviceId: device.id, workspaceKey: 'workspace',
          sessionId: id, title: 'Review $id'),
      );
      try {
        await open(rootContext, 'task');
        await tester.pumpAndSettle();
        final shellState = tester.state(find.byType(WorkspaceShell));
        await tester.enterText(find.byKey(const ValueKey('composer-input')), 'draft A');
        await open(tester.element(find.byType(WorkspaceShell)), 'task-B');
        await tester.pumpAndSettle();
        final shellCount = find.byType(WorkspaceShell, skipOffstage: false).evaluate().length;
        final sameShell = identical(tester.state(find.byType(WorkspaceShell)), shellState);
        expect(tester.widget<ChatPage>(find.byType(ChatPage)).sessionId, 'task-B');
        await tester.enterText(find.byKey(const ValueKey('composer-input')), 'draft B');
        await open(tester.element(find.byType(WorkspaceShell)), 'task');
        await tester.pumpAndSettle();
        expect(find.text('draft A'), findsOneWidget);
        expect(sameShell, isTrue, reason: 'B must update the current wide shell.');
        expect(shellCount, 1, reason: 'A hidden full-page shell is still a stacked route.');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        sessions.dispose();
        await sessions.notifications.settled;
        preferences.dispose();
      }
    });
  }
}
