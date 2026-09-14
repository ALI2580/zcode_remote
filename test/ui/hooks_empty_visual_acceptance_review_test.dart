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
import 'review_connected_session.dart';

void main() {
  testWidgets('review: Hooks empty state keeps official catalog chrome',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1158, 722);
    addTearDown(tester.view.reset);

    final preferences = ClientPreferences();
    await preferences.setLanguage('zh');
    await preferences.setTheme(ThemeMode.dark);
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
      'https://zcode.z.ai/remote/v4?sid=synthetic-hooks-empty&hash=synthetic&t=1',
      label: 'Hooks review',
    );
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, method, __) =>
        method == 'loadHooks' ? {'hooks': <dynamic>[]} : <String, dynamic>{};
    final sessions = FakeAppSessions(
      store: store,
      sessionFactory: (value) => ReviewConnectedSession(value.params!, bridge),
    );
    sessions.sessionFor(device);
    final monitor = FakeWorkspaceMonitor(
      bridge: bridge,
      scope: const {
        'workspaceIdentity': 'workspace',
        'workspacePath': 'D:/Synthetic',
      },
      source: WorkspaceTaskSource(
        deviceId: device.id,
        deviceLabel: 'Hooks review',
        workspaceKey: 'workspace',
        workspacePath: 'D:/Synthetic',
      ),
      notifications: sessions.notifications,
    );
    sessions.monitors[device.id] = monitor;
    final boundary = GlobalKey();
    final capture = Platform.environment['ZCODE_UI_CAPTURE_DIR'] != null;

    try {
      if (capture) {
        await tester.runAsync(() async {
          await loadReviewCaptureFonts();
          final data = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
          await (FontLoader('HooksEmptyReview')
                ..addFont(Future.value(ByteData.sublistView(data))))
              .load();
        });
      }
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: Builder(builder: (context) {
          final base = Theme.of(context);
          final font = capture ? 'HooksEmptyReview' : null;
          return Theme(
            data: base.copyWith(
              textTheme: base.textTheme.apply(fontFamily: font),
              primaryTextTheme: base.primaryTextTheme.apply(fontFamily: font),
              appBarTheme: base.appBarTheme.copyWith(
                titleTextStyle:
                    base.appBarTheme.titleTextStyle?.copyWith(fontFamily: font),
              ),
            ),
            child: RepaintBoundary(
              key: boundary,
              child: SettingsCenterPage(
                preferences: preferences,
                sessions: sessions,
                remoteMonitor: monitor,
                initialSection: 'hooks',
                onManageDevices: () {},
              ),
            ),
          );
        }),
      ));
      await tester.pumpAndSettle();
      expect(find.text('已安装 0'), findsOneWidget);
      expect(find.byKey(const ValueKey('hooks-new-empty')), findsOneWidget);
      expect(find.byKey(const ValueKey('hooks-refresh')), findsOneWidget);
      await captureReviewBoundary(tester, boundary, 'hooks-empty-1158-zh-dark');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled;
      preferences.dispose();
    }
  });
}
