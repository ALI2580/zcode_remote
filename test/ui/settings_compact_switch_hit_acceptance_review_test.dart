import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/ui/appearance_settings_page.dart';
import 'package:zcode_remote/ui/app.dart';

void main() {
  testWidgets('review: compact appearance switch retains its full tap target',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 1100);
    addTearDown(tester.view.reset);
    final preferences = ClientPreferences();
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: preferences,
          home: AppearanceSettingsPage(preferences: preferences)));
      await tester.pumpAndSettle();
      final row = find.byKey(const ValueKey('appearance-wrap-long-lines'));
      await tester.ensureVisible(row);
      await tester.pumpAndSettle();
      final control = find.descendant(of: row, matching: find.byType(Switch));
      expect(control, findsOneWidget);
      final original = preferences.wrapLongLines;
      // Compact paint is about 32 px wide; the surrounding 48 px target must
      // remain interactive instead of becoming inert transform padding.
      await tester.tapAt(tester.getCenter(control) + const Offset(21, 0));
      await tester.pumpAndSettle();
      expect(preferences.wrapLongLines, !original,
          reason: 'Shrinking the switch paint must not shrink its tap target.');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      preferences.dispose();
    }
  });
}
