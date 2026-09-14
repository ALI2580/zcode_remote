import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/shell/shell_layout.dart';
import 'package:zcode_remote/ui/theme.dart';

Widget _host({required bool fullHeight}) => MaterialApp(
    theme: ZInkTheme.light(),
    home: Scaffold(
        body: Center(
            child: SizedBox(
                width: 390,
                child: WorkspaceShellLayout(
                    title: 'T',
                    project: 'P',
                    sidebarCollapsed: true,
                    onSidebarCollapsed: (_) {},
                    sidebar: const SizedBox.shrink(),
                    conversation: const SizedBox.expand(),
                    bottomPanelOpen: true,
                    bottomPanelFullHeight: fullHeight,
                    bottomPanel: Container(
                        key: const ValueKey('terminal-max-panel'),
                        color: Colors.black))))));

void main() {
  testWidgets('terminal drawer defaults to the official 320px height',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(fullHeight: false));
    await tester.pumpAndSettle();

    final drawer =
        tester.getRect(find.byKey(const ValueKey('terminal-max-panel')));
    expect(drawer.height, closeTo(320, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('full-height flag stretches the drawer without a rebuild of PTY identity',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(fullHeight: true));
    await tester.pumpAndSettle();

    final drawer =
        tester.getRect(find.byKey(const ValueKey('terminal-max-panel')));
    // The drawer spans the whole body (minus the header row height that the
    // shell reserves for the title bar).
    expect(drawer.top, closeTo(49, 0.5));
    expect(drawer.bottom, closeTo(844, 0.5));
    expect(drawer.height, closeTo(795, 0.5));
    expect(drawer.height, greaterThan(600));
    expect(tester.takeException(), isNull);
  });
}
