import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_toolbar.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'package:zcode_remote/ui/shell/shell_layout.dart';
import 'package:zcode_remote/ui/theme.dart';
import '../fake_workspace.dart';

const _phoneSizes = [
  Size(320, 568),
  Size(344, 760),
  Size(360, 640),
  Size(390, 844),
  Size(412, 915),
];
const _wideSizes = [Size(720, 900), Size(834, 900), Size(1180, 820)];

Future<ComposerController> _controller() async {
  SharedPreferences.setMockInitialValues({});
  final bridge = FakeBridge();
  final store = ComposerStore();
  final controller = store.obtain(
      transport: bridge.conversationTransport,
      deviceId: 'A',
      workspaceKey: 'workspace',
      sessionId: 'task');
  final subscription = await bridge.conversationTransport.subscribe('task');
  controller.bind(subscription.state);
  await controller.loadOptions();
  return controller;
}

void main() {
  testWidgets('matrix: composer toolbar renders all phone sizes without overflow',
      (tester) async {
    final controller = await _controller();
    addTearDown(controller.store.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final size in _phoneSizes) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
          theme: ZInkTheme.light(),
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: size.width - 8,
                      child: ComposerToolbar(
                          controller: controller, onSend: () {}))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'composer overflow at ${size.width}');
      // Container width = viewport - 8; all matrix sizes reach the 312
      // touch threshold, so the primary action is a full 48px target.
      expect(
          tester.getRect(find.byKey(const ValueKey('composer-submit'))).height,
          greaterThanOrEqualTo(48),
          reason: 'composer submit at ${size.width}');
    }
  });

  testWidgets('matrix: settings section list renders all phone sizes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = ClientPreferences();
    await prefs.load();
    addTearDown(prefs.dispose);
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
    addTearDown(sessions.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final size in _phoneSizes) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: prefs,
          home: Builder(
              builder: (context) => Scaffold(
                  body: Center(
                      child: TextButton(
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => SettingsCenterPage(
                                      preferences: prefs,
                                      sessions: sessions,
                                      onManageDevices: () {}))),
                          child: const Text('open')))))));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'settings overflow at ${size.width}');
      expect(find.byKey(const ValueKey('settings-section-appearance')),
          findsOneWidget,
          reason: 'settings list at ${size.width}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });

  testWidgets('matrix: shell with terminal drawer renders phone and wide sizes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final size in [..._phoneSizes, ..._wideSizes]) {
      tester.view.physicalSize = size;
      await tester.pumpWidget(MaterialApp(
          theme: ZInkTheme.light(),
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: size.width,
                      child: WorkspaceShellLayout(
                          title: 'M',
                          project: 'P',
                          sidebarCollapsed: true,
                          onSidebarCollapsed: (_) {},
                          sidebar: const SizedBox.shrink(),
                          conversation: const SizedBox.expand(),
                          bottomPanelOpen: true,
                          bottomPanel: Container(
                              key: const ValueKey('matrix-terminal'),
                              color: Colors.black)))))));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'shell overflow at ${size.width}');
      final drawer =
          tester.getRect(find.byKey(const ValueKey('matrix-terminal')));
      expect(drawer.height, closeTo(320, 1.0),
          reason: 'default drawer height at ${size.width}');
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
    }
  });
}
