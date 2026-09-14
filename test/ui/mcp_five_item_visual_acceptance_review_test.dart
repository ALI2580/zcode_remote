import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'fake_features.dart';
import 'fake_workspace.dart';
import 'review_capture.dart';

void main() {
  testWidgets(
      'review: actual MCP settings with two native and three plugin servers',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1158, 722);
    addTearDown(tester.view.reset);
    final preferences = ClientPreferences();
    await preferences.setLanguage('zh');
    await preferences.setTheme(ThemeMode.dark);
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (device) =>
            FakeDeviceSession(device.params!, FakeBridge()));
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, method, __) => switch (method) {
          'loadMcpFromUserDirectory' => {
              'servers': [
                for (final name in ['web-search', 'vision-server'])
                  {
                    'id': name,
                    'name': name,
                    'source': 'zcodeagentmcp',
                    'scope': 'user',
                    'enabled': true,
                    'config': {
                      'type': 'stdio',
                      'command': name == 'web-search'
                          ? 'D:/SoftWare/Develop/NodeJS22/node.exe'
                          : 'python',
                      'args': [
                        name == 'web-search'
                            ? 'D:/Synthetic/open-websearch/node_modules/open-websearch/index.js'
                            : 'D:/WorkSpace/pythonCode/agentUtils/mcp/vision-server/server.py'
                      ]
                    },
                  }
              ]
            },
          'listWorkspaceMcpServerStatuses' => {
              'statuses': [
                for (final name in [
                  'web-search',
                  'vision-server',
                  'plugin:computer-use:computer-use'
                ])
                  {'name': name, 'status': 'connected'},
              ]
            },
          'listPlugins' => {
              'plugins': [
                {
                  'id': 'browser-use@zcode-plugins-official',
                  'name': 'browser-use',
                  'marketplace': 'zcode-plugins-official',
                  'enabled': true,
                  'listing': {
                    'displayName': 'Browser use',
                    'displayNameI18n': {'zh-CN': '浏览器操作'},
                  },
                  'hostMcpServerNames': ['node_repl']
                },
                {
                  'id': 'computer-use@zcode-plugins-official',
                  'name': 'computer-use',
                  'marketplace': 'zcode-plugins-official',
                  'enabled': true,
                  'listing': {
                    'displayName': 'Computer control',
                    'displayNameI18n': {'zh-CN': '电脑控制'},
                  },
                  'declaredMcpServerNames': ['computer-use'],
                  'mcpServerNames': ['plugin:computer-use:computer-use']
                },
                {
                  'id': 'doc-skills@zcode-plugins-official',
                  'name': 'doc-skills',
                  'marketplace': 'zcode-plugins-official',
                  'enabled': true,
                  'listing': {
                    'displayName': 'Document skills',
                    'displayNameI18n': {'zh-CN': '文档技能'},
                  },
                  'declaredMcpServerNames': ['image_search'],
                  'mcpServerNames': ['plugin:doc-skills:image_search']
                },
              ]
            },
          'getPluginsOverview' => {
              'availablePlugins': [],
              'installedPlugins': [
                for (final name in [
                  'browser-use',
                  'computer-use',
                  'doc-skills'
                ])
                  {'id': '$name@zcode-plugins-official', 'scope': 'user'}
              ]
            },
          'getAll' || 'getDisplayOrder' => [],
          _ => <String, dynamic>{},
        };
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
      await tester.runAsync(() async {
        await loadReviewCaptureFonts();
        if (capture) {
          final data = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
          await (FontLoader('ReviewUi')
                ..addFont(Future.value(ByteData.sublistView(data))))
              .load();
        }
      });
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: preferences,
          home: Builder(builder: (context) {
            final base = Theme.of(context);
            final family = capture ? 'ReviewUi' : null;
            return Theme(
                data: base.copyWith(
                    textTheme: base.textTheme.apply(fontFamily: family),
                    filledButtonTheme: FilledButtonThemeData(
                        style: FilledButton.styleFrom(
                            textStyle: TextStyle(fontFamily: family))),
                    outlinedButtonTheme: OutlinedButtonThemeData(
                        style: OutlinedButton.styleFrom(
                            textStyle: TextStyle(fontFamily: family))),
                    appBarTheme: base.appBarTheme.copyWith(
                        titleTextStyle: base.appBarTheme.titleTextStyle
                            ?.copyWith(fontFamily: family))),
                child: DefaultTextStyle.merge(
                    style: TextStyle(fontFamily: family),
                    child: RepaintBoundary(
                        key: boundary,
                        child: SettingsCenterPage(
                            preferences: preferences,
                            sessions: sessions,
                            remoteMonitor: monitor,
                            initialSection: 'mcp',
                            onManageDevices: () {}))));
          })));
      await tester.pumpAndSettle();
      for (final name in [
        'web-search',
        'vision-server',
        'node_repl',
        'computer-use',
        'image_search'
      ]) {
        expect(find.text(name), findsOneWidget);
      }
      expect(find.text('浏览器操作'), findsOneWidget);
      expect(find.text('电脑控制'), findsOneWidget);
      expect(find.text('文档技能'), findsOneWidget);
      await captureReviewBoundary(
          tester, boundary, 'mcp-five-items-1158-zh-dark');
      expect(tester.takeException(), isNull);
      tester.view.physicalSize = const Size(1158, 1220);
      await tester.pumpAndSettle();
      expect(find.text('image_search').hitTestable(), findsOneWidget,
          reason: 'A tall Settings viewport must reveal the fifth server without '
              'scrolling a fixed inner list while the page below is empty.');
      await captureReviewBoundary(
          tester, boundary, 'mcp-five-items-1158-tall-zh-dark');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      monitor.dispose();
      sessions.dispose();
      await sessions.notifications.settled;
      preferences.dispose();
    }
  });
}
