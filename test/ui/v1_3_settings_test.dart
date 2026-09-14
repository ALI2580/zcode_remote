import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'fake_features.dart';
import 'fake_workspace.dart';

/// V1.3 settings-center review renders. PNGs are only written when
/// ZCODE_UI_CAPTURE_DIR is set; every run still pumps each real section.
void main() {
  testWidgets('settings center renders every remote section at the official '
      'review condition', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final captureDir = Platform.environment['ZCODE_UI_CAPTURE_DIR'];
    final fontPath = Platform.environment['ZCODE_TEST_FONT'];
    if (fontPath != null) {
      await tester.runAsync(() async {
        final bytes = await File(fontPath).readAsBytes();
        await (FontLoader('V1Preview')
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
        for (final entry in {
          'monospace': Platform.environment['ZCODE_TEST_MONO_FONT'],
          'MaterialIcons': Platform.environment['ZCODE_TEST_ICON_FONT'],
        }.entries) {
          if (entry.value == null) continue;
          final bytes = await File(entry.value!).readAsBytes();
          await (FontLoader(entry.key)
                ..addFont(Future.value(ByteData.sublistView(bytes))))
              .load();
        }
      });
    }

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);

    final prefs = ClientPreferences();
    await prefs.load();
    await prefs.setTheme(ThemeMode.dark);
    await prefs.setLanguage('zh');

    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'oauth') {
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
              'productName': 'Team Plan',
              'teamProjects': [
                {'organizationId': 'org', 'projectId': 'prj'},
              ],
            },
          ],
        };
      }
      if (channel == 'setting' && method == 'update') return null;
      if (channel == 'plugin-management') {
        if (method == 'listPlugins') {
          return {
            'plugins': [
              {'id': 'demo@official', 'name': 'Demo 插件', 'enabled': true}
            ]
          };
        }
        if (method == 'getPluginsOverview') {
          return {
            'availablePlugins': [
              {
                'id': 'demo@official',
                'name': 'Demo 插件',
                'marketplace': 'official',
                'description': '演示工具',
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
      }
      // Empty catalogs match the official fresh-workspace review shots
      // (hooks/subagents/skills/commands show "已安装 0").
      if (method.startsWith('list') || method == 'getAll') return [];
      return {
        'providerFamilyDomain': 'zai',
        'modelProviderFamilyModes': {'zai': 'oauth', 'bigmodel': 'oauth'},
        'modelProviderFamilySelectedKeys': {
          'zai': 'coding-plan:builtin:zai-start-plan',
          'bigmodel': 'coding-plan:builtin:bigmodel-coding-plan',
        },
        'askUserQuestionAutoResolutionEnabled': false,
        'memoryEnabled': true,
        'taskAutoArchiveEnabled': true,
        'taskAutoArchiveOlderThanDays': 30,
        'embeddedBrowserAllowInsecureCertificates': false,
        'repoSnapshotIndexingEnabled': false,
        'instantGrepIndexingEnabled': false,
        'messageStreamShowReasoning': true,
        'messageStreamShowTodos': true,
        'modelIoFullRetentionEnabled': true,
        'zcodeInteractionBehavior': 'queue',
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

    final boundary = GlobalKey();
    Widget app(String section, Key key) => RepaintBoundary(
        key: boundary,
        child: ZcodeRemoteApp(
            preferences: prefs,
            home: Builder(builder: (context) {
              final family = fontPath == null ? null : 'V1Preview';
              return Theme(
                  data: Theme.of(context).copyWith(
                      textTheme: Theme.of(context).textTheme.apply(
                          fontFamily: family,
                          fontFamilyFallback:
                              family == null ? null : const ['V1Preview'])),
                  child: SettingsCenterPage(
                      key: key,
                      preferences: prefs,
                      sessions: sessions,
                      remoteMonitor: monitor,
                      initialSection: section,
                      onManageDevices: () {}));
            })));

    const sections = [
      'general',
      'appearance',
      'modelProvider',
      'plugins',
      'skills',
      'subagents',
      'commands',
      'mcp',
      'hooks',
      'memory',
      'indexing',
      'browser',
    ];
    for (final section in sections) {
      await tester.pumpWidget(app(
          section, ValueKey('v13-$section')));
      await tester.pumpAndSettle();
      final error = tester.takeException();
      expect(error, isNull, reason: '$section: $error');
      if (captureDir != null) {
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()
              as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(captureDir).create(recursive: true);
          await File('$captureDir/v1.3-settings-$section-dark-zh.png')
              .writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(milliseconds: 50));
    }
    sessions.dispose();
    await sessions.notifications.settled;
  }, timeout: const Timeout(Duration(minutes: 3)));
}
