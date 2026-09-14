import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/protocol/file_changes.dart';
import 'package:zcode_remote/ui/code_renderer.dart';

void main() {
  test('projects the frozen ten themes and CSS RGBA alpha correctly', () {
    expect(CodeThemeCatalog.all, hasLength(10));
    expect(CodeThemeCatalog.themeIds, hasLength(10));
    expect(
      CodeThemeCatalog.byId('github-light', Brightness.light)
          .insertedBackground,
      const Color(0x2234D058),
    );
    expect(
      CodeThemeCatalog.byId('min-dark', Brightness.dark).foreground,
      const Color(0xFFB392F0),
      reason: 'min-dark has no editor.foreground; use its unscoped token',
    );
    expect(
      CodeThemeCatalog.byId('catppuccin-mocha', Brightness.dark)
          .tokenColors['keyword'],
      const Color(0xFFCBA6F7),
    );
  });

  testWidgets('legacy labels migrate to stable IDs and px ranges stay official',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      ClientPreferences.storageKey: jsonEncode({
        'textScale': 1,
        'codeFontSize': 10,
        'lightCodeTheme': 'GitHub Light',
        'darkCodeTheme': 'github-dark',
      }),
    });
    final prefs = ClientPreferences();
    addTearDown(prefs.dispose);
    await prefs.load();

    expect(prefs.lightCodeThemeId, 'github-light');
    expect(prefs.darkCodeThemeId, 'github-dark');
    expect(prefs.lightCodeTheme, 'GitHub Light');
    expect(prefs.codeFontSize, 12);
    expect(prefs.uiFontSizePx, 14);

    await prefs.setUiFontSizePx(19);
    await prefs.setCodeFontSize(20);
    expect(prefs.uiFontSizePx, 19);
    expect(prefs.codeFontSize, 20);
    expect(prefs.textScale, closeTo(19 / 14, 0.0001));
  });

  testWidgets('code viewer preserves source text and uses the saved code px size',
      (tester) async {
    final theme = CodeThemeCatalog.byId('github-dark', Brightness.dark);
    const source = 'const first = 1;\r\n\r\nreturn first;';
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: CodeViewer(
          source: source,
          theme: theme,
          fontSize: 18,
          showLineNumbers: true,
          wrapLongLines: false,
        ),
      ),
    ));
    final code = find.byType(SelectableText).first;
    expect(tester.widget<SelectableText>(code).textSpan!.toPlainText(), source);
    final rich = tester.widget<RichText>(find.byType(RichText).first);
    expect(rich.text.style!.fontSize, 18);
    expect(find.text('1\n2\n3'), findsOneWidget);
  });

  testWidgets('markdown fenced code uses the shared renderer', (tester) async {
    final theme = CodeThemeCatalog.byId('github-light', Brightness.light);
    const source = 'Before\n\n```dart\nfinal markdownCode = 18;\n```\n\nAfter';
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.light(),
      home: Scaffold(
        body: SelectionArea(
          child: MarkdownBody(
            data: source,
            builders: {
              'pre': CodeMarkdownBuilder(
                theme: theme,
                fontSize: 18,
                showLineNumbers: true,
                wrapLongLines: true,
              ),
            },
          ),
        ),
      ),
    ));
    expect(find.textContaining('markdownCode'), findsOneWidget);
    expect(find.byType(CodeViewer), findsOneWidget);
  });

  testWidgets('wrapped code keeps a single selectable source paragraph',
      (tester) async {
    final theme = CodeThemeCatalog.byId('github-light', Brightness.light);
    const source = 'final veryLongName = "a value that wraps at narrow widths";\n\nend';
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(260, 480);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CodeViewer(
          source: source,
          theme: theme,
          fontSize: 18,
          showLineNumbers: true,
          wrapLongLines: true,
        ),
      ),
    ));
    expect(find.byType(CustomPaint), findsWidgets);
    expect(
      tester
          .widgetList<SelectableText>(find.byType(SelectableText))
          .any((widget) => widget.textSpan?.toPlainText() == source),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('diff keeps one selectable source and suppresses text-range numbers',
      (tester) async {
    final theme = CodeThemeCatalog.byId('github-light', Brightness.light);
    const patch = FileChangesHunk(
      oldStart: 4,
      oldLines: 1,
      newStart: 6,
      newLines: 1,
      lines: ['-before', '+after'],
    );
    const range = FileChangesHunk(
      oldStart: 0,
      oldLines: 1,
      newStart: 0,
      newLines: 1,
      lines: ['-before', '+after'],
      isTextRange: true,
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CodeDiffViewer(
          hunks: const [patch],
          theme: theme,
          fontSize: 18,
          showLineNumbers: true,
          wrapLongLines: false,
        ),
      ),
    ));
    final selectable = tester.widget<SelectableText>(
        find.byType(SelectableText));
    expect(selectable.textSpan!.toPlainText(), contains('-before\n+after'));
    expect(find.text('-before'), findsNothing,
        reason: 'The rendered diff remains one selectable paragraph.');

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: CodeDiffViewer(
          hunks: const [range],
          theme: theme,
          fontSize: 18,
          showLineNumbers: true,
          wrapLongLines: false,
        ),
      ),
    ));
    final rangeSelectable = tester.widget<SelectableText>(
        find.byType(SelectableText));
    expect(rangeSelectable.textSpan!.toPlainText(), isNot(contains('@@')));
    expect(rangeSelectable.textSpan!.toPlainText(), '-before\n+after');
  });
}
