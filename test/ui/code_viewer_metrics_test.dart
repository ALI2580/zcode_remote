import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/ui/code_renderer.dart';

/// P3-code measurement harness (references/optimization/
/// performance-todolist.md): CodeViewer reformats the full source on every
/// parent rebuild (twice with wrapLongLines, plus unconditional line-number
/// string building). Deterministic counters + wall clock over a fixed
/// 40-frame rebuild sequence.
void main() {
  test('format algorithmic cost (baseline data)', () {
    for (final n in [100, 1000, 10000]) {
      final line = 'final value_$n = compute(input, 42); // 注释行 with 中文 '
          'and a fairly long trailing segment to exercise wrap behavior';
      final source = List<String>.generate(n, (_) => line).join('\n');
      final theme = CodeThemeCatalog.byId('github-dark', Brightness.dark);
      final highlighter = CodeSyntaxHighlighter(theme, 13);
      for (var i = 0; i < 3; i++) {
        highlighter.format(source);
      }
      final sw = Stopwatch()..start();
      const rounds = 20;
      for (var i = 0; i < rounds; i++) {
        highlighter.format(source);
      }
      sw.stop();
      // ignore: avoid_print
      print('P3CODE format lines=$n '
          'total_us=${sw.elapsedMicroseconds} '
          'per_call_us=${(sw.elapsedMicroseconds / rounds).toStringAsFixed(1)}');
    }
  });

  Widget host(CodeThemeDefinition theme, double fontSize, String source,
          {required bool wrap}) =>
      MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: CodeViewer(
        source: source,
        theme: theme,
        fontSize: fontSize,
        showLineNumbers: true,
        wrapLongLines: wrap,
        padding: const EdgeInsets.all(12),
      ))));

  Future<void> runRebuildFrames(
    WidgetTester tester, {
    required int lines,
    required bool wrap,
  }) async {
    final prefs = ClientPreferences();
    addTearDown(prefs.dispose);
    final line = 'final value = compute(input, 42); // 注释行 with 中文 '
        'and a fairly long trailing segment to exercise wrap behavior';
    final source = List<String>.generate(lines, (_) => line).join('\n');
    final theme = CodeThemeCatalog.byId('github-dark', Brightness.dark);
    await tester.pumpWidget(host(theme, 13, source, wrap: wrap));
    await tester.pumpAndSettle();
    final baseline = codeFormatCalls;
    final sw = Stopwatch()..start();
    for (var f = 0; f < 40; f++) {
      // Parent rebuild with identical source: the streaming case where the
      // conversation frame rebuilds visible tool cards but their code content
      // did not change.
      await tester.pumpWidget(host(theme, 13, source, wrap: wrap));
      await tester.pump();
    }
    sw.stop();
    await tester.pumpAndSettle();
    // ignore: avoid_print
    print('P3CODE rebuild lines=$lines wrap=$wrap frames=40 '
        'wallUs=${sw.elapsedMicroseconds} '
        'formatCalls=${codeFormatCalls - baseline}');
  }

  testWidgets('metric: 40 parent rebuilds, wrap off', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await runRebuildFrames(tester, lines: 1000, wrap: false);
  });

  testWidgets('metric: 40 parent rebuilds, wrap on', (tester) async {
    SharedPreferences.setMockInitialValues({});
    await runRebuildFrames(tester, lines: 1000, wrap: true);
  });
}
