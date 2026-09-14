import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/ui/appearance_settings_page.dart';
import 'package:zcode_remote/ui/app.dart';

void main() {
  testWidgets(
      'appearance controls expose official ranges and both theme selectors',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = ClientPreferences();
    addTearDown(prefs.dispose);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    for (final width in [344.0, 1180.0]) {
      tester.view.physicalSize = Size(width, 900);
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: AppearanceSettingsPage(preferences: prefs),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('appearance-ui-font-size')),
          findsOneWidget);
      expect(find.byKey(const ValueKey('appearance-code-font-size')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('appearance-ui-font-size')),
              matching: find.byType(TextField)),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('appearance-code-font-size')),
              matching: find.byType(TextField)),
          findsOneWidget);
      expect(find.byType(DropdownButton<String>), findsNWidgets(2));
      for (final dropdown in tester.widgetList<DropdownButton<String>>(
          find.byType(DropdownButton<String>))) {
        expect(dropdown.items, hasLength(10));
      }
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: find.byKey(const ValueKey('appearance-ui-font-size')),
                  matching: find.byType(TextField)))
              .controller!
              .text,
          '14');
      expect(
          tester
              .widget<TextField>(find.descendant(
                  of: find.byKey(const ValueKey('appearance-code-font-size')),
                  matching: find.byType(TextField)))
              .controller!
              .text,
          '12');
      expect(tester.takeException(), isNull);
    }

    await prefs.setUiFontSizePx(20);
    await prefs.setCodeFontSize(18);
    await prefs.setWrapLongLines(true);
    await tester.pump();
    expect(
        tester
            .widget<TextField>(find.descendant(
                of: find.byKey(const ValueKey('appearance-ui-font-size')),
                matching: find.byType(TextField)))
            .controller!
            .text,
        '20');
    expect(
        tester
            .widget<TextField>(find.descendant(
                of: find.byKey(const ValueKey('appearance-code-font-size')),
                matching: find.byType(TextField)))
            .controller!
            .text,
        '18');
    final wrap = find.byKey(const ValueKey('appearance-wrap-long-lines'),
        skipOffstage: false);
    await tester.ensureVisible(wrap);
    expect(
        tester
            .widget<Switch>(
                find.descendant(of: wrap, matching: find.byType(Switch)))
            .value,
        isTrue);
  });

  testWidgets(
      'appearance font inputs commit valid values and restore invalid edits',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = ClientPreferences();
    addTearDown(prefs.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppearanceSettingsPage(preferences: prefs)),
    ));
    await tester.pumpAndSettle();

    final uiInput = find.descendant(
        of: find.byKey(const ValueKey('appearance-ui-font-size')),
        matching: find.byType(TextField));
    await tester.tap(uiInput);
    await tester.enterText(uiInput, '17');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    await prefs.settled;
    expect(prefs.uiFontSizePx, 17);

    await tester.tap(uiInput);
    await tester.enterText(uiInput, '21');
    await tester.tap(find.text('Interface'));
    await tester.pumpAndSettle();
    expect(prefs.uiFontSizePx, 17);
    expect(tester.widget<TextField>(uiInput).controller!.text, '17');

    await tester.tap(uiInput);
    await tester.enterText(uiInput, '19');
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(prefs.uiFontSizePx, 17);
    expect(tester.widget<TextField>(uiInput).controller!.text, '17');

    await prefs.setUiFontSizePx(14);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(uiInput).controller!.text, '14');
  });
}
