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
  testWidgets('review: model settings tests the configured model through RPC',
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
      sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()),
    );
    final bridge = FeatureBridge();
    final provider = <String, dynamic>{
      'id': 'custom-review',
      'name': 'Review provider',
      'source': 'custom',
      'enabled': true,
      'apiFormat': 'anthropic-messages',
      'defaultKind': 'anthropic',
      'apiKey': 'synthetic-review-key',
      'endpoints': {
        'baseURL': 'https://synthetic.invalid',
        'paths': {'anthropic-messages': '/v1/messages'},
      },
      'headers': {'x-synthetic': 'review'},
      'models': [
        {
          'id': 'review-model',
          'name': 'Review model',
          'kinds': ['anthropic'],
          'defaultKind': 'anthropic',
          'contextWindow': 128000,
        },
      ],
    };
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.modelProvider) {
        if (method == 'getDisplayOrder') return <String>[];
        if (method == 'testModelConnectivity') {
          return {
            'results': [
              {'success': true}
            ]
          };
        }
        return [provider];
      }
      return <String, dynamic>{};
    };
    final monitor = FakeWorkspaceMonitor(
      bridge: bridge,
      scope: const {
        'workspaceIdentity': 'model-review',
        'workspacePath': 'D:/Synthetic',
      },
      notifications: sessions.notifications,
      source: const WorkspaceTaskSource(
        deviceId: 'synthetic-device',
        deviceLabel: 'Synthetic device',
        workspaceKey: 'model-review',
      ),
    );
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: SettingsCenterPage(
          preferences: preferences,
          sessions: sessions,
          remoteMonitor: monitor,
          initialSection: 'modelProvider',
          onManageDevices: () {},
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Review provider'), findsWidgets,
          reason: 'A completed provider read must replace the loading state.');
      final testButton = find.byTooltip('Test model');
      expect(testButton, findsOneWidget,
          reason:
              'The configured model needs the official connectivity action.');
      await tester.ensureVisible(testButton);
      await tester.tap(testButton);
      await tester.pumpAndSettle();
      final requests = bridge.channels.calls
          .where((call) => call.method == 'testModelConnectivity')
          .toList();
      expect(requests, hasLength(1));
      final payload = requests.single.args.single as Map;
      expect(payload['model'], 'review-model');
      expect(payload['apiKey'], 'synthetic-review-key');
      expect(payload['endpoints'], provider['endpoints']);
      expect((payload['provider'] as Map)['headers'], provider['headers']);
      expect(
          bridge.channels.calls.where((call) => call.method == 'save'), isEmpty,
          reason: 'Testing a connection must not save the provider first.');
      expect(find.textContaining('synthetic-review-key'), findsNothing);
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
