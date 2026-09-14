import 'dart:async';

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
import 'review_connected_session.dart';

class _SourceFixture {
  final preferences = ClientPreferences();
  final store =
      DeviceStore(requireEncryption: false, encrypt: (_) async => null);
  final gateA = Completer<void>();
  final devices = <Device>[];
  final bridges = <String, FeatureBridge>{};
  late FakeAppSessions sessions;
  late FakeWorkspaceMonitor current;

  Future<void> initialize() async {
    await preferences.setLanguage('en');
    for (final name in ['A', 'B', 'C']) {
      final device = await store.addUrl(
          'https://zcode.z.ai/remote/v4?sid=synthetic-agent-$name&hash=synthetic&t=1',
          label: 'Device $name');
      devices.add(device);
      final bridge = FeatureBridge();
      bridge.channels.handler = (channel, method, args) {
        if (channel == Channels.subagents && method == 'list') {
          return {
            'capability': {'supported': true, 'userScopeAvailable': true},
            'agents': [
              for (final scope in ['user', 'workspace'])
                {
                  'id': 'agent-$name-$scope',
                  'name': 'agent-$name-$scope',
                  'scope': scope,
                  'source': 'user',
                  'description': 'Synthetic source $name',
                  'systemPrompt': 'Synthetic prompt',
                  'projectPath': 'D:/Project',
                  'enabled': true,
                }
            ],
            'pluginAgents': <Map<String, dynamic>>[],
          };
        }
        if (channel == Channels.modelProvider) {
          if (method == 'getDisplayOrder') return <String>[];
          if (method == 'getAll') {
            return [
              {
                'id': 'provider-$name',
                'name': 'Provider $name',
                'enabled': true,
                'source': 'custom',
                'models': [
                  {
                    'id': 'model-$name',
                    'name': 'Model $name',
                    'kinds': ['anthropic'],
                    'defaultKind': 'anthropic',
                    'contextWindow': 128000,
                  }
                ],
              }
            ];
          }
        }
        return <String, dynamic>{};
      };
      bridges[device.id] = bridge;
    }
    sessions = FakeAppSessions(
        store: store,
        sessionFactory: (device) => ReviewConnectedSession(
            device.params!, bridges[device.id]!,
            gate: device.id == devices.first.id ? gateA.future : null));
    for (final device in devices) {
      sessions.sessionFor(device);
    }
    current = FakeWorkspaceMonitor(
        bridge: bridges[devices.last.id]!,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
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
          preferences: preferences,
          sessions: sessions,
          remoteMonitor: current,
          initialSection: 'subagents',
          onManageDevices: () {}));

  Future<void> select(WidgetTester tester, String name) async {
    final picker = find.byKey(const ValueKey('subagents-scope'));
    await tester.ensureVisible(picker);
    await tester.pumpAndSettle();
    await tester.tap(picker);
    await tester.pumpAndSettle();
    final option = find.text('Device $name · ZcodeRemote');
    expect(option, findsOneWidget,
        reason:
            'The actual Settings page must expose each connected workspace.');
    await tester.tap(option.last);
    await tester.pumpAndSettle();
  }

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
  for (final pendingA in [false, true]) {
    testWidgets(
        'review: actual Subagents scope and model options use selected bridge pendingA=$pendingA',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 1000);
      addTearDown(tester.view.reset);
      final fixture = _SourceFixture();
      await fixture.initialize();
      try {
        await tester.pumpWidget(fixture.page);
        await tester.pumpAndSettle();
        expect(find.text('agent-C-user'), findsOneWidget);
        if (pendingA) await fixture.select(tester, 'A');
        await fixture.select(tester, 'B');
        if (pendingA) {
          fixture.gateA.complete();
          await tester.pumpAndSettle();
        }
        expect(find.text('agent-B-workspace'), findsOneWidget);
        expect(find.text('agent-C-user'), findsNothing);
        expect(find.text('agent-A-workspace'), findsNothing);
        final create = find.byKey(const ValueKey('subagents-create'));
        await tester.ensureVisible(create);
        await tester.tap(create);
        await tester.pumpAndSettle();
        final model = tester.widget<DropdownButton<String>>(find.descendant(
            of: find.byKey(const ValueKey('subagent-model-field')),
            matching: find.byType(DropdownButton<String>)));
        expect(model.items!.map((item) => item.value),
            contains('provider-B/model-B'));
        expect(model.items!.map((item) => item.value),
            isNot(contains('provider-C/model-C')),
            reason:
                'Changing scope must also change the model catalog source.');
        for (final bridge in fixture.bridges.values) {
          expect(bridge.conversationTransport.sent, isEmpty);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    });
  }
}
