import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/mobile/touch_target.dart';
import 'package:zcode_remote/ui/shell/shell_layout.dart';
import 'package:zcode_remote/ui/theme.dart';

Widget _host(double width, {List<Widget> actions = const []}) =>
    MaterialApp(
        theme: ZInkTheme.light(),
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: width,
                    child: WorkspaceShellLayout(
                        title: 'T',
                        project: 'P',
                        sidebarCollapsed: true,
                        onSidebarCollapsed: (_) {},
                        sidebar: const SizedBox.shrink(),
                        conversation: const SizedBox.expand(),
                        onMore: () {},
                        actions: actions)))));

void main() {
  testWidgets(
      'compact header navigation and more buttons are full 48px targets',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(390));
    await tester.pumpAndSettle();

    final nav =
        tester.getRect(find.byTooltip('Projects and tasks').first);
    expect(nav.width, greaterThanOrEqualTo(48));
    expect(nav.height, greaterThanOrEqualTo(48));
    final more = tester.getRect(find.byTooltip('More').first);
    expect(more.width, greaterThanOrEqualTo(48));
    expect(more.height, greaterThanOrEqualTo(48));
    // Both are real MobileIconButtons on compact.
    expect(find.byType(MobileIconButton), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide header keeps the 40px desktop shell buttons',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(1180));
    await tester.pumpAndSettle();

    expect(find.byType(MobileIconButton), findsNothing);
    final nav =
        tester.getRect(find.byTooltip('Projects and tasks').first);
    expect(nav.width, closeTo(40, 0.1));
    expect(nav.height, closeTo(40, 0.1));
    expect(tester.takeException(), isNull);
  });
}
