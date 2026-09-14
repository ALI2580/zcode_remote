import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/mobile/touch_target.dart';
import 'package:zcode_remote/ui/theme.dart';

Widget _host({void Function()? onFirst, void Function()? onSecond}) =>
    MaterialApp(
        theme: ZInkTheme.light(),
        home: Scaffold(
            body: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
          MobileIconButton(
              icon: 'terminal', label: 'first', onPressed: onFirst),
          MobileIconButton(
              icon: 'x', label: 'second', onPressed: onSecond),
        ]))));

void main() {
  Future<void> usePhoneViewport(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pump();
  }

  testWidgets('compact hit boxes are at least 48x48 and do not overlap',
      (tester) async {
    await usePhoneViewport(tester);
    await tester.pumpWidget(_host());
    await tester.pumpAndSettle();

    final first = tester.getRect(find.byType(MobileIconButton).first);
    final second = tester.getRect(find.byType(MobileIconButton).at(1));
    expect(first.width, greaterThanOrEqualTo(48));
    expect(first.height, greaterThanOrEqualTo(48));
    expect(second.width, greaterThanOrEqualTo(48));
    expect(second.height, greaterThanOrEqualTo(48));
    final overlap = first.intersect(second);
    expect(overlap.width * overlap.height, 0,
        reason: 'adjacent targets must not overlap');
  });

  testWidgets('center and edge taps register, neighbours stay quiet',
      (tester) async {
    await usePhoneViewport(tester);
    var firstTaps = 0;
    var secondTaps = 0;
    await tester.pumpWidget(
        _host(onFirst: () => firstTaps++, onSecond: () => secondTaps++));
    await tester.pumpAndSettle();

    final firstRect = tester.getRect(find.byType(MobileIconButton).first);
    final secondRect = tester.getRect(find.byType(MobileIconButton).at(1));

    // Center of the first target.
    await tester.tapAt(firstRect.center);
    await tester.pump();
    expect(firstTaps, 1);
    expect(secondTaps, 0);

    // 1px inside the far edge still hits the first target.
    await tester.tapAt(firstRect.bottomRight - const Offset(1, 1));
    await tester.pump();
    expect(firstTaps, 2);
    expect(secondTaps, 0);

    // Center of the neighbour triggers only the neighbour.
    await tester.tapAt(secondRect.center);
    await tester.pump();
    expect(firstTaps, 2);
    expect(secondTaps, 1);

    // The 48px box is a real hit-test surface: a point inside the box but
    // far outside the 18px glyph still hits.
    await tester.tapAt(firstRect.centerRight - const Offset(4, 0));
    await tester.pump();
    expect(firstTaps, 3);
    expect(secondTaps, 1);
  });

  testWidgets('hit box stays 48 logical px at 200% text scale',
      (tester) async {
    await usePhoneViewport(tester);
    final row = Row(mainAxisSize: MainAxisSize.min, children: [
      MobileIconButton(icon: 'terminal', label: 'first', onPressed: () {}),
      MobileIconButton(icon: 'x', label: 'second', onPressed: () {}),
    ]);
    final page = MaterialApp(
        theme: ZInkTheme.light(),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(2.0)),
            child: child!),
        home: Scaffold(body: Center(child: row)));
    await tester.pumpWidget(
        MediaQuery(
            data:
                const MediaQueryData(textScaler: TextScaler.linear(2.0)),
            child: page));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final first = tester.getRect(find.byType(MobileIconButton).first);
    final second = tester.getRect(find.byType(MobileIconButton).at(1));
    expect(first.width, greaterThanOrEqualTo(48));
    expect(first.height, greaterThanOrEqualTo(48));
    expect(second.width, greaterThanOrEqualTo(48));
    expect(second.height, greaterThanOrEqualTo(48));
  });
}
