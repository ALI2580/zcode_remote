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
  testWidgets(
      'review: real Plugins settings refreshes capability pages and existing/future composers once',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 1100);
    addTearDown(tester.view.reset);
    final preferences = ClientPreferences();
    await preferences.setLanguage('en');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (device) =>
            FakeDeviceSession(device.params!, FeatureBridge()));
    final bridge = FeatureBridge();
    var enabled = true;
    var prepRequests = 0;
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.pluginManagement) {
        if (method == 'setPluginEnabled') {
          final payload = args.single as Map;
          expect(payload['pluginId'], 'review-plugin@synthetic');
          expect(payload['scope'], 'user');
          enabled = payload['enabled'] == true;
          return {'success': true};
        }
        if (method == 'listPlugins') {
          return {
            'plugins': [
              {
                'id': 'review-plugin@synthetic',
                'name': 'review-plugin',
                'marketplace': 'synthetic',
                'scope': 'user',
                'enabled': enabled,
                'packageStatus': 'ok',
                'declaredMcpServerNames': ['review-mcp'],
                'mcpServerNames': [
                  if (enabled) 'plugin:review-plugin:review-mcp'
                ],
              }
            ]
          };
        }
        if (method == 'getPluginsOverview') {
          return {
            'installedPlugins': [
              {'id': 'review-plugin@synthetic', 'scope': 'user'}
            ]
          };
        }
      }
      if (channel == Channels.skills && method == 'list') {
        return {
          'capability': {'supported': true, 'userScopeAvailable': true},
          'skills': [
            {
              'id': 'review-skill',
              'name': 'review-skill',
              'scope': 'plugin',
              'path': 'D:/Synthetic/SKILL.md',
              'enabled': true,
              'pluginId': 'review-plugin@synthetic',
              'pluginName': 'review-plugin',
              'pluginMarketplace': 'synthetic',
            }
          ]
        };
      }
      if (method == 'loadMcpFromUserDirectory') return {'servers': []};
      if (method == 'listWorkspaceMcpServerStatuses') return {'statuses': []};
      // Independent capability pages must work even when setting.get is empty.
      return <String, dynamic>{};
    };
    bridge.conversationTransport.prepHandler = () async {
      prepRequests++;
      return WorkspacePrep.fromRaw({
        'configOptions': [
          {
            'id': 'model',
            'name': 'Model',
            'category': 'model',
            'type': 'select',
            'currentValue': 'synthetic/model',
            'options': [
              {
                'value': 'synthetic/model',
                'name': enabled ? 'Plugin enabled' : 'Plugin disabled',
                'modelProviderId': 'synthetic',
                'modelProviderName': 'Synthetic',
              }
            ]
          }
        ]
      });
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Synthetic'
        },
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Synthetic',
            workspaceKey: 'workspace',
            workspacePath: 'D:/Synthetic'),
        notifications: sessions.notifications);
    final composers = [
      for (final id in ['main', 'side'])
        sessions.composers.obtain(
            transport: bridge.conversationTransport,
            deviceId: 'device',
            workspaceKey: 'workspace',
            sessionId: id)
    ];
    Future<void> section(String label) async {
      final entry = find.text(label).first;
      await tester.ensureVisible(entry);
      await tester.pumpAndSettle();
      await tester.tap(entry);
      await tester.pumpAndSettle();
    }

    try {
      for (final composer in composers) {
        await composer.loadOptions();
        composer.input.text = 'Preserve ${composer.sessionId}';
      }
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: preferences,
          home: SettingsCenterPage(
              preferences: preferences,
              sessions: sessions,
              remoteMonitor: monitor,
              initialSection: 'skills',
              onManageDevices: () {})));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('skill-item-review-skill-plugin')),
          findsOneWidget);
      await section('MCP Servers');
      expect(find.text('review-mcp'), findsOneWidget);
      await section('Plugins');
      final toggle =
          find.byKey(const ValueKey('plugin-enabled-review-plugin@synthetic'));
      expect(toggle, findsOneWidget);
      final beforePrepare = prepRequests;
      await tester.ensureVisible(toggle);
      await tester.pumpAndSettle();
      await tester.tap(toggle);
      await tester.pumpAndSettle();
      expect(enabled, isFalse);
      expect(prepRequests - beforePrepare, 1,
          reason:
              'The shared source refresh must not be duplicated by page callbacks.');
      for (final composer in composers) {
        expect(composer.options.models.single.name, 'Plugin disabled');
        expect(composer.input.text, 'Preserve ${composer.sessionId}');
      }
      final futureDraft = sessions.composers.obtain(
          transport: bridge.conversationTransport,
          deviceId: 'device',
          workspaceKey: 'workspace',
          sessionId: '');
      await futureDraft.loadOptions();
      expect(futureDraft.options.models.single.name, 'Plugin disabled');
      await section('Skills');
      expect(find.byKey(const ValueKey('skill-item-review-skill-plugin')),
          findsNothing);
      await section('MCP Servers');
      expect(find.text('review-mcp'), findsNothing,
          reason:
              'Official CXt filters disabled plugins before Zxt/SXt projects MCP rows.');
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
