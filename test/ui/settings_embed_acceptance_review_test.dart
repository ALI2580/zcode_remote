import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';

import 'fake_features.dart';
import 'fake_workspace.dart';

void main() {
  for (final section in ['devices', 'usage']) {
    testWidgets('review: $section content opens inside settings',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      const platform = MethodChannel('zcode_remote/platform');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform,
              (call) async => call.method == 'timeZone' ? 'Asia/Shanghai' : null);
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(platform, null));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 820);
      addTearDown(tester.view.reset);
      final preferences = ClientPreferences();
      await preferences.setLanguage('en');
      final store = DeviceStore(requireEncryption: false);
      await store.load();
      final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()),
      );
      final monitor = FakeWorkspaceMonitor(
        bridge: FeatureBridge(),
        scope: const {
          'workspaceIdentity': 'embed-review',
          'workspacePath': 'D:/Synthetic',
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
          deviceId: 'synthetic-device',
          deviceLabel: 'Synthetic device',
          workspaceKey: 'embed-review',
        ),
      );
      try {
        await tester.pumpWidget(ZcodeRemoteApp(
          preferences: preferences,
          home: SettingsCenterPage(
            preferences: preferences,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: section,
            onManageDevices: () => fail('Settings must show device content directly'),
          ),
        ));
        await tester.pumpAndSettle();
        expect(find.text('General'), findsOneWidget,
            reason: 'Wide settings navigation must remain visible.');
        if (section == 'devices') {
          expect(find.byTooltip('Add device'), findsOneWidget,
              reason: 'The actual device directory action must be inline.');
          expect(find.text('Manage devices'), findsNothing);
        } else {
          expect(find.text('App usage'), findsOneWidget,
              reason: 'The actual statistics controls must be inline.');
          expect(find.text('Open usage page'), findsNothing);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        monitor.dispose();
        sessions.dispose();
        await sessions.notifications.settled;
        preferences.dispose();
      }
    });
  }
}
