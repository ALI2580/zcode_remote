import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'fake_workspace.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

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
      expect(find.text('140%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    sessions.dispose();
    await sessions.notifications.settled;
    prefs.dispose();
    restored.dispose();
  });
}
