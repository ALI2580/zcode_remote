import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/composer_input.dart';
import 'package:zcode_remote/state/composer_attachments.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';

import 'fake_features.dart';
import 'fake_workspace.dart';
import 'review_connected_session.dart';

void main() {
  for (final occupied in [false, true]) {
    testWidgets(
        'review: skill draft navigation preserves existing content occupied=$occupied',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 900);
      addTearDown(tester.view.reset);
      final store =
          DeviceStore(requireEncryption: false, encrypt: (_) async => null);
      final device = await store.addUrl(
          'https://zcode.z.ai/remote/v4?sid=synthetic-skill-navigation&hash=synthetic&t=1',
          label: 'Review device');
      final bridge = FeatureBridge();
      bridge.channels.handler = (channel, method, _) {
        if (channel == Channels.skills && method == 'list') {
          return {
            'capability': {'supported': true, 'userScopeAvailable': true},
            'skills': [
              {
                'id': 'creator-id',
                'name': 'skill-creator',
                'scope': 'user',
                'path': 'C:/Synthetic/skills/skill-creator/SKILL.md',
                'enabled': true
              }
            ],
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
          sessions.composers.attachmentDrafts[draftKey] = [
            PickedAttachment(
                name: 'preserved.txt',
                mime: 'text/plain',
                size: 1,
                read: () async => throw StateError(
                    'Navigation must not read or upload the attachment'))
          ];
          final existing = sessions.composers.obtain(
              transport: bridge.conversation(shell.monitor.scope),
              deviceId: device.id,
              workspaceKey: 'workspace');
          existing.input.text = 'Keep unrelated draft ';
          existing.input.insertReference(
              TextRange.collapsed(existing.input.text.length),
              const ComposerReference(
                  id: 'original-file',
                  category: 'files',
                  label: 'original.txt',
                  value: 'C:/Synthetic/original.txt'));
          previousInput = existing.input.snapshot.toJson();
        }
        await tester.enterText(find.byKey(const ValueKey('composer-input')),
            'Keep original task draft');
        showSettingsCenter(
            tester.element(find.byType(WorkspaceShell)), sessions, preferences,
            remoteMonitor: shell.monitor, section: 'skills');
        await tester.pumpAndSettle();
        final create = find.byKey(const ValueKey('skills-new'));
        await tester.ensureVisible(create);
        await tester.pumpAndSettle();
        await tester.tap(create);
        await tester.pumpAndSettle();
        if (occupied) {
          expect(find.text('Draft already contains content'), findsOneWidget);
          await tester.tap(find.text('Back to Composer'));
          await tester.pumpAndSettle();
        }
        final chat = tester.widget<ChatPage>(find.byType(ChatPage));
        expect(chat.sessionId, isNull,
            reason:
                'Closing settings must select the new draft rather than return to the existing task.');
        expect(chat.deviceId, device.id);
        expect(chat.workspaceKey, 'workspace');
        expect(tester.state(find.byType(WorkspaceShell)), same(shellState));
        final input = tester.widget<EditableText>(find.descendant(
            of: find.byKey(const ValueKey('composer-input')),
            matching: find.byType(EditableText)));
        if (occupied) {
          expect(sessions.composers.inputSnapshots[draftKey]!.toJson(),
              previousInput);
          expect(sessions.composers.attachmentDrafts[draftKey]!.single.name,
              'preserved.txt');
          expect(input.controller.text, isNot(contains('skill-creator')));
          expect(bridge.conversationTransport.uploads, isEmpty);
        } else {
          expect(input.controller.text, contains('skill-creator'));
        }
        expect(sessions.drafts[composerKey(device.id, 'workspace', 'task')],
            'Keep original task draft');
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
