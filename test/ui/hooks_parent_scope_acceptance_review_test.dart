import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'fake_features.dart';
import 'fake_workspace.dart';
import 'review_connected_session.dart';

class _Fixture {
  final preferences = ClientPreferences();
  final store =
      DeviceStore(requireEncryption: false, encrypt: (_) async => null);
  final gateA = Completer<void>();
  final bridges = <String, FeatureBridge>{};
  final devices = <Device>[];
  late FakeAppSessions sessions;
  late FakeWorkspaceMonitor current;

  Future<void> initialize() async {
    await preferences.setLanguage('en');
    for (final name in ['A', 'B', 'C']) {
      final device = await store.addUrl(
          'https://zcode.z.ai/remote/v4?sid=synthetic-scope-$name&hash=synthetic&t=1',
          label: 'Device $name');
      devices.add(device);
      final bridge = FeatureBridge();
      bridge.channels.handler = (_, method, __) => method == 'loadHooks'
          ? {
              'hooks': [
                {
                  'id': '$name-user',
                  'event': 'Stop',
                  'command': 'synthetic-$name',
                  'type': 'command',
                  'location': {'source': 'zcode', 'scope': 'user'},
                  'editable': true,
                  'enabled': true
                }
              ]
            }
          : <String, dynamic>{};
      bridges[device.id] = bridge;
    }
    sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => ReviewConnectedSession(d.params!, bridges[d.id]!,
            gate: d.id == devices.first.id ? gateA.future : null));
    for (final device in devices) {
      sessions.sessionFor(device);
    }
    current = FakeWorkspaceMonitor(
        bridge: bridges[devices.last.id]!,
        scope: const {
          'workspacePath': 'D:/Project',
          'workspaceIdentity': 'workspace'
        },
        source: WorkspaceTaskSource(
            deviceId: devices.last.id,
            deviceLabel: 'Device C',
            workspaceKey: 'workspace',
            workspacePath: 'D:/Project'),
        notifications: sessions.notifications);
    sessions.monitors[devices.last.id] = current;
  }

  Widget get page => ZcodeRemoteApp(
      preferences: preferences,
      home: SettingsCenterPage(
          sessions: sessions,
          preferences: preferences,
          onManageDevices: () {},
          remoteMonitor: current,
          initialSection: 'hooks'));

  Future<void> dispose(WidgetTester tester) async {
    if (!gateA.isCompleted) gateA.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    for (final device in devices) {
      final session = sessions.sessionOf(device.id);
      if (session is ReviewConnectedSession) {
        await tester.runAsync(session.reviewClient.dispose);
      }
    }
    sessions.dispose();
    await sessions.notifications.settled;
    preferences.dispose();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  testWidgets(
      'review: pending workspace selection cannot overwrite a later User selection',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);
    final fixture = _Fixture();
    await fixture.initialize();
    try {
      await tester.pumpWidget(fixture.page);
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('hooks-scope-picker'));
      expect(picker, findsOneWidget);
      expect(find.byKey(const ValueKey('hook-toggle-C-user')), findsOneWidget);
      await tester.ensureVisible(picker);
      await tester.pumpAndSettle();
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Device A · ZcodeRemote').last);
      await tester.pumpAndSettle();
      await tester.tap(picker);
      await tester.pumpAndSettle();
      await tester.tap(find.text('User').last);
      await tester.pumpAndSettle();
      fixture.gateA.complete();
      await tester.pumpAndSettle();
      expect(tester.widget<DropdownButton<String>>(picker).value, 'user');
      expect(find.byKey(const ValueKey('hook-toggle-C-user')), findsOneWidget,
          reason:
              'The source remains C when a pending A was superseded by User.');
      expect(find.byKey(const ValueKey('hook-toggle-A-user')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });
}
