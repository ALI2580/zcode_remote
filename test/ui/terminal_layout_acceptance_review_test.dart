import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/terminal.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/shell/shell_layout.dart';
import 'package:zcode_remote/ui/terminal_panel.dart';
import 'package:zcode_remote/ui/theme.dart';

import 'fake_workspace.dart';

void main() {
  testWidgets('review: actual chat and terminal fit a landscape keyboard',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge();
    final composers = ComposerStore();
    try {
      await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: WorkspaceShellLayout(
          title: 'Chat and terminal',
          project: 'Synthetic workspace',
          sidebar: const SizedBox.shrink(),
          sidebarCollapsed: true,
          onSidebarCollapsed: (_) {},
          conversation: ChatPage(
            session: bridge,
            scope: const {'workspaceIdentity': 'keyboard-review'},
            workspaceKey: 'keyboard-review',
            sessionId: 'task',
            title: 'Chat',
            embedded: true,
            composerStore: composers,
          ),
          panelOpen: false,
          bottomPanelOpen: true,
          bottomPanel: TerminalDrawer(
            client: TerminalClient(session: bridge),
            cwd: 'D:/Synthetic',
            visible: false,
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull,
          reason: 'Real chat content and Composer must fit with the terminal, not only an empty placeholder.');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      composers.dispose();
    }
  });

  testWidgets('review: native view keyboard insets are consumed exactly once',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    tester.view.viewInsets = const FakeViewPadding(bottom: 220);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: WorkspaceShellLayout(
        title: 'Native insets',
        project: 'Synthetic workspace',
        sidebar: const SizedBox.shrink(),
        sidebarCollapsed: true,
        onSidebarCollapsed: (_) {},
        conversation: const SizedBox.shrink(),
        panelOpen: false,
        bottomPanelOpen: true,
        bottomPanel: const ColoredBox(
          key: ValueKey('native-insets-terminal'),
          color: Colors.black,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final drawer =
        tester.getRect(find.byKey(const ValueKey('native-insets-terminal')));
    expect(drawer.height, greaterThan(0));
    expect(drawer.bottom, closeTo(170, 1),
        reason: 'Keyboard must not be subtracted a second time.');
  });

  testWidgets('review: terminal drawer fits landscape keyboard space',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.reset);
    final editor = TextEditingController(text: 'retained draft');
    addTearDown(editor.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(844, 390),
          viewInsets: EdgeInsets.only(bottom: 220),
          textScaler: TextScaler.linear(1.4),
        ),
        child: WorkspaceShellLayout(
          title: 'Terminal review',
          project: 'Synthetic workspace',
          sidebar: const SizedBox.shrink(),
          sidebarCollapsed: true,
          onSidebarCollapsed: (_) {},
          conversation: SingleChildScrollView(
            child: TextField(controller: editor),
          ),
          panelOpen: false,
          bottomPanelOpen: true,
          bottomPanel: const ColoredBox(
            key: ValueKey('review-terminal'),
            color: Colors.black,
            child: Center(child: Text('synthetic output')),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull,
        reason: 'The bottom drawer must fit the height left by the keyboard.');
    final drawer = tester.getRect(find.byKey(const ValueKey('review-terminal')));
    expect(drawer.top, greaterThanOrEqualTo(0));
    expect(drawer.bottom, lessThanOrEqualTo(170));
    expect(editor.text, 'retained draft');
  });
}
