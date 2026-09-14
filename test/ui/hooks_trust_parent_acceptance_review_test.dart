import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'fake_features.dart';
import 'fake_workspace.dart';

void main() {
  testWidgets(
      'review: actual Hooks settings performs no-session trust with visible rejection and retry',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);
    final prefs = ClientPreferences();
    await prefs.setLanguage('en');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (device) =>
            FakeDeviceSession(device.params!, FeatureBridge()));
    final bridge = FeatureBridge();
    var accept = false, trusted = false;
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.hooks && method == 'grantWorkspaceHookTrust') {
        if (accept) trusted = true;
        return {
          'accepted': accept,
          if (!accept) 'reasonCode': 'workspace_hooks_bundle_changed'
        };
      }
      if (channel == Channels.hooks && method == 'loadHooks') {
        return {
          'hooks': [
            {
              'id': 'trust-review',
              'event': 'PreToolUse',
              'type': 'command',
              'command': 'synthetic-hook',
              'editable': false,
              'enabled': true,
              'location': {
                'source': 'zcode',
                'scope': 'project',
                'directoryPath': 'D:/Synthetic'
              },
              'workspaceHook': {
                'workspaceIdentity': 'workspace',
                'trustState': trusted ? 'trusted' : 'pending_trust',
                'bundleDigest': 'review-bundle',
                'hookDeclarationDigest': 'review-declaration',
                'reviewItemId': 'review-item'
              }
            }
          ]
        };
      }
      return <String, dynamic>{};
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Synthetic'
        },
        source: const WorkspaceTaskSource(
            deviceId: 'review-device',
            deviceLabel: 'Synthetic device',
            workspaceKey: 'workspace',
            workspacePath: 'D:/Synthetic'),
        notifications: sessions.notifications);
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: prefs,
          home: SettingsCenterPage(
              preferences: prefs,
              sessions: sessions,
              remoteMonitor: monitor,
              initialSection: 'hooks',
              onManageDevices: () {})));
      await tester.pumpAndSettle();
      final scope = find.byKey(const ValueKey('hooks-scope-picker'));
      await tester.tap(scope);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Synthetic device · workspace').last);
      await tester.pumpAndSettle();
      final trust = find.byKey(const ValueKey('hook-trust-trust-review'));
      expect(trust, findsOneWidget);
      await tester.ensureVisible(trust);
      await tester.pumpAndSettle();
      await tester.tap(trust);
      await tester.pumpAndSettle();
      expect(
          find.textContaining('workspace_hooks_bundle_changed'), findsOneWidget,
          reason: 'A rejected grant must remain visible and retryable.');
      accept = true;
      await tester.tap(trust);
      await tester.pumpAndSettle();
      final requests = bridge.channels.calls
          .where((call) => call.method == 'grantWorkspaceHookTrust');
      expect(requests, hasLength(2));
      for (final request in requests) {
        expect(request.args.single, {
          'workspacePath': 'D:/Synthetic',
          'workspaceIdentity': 'workspace',
          'bundleDigest': 'review-bundle',
          'hookDeclarationDigest': 'review-declaration'
        });
      }
      expect(trusted, isTrue);
      expect(bridge.channels.calls.where((call) => call.method == 'saveHooks'),
          isEmpty);
      expect(bridge.conversationTransport.sent, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
      sessions.dispose();
      await sessions.notifications.settled;
      prefs.dispose();
    }
  });
}
