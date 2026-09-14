import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';

import 'fake_features.dart';
import 'fake_workspace.dart';

void main() {
  for (final leaveByCleanup in [false, true]) {
    testWidgets(
        'review: provider configuration refreshes existing main and side composer catalogs cleanup=$leaveByCleanup',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 900);
      addTearDown(tester.view.reset);
      final preferences = ClientPreferences();
      await preferences.setLanguage('en');
      final store = DeviceStore(requireEncryption: false);
      await store.load();
      final sessions = FakeAppSessions(
          store: store,
          sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
      final bridge = FeatureBridge();
      Map<String, dynamic> provider = {
        'id': 'custom-review',
        'name': 'Before change',
        'source': 'custom',
        'enabled': true,
        'apiFormat': 'anthropic-messages',
        'defaultKind': 'anthropic',
        'apiKey': 'synthetic-key',
        'endpoints': {'baseURL': 'https://synthetic.invalid'},
        'models': [
          {
            'id': 'm1',
            'name': 'Before change',
            'contextWindow': 128000,
            'kinds': ['anthropic'],
            'defaultKind': 'anthropic'
          }
        ],
      };
      bridge.channels.handler = (channel, method, args) {
        if (channel == Channels.modelProvider) {
          if (method == 'save') {
            provider = Map<String, dynamic>.from(args.single as Map);
          }
          if (method == 'getDisplayOrder') return <String>[];
          return [provider];
        }
        return <String, dynamic>{};
      };
      bridge.conversationTransport.prepHandler =
          () async => WorkspacePrep.fromRaw({
                'configOptions': [
                  {
                    'id': 'model',
                    'name': 'Model',
                    'category': 'model',
                    'type': 'select',
                    'currentValue': 'custom-review/m1',
                    'options': [
                      {
                        'value': 'custom-review/m1',
                        'name': provider['name'],
                        'modelProviderId': 'custom-review',
                        'modelProviderName': 'Catalog review'
                      }
                    ],
                  }
                ],
              });
      final monitor = FakeWorkspaceMonitor(
          bridge: bridge,
          scope: const {
            'workspaceIdentity': 'workspace',
            'workspacePath': 'D:/Synthetic'
          },
          notifications: sessions.notifications,
          source: const WorkspaceTaskSource(
              deviceId: 'device',
              deviceLabel: 'Review',
              workspaceKey: 'workspace'));
      final controllers = [
        for (final id in ['main', 'side'])
          sessions.composers.obtain(
              transport: bridge.conversation(monitor.scope),
              deviceId: 'device',
              workspaceKey: 'workspace',
              sessionId: id),
      ];
      try {
        for (final controller in controllers) {
          await controller.loadOptions();
          expect(controller.options.models.single.name, 'Before change');
          controller.input.text = 'Preserve ${controller.sessionId} draft';
        }
        await tester.pumpWidget(ZcodeRemoteApp(
            preferences: preferences,
            home: SettingsCenterPage(
                preferences: preferences,
                sessions: sessions,
                remoteMonitor: monitor,
                initialSection: 'modelProvider',
                onManageDevices: () {})));
        await tester.pumpAndSettle();
        final edit = find.byTooltip('Edit provider');
        await tester.ensureVisible(edit);
        await tester.tap(edit);
        await tester.pumpAndSettle();
        final name = find.byWidgetPredicate((widget) =>
            widget is TextField && widget.decoration?.labelText == 'Name');
        await tester.enterText(name, 'After change');
        if (leaveByCleanup) {
          Navigator.of(tester.element(name)).pop();
        } else {
          await tester.ensureVisible(find.text('Save'));
          await tester.tap(find.text('Save'));
        }
        await tester.pumpAndSettle();
        expect(provider['name'], 'After change');
        for (final controller in controllers) {
          expect(controller.options.models.single.name, 'After change',
              reason:
                  'A successful model save must refresh the existing ${controller.sessionId} catalog, not only @draft.');
          expect(
              controller.input.text, 'Preserve ${controller.sessionId} draft');
        }
        expect(bridge.conversationTransport.sent, isEmpty);
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
