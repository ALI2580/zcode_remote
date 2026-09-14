
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/code_renderer.dart';

/// M4-3 compact verification: on a phone-width column long code lines scroll
/// horizontally inside the code block only — the page itself must never
/// scroll sideways — and the wrap toggle removes the horizontal scroller.
void main() {
  const source = '''
final value = compute(input, 42); // a deliberately long trailing comment that
// keeps going far beyond a 390 logical pixel phone column so wrapping matters
final short = 1;
''';

  Widget host(double width, double height, {required bool wrap}) =>
      MaterialApp(
          theme: ThemeData(brightness: Brightness.dark),
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: width,
                      child: SingleChildScrollView(
                          child: CodeViewer(
                              source: source,
                              theme:
                                  CodeThemeCatalog.byId('github-dark', Brightness.dark),
                              fontSize: 13,
                              showLineNumbers: true,
                              wrapLongLines: wrap,
                              padding: const EdgeInsets.all(12)))))));

  bool hasHorizontalCodeScroller(WidgetTester tester) {
    final scrollers = tester.widgetList<Scrollable>(find.byType(Scrollable));
    return scrollers.any((s) => s.axisDirection == AxisDirection.right);
  }

  testWidgets('compact 390: unwrapped long code scrolls inside its block only',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(390, 844, wrap: false));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'page must not overflow horizontally with unwrapped code');
    expect(hasHorizontalCodeScroller(tester), isTrue,
        reason: 'the code block provides its own horizontal scroller');
  });

  testWidgets('compact 390: wrap toggle removes the horizontal scroller',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(host(390, 844, wrap: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(hasHorizontalCodeScroller(tester), isFalse,
        reason: 'wrapped code needs no horizontal scroller');
  });

  testWidgets('compact 320 at 200% text: unwrapped code still fits vertically',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(320, 568);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(2.0)),
        child: host(320, 568, wrap: false)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'no page-level overflow with large text and unwrapped code');
    expect(hasHorizontalCodeScroller(tester), isTrue);
  });
}
