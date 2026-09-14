import 'review_capture.dart';

import 'package:flutter/material.dart';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/workspace_catalog.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';
import 'fake_workspace.dart';

void main() {
  setUpAll(loadReviewCaptureFonts);
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets(
      'device switcher is anchored to its button and constrains a long list',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(834, 520);
    addTearDown(tester.view.reset);

    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final devices = <Device>[];
    for (var i = 0; i < 18; i++) {
      devices.add(await store.addUrl(
          'https://zcode.z.ai/remote/v4?sid=synthetic-$i&hash=synthetic&t=1',
          label: '设备 ${i + 1}'));
    }
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (device) =>
            FakeDeviceSession(device.params!, FakeBridge()));
    final preferences = ClientPreferences();
    await preferences.setLanguage('zh');
    final workspace = const WorkspaceDescriptor(
        key: 'workspace',
        title: 'ZcodeRemote',
        scope: {'workspaceIdentity': 'workspace'});
    final monitor = await sessions.openWorkspace(
        devices.first, workspace.key, workspace.scope);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled
          .timeout(const Duration(seconds: 1), onTimeout: () {});
      preferences.dispose();
    });

    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ZcodeRemoteApp(
            preferences: preferences,
            home: Builder(builder: (context) {
              final media = MediaQuery.of(context);
              return MediaQuery(
                  data:
                      media.copyWith(textScaler: const TextScaler.linear(1.4)),
                  child: WorkspaceShell(
                      device: devices.first,
                      workspace: workspace,
                      monitor: monitor,
                      sessions: sessions,
                      preferences: preferences,
                      conversationBuilder: (_, __) => const SizedBox.shrink()));
            }))));
    await tester.pumpAndSettle();

    final tooltipFinder = find.byTooltip('切换设备');
    final buttonFinder = find.ancestor(
        of: tooltipFinder, matching: find.byType(PopupMenuButton<String>));
    expect(tooltipFinder, findsOneWidget);
    expect(buttonFinder, findsOneWidget);
    final button = tester.widget<PopupMenuButton<String>>(buttonFinder);
    expect(button.position, PopupMenuPosition.under);
    expect(button.offset, Offset.zero);
    expect(button.constraints, isNotNull);
    expect(button.constraints!.maxWidth, lessThanOrEqualTo(834));
    expect(button.constraints!.maxHeight, lessThanOrEqualTo(520));

    await tester.tap(buttonFinder);
    await tester.pumpAndSettle();
    await captureReviewBoundary(tester, boundary, 'u02-device-menu-wide');
    expect(find.text('设备 1'), findsWidgets);
    expect(find.text('设备 18'), findsOneWidget);
    expect(find.text('管理设备'), findsOneWidget);

    final menuScrollables = find.byType(SingleChildScrollView);
    expect(menuScrollables, findsWidgets);
    final menu = tester.getRect(menuScrollables.last);
    expect(menu.left, greaterThanOrEqualTo(0));
    expect(menu.top, greaterThanOrEqualTo(0));
    expect(menu.right, lessThanOrEqualTo(834));
    expect(menu.bottom, lessThanOrEqualTo(520));
    await tester.ensureVisible(find.text('管理设备'));
    await tester.pumpAndSettle();
    final managementRect = tester.getRect(find.text('管理设备'));
    expect(managementRect.top, greaterThanOrEqualTo(0));
    expect(managementRect.bottom, lessThanOrEqualTo(520));
    await captureReviewBoundary(tester, boundary, 'u02-device-menu-scrolled');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('管理设备'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'device switcher flips within a short viewport and selects device',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(834, 360);
    addTearDown(tester.view.reset);
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final first = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1',
        label: '设备 A');
    final second = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-B&hash=synthetic&t=1',
        label: '设备 B');
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (device) =>
            FakeDeviceSession(device.params!, FakeBridge()));
    final preferences = ClientPreferences();
    await preferences.setLanguage('zh');
    final workspace = const WorkspaceDescriptor(
        key: 'workspace',
        title: 'ZcodeRemote',
        scope: {'workspaceIdentity': 'workspace'});
    final monitor =
        await sessions.openWorkspace(first, workspace.key, workspace.scope);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled
          .timeout(const Duration(seconds: 1), onTimeout: () {});
      preferences.dispose();
    });
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ZcodeRemoteApp(
            preferences: preferences,
            home: WorkspaceShell(
                device: first,
                workspace: workspace,
                monitor: monitor,
                sessions: sessions,
                preferences: preferences,
                conversationBuilder: (_, __) => const SizedBox.shrink()))));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('切换设备'));
    await tester.pumpAndSettle();
    await captureReviewBoundary(tester, boundary, 'u02-device-menu-short');
    final menu = tester.getRect(find.byType(SingleChildScrollView).last);
    expect(menu.top, greaterThanOrEqualTo(0));
    expect(menu.bottom, lessThanOrEqualTo(360));
    await tester.tap(find.text('设备 B'));
    await tester.pumpAndSettle();
    expect(tester.widget<WorkspaceShell>(find.byType(WorkspaceShell)).device.id,
        second.id);
    expect(tester.takeException(), isNull);
  });
}
