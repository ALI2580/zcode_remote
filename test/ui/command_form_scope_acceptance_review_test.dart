import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/remote_agent_catalogs.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/command_form_dialog.dart';
import 'package:zcode_remote/ui/commands_settings.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';

import 'fake_features.dart';
import 'fake_workspace.dart';

class _WorkspaceSession extends FakeDeviceSession {
  _WorkspaceSession(super.params, super.bridge, this.path);

  final String path;

  @override
  List<Map<String, dynamic>> get workspaces => [
        {
          'workspaceIdentity': 'workspace',
          'name': 'Workspace',
          'workspacePath': path,
        }
      ];
}

void main() {
  testWidgets(
      'review: selecting a command form workspace preserves edits and writes that source',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 1100);
    addTearDown(tester.view.reset);
    final a = FeatureBridge(), b = FeatureBridge();
    for (final bridge in [a, b]) {
      bridge.channels.handler = (_, method, args) => method == 'list'
          ? {
              'commands': [],
              'capability': {'userScopeAvailable': true}
            }
          : <String, dynamic>{};
    }
    final first = CommandsCatalog(
        session: a,
        scope: const {'workspaceIdentity': 'a'},
        scopeKey: 'user',
        workspacePath: 'D:/A');
    final second = CommandsCatalog(
        session: b,
        scope: const {'workspaceIdentity': 'b'},
        scopeKey: 'b',
        workspacePath: 'D:/B',
        scopeKind: 'project');
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: CommandsSettingsPage(catalog: first, scopes: [
        CommandScopeOption(
            key: 'user',
            label: 'User',
            scope: 'user',
            identity: const {'workspaceIdentity': 'a'},
            workspacePath: 'D:/A',
            catalog: first),
        CommandScopeOption(
            key: 'b',
            label: 'Workspace B',
            scope: 'project',
            identity: const {'workspaceIdentity': 'b'},
            workspacePath: 'D:/B',
            catalog: second),
      ])))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('commands-create')));
      await tester.pumpAndSettle();
      final name = find.byWidgetPredicate((widget) =>
          widget is TextField && widget.decoration?.labelText == 'Name');
      final prompt = find.byWidgetPredicate((widget) =>
          widget is TextField && widget.decoration?.labelText == 'Prompt');
      await tester.enterText(name, 'source-review');
      await tester.enterText(prompt, 'Keep this unsaved prompt');
      await tester.tap(find.byKey(const ValueKey('command-form-scope')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workspace B').last);
      await tester.pumpAndSettle();
      expect(name, findsOneWidget,
          reason:
              'Official MXt changes form scope without closing the editor.');
      expect(tester.widget<TextField>(name).controller!.text, 'source-review');
      expect(tester.widget<TextField>(prompt).controller!.text,
          'Keep this unsaved prompt');
      await tester.ensureVisible(find.text('Save'));
      await tester.tap(find.text('Save'));
      await tester.pumpAndSettle();
      expect(
          a.channels.calls.where((call) => call.method == 'writeCommandFile'),
          isEmpty);
      final writes = b.channels.calls
          .where((call) => call.method == 'writeCommandFile')
          .toList();
      expect(writes, hasLength(1));
      expect(writes.single.args.single, {
        'config': {
          'name': 'source-review',
          'prompt': 'Keep this unsaved prompt'
        },
        'agentSource': 'zcodeAgent',
        'storageLevel': 'project',
        'workspacePath': 'D:/B'
      });
      expect(
          tester
              .widget<DropdownButton<String>>(
                  find.byKey(const ValueKey('commands-scope')))
              .value,
          'user',
          reason:
              'The form target is independent of the list scope (official IXt I versus r).');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      second.dispose();
    }
  });

  testWidgets(
      'review: pending command form target cannot submit through the old bridge',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 1100);
    addTearDown(tester.view.reset);
    final a = FeatureBridge(), b = FeatureBridge();
    for (final bridge in [a, b]) {
      bridge.channels.handler = (_, method, args) => method == 'list'
          ? {
              'commands': [],
              'capability': {'userScopeAvailable': true}
            }
          : <String, dynamic>{};
    }
    final first = CommandsCatalog(
        session: a,
        scope: const {'workspaceIdentity': 'a'},
        scopeKey: 'user',
        workspacePath: 'D:/A');
    final second = CommandsCatalog(
        session: b,
        scope: const {'workspaceIdentity': 'b'},
        scopeKey: 'b',
        workspacePath: 'D:/B',
        scopeKind: 'project');
    final openingB = Completer<CommandsCatalog?>();
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: CommandsSettingsPage(
                      catalog: first,
                      onScopeSelected: (_) => openingB.future,
                      scopes: [
            CommandScopeOption(
                key: 'user',
                label: 'User',
                scope: 'user',
                identity: const {'workspaceIdentity': 'a'},
                workspacePath: 'D:/A',
                catalog: first),
            const CommandScopeOption(
                key: 'b',
                label: 'Workspace B',
                scope: 'project',
                identity: {'workspaceIdentity': 'b'},
                workspacePath: 'D:/B'),
          ])))));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('commands-create')));
      await tester.pumpAndSettle();
      await tester.enterText(
          find.byWidgetPredicate((widget) =>
              widget is TextField && widget.decoration?.labelText == 'Name'),
          'pending-target');
      await tester.enterText(
          find.byWidgetPredicate((widget) =>
              widget is TextField && widget.decoration?.labelText == 'Prompt'),
          'Preserve this prompt');
      await tester.tap(find.byKey(const ValueKey('command-form-scope')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workspace B').last);
      await tester.pump();
      final save = find.text('Save');
      await tester.ensureVisible(save);
      await tester.tap(save, warnIfMissed: false);
      await tester.pump();
      expect(
          a.channels.calls.where((call) => call.method == 'writeCommandFile'),
          isEmpty,
          reason:
              'The old A bridge cannot receive a write labelled for pending B.');
      expect(
          b.channels.calls.where((call) => call.method == 'writeCommandFile'),
          isEmpty);
      openingB.complete(second);
      await tester.pumpAndSettle();
      expect(
          find.byWidgetPredicate((widget) =>
              widget is TextField &&
              widget.controller?.text == 'Preserve this prompt'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      if (!openingB.isCompleted) openingB.complete(second);
      await tester.pump();
      await tester.pumpWidget(const SizedBox.shrink());
      first.dispose();
      second.dispose();
    }
  });

  testWidgets(
      'review: parent form writes B and refreshes B while list remains User',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 1100);
    addTearDown(tester.view.reset);
    final preferences = ClientPreferences();
    await preferences.setLanguage('en');
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final a = FeatureBridge();
    final b = FeatureBridge();
    final writesA = <List<Object?>>[];
    final writesB = <List<Object?>>[];
    var composerRefreshB = 0;
    final bridgeById = <String, FeatureBridge>{};
    final pathById = <String, String>{};
    final deviceA = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=parent-a&hash=synthetic&t=1',
        label: 'Device A');
    final deviceB = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=parent-b&hash=synthetic&t=1',
        label: 'Device B');
    bridgeById[deviceA.id] = a;
    bridgeById[deviceB.id] = b;
    pathById[deviceA.id] = 'D:/A';
    pathById[deviceB.id] = 'D:/B';

    void configure(FeatureBridge bridge, String deviceId, String path) {
      bridge.channels.handler = (channel, method, args) {
        if (channel == Channels.commands && method == 'list') {
          return {
            'commands': deviceId == deviceA.id
                ? [
                    {
                      'id': 'existing-a',
                      'name': 'existing-a',
                      'source': 'user',
                      'agentSource': 'zcodeAgent',
                      'enabled': true,
                      'filePath': '$path/existing-a.md',
                      'location': {'source': 'zcode', 'scope': 'user'},
                    }
                  ]
                : <Map<String, dynamic>>[],
            'capability': {'userScopeAvailable': true},
          };
        }
        if (channel == Channels.commands && method == 'writeCommandFile') {
          (deviceId == deviceA.id ? writesA : writesB).add(args);
          return <String, dynamic>{};
        }
        if (channel == Channels.modelProvider && method == 'getAll') {
          return <Map<String, dynamic>>[];
        }
        if (channel == Channels.modelProvider && method == 'getDisplayOrder') {
          return <String>[];
        }
        return <String, dynamic>{};
      };
      bridge.conversationTransport.prepHandler = () async {
        if (deviceId == deviceB.id) composerRefreshB++;
        return WorkspacePrep.fromRaw(composerPrepFixture);
      };
    }

    configure(a, deviceA.id, 'D:/A');
    configure(b, deviceB.id, 'D:/B');
    final sessions = FakeAppSessions(
      store: store,
      sessionFactory: (device) => _WorkspaceSession(
          device.params!, bridgeById[device.id]!, pathById[device.id]!),
    );
    for (final device in store.devices) {
      sessions.sessionFor(device);
    }
    final monitorA = FakeWorkspaceMonitor(
      bridge: a,
      scope: const {
        'workspaceIdentity': 'workspace',
        'workspacePath': 'D:/A',
      },
      source: const WorkspaceTaskSource(
        deviceId: 'device-a',
        deviceLabel: 'Device A',
        workspaceKey: 'workspace',
        workspacePath: 'D:/A',
      ),
      notifications: sessions.notifications,
    );
    sessions.monitors[deviceA.id] = monitorA;
    Future<void> settle() async {
      for (var index = 0; index < 30; index++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    try {
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: SettingsCenterPage(
          preferences: preferences,
          sessions: sessions,
          remoteMonitor: monitorA,
          initialSection: 'commands',
          onManageDevices: () {},
        ),
      ));
      await settle();
      await tester.tap(find.byKey(const ValueKey('commands-create')));
      await settle();
      await tester.enterText(
          find.byWidgetPredicate((widget) =>
              widget is TextField && widget.decoration?.labelText == 'Name'),
          'parent-b');
      await tester.enterText(
          find.byWidgetPredicate((widget) =>
              widget is TextField && widget.decoration?.labelText == 'Prompt'),
          'Write through B');
      await tester.tap(find.byKey(const ValueKey('command-form-scope')));
      await settle();
      await tester.tap(find.text('Device B · Workspace').last);
      await settle();
      await tester.tap(find.text('Save'));
      await settle();
      expect(writesA, isEmpty);
      expect(writesB, hasLength(1));
      expect(writesB.single.single, {
        'config': {'name': 'parent-b', 'prompt': 'Write through B'},
        'agentSource': 'zcodeAgent',
        'storageLevel': 'project',
        'workspacePath': 'D:/B',
      });
      expect(
          tester
              .widget<DropdownButton<String>>(
                  find.byKey(const ValueKey('commands-scope')))
              .value,
          'user');
      expect(composerRefreshB, greaterThan(0));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      monitorA.dispose();
      sessions.dispose();
      await sessions.notifications.settled;
      preferences.dispose();
    }
  });
}
