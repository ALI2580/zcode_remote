import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_input.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';

import 'fake_features.dart';
import 'fake_workspace.dart';
import 'review_connected_session.dart';

void main() {
  for (final route in ['settings', 'marketplace']) {
    for (final occupied in [false, true]) {
      testWidgets(
          'review: plugin use returns typed draft route=$route occupied=$occupied',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = const Size(1180, 900);
        addTearDown(tester.view.reset);
        final store =
            DeviceStore(requireEncryption: false, encrypt: (_) async => null);
        final device = await store.addUrl(
            'https://zcode.z.ai/remote/v4?sid=synthetic-plugin-navigation&hash=synthetic&t=1',
            label: 'Review device');
        final bridge = FeatureBridge();
        bridge.channels.handler = (channel, method, args) {
          if (channel == Channels.pluginManagement && method == 'listPlugins') {
            return {
              'plugins': [
                {
                  'id': 'writer@official',
                  'name': 'Writer',
                  'marketplace': 'official',
                  'enabled': true,
                  'scope': 'user',
                  'packageStatus': 'ok',
                }
              ]
            };
          }
          if (channel == Channels.pluginManagement &&
              method == 'getPluginsOverview') {
            return {
              'availablePlugins': [
                {
                  'id': 'writer@official',
                  'name': 'Writer',
                  'marketplace': 'official',
                  'installed': true,
                }
              ],
              'installedPlugins': [
                {'id': 'writer@official', 'scope': 'user'}
              ],
              'restorableBuiltins': [],
              'marketplaces': [],
            };
          }
          return <String, dynamic>{};
        };
        final sessions = FakeAppSessions(
            store: store,
            sessionFactory: (d) => ReviewConnectedSession(d.params!, bridge));
        final preferences = ClientPreferences();
        await preferences.setLanguage('en');
        late BuildContext rootContext;
        try {
          await tester.pumpWidget(ZcodeRemoteApp(
              preferences: preferences,
              home: Builder(builder: (context) {
                rootContext = context;
                return const Scaffold(body: Text('Directory'));
              })));
          await openDeviceWorkspace(rootContext, sessions, preferences, device,
              target: TaskTarget(
                  deviceId: device.id,
                  workspaceKey: 'workspace',
                  sessionId: 'task',
                  title: 'Existing task'));
          await tester.pumpAndSettle();
          final shell =
              tester.widget<WorkspaceShell>(find.byType(WorkspaceShell));
          final shellState = tester.state(find.byType(WorkspaceShell));
          final draftKey = composerKey(device.id, 'workspace', null);
          Map<String, dynamic>? previousInput;
          if (occupied) {
            final existing = sessions.composers.obtain(
                transport: bridge.conversation(shell.monitor.scope),
                deviceId: device.id,
                workspaceKey: 'workspace');
            existing.input.text = 'Keep current draft ';
            existing.input.insertReference(
                TextRange.collapsed(existing.input.text.length),
                const ComposerReference(
                    id: 'existing',
                    category: 'files',
                    label: 'current.txt',
                    value: 'C:/Synthetic/current.txt'));
            previousInput = existing.input.snapshot.toJson();
          }
          showSettingsCenter(tester.element(find.byType(WorkspaceShell)),
              sessions, preferences,
              remoteMonitor: shell.monitor, section: 'plugins');
          await tester.pumpAndSettle();
          if (route == 'marketplace') {
            await tester.tap(find.text('Manage plugins'));
            await tester.pumpAndSettle();
            await tester.tap(find.byTooltip('Plugin actions'));
          } else {
            await tester.tap(
                find.byKey(const ValueKey('plugin-actions-writer@official')));
          }
          await tester.pumpAndSettle();
          await tester.tap(find.text('Use in new task'));
          await tester.pumpAndSettle();
          if (occupied) {
            expect(find.text('Draft already contains content'), findsOneWidget);
            await tester.tap(find.text('Back to Composer'));
            await tester.pumpAndSettle();
          }
          final chat = tester.widget<ChatPage>(find.byType(ChatPage));
          expect(chat.sessionId, isNull);
          expect(chat.deviceId, device.id);
          expect(chat.workspaceKey, 'workspace');
          expect(tester.state(find.byType(WorkspaceShell)), same(shellState));
          final input = tester.widget<EditableText>(find.descendant(
              of: find.byKey(const ValueKey('composer-input')),
              matching: find.byType(EditableText)));
          if (occupied) {
            expect(sessions.composers.inputSnapshots[draftKey]!.toJson(),
                previousInput);
            expect(input.controller.text, isNot(contains('Writer')));
          } else {
            expect(input.controller.text, contains('@Writer'));
          }
          expect(bridge.conversationTransport.sent, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          final session = sessions.sessionOf(device.id);
          if (session is ReviewConnectedSession) {
            await tester.runAsync(session.reviewClient.dispose);
          }
          sessions.dispose();
          await sessions.notifications.settled;
          preferences.dispose();
        }
      });
    }
  }
}
