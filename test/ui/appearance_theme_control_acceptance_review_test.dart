import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'fake_workspace.dart';

void main() {
  testWidgets(
      'review: actual appearance settings retains all three interface theme choices',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);
    final prefs = ClientPreferences();
    await prefs.setLanguage('en');
    final sessions = FakeAppSessions(
        store: DeviceStore(requireEncryption: false),
        sessionFactory: (device) =>
            FakeDeviceSession(device.params!, FakeBridge()));
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: prefs,
          home: SettingsCenterPage(
              preferences: prefs,
              sessions: sessions,
              initialSection: 'appearance',
              onManageDevices: () {})));
      await tester.pumpAndSettle();
      for (final entry in {
        'Dark': ThemeMode.dark,
        'Light': ThemeMode.light,
        'System': ThemeMode.system
      }.entries) {
        await tester.tap(
            find.byKey(const ValueKey('appearance-theme-mode')));
        await tester.pumpAndSettle();
        final choice = find.text(entry.key);
        expect(choice, findsOneWidget,
            reason:
                'The interface theme control must remain available inside Appearance.');
        await tester.tap(choice);
        await tester.pumpAndSettle();
        expect(prefs.theme, entry.value);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled;
      prefs.dispose();
    }
  });
}
