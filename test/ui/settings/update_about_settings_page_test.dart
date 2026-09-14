import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zcode_remote/ui/settings/update_about_settings_page.dart';
import 'package:zcode_remote/update/update_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    updateChannelSettings.receiveBetaUpdates = false;
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [const UpdateAboutSettingsPage()]))));
    await tester.pumpAndSettle();
  }

  testWidgets('renders version, beta toggle and check entry without a check',
      (tester) async {
    await pumpPage(tester);

    expect(find.textContaining('ZcodeRemote'), findsOneWidget);
    expect(
        find.byWidgetPredicate((w) => w is Text &&
            (w.data == '接收 Beta 更新' || w.data == 'Receive beta updates')),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((w) =>
            w is Text && (w.data == '检查更新' || w.data == 'Check for updates')),
        findsOneWidget);

    final switchFinder = find.byType(Switch);
    expect(switchFinder, findsOneWidget);
    expect(tester.widget<Switch>(switchFinder).value, isFalse);
  });

  testWidgets('beta toggle persists through the channel settings singleton',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(updateChannelSettings.receiveBetaUpdates, isTrue);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('zcode_remote_receive_beta_updates'), isTrue);
  });
}
