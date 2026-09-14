import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/remote_settings.dart';
import 'package:zcode_remote/ui/settings/general_settings_page.dart';

import '../fake_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // The real host embeds section pages inside the settings ListView, so
  // mirror the unbounded-height constraints here.
  Widget host(Widget child) => MaterialApp(
      home: Scaffold(body: ListView(children: [child])));

  testWidgets('renders language preference and remote-unavailable placeholder',
      (tester) async {
    final prefs = ClientPreferences();
    addTearDown(prefs.dispose);
    await tester.pumpWidget(host(GeneralSettingsPage(
      preferences: prefs,
      remoteSettings: null,
      remoteMonitor: null,
    )));
    await tester.pumpAndSettle();

    expect(find.byType(DropdownButton<String>), findsOneWidget);
    expect(find.text('No remote workspace connected. Remote settings are '
        'unavailable.'), findsOneWidget);
    // No remote cards render without a controller.
    expect(find.text('Inherit system terminal profile'), findsNothing);
  });

  testWidgets('renders the official terminal/proxy/behavior/archive cards',
      (tester) async {
    final prefs = ClientPreferences();
    final controller = RemoteSettingsController(
        session: FakeBridge(), scopeKey: 'general-page');
    addTearDown(prefs.dispose);
    addTearDown(controller.dispose);
    await tester.pumpWidget(host(GeneralSettingsPage(
      preferences: prefs,
      remoteSettings: controller,
      remoteMonitor: null,
    )));
    await tester.pumpAndSettle();

    expect(find.text('Inherit system terminal profile'), findsOneWidget);
    expect(find.text('Enhanced Find and Grep'), findsOneWidget);
    expect(find.text('HTTP proxy'), findsOneWidget);
    expect(find.text('Interaction behavior'), findsOneWidget);
    expect(find.text('Show reasoning'), findsOneWidget);
    expect(find.text('Auto-archive old tasks'), findsOneWidget);
    expect(find.text('Archive retention'), findsOneWidget);
    // The win32-only integrated shell select stays hidden without a
    // win32 system-info answer.
    expect(find.text('Integrated terminal shell'), findsNothing);
  });
}
