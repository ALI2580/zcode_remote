import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'review_capture.dart';

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
        }
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
  if (method == 'getAll' || method == 'getDisplayOrder') return <dynamic>[];
  if (method == 'loadMcpFromUserDirectory') return {'servers': <dynamic>[]};
  if (method == 'listWorkspaceMcpServerStatuses') {
    return {'statuses': <dynamic>[]};
  }
  return <String, dynamic>{};
}

void main() {
  for (final section in [
    'general',
    'browser',
    'memory',
    'indexing',
    'hooks',
    'plugins',
    'subagents'
  ]) {
    for (final narrow in [false, true]) {
      testWidgets(
          'review: Settings $section ${narrow ? '344 en 140' : '1158 zh dark'}',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize =
            narrow ? const Size(344, 800) : const Size(1158, 722);
        addTearDown(tester.view.reset);
        final preferences = ClientPreferences();
        await preferences.setLanguage(narrow ? 'en' : 'zh');
        await preferences.setTheme(narrow ? ThemeMode.light : ThemeMode.dark);
        final sessions = FakeAppSessions(
            store: DeviceStore(requireEncryption: false),
            sessionFactory: (device) =>
                FakeDeviceSession(device.params!, FeatureBridge()));
        final bridge = FeatureBridge();
        bridge.channels.handler = _read;
        final monitor = FakeWorkspaceMonitor(
            bridge: bridge,
            scope: const {
              'workspaceIdentity': 'workspace',
              'workspacePath': 'D:/Synthetic'
            },
            source: const WorkspaceTaskSource(
                deviceId: 'review',
                deviceLabel: 'Review',
                workspaceKey: 'workspace',
                workspacePath: 'D:/Synthetic'),
            notifications: sessions.notifications);
        final boundary = GlobalKey();
        final capture = Platform.environment['ZCODE_UI_CAPTURE_DIR'] != null;
        try {
          if (capture) {
            await tester.runAsync(() async {
              await loadReviewCaptureFonts();
              final data =
                  await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
              await (FontLoader('SettingsReview')
                    ..addFont(Future.value(ByteData.sublistView(data))))
                  .load();
            });
          }
          await tester.pumpWidget(ZcodeRemoteApp(
              preferences: preferences,
              home: Builder(builder: (context) {
                final base = Theme.of(context);
                final font = capture ? 'SettingsReview' : null;
                return Theme(
                    data: base.copyWith(
                        textTheme: base.textTheme.apply(fontFamily: font),
                        primaryTextTheme:
                            base.primaryTextTheme.apply(fontFamily: font),
                        appBarTheme: base.appBarTheme.copyWith(
                            titleTextStyle: base.appBarTheme.titleTextStyle
                                ?.copyWith(fontFamily: font))),
                    child: MediaQuery(
                        data: MediaQuery.of(context).copyWith(
                            textScaler: TextScaler.linear(narrow ? 1.4 : 1)),
                        child: RepaintBoundary(
                            key: boundary,
                            child: SettingsCenterPage(
                                preferences: preferences,
                                sessions: sessions,
                                remoteMonitor: monitor,
                                initialSection: section,
                                onManageDevices: () {}))));
              })));
          await tester.pumpAndSettle();
          await captureReviewBoundary(tester, boundary,
              '$section-${narrow ? '344-en-light-140' : '1158-zh-dark-100'}');
          expect(tester.takeException(), isNull);
          expect(bridge.conversationTransport.sent, isEmpty);
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
}
