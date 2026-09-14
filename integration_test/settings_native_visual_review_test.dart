import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/device_connection_status.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';

import '../test/ui/fake_features.dart';
import '../test/ui/fake_workspace.dart';
import '../test/ui/review_connected_session.dart';

const _enabled = bool.fromEnvironment('NATIVE_SETTINGS_VISUAL_REVIEW');
const _populated = bool.fromEnvironment('NATIVE_SETTINGS_POPULATED_REVIEW');

Map<String, dynamic> _settings() => {
      'terminalInheritSystemProfile': true,
      'terminalFontFamily': '',
      'integratedTerminalShell': {'mode': 'auto'},
      'nativeSearchEnhancementsEnabled': true,
      'httpProxy': '',
      'httpProxyNoProxy': '',
      'httpProxyCaCertPath': '',
      'askUserQuestionAutoResolutionEnabled': true,
      'modelIoFullRetentionEnabled': false,
      'messageStreamShowReasoning': true,
      'messageStreamShowTodos': false,
      'toolGroupingExploreEnabled': true,
      'toolGroupingTerminalEnabled': true,
      'toolGroupingChangesEnabled': false,
      'taskAutoArchiveEnabled': false,
      'taskAutoArchiveOlderThanDays': 30,
      'memoryEnabled': true,
      'repoSnapshotIndexingEnabled': true,
      'instantGrepIndexingEnabled': false,
    };

/// Read-only synthetic remote settings fixture. No write handler is provided,
/// so this review cannot mutate a real remote or pretend a write succeeded.
dynamic _read(String channel, String method, List<dynamic> args) {
  if (channel == 'setting' && method == 'get') return _settings();
  if (method == 'getSystemInfo') return {'platform': 'win32'};
  if (method == 'listIntegratedTerminalShells') return <dynamic>[];
  if (method == 'listPlugins') {
    return {
      'plugins': [
        {
          'id': 'browser-use@zcode-plugins-official',
          'name': 'browser-use',
          'marketplace': 'zcode-plugins-official',
          'enabled': true,
          'scope': 'user',
          'packageStatus': 'ok',
          'hostMcpServerNames': ['node_repl'],
        },
        if (_populated)
          for (final entry in const {
            'computer-use': 'computer-use',
            'doc-skills': 'image_search',
          }.entries)
            {
              'id': '${entry.key}@zcode-plugins-official',
              'name': entry.key,
              'marketplace': 'zcode-plugins-official',
              'enabled': true,
              'scope': 'user',
              'packageStatus': 'ok',
              'declaredMcpServerNames': [entry.value],
              'mcpServerNames': ['plugin:${entry.key}:${entry.value}'],
            },
      ]
    };
  }
  if (method == 'getPluginsOverview') {
    return {
      'installedPlugins': [
        {'id': 'browser-use@zcode-plugins-official', 'scope': 'user'}
      ],
      'availablePlugins': <dynamic>[],
      'marketplaces': <dynamic>[],
    };
  }
  if (method == 'loadHooks') {
    return {
      'hooks': [
        {
          'id': 'review-hook',
          'event': 'PreToolUse',
          'type': 'command',
          'command': 'python scripts/check_tool.py',
          'matcher': 'Edit|Write',
          'enabled': true,
          'location': {'source': 'zcode', 'scope': 'user'},
        }
      ]
    };
  }
  if (channel == Channels.skills && method == 'list') {
    return {
      'skills': <dynamic>[],
      'capability': {'supported': true, 'userScopeAvailable': true},
      'diagnostics': <dynamic>[],
    };
  }
  if (channel == Channels.commands && method == 'list') {
    return {
      'commands': <dynamic>[],
      'userCommands': <dynamic>[],
      'pluginCommands': <dynamic>[],
      'capability': {'userScopeAvailable': true},
    };
  }
  if (channel == Channels.subagents && method == 'list') {
    return {
      'capability': {'supported': true, 'userScopeAvailable': true},
      'agents': [
        {
          'id': 'general-purpose',
          'name': 'general-purpose',
          'description': 'General-purpose agent for complex tasks.',
          'scope': 'built-in',
          'source': 'built-in',
        },
        {
          'id': 'review-agent',
          'name': 'review-agent',
          'description': 'Review implementation and verify results.',
          'scope': 'user',
          'source': 'user',
          'enabled': true,
        }
      ],
      'pluginAgents': <dynamic>[],
    };
  }
  if (method == 'getAll' && _populated) {
    return [
      {
        'id': 'custom-native-review',
        'name': 'Native provider review',
        'source': 'custom',
        'enabled': true,
        'apiFormat': 'anthropic-messages',
        'defaultKind': 'anthropic',
        'apiKey': 'synthetic-key',
        'endpoints': {'baseURL': 'https://synthetic.invalid'},
        'models': [
          {
            'id': 'review-model',
            'name': 'Review model',
            'contextWindow': 128000,
            'kinds': ['anthropic'],
            'defaultKind': 'anthropic',
          }
        ],
      }
    ];
  }
  if (method == 'getAll' || method == 'getDisplayOrder') return <dynamic>[];
  if (method == 'loadMcpFromUserDirectory') {
    return {
      'servers': [
        if (_populated)
          for (final name in ['web-search', 'vision-server'])
            {
              'id': name,
              'name': name,
              'source': 'zcodeagentmcp',
              'scope': 'user',
              'enabled': true,
              'config': {'type': 'stdio', 'command': 'synthetic-$name'},
            },
      ]
    };
  }
  if (method == 'listWorkspaceMcpServerStatuses') {
    return {'statuses': <dynamic>[]};
  }
  return <String, dynamic>{};
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native SettingsCenter visual navigation uses real device typography',
    (tester) async {
      final environment = await const MethodChannel('zcode_remote/attachments')
          .invokeMapMethod<String, dynamic>('environment');
      expect(
        environment?['packageName'],
        'com.zcoderemote.zcode_remote.qa',
        reason: 'Run only against the isolated .qa package.',
      );
      if (!_enabled) {
        debugPrint(
            'NATIVE_SETTINGS_VISUAL_REVIEW skipped; pass --dart-define=NATIVE_SETTINGS_VISUAL_REVIEW=true to enable.');
        return;
      }

      final cacheDirectory = environment?['cacheDirectory'] as String?;
      expect(cacheDirectory, isNotNull,
          reason: 'The .qa environment must expose its cache directory.');
      final configuredRunId =
          const String.fromEnvironment('NATIVE_SETTINGS_VISUAL_RUN_ID');
      final runId = configuredRunId.trim().isEmpty
          ? 'run-${DateTime.now().millisecondsSinceEpoch}'
          : configuredRunId.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final runDirectory =
          Directory('${cacheDirectory!}/native-settings-visual/$runId');
      expect(await runDirectory.exists(), isFalse,
          reason: 'Use a new cache run directory for every native review.');
      await runDirectory.create(recursive: true);

      final store = DeviceStore(requireEncryption: false);
      final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=native-settings-review&hash=synthetic&t=1',
        label: 'Settings QA device',
      );
      final bridge = FeatureBridge()..channels.handler = _read;
      final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (value) =>
            ReviewConnectedSession(value.params!, bridge),
      );
      sessions.sessionFor(device);
      expect(
          connectionStatusSnapshot(sessions.sessionOf(device.id), bridge)
              .healthy,
          isTrue,
          reason: 'Native settings capture uses a paired synthetic source.');
      final monitor = FakeWorkspaceMonitor(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Synthetic',
        },
        source: WorkspaceTaskSource(
          deviceId: device.id,
          deviceLabel: device.label,
          workspaceKey: 'workspace',
          workspacePath: 'D:/Synthetic',
        ),
        notifications: sessions.notifications,
      );
      sessions.monitors[device.id] = monitor;
      final preferences = ClientPreferences();
      await preferences.load();
      final originalTheme = preferences.theme;
      final originalLanguage = preferences.language;
      final originalTextScale = preferences.textScale;
      final originalUiFontSize = preferences.uiFontSizePx;
      final boundary = GlobalKey();
      final manifestEntries = <Map<String, String>>[];

      final labels = <String, String>{
        'general': '常规',
        'appearance': '外观',
        'modelProvider': '模型设置',
        'plugins': '插件',
        'skills': '技能',
        'mcp': 'MCP 服务器',
        'subagents': '子智能体',
        'commands': '命令',
        'hooks': '钩子',
        'memory': '记忆',
        'browser': '浏览器控制',
        'indexing': '索引库',
        'devices': '设备',
        'usage': '使用统计',
        'voice': '语音模型',
        'notifications': '通知与上岛',
        'updates': '更新与关于',
      };
      final englishLabels = <String, String>{
        'general': 'General',
        'appearance': 'Appearance',
        'modelProvider': 'Model settings',
        'plugins': 'Plugins',
        'skills': 'Skills',
        'mcp': 'MCP Servers',
        'subagents': 'Subagents',
        'commands': 'Commands',
        'hooks': 'Hooks',
        'memory': 'Memory',
        'browser': 'Browser control',
        'indexing': 'Indexing',
        'devices': 'Devices',
        'usage': 'Usage stats',
        'voice': 'Voice models',
        'notifications': 'Task notifications',
        'updates': 'Updates and about',
      };
      const remoteSections = {
        'general',
        'modelProvider',
        'plugins',
        'skills',
        'mcp',
        'subagents',
        'commands',
        'hooks',
        'memory',
        'browser',
        'indexing',
        'usage',
      };

      Future<void> writeManifest() async {
        final file = File('${runDirectory.path}/manifest.tsv');
        final rows = <String>[
          'section\tevidence\tcondition\tsourceGate\tfixture\tstatus\tunverified',
          for (final entry in manifestEntries)
            [
              entry['section'],
              entry['evidence'],
              entry['condition'],
              entry['sourceGate'],
              entry['fixture'],
              entry['status'],
              entry['unverified'],
            ].join('\t'),
        ];
        await file.writeAsString('${rows.join('\n')}\n');
      }

      Future<void> pumpBounded() async {
        // Remote pages may schedule async reads; the finite loop avoids a
        // hanging pumpAndSettle if a page contains a persistent animation.
        for (var index = 0; index < 30; index++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> capture(String section, String condition) async {
        if (_populated && section == 'mcp') {
          await tester.ensureVisible(find.text('image_search'));
          await tester.pumpAndSettle();
          expect(find.text('image_search').hitTestable(), findsOneWidget);
        }
        await tester.pump();
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(data, isNotNull);
          final path = '${runDirectory.path}/$section-$condition.png';
          await File(path).writeAsBytes(data!.buffer.asUint8List());
          final sourceGate = remoteSections.contains(section)
              ? 'remote synthetic read-only FeatureBridge'
              : 'client-local SettingsCenter source';
          final entry = <String, String>{
            'section': section,
            'evidence': path,
            'condition': condition,
            'sourceGate': sourceGate,
            'fixture': 'fixed synthetic settings/workspace scope',
            'status': 'native Flutter surface captured; inspect required',
            'unverified': remoteSections.contains(section)
                ? 'no real remote or official same-data comparison'
                : 'no official same-data comparison',
          };
          manifestEntries.add(entry);
          await writeManifest();
          debugPrint('NATIVE_SETTINGS_IMAGE ${jsonEncode(entry)}');
        } finally {
          image.dispose();
        }
      }

      Future<void> selectSection(String section) async {
        final label = preferences.language == 'en'
            ? englishLabels[section]!
            : labels[section]!;
        final width = MediaQuery.sizeOf(boundary.currentContext!).width;
        if (width < 700) {
          final navigation = find.byType(DropdownButton<String>).first;
          expect(navigation, findsOneWidget,
              reason:
                  'Compact SettingsCenter navigation must remain reachable.');
          await tester.tap(navigation);
          await pumpBounded();
          final option = find.text(label).last;
          expect(option, findsOneWidget,
              reason: 'Compact navigation option missing for $section.');
          await tester.tap(option);
        } else {
          final option = find.text(label).first;
          expect(option, findsOneWidget,
              reason: 'Wide navigation option missing for $section.');
          await tester.tap(option);
        }
        await pumpBounded();
      }

      Future<void> captureNotificationsDetail(String condition) async {
        final title = find.text(preferences.language == 'en'
            ? 'Task notifications and Live Updates'
            : '任务通知与上岛设置');
        if (title.evaluate().isEmpty) return;
        await tester.tap(title.last);
        await pumpBounded();
        final render = boundary.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        try {
          final data = await image.toByteData(format: ui.ImageByteFormat.png);
          expect(data, isNotNull);
          final path =
              '${runDirectory.path}/notifications-detail-$condition.png';
          await File(path).writeAsBytes(data!.buffer.asUint8List());
          final entry = <String, String>{
            'section': 'notifications-detail',
            'evidence': path,
            'condition': condition,
            'sourceGate': 'client-local notification settings route',
            'fixture': 'fixed synthetic notification controller',
            'status': 'native Flutter surface captured; inspect required',
            'unverified':
                'permission dialog and OS live activity not exercised',
          };
          manifestEntries.add(entry);
          await writeManifest();
          debugPrint('NATIVE_SETTINGS_IMAGE ${jsonEncode(entry)}');
        } finally {
          image.dispose();
        }
        await tester.pageBack();
        await pumpBounded();
      }

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ZcodeRemoteApp(
            preferences: preferences,
            home: SettingsCenterPage(
              preferences: preferences,
              sessions: sessions,
              remoteMonitor: monitor,
              initialSection: 'general',
              onManageDevices: () {},
            ),
          ),
        ),
      );
      await pumpBounded();

      const firstCondition = 'zh-dark-100';
      const secondCondition = 'en-light-140';
      const firstSections = [
        'general',
        'appearance',
        'modelProvider',
        'plugins',
        'skills',
        'mcp',
        'subagents',
        'commands',
        'hooks',
      ];
      const secondSections = [
        'memory',
        'browser',
        'indexing',
        'devices',
        'usage',
        'voice',
        'notifications',
        'updates',
      ];
      final requestedSections =
          const String.fromEnvironment('NATIVE_SETTINGS_VISUAL_SECTIONS')
              .split(',')
              .map((value) => value.trim())
              .where((value) => value.isNotEmpty)
              .toSet();
      final allSections = {...firstSections, ...secondSections};
      expect(requestedSections.difference(allSections), isEmpty,
          reason: 'A focused replay must name existing Settings sections.');
      final selectedSections =
          requestedSections.isEmpty ? allSections : requestedSections;

      try {
        await preferences.setLanguage('zh');
        await preferences.setTheme(ThemeMode.dark);
        await preferences.setTextScale(1);
        await pumpBounded();
        for (final section in firstSections) {
          if (!selectedSections.contains(section)) continue;
          if (section != 'general') await selectSection(section);
          await capture(section, firstCondition);
        }
        await preferences.setLanguage('en');
        await preferences.setTheme(ThemeMode.light);
        await preferences.setTextScale(1.4);
        await pumpBounded();
        for (final section in secondSections) {
          if (!selectedSections.contains(section)) continue;
          await selectSection(section);
          await capture(section, secondCondition);
          if (section == 'notifications') {
            await captureNotificationsDetail(secondCondition);
          }
        }
        expect(
            manifestEntries.length,
            selectedSections.length +
                (selectedSections.contains('notifications') ? 1 : 0));
        expect(
            bridge.channels.calls.where((call) => const {
                  'save',
                  'update',
                  'delete',
                  'saveHooks',
                  'setPluginEnabled',
                  'writeCommandFile',
                  'updateCommandFile',
                  'deleteCommandFile',
                  'configurePlugin',
                  'resetPluginConfig',
                  'installPlugin',
                  'uninstallPlugin',
                  'importSelected',
                }.contains(call.method)),
            isEmpty,
            reason: 'Navigation and captures must not issue remote mutations.');
        await writeManifest();
        debugPrint('NATIVE_SETTINGS_MANIFEST ${jsonEncode({
              'path': '${runDirectory.path}/manifest.tsv',
              'entries': manifestEntries.length,
              'packageName': environment?['packageName'],
              'physicalSizeOverridden': false,
              'fontOverride': false,
              'syntheticTransport': true,
            })}');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await preferences.setTheme(originalTheme);
        await preferences.setLanguage(originalLanguage);
        await preferences.setUiFontSizePx(originalUiFontSize);
        await preferences.setTextScale(originalTextScale);
        await preferences.settled;
        preferences.dispose();
        monitor.dispose();
        final session = sessions.sessionOf(device.id);
        if (session is ReviewConnectedSession) {
          await tester.runAsync(session.reviewClient.dispose);
        }
        sessions.dispose();
        await sessions.notifications.settled;
        bridge.channels.dispose();
        store.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
