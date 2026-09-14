import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/notifications/notification_platform.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'package:zcode_remote/ui/upgrade_page.dart';
import 'package:zcode_remote/ui/usage/usage_page.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';
import 'package:zcode_remote/state/workspace_catalog.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'fake_features.dart';
import 'usage_fixtures.dart';
import 'fake_workspace.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    const platform = MethodChannel('zcode_remote/platform');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(platform,
            (call) async => call.method == 'timeZone' ? 'Asia/Shanghai' : null);
  });
  tearDown(() => TestDefaultBinaryMessengerBinding
      .instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
          const MethodChannel('zcode_remote/platform'), null));

  testWidgets(
      'client preferences persist and narrow large-text settings stay usable',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.setLanguage('en');
    await prefs.setTheme(ThemeMode.light);
    await prefs.setTextScale(1.4);
    await prefs.setCodeFontSize(18);
    final restored = ClientPreferences();
    await restored.load();
    expect(restored.language, 'en');
    expect(restored.theme, ThemeMode.light);
    expect(restored.textScale, 1.4);
    expect(restored.codeFontSize, 18);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    for (final width in [344.0, 390.0, 720.0, 834.0, 1180.0]) {
      tester.view.physicalSize = Size(width, 740);
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: restored,
          home: SettingsCenterPage(
              preferences: restored,
              sessions: sessions,
              initialSection: 'appearance',
              onManageDevices: () {})));
      await tester.pumpAndSettle();
      final uiInput = find.descendant(
          of: find.byKey(const ValueKey('appearance-ui-font-size')),
          matching: find.byType(TextField));
      expect(tester.widget<TextField>(uiInput).controller!.text, '20');
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
    prefs.dispose();
    restored.dispose();
  });

  testWidgets(
      'remote settings load and render the connected workspace snapshot',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('en');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) => {
          'providerFamilyDomain': 'zai',
          'modelProviderFamilyModes': {'zai': 'oauth'},
          'modelProviderFamilySelectedKeys': {
            'zai': 'coding-plan:builtin:zai-start-plan'
          },
          'askUserQuestionAutoResolutionEnabled': false,
        };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            key: const ValueKey('commands-settings'),
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'modelProvider',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    // The zai family row leads the nav; the closed select shows the official
    // short mode label for the selected start-plan key (en locale).
    expect(find.text('Start plan'), findsWidgets);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'general auto-resolve toggle saves through the remote update and keeps the value on failure',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var autoResolve = false;
    var failUpdate = false;
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'system') {
        // Read-only system probe: no platform means the integrated-shell
        // select stays hidden in tests.
        return const {'platform': 'linux'};
      }
      if (method == 'update') {
        expect(channel, 'setting');
        if (failUpdate) throw StateError('rejected');
        autoResolve = (args.single
            as Map)['askUserQuestionAutoResolutionEnabled'] as bool;
        return null;
      }
      return {
        'providerFamilyDomain': 'zai',
        'askUserQuestionAutoResolutionEnabled': autoResolve,
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'general',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    expect(find.text('提问自动继续'), findsOneWidget);
    final autoResolveSwitch = find.byKey(
        const ValueKey('remote-toggle-askUserQuestionAutoResolutionEnabled'));
    expect(tester.widget<Switch>(autoResolveSwitch).value, isFalse);

    await tester.ensureVisible(autoResolveSwitch);
    await tester.pumpAndSettle();
    failUpdate = true;
    await tester.tap(autoResolveSwitch);
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(tester.widget<Switch>(autoResolveSwitch).value, isFalse);

    failUpdate = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsNothing);
    expect(tester.widget<Switch>(autoResolveSwitch).value, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'general terminal text and integrated shell follow the official save flow',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var terminalFont = 'Cascadia Mono';
    var shell = <String, dynamic>{
      'mode': 'shell',
      'id': 'git-bash',
      'label': 'Git Bash',
      'dialect': 'bash',
      'path': 'D:/Git/bin/bash.exe',
    };
    final patches = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'system') {
        if (method == 'info') return {'platform': 'win32'};
        if (method == 'listIntegratedTerminalShells') {
          return [
            {
              'id': 'git-bash',
              'label': 'Git Bash',
              'dialect': 'bash',
              'path': 'D:/Git/bin/bash.exe',
            },
            {
              'id': 'powershell',
              'label': 'PowerShell',
              'dialect': 'powershell',
              'path': 'C:/Windows/System32/WindowsPowerShell/powershell.exe',
            },
          ];
        }
        return const {};
      }
      if (method == 'update') {
        final patch = (args.single as Map).cast<String, dynamic>();
        patches.add(patch);
        if (patch.containsKey('terminalFontFamily')) {
          terminalFont = patch['terminalFontFamily'] as String;
        }
        if (patch.containsKey('integratedTerminalShell')) {
          shell =
              (patch['integratedTerminalShell'] as Map).cast<String, dynamic>();
        }
        return null;
      }
      return {
        'terminalFontFamily': terminalFont,
        'integratedTerminalShell': shell,
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 1200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'general',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    expect(find.text('集成终端Shell'), findsOneWidget);
    expect(find.text('Git Bash'), findsWidgets);

    // The stored shell not present on the system would still show; a stored
    // shell that IS present selects the matching option and switching to
    // auto writes the official `{mode: auto}` object.
    await tester.ensureVisible(find.text('Git Bash').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Git Bash').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('自动选择').last);
    await tester.pumpAndSettle();
    expect(patches.last, {
      'integratedTerminalShell': {'mode': 'auto'}
    });

    // Terminal font saves the trimmed text only when it differs from the
    // remote snapshot.
    final fontField = find.byWidgetPredicate((widget) =>
        widget is TextField && widget.controller?.text == 'Cascadia Mono');
    expect(fontField, findsOneWidget);
    await tester.ensureVisible(fontField);
    await tester.pumpAndSettle();
    await tester.enterText(fontField, '  JetBrains Mono  ');
    await tester.pumpAndSettle();
    // Official parity: Enter submits the trimmed text.
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(patches.last, {'terminalFontFamily': 'JetBrains Mono'});
    // Read-back renders the stored value and disables the button again.
    expect(
        find.byWidgetPredicate((widget) =>
            widget is TextField && widget.controller?.text == 'JetBrains Mono'),
        findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('memory toggle saves through the remote update', (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var memoryEnabled = false;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'update') {
        expect(channel, 'setting');
        memoryEnabled = (args.single as Map)['memoryEnabled'] as bool;
        return null;
      }
      return {
        'memoryEnabled': memoryEnabled,
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'memory',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    expect(find.text('工作区记忆'), findsOneWidget);
    expect(find.textContaining('长期上下文'), findsOneWidget);
    expect(find.textContaining('记忆详情仅支持在本地桌面端查看'), findsOneWidget);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'general remote task auto-archive writes switch and archive window',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var autoArchive = false;
    var archiveDays = 7;
    final patches = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      if (method == 'update') {
        final patch = (args.single as Map).cast<String, dynamic>();
        patches.add(patch);
        if (patch.containsKey('taskAutoArchiveEnabled')) {
          autoArchive = patch['taskAutoArchiveEnabled'] as bool;
        }
        if (patch.containsKey('taskAutoArchiveOlderThanDays')) {
          archiveDays = patch['taskAutoArchiveOlderThanDays'] as int;
        }
        return null;
      }
      return {
        'taskAutoArchiveEnabled': autoArchive,
        'taskAutoArchiveOlderThanDays': archiveDays,
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'general',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    expect(find.text('自动归档旧任务'), findsOneWidget);
    expect(find.text('归档保留时长'), findsOneWidget);

    final archiveSwitch =
        find.byKey(const ValueKey('remote-toggle-taskAutoArchiveEnabled'));
    await tester.ensureVisible(archiveSwitch);
    await tester.pumpAndSettle();
    await tester.tap(archiveSwitch);
    await tester.pumpAndSettle();
    expect(patches.last['taskAutoArchiveEnabled'], isTrue);
    expect(tester.widget<Switch>(archiveSwitch).value, isTrue);

    await tester.ensureVisible(find.text('7 天后归档'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('7 天后归档'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('14 天后归档').last);
    await tester.pumpAndSettle();
    expect(patches.last['taskAutoArchiveOlderThanDays'], 14);
    expect(find.text('14 天后归档'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'browser control toggles the browser-use plugin through the verified write',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var browserUseEnabled = false;
    final managementCalls = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'plugin-management') {
        final values = args.isNotEmpty ? (args.single as Map) : const {};
        if (method == 'listPlugins') {
          return {
            'plugins': [
              {
                'id': 'browser-use@zcode-plugins-official',
                'enabled': browserUseEnabled,
                'packageStatus': 'ok',
              }
            ],
          };
        }
        if (method == 'getPluginsOverview') {
          return {
            'availablePlugins': [
              {
                'id': 'browser-use@zcode-plugins-official',
                'name': 'Browser Use',
                'marketplace': 'zcode-plugins-official',
                'installed': true,
              }
            ],
            'installedPlugins': [
              {
                'id': 'browser-use@zcode-plugins-official',
                'packageStatus': 'ok'
              }
            ],
            'restorableBuiltins': [],
            'marketplaces': [],
          };
        }
        if (method == 'setPluginEnabled') {
          managementCalls.add(values.cast<String, dynamic>());
          browserUseEnabled = values['enabled'] as bool;
          return null;
        }
      }
      return {
        'memoryEnabled': false,
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'browser',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    // Official remote page: the desktop-only security toggle is absent and
    // the control card drives the browser-use plugin.
    expect(find.text('开启内置浏览器控制'), findsOneWidget);
    expect(find.text('允许不安全证书'), findsNothing);
    expect(find.textContaining('浏览器数据只能在'), findsOneWidget);
    final controlSwitch = find.byKey(const ValueKey('browser-control-toggle'));
    expect(tester.widget<Switch>(controlSwitch).value, isFalse);

    await tester.tap(controlSwitch);
    await tester.pumpAndSettle();
    expect(
        managementCalls.last['pluginId'], 'browser-use@zcode-plugins-official');
    expect(managementCalls.last['enabled'], isTrue);
    expect(tester.widget<Switch>(controlSwitch).value, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'general behavior toggles and interaction behavior write official patches',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var showReasoning = false;
    var behavior = 'queue';
    final patches = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'system') {
        return const {'platform': 'linux'};
      }
      if (method == 'update') {
        final patch = (args.single as Map).cast<String, dynamic>();
        patches.add(patch);
        if (patch.containsKey('messageStreamShowReasoning')) {
          showReasoning = patch['messageStreamShowReasoning'] as bool;
        }
        if (patch.containsKey('zcodeInteractionBehavior')) {
          behavior = patch['zcodeInteractionBehavior'] as String;
        }
        return null;
      }
      return {
        'messageStreamShowReasoning': showReasoning,
        'messageStreamShowTodos': true,
        'modelIoFullRetentionEnabled': false,
        'zcodeInteractionBehavior': behavior,
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 1200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'general',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    expect(find.text('显示思考过程'), findsOneWidget);
    expect(find.text('交互行为'), findsOneWidget);
    // Official IntlProvider labels (V1.3 locale alignment).
    expect(find.text('显示待办'), findsOneWidget);
    expect(find.text('完整保留模型 I/O'), findsOneWidget);
    expect(find.text('分组探索工具'), findsOneWidget);
    expect(find.text('分组终端命令'), findsOneWidget);
    expect(find.text('分组文件更改'), findsOneWidget);
    expect(find.text('在消息流中展示完整的模型思考内容；关闭时每轮仍展示第一次思考。'), findsOneWidget);

    final reasoningSwitch =
        find.byKey(const ValueKey('remote-toggle-messageStreamShowReasoning'));
    await tester.ensureVisible(reasoningSwitch);
    await tester.pumpAndSettle();
    await tester.tap(reasoningSwitch);
    await tester.pumpAndSettle();
    expect(patches.last, {'messageStreamShowReasoning': true});

    await tester.ensureVisible(find.text('队列'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('队列'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('引导').last);
    await tester.pumpAndSettle();
    expect(patches.last, {'zcodeInteractionBehavior': 'guide'});

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'indexing toggles write the official single and multi-key patches',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var repoEnabled = false;
    var grepEnabled = false;
    final patches = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      if (method == 'update') {
        final patch = (args.single as Map).cast<String, dynamic>();
        patches.add(patch);
        if (patch.containsKey('repoSnapshotIndexingEnabled')) {
          repoEnabled = patch['repoSnapshotIndexingEnabled'] as bool;
        }
        if (patch.containsKey('instantGrepIndexingEnabled')) {
          grepEnabled = patch['instantGrepIndexingEnabled'] as bool;
        }
        return null;
      }
      return {
        'repoSnapshotIndexingEnabled': repoEnabled,
        'instantGrepIndexingEnabled': grepEnabled,
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'indexing',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    expect(find.text('索引新文件夹'), findsOneWidget);
    expect(find.textContaining('50,000'), findsOneWidget);
    expect(find.text('索引存储库以实现即时搜索（测试版）'), findsOneWidget);

    final repoSwitch = find.byKey(const ValueKey(
        'remote-toggle-repoSnapshotIndexingEnabled|repoSnapshotIndexingUserConfigured'));
    final grepSwitch =
        find.byKey(const ValueKey('remote-toggle-instantGrepIndexingEnabled'));
    await tester.tap(repoSwitch);
    await tester.pumpAndSettle();
    expect(patches.first, {
      'repoSnapshotIndexingEnabled': true,
      'repoSnapshotIndexingUserConfigured': true,
    });
    expect(tester.widget<Switch>(repoSwitch).value, isTrue);

    await tester.tap(grepSwitch);
    await tester.pumpAndSettle();
    expect(patches.last, {'instantGrepIndexingEnabled': true});
    expect(tester.widget<Switch>(grepSwitch).value, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('modelProvider connection choice writes mode and key together',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var modes = <String, String>{
      'zai': 'oauth',
      'bigmodel': 'oauth',
    };
    Map<String, dynamic>? lastPatch;
    var prepCalls = 0;
    bridge.conversationTransport.prepHandler = () async {
      prepCalls++;
      return WorkspacePrep.fromRaw(composerPrepFixture);
    };
    bridge.channels.handler = (channel, method, args) {
      if (method == 'update') {
        lastPatch = (args.single as Map).cast<String, dynamic>();
        modes = (lastPatch!['modelProviderFamilyModes'] as Map)
            .cast<String, String>();
        return null;
      }
      return {
        'providerFamilyDomain': 'zai',
        'modelProviderFamilyModes': modes,
        'modelProviderFamilySelectedKeys': {
          'zai': 'coding-plan:builtin:zai-start-plan',
        },
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'modelProvider',
            onManageDevices: () {})));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<FamilyConnectionOption>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('API').last);
    await tester.pumpAndSettle();
    expect(lastPatch, {
      'modelProviderFamilyModes': <String, String>{
        'zai': 'apiKey',
        'bigmodel': 'oauth',
      },
      // The merged key map mirrors the remote value, which only carries zai.
      'modelProviderFamilySelectedKeys': <String, String>{
        'zai': 'preset:builtin:zai',
      },
    });
    expect(prepCalls, 1, reason: 'composer prep invalidated after write');

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('plugin settings open the scoped workspace plugin manager',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      expect(channel, 'plugin-management');
      if (method == 'listPlugins') {
        return {
          'plugins': [
            {'id': 'demo@official', 'name': 'Demo plugin', 'enabled': true}
          ]
        };
      }
      if (method == 'getPluginsOverview') {
        return {
          'availablePlugins': [
            {
              'id': 'demo@official',
              'name': 'Demo plugin',
              'marketplace': 'official',
              'description': 'Demo tools',
              'listing': {'category': 'utilities'}
            }
          ],
          'installedPlugins': [
            {'id': 'demo@official', 'packageStatus': 'ok'}
          ],
          'restorableBuiltins': [],
          'marketplaces': []
        };
      }
      return {};
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            key: const ValueKey('provider-order'),
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'plugins',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    final buttonFinder = find.text('Manage plugins');
    expect(buttonFinder, findsOneWidget);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();
    expect(find.text('Demo plugin'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('skills settings read the enabled workspace catalog',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) => {
          'skills': [
            {
              'id': 'review-code',
              'name': 'review-code',
              'path': '/user/review.md',
              'scope': 'user',
              'description': 'Review the patch',
              'enabled': true
            }
          ]
        };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'skills',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('review-code'), findsOneWidget);
    expect(find.textContaining('Review the patch'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('command form create, edit and delete write official payloads',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var commands = <Map<String, dynamic>>[];
    final writes = <String, Map<String, dynamic>>{};
    bridge.channels.handler = (channel, method, args) {
      if (channel != 'commands') {
        return method == 'update' ? null : {};
      }
      if (method == 'list') {
        return {
          'commands': commands,
          'userCommands': [],
          'pluginCommands': [],
          'capability': {'userScopeAvailable': true},
        };
      }
      if (method == 'writeCommandFile') {
        final payload = (args.single as Map).cast<String, dynamic>();
        writes['write'] = payload;
        final config = (payload['config'] as Map).cast<String, dynamic>();
        final row = <String, dynamic>{
          'id': 'cmd-1',
          'name': config['name'],
          'description': config['description'],
          'prompt': config['prompt'],
          'enabled': true,
          'source': 'user',
          'agentSource': payload['agentSource'],
          'filePath': 'commands/review.md',
          'location': {'source': 'zcode', 'scope': 'user'},
        };
        commands = [...commands, row];
        return {'command': row};
      }
      if (method == 'updateCommandFile') {
        final payload = (args.single as Map).cast<String, dynamic>();
        writes['update'] = payload;
        final config = (payload['config'] as Map).cast<String, dynamic>();
        final row = <String, dynamic>{
          ...commands.first,
          'description': config['description'],
        };
        commands = [row];
        return {'command': row};
      }
      if (method == 'deleteCommandFile') {
        writes['delete'] = (args.single as Map).cast<String, dynamic>();
        commands = [];
        return null;
      }
      return null;
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 1200);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'commands',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未安装命令'), findsOneWidget);

    // Create: chrome button opens the form; empty prompt blocks saving.
    // The inline form replaces the catalog toolbar: name/description/hint/prompt.
    await tester.tap(find.text('新建').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'review');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('提示词不能为空'), findsOneWidget);
    expect(writes.containsKey('write'), isFalse);

    await tester.enterText(find.byType(TextField).at(3), 'Review this');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.textContaining('/review'), findsOneWidget);
    final write = writes['write']!;
    expect((write['config'] as Map)['name'], 'review');
    expect((write['config'] as Map)['prompt'], 'Review this');
    expect((write['config'] as Map).containsKey('description'), isFalse);
    expect(write['storageLevel'], 'user');
    expect(write.containsKey('workspacePath'), isFalse);

    // Edit keeps the original row identity and sends the old file path.
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(1), 'Reviews changes');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final update = writes['update']!;
    expect(update['commandId'], 'cmd-1');
    expect(update['oldFilePath'], 'commands/review.md');
    expect((update['config'] as Map)['description'], 'Reviews changes');
    expect(find.text('Reviews changes'), findsOneWidget);

    // Delete is a two-step confirm and the list read-back empties the page.
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('此操作无法撤销'), findsOneWidget);
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(writes['delete'], {
      'agentSource': 'zcodeAgent',
      'commandId': 'cmd-1',
      'filePath': 'commands/review.md',
    });
    expect(find.textContaining('尚未安装命令'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'subagents and commands settings render catalogs and command enable writes read-back',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var commandEnabled = true;
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'subagents') {
        return {
          'agents': [
            {
              'id': 'reviewer',
              'name': 'Reviewer',
              'description': 'Reviews changes',
              'enabled': true,
              'scope': 'user',
            },
            {
              'id': 'builtin-general',
              'name': 'general-purpose',
              'description': 'General-purpose research agent.',
              'scope': 'built-in',
            },
            {
              'id': 'builtin-explore',
              'name': 'Explore',
              'description': 'Read-only search agent.',
              'scope': 'built-in',
              'source': 'built-in',
              'tools': [
                'Read',
                'Grep',
                'Glob',
                'Bash',
                'Edit',
                'Write',
                'NotebookEdit'
              ],
            },
            {
              'id': 'plugin-agent',
              'name': 'Plugin Agent',
              'description': 'From a plugin.',
              'scope': 'plugin',
              'source': 'plugin',
            }
          ],
          'capability': {'supported': true},
        };
      }
      if (channel == 'commands' && method == 'setCommandEnabled') {
        final patch = (args.single as Map).cast<String, Object?>();
        commandEnabled = patch['enabled'] as bool;
        return null;
      }
      return {
        'commands': [
          {
            'id': 'goal',
            'name': 'goal',
            'description': 'Set a goal',
            'enabled': commandEnabled
          }
        ],
        'userCommands': [],
        'pluginCommands': [],
        'capability': {'userScopeAvailable': true},
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace',
            workspacePath: 'D:/Project'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'subagents',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Reviewer'), findsOneWidget);
    // Official chrome: scope pill + count + search box + installed row.
    expect(find.text('Subagents 4'), findsOneWidget);
    // Installed count only covers user rows; builtin/plugin rows group below.
    expect(find.text('Installed 1'), findsOneWidget);
    expect(find.text('Built-in subagents'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('general-purpose'), findsOneWidget);
    // Rows without a tools list inherit all tools (plugin row included).
    expect(find.text('All tools'), findsNWidgets(2));
    expect(find.text('Explore'), findsOneWidget);
    expect(find.text('7 tools'), findsOneWidget);
    expect(find.text('Plugin subagents'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'zzz'), findsNothing);

    // Local search filters the card rows.
    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('Reviewer'), findsNothing);
    expect(find.textContaining('No subagents found'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Explore');
    await tester.pumpAndSettle();
    // One match in the search field itself plus the filtered card row.
    expect(find.text('Explore'), findsNWidgets(2));
    expect(find.text('7 tools'), findsOneWidget);
    expect(find.text('Reviewer'), findsNothing);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('Reviewer'), findsOneWidget);

    await tester.ensureVisible(find.text('Commands'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Commands'));
    await tester.pumpAndSettle();
    expect(find.text('/goal · all'), findsOneWidget);
    expect(find.text('Commands 1'), findsOneWidget);
    expect(find.text('Installed 1'), findsOneWidget);
    expect(find.text('Reviewer'), findsNothing);
    expect(tester.widget<Switch>(find.byType(Switch)).value, isTrue);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(find.byType(Switch)).value, isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'hooks page lists workspace hooks and saves the whole list on toggle',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var secondEnabled = false;
    final saves = <List<Map<String, dynamic>>>[];
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'hooks') {
        if (method == 'loadHooks') {
          return {
            'hooks': [
              {
                'id': 'plugin-hook',
                'event': 'PostToolUse',
                'matcher': 'Read',
                'type': 'command',
                'command': 'echo plugin',
                'enabled': true,
                'editable': false,
                'location': {'source': 'plugin'},
              },
              {
                'id': 'hook-abc',
                'event': 'PreToolUse',
                'matcher': 'Bash',
                'type': 'command',
                'command': 'echo hi',
                'enabled': secondEnabled,
                'location': {'source': 'zcode', 'scope': 'user'},
              },
            ],
            'hooksEnabled': true,
          };
        }
        if (method == 'saveHooks') {
          final values = (args.single as Map).cast<String, dynamic>();
          saves.add((values['hooks'] as List)
              .whereType<Map>()
              .map((row) => row.cast<String, dynamic>())
              .toList());
          for (final hook in saves.last) {
            if (hook['id'] == 'hook-abc') {
              secondEnabled = hook['enabled'] as bool;
            }
          }
          return null;
        }
      }
      return {'hooksEnabled': true};
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace',
            workspacePath: 'D:/Project'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'hooks',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    expect(find.text('Hooks 2'), findsOneWidget);
    expect(find.text('Installed 2'), findsOneWidget);
    expect(find.text('PostToolUse'), findsOneWidget);
    expect(find.text('PreToolUse'), findsOneWidget);

    // The plugin-provided hook stays read-only; the zcode hook toggles
    // through the whole-list saveHooks write.
    final readOnly = find.byKey(const ValueKey('hook-toggle-plugin-hook'));
    expect(tester.widget<Switch>(readOnly).onChanged, isNull);
    final editable = find.byKey(const ValueKey('hook-toggle-hook-abc'));
    await tester.ensureVisible(editable);
    await tester.pumpAndSettle();
    await tester.tap(editable);
    await tester.pumpAndSettle();
    expect(saves, hasLength(1));
    expect(saves.last, hasLength(2));
    final flipped = saves.last.singleWhere((row) => row['id'] == 'hook-abc');
    expect(flipped['enabled'], isTrue);
    expect(tester.widget<Switch>(editable).value, isTrue);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('hook form creates a process hook through the whole-list save',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    final saves = <List<Map<String, dynamic>>>[];
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'hooks') {
        if (method == 'loadHooks') {
          return {
            'hooks': [
              {
                'id': 'plugin-hook',
                'event': 'PostToolUse',
                'matcher': 'Read',
                'type': 'command',
                'command': 'echo plugin',
                'enabled': true,
                'editable': false,
                'location': {'source': 'plugin'},
              },
              {
                'id': 'hook-abc',
                'event': 'PreToolUse',
                'matcher': 'Bash',
                'type': 'command',
                'command': 'echo hi',
                'enabled': true,
                'location': {'source': 'zcode', 'scope': 'user'},
              },
            ],
            'hooksEnabled': true,
          };
        }
        if (method == 'saveHooks') {
          final values = (args.single as Map).cast<String, dynamic>();
          saves.add((values['hooks'] as List)
              .whereType<Map>()
              .map((row) => row.cast<String, dynamic>())
              .toList());
          return null;
        }
      }
      return {'hooksEnabled': true};
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace',
            workspacePath: 'D:/Project'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'hooks',
            onManageDevices: () {})));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('hooks-new')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hook-form-save')), findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('hook-form-command')), 'echo new');
    await tester.enterText(
        find.byKey(const ValueKey('hook-form-args')), 'a\n\nb');
    await tester.tap(find.byKey(const ValueKey('hook-form-advanced')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('hook-form-timeout')));
    await tester.enterText(
        find.byKey(const ValueKey('hook-form-timeout')), '120');
    await tester
        .ensureVisible(find.byKey(const ValueKey('hook-form-customJson')));
    await tester.enterText(
        find.byKey(const ValueKey('hook-form-customJson')), '{"k": 1}');
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const ValueKey('hook-form-save')));
    await tester.tap(find.byKey(const ValueKey('hook-form-save')));
    await tester.pumpAndSettle();
    expect(saves, hasLength(1));
    expect(saves.last, hasLength(3));
    final created = saves.last.singleWhere(
        (row) => row['id'] != 'plugin-hook' && row['id'] != 'hook-abc');
    expect(created['id'], startsWith('hook-'));
    expect(created['event'], 'PreToolUse');
    expect(created['type'], 'process');
    expect(created['command'], 'echo new');
    expect(created['args'], ['a', 'b']);
    expect(created.containsKey('async'), isFalse);
    expect(created.containsKey('shell'), isFalse);
    expect(created['timeout'], 120);
    expect(created['enabled'], isTrue);
    expect(created['custom'], {'k': 1});
    expect((created['location'] as Map)['source'], 'zcode');
    expect((created['location'] as Map)['scope'], 'user');
    expect(find.byKey(const ValueKey('hook-form-save')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'hook form edits an existing hook, validates custom JSON, '
      'and deletes', (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    final saves = <List<Map<String, dynamic>>>[];
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'hooks') {
        if (method == 'loadHooks') {
          return {
            'hooks': [
              {
                'id': 'plugin-hook',
                'event': 'PostToolUse',
                'matcher': 'Read',
                'type': 'command',
                'command': 'echo plugin',
                'enabled': true,
                'editable': false,
                'location': {'source': 'plugin'},
              },
              {
                'id': 'hook-abc',
                'event': 'PreToolUse',
                'matcher': 'Bash',
                'type': 'command',
                'command': 'echo hi',
                'enabled': true,
                'location': {'source': 'zcode', 'scope': 'user'},
              },
            ],
            'hooksEnabled': true,
          };
        }
        if (method == 'saveHooks') {
          final values = (args.single as Map).cast<String, dynamic>();
          saves.add((values['hooks'] as List)
              .whereType<Map>()
              .map((row) => row.cast<String, dynamic>())
              .toList());
          return null;
        }
      }
      return {'hooksEnabled': true};
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace',
            workspacePath: 'D:/Project'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'hooks',
            onManageDevices: () {})));
    await tester.pumpAndSettle();

    await tester
        .ensureVisible(find.byKey(const ValueKey('hook-edit-hook-abc')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('hook-edit-hook-abc')));
    await tester.pumpAndSettle();
    final commandField = tester
        .widget<TextField>(find.byKey(const ValueKey('hook-form-command')));
    expect(commandField.controller!.text, 'echo hi');
    expect(find.byKey(const ValueKey('hook-form-async')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('hook-form-advanced')));
    await tester.pumpAndSettle();
    await tester
        .ensureVisible(find.byKey(const ValueKey('hook-form-customJson')));
    await tester.enterText(
        find.byKey(const ValueKey('hook-form-customJson')), '[1,2]');
    await tester.pumpAndSettle();
    expect(find.text('Must be a JSON object.'), findsOneWidget);
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('hook-form-save')))
            .onPressed,
        isNull);
    await tester.enterText(
        find.byKey(const ValueKey('hook-form-customJson')), '{"a": 1}');
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<FilledButton>(find.byKey(const ValueKey('hook-form-save')))
            .onPressed,
        isNotNull);

    await tester.ensureVisible(find.byKey(const ValueKey('hook-form-type')));
    await tester.tap(find.byKey(const ValueKey('hook-form-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Process').last);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('hook-form-async')), findsNothing);
    expect(find.byKey(const ValueKey('hook-form-args')), findsOneWidget);

    await tester.ensureVisible(find.byKey(const ValueKey('hook-form-save')));
    await tester.tap(find.byKey(const ValueKey('hook-form-save')));
    await tester.pumpAndSettle();
    expect(saves, hasLength(1));
    final edited = saves.last.singleWhere((row) => row['id'] == 'hook-abc');
    expect(edited['type'], 'process');
    expect(edited['args'], <String>[]);
    expect(edited.containsKey('async'), isFalse);
    expect(edited['custom'], {'a': 1});
    // The update builder (GXt) spreads the original raw, so id/location
    // survive unchanged while the form fields are overridden.
    expect(edited['location'], {'source': 'zcode', 'scope': 'user'});
    expect(find.byKey(const ValueKey('hook-form-save')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('hook-edit-hook-abc')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('hook-form-delete')));
    await tester.tap(find.byKey(const ValueKey('hook-form-delete')));
    await tester.pumpAndSettle();
    expect(find.text('Confirm delete'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('hook-form-delete')));
    await tester.pumpAndSettle();
    expect(saves, hasLength(2));
    expect(saves.last, hasLength(1));
    expect(saves.last.any((row) => row['id'] == 'hook-abc'), isFalse);
    expect(find.byKey(const ValueKey('hook-form-save')), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('hook form keeps the dialog open when saveHooks fails',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    final attempts = <int>[];
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'hooks') {
        if (method == 'loadHooks') {
          return {
            'hooks': [
              {
                'id': 'hook-abc',
                'event': 'PreToolUse',
                'matcher': 'Bash',
                'type': 'command',
                'command': 'echo hi',
                'enabled': true,
                'location': {'source': 'zcode', 'scope': 'user'},
              },
            ],
            'hooksEnabled': true,
          };
        }
        if (method == 'saveHooks') {
          attempts.add(attempts.length);
          throw StateError('save rejected');
        }
      }
      return {'hooksEnabled': true};
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace',
            workspacePath: 'D:/Project'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'hooks',
            onManageDevices: () {})));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('hooks-new')));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byKey(const ValueKey('hook-form-command')), 'echo new');
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('hook-form-save')));
    await tester.tap(find.byKey(const ValueKey('hook-form-save')));
    await tester.pumpAndSettle();
    expect(attempts, hasLength(1));
    expect(find.textContaining('Save failed'), findsOneWidget);
    expect(find.byKey(const ValueKey('hook-form-save')), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('MCP settings read the workspace server status list',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (method == 'loadMcpFromUserDirectory') {
        return {
          'servers': [
            {
              'id': 'user:docs:',
              'name': 'docs-server',
              'source': 'zcodeagentmcp',
              'scope': 'user',
              'enabled': true,
              'config': {'type': 'stdio', 'command': 'node'},
            }
          ]
        };
      }
      if (method == 'listWorkspaceMcpServerStatuses') {
        return {
          'statuses': [
            {
              'name': 'docs-server',
              'status': 'connected',
              'enabled': true,
              'toolCount': 3
            }
          ]
        };
      }
      return {};
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'mcp',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    expect(find.textContaining('docs-server'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('usage settings render scoped workspace usage inline',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (method == 'requestCodingPlanResetOpportunity') {
        return {'granted': false};
      }
      if (method == 'getCodingPlanResetStatus') {
        return {
          'availableFiveHourResets': [],
          'availableWeekResets': [],
          'hasUnreadHistory': false
        };
      }
      final query = args.single as Map;
      return statisticsFixture(query['range'],
          application: method == 'getAppUsageSnapshot');
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'usage',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('usage-page-scroll')),
            matching: find.text('Usage stats')),
        findsOneWidget);
    expect(find.text('Usage statistics'), findsNothing,
        reason: 'Embedded usage shares the SettingsCenter page heading.');
    expect(find.text('Open usage page'), findsNothing);
    expect(find.text('App usage'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'account menu disconnect matches the official remote logout entry',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final store = DeviceStore(requireEncryption: false);
    final device = Device(
        id: 'device',
        label: 'Device',
        url: 'https://zcode.z.ai/remote/v4?sid=synthetic&hash=synthetic&t=1',
        addedAt: 0,
        lastUsedAt: 0);
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (method == 'requestCodingPlanResetOpportunity') {
        return {'granted': false};
      }
      if (method == 'getCodingPlanResetStatus') {
        return {
          'availableFiveHourResets': [],
          'availableWeekResets': [],
          'hasUnreadHistory': false
        };
      }
      final query = args.single as Map;
      return statisticsFixture(query['range'],
          application: method == 'getAppUsageSnapshot');
    };
    const workspace = WorkspaceDescriptor(
        key: 'workspace',
        title: 'ZcodeRemote',
        scope: {'workspaceIdentity': 'workspace'});
    final monitor =
        await sessions.openWorkspace(device, workspace.key, workspace.scope);
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);

    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: WorkspaceShell(
            device: device,
            workspace: workspace,
            monitor: monitor,
            sessions: sessions,
            preferences: prefs,
            sessionId: null,
            conversationBuilder: (_, id) => const SizedBox.shrink())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('账户菜单'));
    await tester.pumpAndSettle();
    // Official remote-control account menu has no login entry (E2.1).
    expect(find.text('登录'), findsNothing);
    expect(find.text('断开连接'), findsOneWidget);
    await tester.tap(find.text('断开连接').last);
    await tester.pumpAndSettle();
    // The current remote session is gone after the disconnect.
    expect(sessions.sessionOf(device.id), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('account menu opens the scoped workspace usage page',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final store = DeviceStore(requireEncryption: false);
    final device = Device(
        id: 'device',
        label: 'Device',
        url: 'https://zcode.z.ai/remote/v4?sid=synthetic&hash=synthetic&t=1',
        addedAt: 0,
        lastUsedAt: 0);
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (method == 'requestCodingPlanResetOpportunity') {
        return {'granted': false};
      }
      if (method == 'getCodingPlanResetStatus') {
        return {
          'availableFiveHourResets': [],
          'availableWeekResets': [],
          'hasUnreadHistory': false
        };
      }
      final query = args.single as Map;
      return statisticsFixture(query['range'],
          application: method == 'getAppUsageSnapshot');
    };
    const workspace = WorkspaceDescriptor(
        key: 'workspace',
        title: 'ZcodeRemote',
        scope: {'workspaceIdentity': 'workspace'});
    final monitor =
        await sessions.openWorkspace(device, workspace.key, workspace.scope);
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);

    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: WorkspaceShell(
            device: device,
            workspace: workspace,
            monitor: monitor,
            sessions: sessions,
            preferences: prefs,
            sessionId: null,
            conversationBuilder: (_, id) => const SizedBox.shrink())));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('账户菜单'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('使用统计').last);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(UsagePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('account upgrade opens the read-only plan catalog',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final store = DeviceStore(requireEncryption: false);
    final device = Device(
        id: 'device',
        label: 'Device',
        url: 'https://zcode.z.ai/remote/v4?sid=synthetic&hash=synthetic&t=1',
        addedAt: 0,
        lastUsedAt: 0);
    final bridge = FeatureBridge();
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'oauth' && method == 'restoreCachedSessionState') {
        return {
          'status': 'authenticated',
          'userInfo': {'displayName': 'Synthetic User'},
        };
      }
      if (channel == 'setting') {
        return {'providerFamilyDomain': 'zai'};
      }
      return {};
    };
    bridge.conversationTransport.teamProductsHandler = (_) async => {
          'authenticated': true,
          'productList': [
            {
              'productId': 'lite-month',
              'productName': 'GLM Coding Plan Lite',
              'priceUnit': 'month',
              'priceCurrency': 'USD',
              'payAmount': 8,
              'subscribed': true,
            }
          ],
        };
    const workspace = WorkspaceDescriptor(
        key: 'workspace',
        title: 'ZcodeRemote',
        scope: {'workspaceIdentity': 'workspace'});
    final monitor =
        await sessions.openWorkspace(device, workspace.key, workspace.scope);
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: WorkspaceShell(
            device: device,
            workspace: workspace,
            monitor: monitor,
            sessions: sessions,
            preferences: prefs,
            sessionId: null,
            conversationBuilder: null)));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('账户菜单'));
    await tester.pumpAndSettle();
    expect(find.text('升级'), findsOneWidget);
    await tester.tap(find.text('升级').last);
    await tester.pumpAndSettle();
    expect(find.byType(UpgradePage), findsOneWidget);
    expect(find.text('builtin:zai-coding-plan'), findsOneWidget);
    expect(find.text('GLM Coding Plan Lite'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('modelProvider section renders the catalog and saves model edits',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('en');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    final calls = <(String, String, List<Object?>)>[];
    var prepCalls = 0;
    bridge.conversationTransport.prepHandler = () async {
      prepCalls++;
      return WorkspacePrep.fromRaw(composerPrepFixture);
    };
    Map<String, dynamic> provider = {
      'id': 'custom-a',
      'name': 'Custom A',
      'enabled': true,
      'apiFormat': 'anthropic',
      'source': 'custom',
      'apiKey': 'secret',
      'endpoints': {'baseURL': 'https://synthetic.invalid'},
      'models': [
        {
          'id': 'm1',
          'name': 'Model One',
          'kinds': ['chat'],
          'defaultKind': 'chat',
          'modalities': {
            'input': ['text'],
            'output': ['text'],
          },
          'contextWindow': 200000,
          'maxOutputTokens': 8192,
          'reasoning': {
            'defaultLevel': 'high',
            'levels': {'low': {}, 'high': {}},
          },
          'priority': 5,
          'modified': false,
        }
      ],
    };
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.modelProvider) {
        calls.add((channel, method, args));
        if (method == 'save') {
          provider = args.single as Map<String, dynamic>;
          return provider;
        }
        return [provider];
      }
      return {
        'providerFamilyDomain': 'zai',
        'modelProviderFamilyModes': {'zai': 'oauth'},
        'modelProviderFamilySelectedKeys': {'zai': 'coding-plan:builtin:x'},
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    // Two-pane layout needs width; the default 800x600 surface stacks the
    // panes and pushes the model row below the fold.
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            key: const ValueKey('model-catalog'),
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'modelProvider',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    // The zai family row leads the nav by default; select the custom row to
    // exercise the provider detail.
    await tester.tap(find.text('Custom A').first);
    await tester.pumpAndSettle();

    expect(
        find.textContaining('Manage custom model providers'), findsOneWidget);
    expect(find.text('Custom providers'), findsOneWidget);
    // Detail header shows the enabled badge for the selected provider.
    expect(find.text('Enabled'), findsOneWidget);
    // Two-pane: the provider shows in the list tile and the detail title.
    expect(find.text('Custom A'), findsNWidgets(2));
    expect(find.textContaining('anthropic'), findsWidgets);
    expect(find.text('Model One'), findsOneWidget);
    expect(find.text('200K'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    await tester.tap(find.byTooltip('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Model Two');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Model Two'), findsOneWidget);
    final save = calls.firstWhere((call) => call.$2 == 'save');
    expect(save.$1, Channels.modelProvider);
    final payload = save.$3.single as Map<String, dynamic>;
    expect(payload['id'], 'custom-a');
    expect((payload['models'] as List).single['name'], 'Model Two');
    expect(prepCalls, 1, reason: 'composer prep invalidated after model save');
    expect(find.textContaining('secret'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'custom provider deletion confirms, refreshes and invalidates prep',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('en');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    final calls = <(String, String, List<Object?>)>[];
    var prepCalls = 0;
    bridge.conversationTransport.prepHandler = () async {
      prepCalls++;
      return WorkspacePrep.fromRaw(composerPrepFixture);
    };
    Map<String, dynamic> provider = {
      'id': 'custom-a',
      'name': 'Custom A',
      'enabled': true,
      'apiFormat': 'anthropic',
      'source': 'custom',
      'apiKey': 'secret',
      'endpoints': {'baseURL': 'https://synthetic.invalid'},
      'models': const <Map<String, dynamic>>[],
    };
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.modelProvider) {
        calls.add((channel, method, args));
        if (method == 'delete') {
          provider = const <String, dynamic>{};
          return null;
        }
        return [provider];
      }
      return {
        'providerFamilyDomain': 'zai',
        'modelProviderFamilyModes': {'zai': 'oauth'},
        'modelProviderFamilySelectedKeys': {'zai': 'coding-plan:builtin:x'},
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            key: const ValueKey('provider-delete'),
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'modelProvider',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    // The family row leads the nav by default; select the custom row.
    await tester.tap(find.text('Custom A').first);
    await tester.pumpAndSettle();
    expect(find.text('Custom A'), findsNWidgets(2));
    expect(find.text('0 models · anthropic'), findsOneWidget);

    await tester.tap(find.byTooltip('Delete provider'));
    await tester.pumpAndSettle();
    expect(find.text('Delete provider "Custom A"?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(calls.where((call) => call.$2 == 'delete'), isEmpty);
    expect(find.text('Custom A'), findsNWidgets(2));

    await tester.tap(find.byTooltip('Delete provider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete provider').last);
    await tester.pumpAndSettle();
    final deletion = calls.singleWhere((call) => call.$2 == 'delete');
    expect(deletion.$1, Channels.modelProvider);
    expect(deletion.$3, ['custom-a']);
    expect(find.text('Custom A'), findsNothing);
    expect(prepCalls, 1, reason: 'composer prep invalidated after delete');
    expect(find.textContaining('secret'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('failed provider deletion keeps the provider and shows error',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('en');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    final provider = {
      'id': 'custom-a',
      'name': 'Custom A',
      'enabled': true,
      'apiFormat': 'anthropic',
      'source': 'custom',
      'apiKey': 'secret',
      'endpoints': {'baseURL': 'https://synthetic.invalid'},
      'models': const <Map<String, dynamic>>[],
    };
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.modelProvider) {
        if (method == 'delete') throw StateError('delete rejected');
        return [provider];
      }
      return {
        'providerFamilyDomain': 'zai',
        'modelProviderFamilyModes': {'zai': 'oauth'},
        'modelProviderFamilySelectedKeys': {'zai': 'coding-plan:builtin:x'},
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            key: const ValueKey('provider-delete-failure'),
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'modelProvider',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    // The family row leads the nav by default; select the custom row.
    await tester.tap(find.text('Custom A').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete provider'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete provider').last);
    await tester.pumpAndSettle();

    expect(find.text('Custom A'), findsNWidgets(2));
    expect(find.textContaining('Provider delete failed'), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('add provider form retries after failure and hides the secret',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('en');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    final calls = <(String, String, List<Object?>)>[];
    var prepCalls = 0;
    var fail = true;
    Map<String, dynamic>? saved;
    bridge.conversationTransport.prepHandler = () async {
      prepCalls++;
      return WorkspacePrep.fromRaw(composerPrepFixture);
    };
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.modelProvider) {
        calls.add((channel, method, args));
        if (method == 'save') {
          if (fail) throw StateError('create rejected');
          saved = args.single as Map<String, dynamic>;
          return saved;
        }
        return [if (saved != null) saved!];
      }
      return {
        'providerFamilyDomain': 'zai',
        'modelProviderFamilyModes': {'zai': 'oauth'},
        'modelProviderFamilySelectedKeys': {'zai': 'coding-plan:builtin:x'},
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            key: const ValueKey('provider-create'),
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'modelProvider',
            onManageDevices: () {})));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add provider'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Synthetic Provider');
    await tester.enterText(
        find.byType(TextField).at(1), 'https://synthetic.invalid/v1');
    await tester.enterText(find.byType(TextField).at(2), 'secret-create');
    await tester.enterText(find.byType(TextField).at(3), 'Test Model');
    await tester.pump();
    expect(
        tester
            .widget<FilledButton>(find.descendant(
                of: find.byType(AlertDialog),
                matching: find.byType(FilledButton)))
            .onPressed,
        isNotNull);
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();

    expect(find.textContaining('create rejected'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(5));

    fail = false;
    await tester.tap(find.descendant(
        of: find.byType(AlertDialog), matching: find.byType(FilledButton)));
    await tester.pumpAndSettle();

    // The created provider is selected to show its detail rows.
    await tester.tap(find.text('Synthetic Provider').first);
    await tester.pumpAndSettle();
    final saves = calls.where((call) => call.$2 == 'save').toList();
    expect(saves, hasLength(2));
    final save = saves.last;
    expect(save.$1, Channels.modelProvider);
    final payload = save.$3.single as Map<String, dynamic>;
    expect(payload['name'], 'Synthetic Provider');
    expect(payload['source'], 'custom');
    expect(payload['apiFormat'], 'anthropic-messages');
    expect(payload['endpoints'], {
      'baseURL': 'https://synthetic.invalid/v1',
      'paths': {
        'anthropic-messages': '/v1/messages',
      },
    });
    expect((payload['models'] as List).single['name'], 'Test Model');
    expect(find.text('Test Model'), findsOneWidget);
    expect(find.textContaining('anthropic'), findsWidgets);
    expect(find.text('Synthetic Provider'), findsWidgets);
    expect(prepCalls, 1);
    expect(find.textContaining('secret-create'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('provider reorder sends display order and refreshes prep',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('en');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    final calls = <(String, String, List<Object?>)>[];
    var prepCalls = 0;
    var order = ['a', 'b'];
    bridge.conversationTransport.prepHandler = () async {
      prepCalls++;
      return WorkspacePrep.fromRaw(composerPrepFixture);
    };
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.modelProvider) {
        calls.add((channel, method, args));
        if (method == 'getDisplayOrder') return order;
        if (method == 'saveDisplayOrder') {
          order = List<String>.from(
              (args.single as Map<String, dynamic>)['providerIds'] as List);
          return null;
        }
        return [
          for (final id in order)
            {
              'id': id,
              'name': 'Provider $id',
              'enabled': true,
              'apiFormat': 'anthropic-messages',
              'source': 'custom',
              'apiKey': '',
              'endpoints': {'baseURL': 'https://synthetic.invalid'},
              'models': const <Map<String, dynamic>>[],
            }
        ];
      }
      return {
        'providerFamilyDomain': 'zai',
        'modelProviderFamilyModes': {'zai': 'oauth'},
        'modelProviderFamilySelectedKeys': {'zai': 'coding-plan:builtin:x'},
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            key: const ValueKey('provider-order'),
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'modelProvider',
            onManageDevices: () {})));
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    await tester.pump();
    await tester.pumpAndSettle();
    // The zai family row leads the nav by default; only the list tile for
    // Provider a shows until it is selected.
    expect(find.text('Provider a'), findsOneWidget);
    expect(find.text('Provider b'), findsOneWidget);

    // Two-pane: select Provider b first; its Move up is then enabled.
    await tester.tap(find.text('Provider b').first);
    await tester.pumpAndSettle();
    await tester.tap(find.byWidgetPredicate((widget) =>
        widget is IconButton &&
        widget.tooltip == 'Move up' &&
        widget.onPressed != null));
    await tester.pumpAndSettle();
    final save = calls.singleWhere((call) => call.$2 == 'saveDisplayOrder');
    expect(save.$1, Channels.modelProvider);
    expect((save.$3.single as Map)['providerIds'], ['b', 'a']);
    expect(find.text('Provider b'), findsNWidgets(2));
    expect(find.text('Provider a'), findsOneWidget);
    expect(prepCalls, 1);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('startup migration runs after the oauth state restore',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final store = DeviceStore(requireEncryption: false);
    final device = Device(
        id: 'device',
        label: 'Device',
        url: 'https://zcode.z.ai/remote/v4?sid=synthetic&hash=synthetic&t=1',
        addedAt: 0,
        lastUsedAt: 0);
    final bridge = FeatureBridge();
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
    var selectedKeys = <String, String>{'zai': 'legacy:zai-key'};
    final updates = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'oauth' && method == 'restoreCachedSessionState') {
        return {
          'status': 'authenticated',
          'userInfo': {'displayName': 'Synthetic User'},
        };
      }
      if (channel == 'coding-plan-subscription') {
        return {
          'productList': [
            {
              'subscribed': true,
              'productId': 'p1',
              'teamProjects': [
                {'organizationId': 'org', 'projectId': 'prj'},
              ],
            },
          ],
        };
      }
      if (channel == 'setting' && method == 'update') {
        final patch = (args.single as Map).cast<String, dynamic>();
        updates.add(patch);
        selectedKeys = (patch['modelProviderFamilySelectedKeys'] as Map)
            .cast<String, String>();
        return {'providerFamilyDomain': 'zai'};
      }
      if (channel == 'setting') {
        return {
          'providerFamilyDomain': 'zai',
          'modelProviderFamilyModes': {'zai': 'oauth'},
          'modelProviderFamilySelectedKeys': selectedKeys,
        };
      }
      return {};
    };
    const workspace = WorkspaceDescriptor(
        key: 'workspace',
        title: 'ZcodeRemote',
        scope: {'workspaceIdentity': 'workspace'});
    final monitor =
        await sessions.openWorkspace(device, workspace.key, workspace.scope);
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: WorkspaceShell(
            device: device,
            workspace: workspace,
            monitor: monitor,
            sessions: sessions,
            preferences: prefs,
            sessionId: null,
            conversationBuilder: null)));
    await tester.pumpAndSettle();

    expect(updates, hasLength(2));
    expect(updates[0]['modelProviderFamilySelectedKeys']['zai'],
        'coding-plan:builtin:zai-coding-plan');
    expect(updates[1]['modelProviderFamilySelectedKeys']['zai'],
        'team-plan:builtin:zai-coding-plan:p1:org:prj');
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('family connection menu lists subscribed team projects',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var selectedKeys = <String, String>{
      'zai': 'legacy:zai-key',
      'bigmodel': 'coding-plan:builtin:bigmodel-coding-plan',
    };
    var modes = <String, String>{'zai': 'oauth', 'bigmodel': 'oauth'};
    Map<String, dynamic>? lastPatch;
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'coding-plan-subscription') {
        return {
          'productList': [
            {'subscribed': false, 'productId': 'p0', 'productName': 'P0'},
            {
              'subscribed': true,
              'productId': 'p1',
              'productName': 'Team Plan',
              'teamProjects': [
                {
                  'organizationId': ' org ',
                  'projectId': 'prj',
                  'apiKeyStatus': 'unavailable'
                },
                {'organizationId': 'org', 'projectId': 'prj'},
              ],
            },
          ],
        };
      }
      if (method == 'update') {
        lastPatch = (args.single as Map).cast<String, dynamic>();
        modes = (lastPatch!['modelProviderFamilyModes'] as Map)
            .cast<String, String>();
        selectedKeys = (lastPatch!['modelProviderFamilySelectedKeys'] as Map)
            .cast<String, String>();
        return null;
      }
      return {
        'providerFamilyDomain': 'zai',
        'modelProviderFamilyModes': modes,
        'modelProviderFamilySelectedKeys': selectedKeys,
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'modelProvider',
            onManageDevices: () {})));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<FamilyConnectionOption>).first);
    await tester.pumpAndSettle();
    // p0 is not subscribed; the unavailable project is hidden; org values
    // are trimmed in the label.
    await tester.tap(find.text('Z.ai - Team Plan · org/prj').last);
    await tester.pumpAndSettle();

    expect(lastPatch, {
      'modelProviderFamilyModes': <String, String>{
        'zai': 'oauth',
        'bigmodel': 'oauth',
      },
      'modelProviderFamilySelectedKeys': <String, String>{
        'zai': 'team-plan:builtin:zai-coding-plan:p1:org:prj',
        'bigmodel': 'coding-plan:builtin:bigmodel-coding-plan',
      },
    });
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('plan card renders the official date line and quota tiles',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.modelProvider) {
        if (method == 'getAll') {
          return [
            {
              'id': 'builtin:zai-coding-plan',
              'name': 'Z.ai - 编程套餐',
              'enabled': true,
              'apiFormat': 'anthropic-messages',
              'source': 'preset',
              'models': [],
            }
          ];
        }
        return null;
      }
      return {
        'providerFamilyDomain': 'zai',
        'modelProviderFamilyModes': {'zai': 'oauth'},
        'modelProviderFamilySelectedKeys': {
          'zai': 'coding-plan:builtin:zai-coding-plan'
        },
      };
    };
    bridge.conversationTransport.quotaHandler =
        (providerId, org, project) async => {
              'provider': {'id': 'builtin:zai-coding-plan'},
              'subscription': {
                'details': [
                  {
                    'productName': 'GLM Coding Pro',
                    'renewTime': DateTime.now()
                        .add(const Duration(days: 30))
                        .millisecondsSinceEpoch,
                  }
                ],
              },
              'quota': {
                'level': 'glm-coding-pro',
                'limits': [
                  {
                    'type': 'TOKENS_LIMIT',
                    'unit': 3,
                    'number': 5,
                    'percentage': 92,
                    'nextResetTime': DateTime.now()
                        .add(const Duration(hours: 3))
                        .millisecondsSinceEpoch,
                  },
                  {'type': 'TOKENS_LIMIT', 'unit': 6, 'percentage': 56},
                  {
                    'type': 'TIME_LIMIT',
                    'unit': 5,
                    'number': 1,
                    'percentage': 95,
                  },
                ],
              },
              'mcpQuota': {
                'aggregate': {'percentage': 100},
              },
            };
    bridge.conversationTransport.teamProductsHandler = (_) async => {
          'authenticated': true,
          'productList': [
            {
              'subscribed': true,
              'productId': 'p1',
              'productName': 'GLM Coding Pro',
              'payAmount': 8,
              'priceUnit': 'month',
            }
          ],
        };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'modelProvider',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    // The entitlement fetch is scheduled from a post-frame callback;
    // give it explicit frames to land.
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    // Official renewal-first date line (EHt) and the four quota tiles.
    // Tiles show the REMAINING percent (100 - used).
    expect(find.textContaining('GLM Coding Pro'), findsWidgets);
    expect(find.textContaining('续费'), findsOneWidget);
    expect(find.text('5h 用量'), findsOneWidget);
    expect(find.text('1w 用量'), findsOneWidget);
    expect(find.text('工具调用'), findsOneWidget);
    expect(find.text('ZCode MCP'), findsOneWidget);
    expect(find.text('8%'), findsOneWidget);
    expect(find.text('44%'), findsOneWidget);
    expect(find.text('5%'), findsOneWidget);
    expect(find.text('0%'), findsOneWidget);
    // Manage/unlink actions stay unimplemented (no verified wire).
    expect(find.text('管理'), findsNothing);
    expect(find.text('解绑'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('provider detail shows the subscribed plan summary card',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.modelProvider) {
        if (method == 'getAll') {
          return [
            {
              'id': 'builtin:zai-coding-plan',
              'name': 'Z.ai - 编程套餐',
              'enabled': true,
              'apiFormat': 'anthropic-messages',
              'source': 'preset',
              'models': [],
            }
          ];
        }
        return null;
      }
      return {
        'providerFamilyDomain': 'zai',
        'modelProviderFamilyModes': {'zai': 'oauth'},
        'modelProviderFamilySelectedKeys': {
          'zai': 'coding-plan:builtin:zai-coding-plan'
        },
      };
    };
    bridge.conversationTransport.quotaHandler =
        (providerId, org, project) async => {
              'provider': {'id': 'builtin:zai-coding-plan'},
              'subscription': {
                'details': [
                  {'productName': 'GLM Coding Pro'}
                ],
              },
              'quota': {'level': 'glm-coding-pro', 'limits': []},
            };
    bridge.conversationTransport.teamProductsHandler = (_) async => {
          'authenticated': true,
          'productList': [
            {
              'subscribed': true,
              'productId': 'p1',
              'productName': 'GLM Coding Pro',
              'payAmount': 8,
              'priceUnit': 'month',
            }
          ],
        };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'modelProvider',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    // The detail header matches the zai provider to the zai family and the
    // subscribed product renders as the official plan summary card.
    expect(find.textContaining('GLM Coding Pro'), findsWidgets);
    expect(find.text('升级'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'zhipu family nav groups builtin providers and renders the start plan card',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    final tomorrow = DateTime.now().add(const Duration(days: 1));
    final expires = DateTime(2026, 9, 14, 9, 0);
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.modelProvider) {
        if (method == 'getAll') {
          return [
            {
              'id': 'builtin:bigmodel-start-plan',
              'name': 'BigModel - Coding Plan',
              'enabled': true,
              'apiFormat': 'anthropic-messages',
              'source': 'preset',
              'endpoints': {'baseURL': 'https://open.bigmodel.cn/api/anthropic'},
              'models': [
                {
                  'id': 'GLM-5.3-Flash',
                  'name': 'GLM-5.3-Flash',
                  'kinds': ['anthropic'],
                  'defaultKind': 'anthropic',
                  'modalities': {
                    'input': ['text', 'image'],
                    'output': ['text'],
                  },
                  'contextWindow': 500000,
                },
              ],
            },
            {
              'id': 'custom-1',
              'name': '火山方舟',
              'enabled': true,
              'apiFormat': 'openai-chat-completions',
              'source': 'custom',
              'models': [],
            },
          ];
        }
        return null;
      }
      return {
        'providerFamilyDomain': 'bigmodel',
        'modelProviderFamilyModes': {'bigmodel': 'oauth'},
        'modelProviderFamilySelectedKeys': {
          'bigmodel': 'coding-plan:builtin:bigmodel-start-plan'
        },
      };
    };
    bridge.conversationTransport.quotaHandler =
        (providerId, org, project) async {
      expect(providerId, 'builtin:bigmodel-start-plan');
      return {
        'provider': {'id': 'builtin:bigmodel-start-plan'},
        'subscription': {
          'details': [
            {
              'productName': 'ZCode Weekend Build',
              'expireTime': expires.millisecondsSinceEpoch,
            }
          ],
        },
        'quota': {
          'level': 'start',
          'limits': [
            {
              'type': 'TOKENS_LIMIT',
              'unit': 3,
              'number': 300000000,
              'remaining': 126741605,
              'percentage': 57.8,
              'nextResetTime': tomorrow.millisecondsSinceEpoch,
              'usageDetails': [
                {'modelCode': 'model:glm-5.3-flash', 'displayName': 'GLM-5.3-Flash'},
              ],
            },
          ],
        },
      };
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'modelProvider',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pump(const Duration(milliseconds: 50));
    // Nav: 智谱 group with the brand row first (default selected), builtin
    // plan providers never leak into the custom list.
    expect(find.text('智谱'), findsOneWidget);
    expect(find.text('BigModel'), findsWidgets);
    expect(find.text('自定义供应商'), findsOneWidget);
    expect(find.text('火山方舟'), findsOneWidget);
    expect(find.text('BigModel - Coding Plan'), findsNothing);
    // Family detail: brand header + enabled pill + connection select showing
    // the official short mode label.
    expect(find.text('已启用'), findsOneWidget);
    expect(find.text('连接方式'), findsOneWidget);
    expect(find.text('体验套餐'), findsWidgets);
    // Official start-plan card: product name, expiry with clock, balance row
    // with remaining percent, progress bar and grouped token counts.
    expect(find.text('ZCode Weekend Build'), findsOneWidget);
    expect(find.textContaining('过期时间'), findsOneWidget);
    expect(find.text('今日余额'), findsOneWidget);
    expect(find.text('GLM-5.3-Flash'), findsWidgets);
    expect(find.text('42%'), findsOneWidget);
    expect(find.text('126,741,605 / 300,000,000'), findsOneWidget);
    expect(find.text('150% 配额'), findsOneWidget);
    // Family model rows carry the official modality/context tags.
    expect(find.text('视觉'), findsOneWidget);
    expect(find.text('500K'), findsOneWidget);
    // The upgrade pill opens the pricing page.
    await tester.tap(find.text('150% 配额'));
    await tester.pumpAndSettle();
    expect(find.byType(UpgradePage), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets('onboarding nav entry opens the multi-category import dialog',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    var detectCalls = 0;
    List<String>? detectCategories;
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.settingsSync && method == 'detect') {
        detectCalls++;
        detectCategories =
            ((args.single as Map)['categories'] as List).cast<String>();
        return {
          'agents': [
            {
              'agent': 'codexCli',
              'name': 'Codex CLI',
              'categories': [
                {
                  'category': 'skills',
                  'sourceRoots': [
                    {
                      'scope': 'global',
                      'path': 'C:/Users/test/.codex/skills',
                      'skills': [
                        {
                          'name': 'review',
                          'path': 'C:/Users/test/.codex/skills/review',
                          'importable': true,
                        },
                      ],
                    },
                  ],
                },
              ],
            },
          ],
        };
      }
      return <String, dynamic>{};
    };
    final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        notifications: sessions.notifications,
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'));
    addTearDown(monitor.dispose);
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            remoteMonitor: monitor,
            initialSection: 'general',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    // Official 数据与统计 group CTA (dashed rocket row); a dialog action, not
    // a section switch.
    expect(find.text('引导'), findsOneWidget);
    expect(find.text('常规'), findsWidgets);
    await tester.tap(find.text('引导'));
    await tester.pumpAndSettle();
    // U24: the 引导 entry opens the official multi-step wizard, not the
    // plain import dialog. The welcome page offers start / migration guide.
    // (Dialog header and welcome headline share the label.)
    expect(find.text('欢迎使用 ZCode'), findsNWidgets(2));
    expect(find.text('开始使用 ZCode'), findsOneWidget);
    expect(find.text('数据迁移向导'), findsOneWidget);
    expect(detectCalls, 1);
    expect(detectCategories, isNotNull);

    // Migration guide: step navigation on the left, category steps advance
    // with Continue and Back keeps selections.
    await tester.tap(find.text('数据迁移向导'));
    await tester.pumpAndSettle();
    expect(find.text('迁移向导'), findsOneWidget);
    expect(find.text('Skills'), findsWidgets);
    await tester.tap(find.text('继续'));
    await tester.pumpAndSettle();
    // Back returns to the previous step without losing step position.
    await tester.tap(find.text('返回'));
    await tester.pumpAndSettle();
    expect(find.text('迁移向导'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
  });

  testWidgets(
      'notifications body embeds directly in the settings right pane (U26)',
      (tester) async {
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidTaskNotifications.channel,
        (call) async {
      if (call.method == 'capabilities') {
        return {'allowed': true, 'promotedSupported': false};
      }
      if (call.method == 'requestPermission') return true;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(
        AndroidTaskNotifications.channel, null));
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled.timeout(
          const Duration(seconds: 5), onTimeout: () {});
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            initialSection: 'notifications',
            onManageDevices: () {})));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('任务进度通知'), findsOneWidget);
    expect(find.text('通知权限'), findsOneWidget);
    // ...without a pushed page AppBar or the old jump-off ListTile.
    expect(find.text('任务通知与上岛设置'), findsNothing);
    final appBars = find.byType(AppBar);
    expect(appBars, findsNothing);
    // The left settings nav stays visible (nav item + section title both
    // carry the label).
    expect(find.text('通知与上岛'), findsNWidgets(2));
    // Visiting another section and coming back keeps the pane mounted.
    await tester.tap(find.text('常规').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('通知与上岛').first);
    await tester.pumpAndSettle();
    expect(find.text('任务进度通知'), findsOneWidget);
  });

  testWidgets(
      'settings right pane uses the full centered official shell width (U19)',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setLanguage('zh');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled.timeout(
          const Duration(seconds: 5), onTimeout: () {});
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1400, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
            preferences: prefs,
            sessions: sessions,
            initialSection: 'notifications',
            onManageDevices: () {})));
    await tester.pumpAndSettle();
    final switchTile = tester.getRect(find.text('任务进度通知'));
    // Official settings shell: a centered max-w-5xl (1024) column. The right
    // pane is 1400-264=1136 wide, so the centered 1024 content leaves ~56px
    // on each side; the old left-aligned 864 cap would render the row at
    // x=296 with a 240px dead gap on the right.
    final paneLeft = 264.0;
    final paneWidth = 1400.0 - paneLeft;
    final contentLeft = paneLeft + (paneWidth - 1024) / 2;
    // 32 outer padding + 16 ListTile content padding.
    expect(switchTile.left, closeTo(contentLeft + 48, 4));
  });
}
