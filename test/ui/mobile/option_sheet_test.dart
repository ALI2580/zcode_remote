import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/mobile/option_sheet.dart';
import 'package:zcode_remote/ui/theme.dart';

const _options = [
  MobileSheetOption(value: 'glm', label: 'GLM-5.3', subtitle: 'default'),
  MobileSheetOption(
      value: 'glm-air', label: 'GLM-5.3-Air', selected: true),
  MobileSheetOption(
      value: 'off', label: 'Offline voice', enabled: false),
];

Future<void> _openSheet(WidgetTester tester,
    {TextScaler scaler = TextScaler.noScaling,
    bool searchable = false}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: scaler),
          child: child!),
      home: Scaffold(
          body: Builder(builder: (context) => Center(
              child: TextButton(
                  onPressed: () => showMobileOptionSheet<String>(
                      context: context,
                      title: '选择模型',
                      options: _options,
                      searchable: searchable),
                  child: const Text('open')))))));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('sheet shows title, options, selection state and cancels',
      (tester) async {
    await _openSheet(tester);

    expect(find.text('选择模型'), findsOneWidget);
    expect(find.text('GLM-5.3'), findsOneWidget);
    expect(find.text('Offline voice'), findsOneWidget);
    // The pre-selected row renders the check glyph.
    expect(find.byIcon(Icons.check), findsNothing);
    expect(find.byType(MobileOptionSheet<String>), findsOneWidget);

    // Cancel closes the sheet and returns no value.
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.byType(MobileOptionSheet<String>), findsNothing);
  });

  testWidgets('tapping an option returns its value and closes one layer',
      (tester) async {
    String? picked;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: Scaffold(
            body: Builder(builder: (context) => Center(
                child: TextButton(
                    onPressed: () async {
                      picked = await showMobileOptionSheet<String>(
                          context: context,
                          title: '选择模型',
                          options: _options);
                    },
                    child: const Text('open')))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('GLM-5.3'));
    await tester.pumpAndSettle();
    expect(picked, 'glm');
    expect(find.byType(MobileOptionSheet<String>), findsNothing);
  });

  testWidgets('one Back dismisses only the sheet, not the page',
      (tester) async {
    await _openSheet(tester);
    expect(find.byType(MobileOptionSheet<String>), findsOneWidget);

    final handled = await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(handled, isTrue);
    expect(find.byType(MobileOptionSheet<String>), findsNothing);

    // The host page survived the sheet Back.
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('disabled options do not return values', (tester) async {
    String? picked;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: Scaffold(
            body: Builder(builder: (context) => Center(
                child: TextButton(
                    onPressed: () async {
                      picked = await showMobileOptionSheet<String>(
                          context: context,
                          title: '选择模型',
                          options: _options);
                    },
                    child: const Text('open')))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Offline voice'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(picked, isNull);
    expect(find.byType(MobileOptionSheet<String>), findsOneWidget);
  });

  testWidgets('search filters options and keeps the sheet usable',
      (tester) async {
    await _openSheet(tester, searchable: true);
    expect(find.text('GLM-5.3-Air'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'air');
    await tester.pumpAndSettle();
    expect(find.text('GLM-5.3'), findsNothing);
    expect(find.text('GLM-5.3-Air'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pumpAndSettle();
    expect(find.text('No matches'), findsOneWidget);
  });

  testWidgets('keyboard inset keeps close and cancel reachable',
      (tester) async {
    await _openSheet(tester, searchable: true);

    tester.view.viewInsets = const FakeViewPadding(bottom: 280);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();

    // Header close button and footer cancel remain on screen with the
    // keyboard up (280 logical px inset on an 844 tall viewport).
    final close = tester.getRect(find.byTooltip('Close').first);
    final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
    expect(close.height, greaterThanOrEqualTo(48));
    expect(close.bottom, lessThan(844));
    expect(cancel.top, greaterThanOrEqualTo(0));
    expect(cancel.bottom, lessThanOrEqualTo(844));

    tester.view.resetViewInsets();
    await tester.pumpAndSettle();
  });

  testWidgets('200% text scale renders without overflow', (tester) async {
    await _openSheet(tester, scaler: TextScaler.linear(2.0));
    expect(tester.takeException(), isNull);
    expect(find.text('选择模型'), findsOneWidget);
    expect(find.text('GLM-5.3'), findsOneWidget);

    final cancel = tester.getRect(find.widgetWithText(TextButton, 'Cancel'));
    expect(cancel.height, greaterThanOrEqualTo(48));
  });
}
