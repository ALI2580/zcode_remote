import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/app_sessions.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import '../fake_workspace.dart';

Future<void> _openSettings(WidgetTester tester, ClientPreferences prefs,
    AppSessions sessions,
    {String initialSection = 'general'}) async {
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
                                  initialSection: initialSection,
                                  onManageDevices: () {}))),
                      child: const Text('open settings')))))));
  await tester.tap(find.text('open settings'));
  await tester.pumpAndSettle();
}

Future<ClientPreferences> _prefs() async {
  SharedPreferences.setMockInitialValues({});
  final prefs = ClientPreferences();
  await prefs.load();
  return prefs;
}

Future<AppSessions> _sessions() async {
  return FakeAppSessions(
      store: DeviceStore(requireEncryption: false),
      sessionFactory: (d) => FakeDeviceSession(d.params!, FakeBridge()));
}

void main() {
  testWidgets(
      'compact settings opens as a section list; picking a section pushes the detail and Back returns to the list',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final prefs = await _prefs();
    addTearDown(prefs.dispose);
    final sessions = await _sessions();
    addTearDown(sessions.dispose);

    await _openSettings(tester, prefs, sessions);

    // The section list is the entry surface — no hidden dropdown.
    expect(find.byType(DropdownButton<String>), findsNothing);
    expect(find.byKey(const ValueKey('settings-section-appearance')),
        findsOneWidget);
    // The list is lazy: scroll to the tail to verify the usage entry.
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('settings-section-usage')), 200,
        scrollable: find.byType(Scrollable).first);
    expect(find.byKey(const ValueKey('settings-section-usage')),
        findsOneWidget);
    // Back to the top for the tap below.
    await tester.drag(find.byType(Scrollable).first, const Offset(0, 2000));
    await tester.pumpAndSettle();

    // Picking a section shows its detail inside the same route.
    await tester.tap(find.byKey(const ValueKey('settings-section-appearance')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-section-appearance')),
        findsNothing);
    expect(find.byKey(const ValueKey('appearance-ui-font-size')),
        findsOneWidget);

    // One Back returns to the list; it must not leave settings. The back
    // gesture is consumed by the detail's PopScope (route stays mounted) and
    // the list comes back.
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(SettingsCenterPage), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-section-appearance')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('deep link to an explicit section opens the detail directly',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final prefs = await _prefs();
    addTearDown(prefs.dispose);
    final sessions = await _sessions();
    addTearDown(sessions.dispose);

    await _openSettings(tester, prefs, sessions,
        initialSection: 'appearance');

    expect(find.byKey(const ValueKey('settings-section-appearance')),
        findsNothing);
    expect(find.byKey(const ValueKey('appearance-ui-font-size')),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide layout never shows the compact section list',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final prefs = await _prefs();
    addTearDown(prefs.dispose);
    final sessions = await _sessions();
    addTearDown(sessions.dispose);

    await _openSettings(tester, prefs, sessions);

    expect(find.byKey(const ValueKey('settings-section-appearance')),
        findsNothing);
    expect(tester.takeException(), isNull);
  });
}
