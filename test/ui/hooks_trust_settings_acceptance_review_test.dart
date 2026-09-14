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

void main() {
  testWidgets('Settings Hooks trust button uses the no-session trust RPC',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);
    final preferences = ClientPreferences();
    await preferences.setLanguage('en');
    final sessions = FakeAppSessions(
      store: DeviceStore(requireEncryption: false),
      sessionFactory: (device) => FakeDeviceSession(
        device.params!,
        bridge,
      ),
    );
    final grants = <Map<String, dynamic>>[];
    bridge.channels.handler = (_, method, args) {
      if (method == 'loadHooks') {
        return {
          'hooks': [
            {
              'id': 'pending-hook',
              'event': 'PreToolUse',
              'type': 'command',
              'command': 'synthetic',
              'enabled': true,
              'editable': true,
              'location': {'source': 'zcode', 'scope': 'project'},
              'workspaceHook': {
                'trustState': 'pending_trust',
                'workspaceIdentity': 'workspace',
                'bundleDigest': 'bundle-digest',
                'hookDeclarationDigest': 'hook-digest',
                'reviewItemId': 'review-item',
              },
            },
          ],
        };
      }
      if (method == 'grantWorkspaceHookTrust') {
        grants.add((args.single as Map).cast<String, dynamic>());
        return {'accepted': true};
      }
      return <String, dynamic>{};
    };
    final monitor = FakeWorkspaceMonitor(
      bridge: bridge,
      scope: const {
        'workspaceIdentity': 'workspace',
        'workspacePath': 'D:/Synthetic',
      },
      source: const WorkspaceTaskSource(
        deviceId: 'device',
        deviceLabel: 'Device',
        workspaceKey: 'workspace',
        workspacePath: 'D:/Synthetic',
      ),
      notifications: sessions.notifications,
    );
    addTearDown(monitor.dispose);
    addTearDown(preferences.dispose);

    await tester.pumpWidget(
      ZcodeRemoteApp(
        preferences: preferences,
        home: SettingsCenterPage(
          preferences: preferences,
          sessions: sessions,
          remoteMonitor: monitor,
          initialSection: 'hooks',
          onManageDevices: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hooks-scope-picker')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Device · workspace').last);
    await tester.pumpAndSettle();
    final trust = find.byKey(const ValueKey('hook-trust-pending-hook'));
    expect(trust, findsOneWidget);
    await tester.tap(trust);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(grants, hasLength(1));
    expect(grants.single, {
      'workspaceIdentity': 'workspace',
      'workspacePath': 'D:/Synthetic',
      'bundleDigest': 'bundle-digest',
      'hookDeclarationDigest': 'hook-digest',
    });

    await tester.pumpWidget(const SizedBox.shrink());
    monitor.dispose();
    sessions.dispose();
    await sessions.notifications.settled;
  });
}

final bridge = FeatureBridge();
