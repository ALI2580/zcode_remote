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
      'review: actual builtin start-plan model editor only changes context window',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 1000);
    addTearDown(tester.view.reset);
    final prefs = ClientPreferences();
    await prefs.setLanguage('en');
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, _) {
      if (channel == Channels.modelProvider && method == 'getAll') {
        return [
          {
            'id': 'builtin:zai-start-plan',
            'name': 'Synthetic start plan',
            'source': 'builtin',
            'enabled': true,
            'apiKey': 'synthetic-plan-key',
            'apiFormat': 'anthropic-messages',
            'defaultKind': 'anthropic',
            'endpoints': {
              'baseURL': 'https://synthetic.invalid/api/v1/zcode-plan'
            },
            'models': [
              {
                'id': 'GLM-5.2',
                'name': 'Review model',
                'kinds': ['anthropic'],
                'defaultKind': 'anthropic',
                'contextWindow': 128000,
                'maxOutputTokens': 8192,
                'modalities': {
                  'input': ['text', 'image'],
                  'output': ['text']
                }
              }
            ]
          }
        ];
      }
      if (method == 'getDisplayOrder') return <String>[];
      return <String, dynamic>{};
    };
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {'workspaceIdentity': 'workspace'},
        source: const WorkspaceTaskSource(
            deviceId: 'd', deviceLabel: 'D', workspaceKey: 'workspace'),
        notifications: sessions.notifications);
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: prefs,
          home: SettingsCenterPage(
              preferences: prefs,
              sessions: sessions,
              remoteMonitor: monitor,
              initialSection: 'modelProvider',
              onManageDevices: () {})));
      await tester.pumpAndSettle();
      final edit = find.byTooltip('Edit');
      await tester.ensureVisible(edit);
      await tester.tap(edit);
      await tester.pumpAndSettle();
      final fields = tester.widgetList<TextField>(find.byType(TextField));
      final contextField = fields
          .where((field) => (field.decoration?.labelText ?? '')
              .toLowerCase()
              .contains('context'))
          .single;
      expect(contextField.readOnly, isFalse);
      expect(contextField.enabled, isNot(false));
      for (final field
          in fields.where((field) => !identical(field, contextField))) {
        expect(field.readOnly || field.enabled == false, isTrue,
            reason:
                'Start-plan ${field.decoration?.labelText} must not be editable.');
      }
      for (final chip
          in tester.widgetList<FilterChip>(find.byType(FilterChip))) {
        expect(chip.onSelected, isNull,
            reason: 'Start-plan modality/kind editing is disabled.');
      }
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
