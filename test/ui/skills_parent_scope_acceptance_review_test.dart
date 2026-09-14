import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'package:zcode_remote/ui/settings_scope.dart';
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
      bridge.channels.handler = (_, method, __) => method == 'list'
          ? {
              'skills': [
                {
                  'id': name,
                  'name': 'Skills for $name',
                  'path': 'C:/Synthetic/skill.md',
                  'scope': 'user',
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
          initialSection: 'skills'));

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
      'review: Skills scope picker initially represents the supplied current monitor',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);
    final fixture = _Fixture();
    await fixture.initialize();
    try {
      await tester.pumpWidget(fixture.page);
      await tester.pumpAndSettle();
      expect(find.text('Skills for C'), findsOneWidget);
      final picker = tester.widget<DropdownButton<SettingsScopeOption>>(
          find.byKey(const ValueKey('settings-workspace-scope')));
      expect(picker.value?.deviceId, fixture.devices.last.id,
          reason:
              'The visible scope label must match the bridge being edited.');
    } finally {
      await fixture.dispose(tester);
    }
  });

  testWidgets(
      'review: old Skills workspace opening cannot replace a later selection',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);
    final fixture = _Fixture();
    await fixture.initialize();
    try {
      await tester.pumpWidget(fixture.page);
      await tester.pumpAndSettle();
      for (final name in ['A', 'B']) {
        await tester
            .tap(find.byKey(const ValueKey('settings-workspace-scope')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Device $name · ZcodeRemote').last);
        await tester.pumpAndSettle();
      }
      expect(find.text('Skills for B'), findsOneWidget);
      fixture.gateA.complete();
      await tester.pumpAndSettle();
      expect(find.text('Skills for B'), findsOneWidget);
      expect(find.text('Skills for A'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await fixture.dispose(tester);
    }
  });
}
