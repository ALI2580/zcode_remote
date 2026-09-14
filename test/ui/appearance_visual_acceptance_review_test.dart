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
      'review: actual appearance top and previews at the official viewport',
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
          'loadMcpFromUserDirectory' => {'servers': []},
          'listWorkspaceMcpServerStatuses' => {'statuses': []},
          'listPlugins' => {'plugins': []},
          'getPluginsOverview' => {
              'availablePlugins': [],
              'installedPlugins': []
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
                    appBarTheme: base.appBarTheme.copyWith(
                        titleTextStyle: base.appBarTheme.titleTextStyle
                            ?.copyWith(fontFamily: family))),
                child: RepaintBoundary(
                    key: boundary,
                    child: SettingsCenterPage(
                        preferences: preferences,
                        sessions: sessions,
                        remoteMonitor: monitor,
                        initialSection: 'appearance',
                        onManageDevices: () {})));
          })));
      await tester.pumpAndSettle();
      await captureReviewBoundary(tester, boundary, 'appearance-top-1158-zh-dark');
      await tester.ensureVisible(find.byKey(const ValueKey('appearance-reset')));
      await tester.pumpAndSettle();
      await captureReviewBoundary(tester, boundary, 'appearance-previews-1158-zh-dark');
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
