import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
// flutter_markdown_plus exposes this callback with markdown's Element type;
// markdown is intentionally kept transitive because no dependency changed.
// ignore: depend_on_referenced_packages
import 'package:markdown/markdown.dart' as md;

import '../protocol/file_changes.dart';
import '../state/client_preferences.dart';

/// A code theme projected from the frozen official catalogTree assets.
///
/// The source files use CSS hex colors (`#RRGGBBAA` is CSS RGBA).  They are
/// converted with [cssColor] instead of treating the trailing alpha as a
/// Flutter ARGB prefix.
class CodeThemeDefinition {
  const CodeThemeDefinition({
    required this.id,
    required this.label,
    required this.brightness,
    required this.colors,
    required this.tokenColors,
  });

  final String id;
  final String label;
  final Brightness brightness;
  final Map<String, Color> colors;
  final Map<String, Color> tokenColors;

  Color get background => colors['editor.background'] ??
      (brightness == Brightness.dark ? const Color(0xFF1E1E1E) : Colors.white);
  Color get foreground => colors['editor.foreground'] ??
      tokenColors[''] ??
      tokenColors['text'] ??
      (brightness == Brightness.dark
          ? const Color(0xFFE1E4E8)
          : const Color(0xFF24292E));
  Color get lineNumberForeground =>
      colors['editorLineNumber.foreground'] ?? foreground.withValues(alpha: .6);
  Color get insertedBackground =>
      colors['diffEditor.insertedTextBackground'] ??
      const Color(0x3334D058);
  Color get removedBackground =>
      colors['diffEditor.removedTextBackground'] ??
      const Color(0x33D73A49);

  Color colorFor(String scope) {
    if (tokenColors.containsKey(scope)) return tokenColors[scope]!;
    final parts = scope.split('.');
    for (var end = parts.length - 1; end > 0; end--) {
      final candidate = parts.take(end).join('.');
      final color = tokenColors[candidate];
      if (color != null) return color;
    }
    return foreground;
  }
}

Color cssColor(String value) {
  var hex = value.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
  if (hex.length == 6) hex = '$hex' 'ff';
  if (hex.length != 8) return const Color(0xFF000000);
  final value32 = int.tryParse(hex, radix: 16);
  if (value32 == null) return const Color(0xFF000000);
  final r = (value32 >> 24) & 0xff;
  final g = (value32 >> 16) & 0xff;
  final b = (value32 >> 8) & 0xff;
  final a = value32 & 0xff;
  return Color.fromARGB(a, r, g, b);
}

Map<String, Color> _colors(Map<String, String> values) =>
    values.map((key, value) => MapEntry(key, cssColor(value)));

Map<String, Color> _tokens(Map<String, String> values) =>
    values.map((key, value) => MapEntry(key, cssColor(value)));

CodeThemeDefinition _theme({
  required String id,
  required String label,
  required Brightness brightness,
  required Map<String, String> colors,
  required Map<String, String> tokens,
}) =>
    CodeThemeDefinition(
      id: id,
      label: label,
      brightness: brightness,
      colors: _colors(colors),
      tokenColors: _tokens(tokens),
    );

/// The ten IDs and labels captured from the official selector.  Each entry
/// carries real `editor.*` colors and representative `tokenColors` from its
/// frozen source file; no label-only aliases are used for rendering.
class CodeThemeCatalog {
  CodeThemeCatalog._();

  static const themeIds = <String>[
    'github-light',
    'github-dark',
    'vitesse-light',
    'vitesse-dark',
    'min-light',
    'min-dark',
    'github-light-high-contrast',
    'github-dark-high-contrast',
    'catppuccin-latte',
    'catppuccin-mocha',
  ];

  static final all = <CodeThemeDefinition>[
    _theme(
      id: 'github-light',
      label: 'GitHub Light',
      brightness: Brightness.light,
      colors: {
        'editor.background': '#fff',
        'editor.foreground': '#24292e',
        'editorLineNumber.foreground': '#1b1f234d',
        'diffEditor.insertedTextBackground': '#34d05822',
        'diffEditor.removedTextBackground': '#d73a4922',
      },
      tokens: {
        '': '#444d56',
        'comment': '#6a737d',
        'constant': '#005cc5',
        'entity': '#6f42c1',
        'entity.name.tag': '#22863a',
        'keyword': '#d73a49',
        'string': '#032f62',
        'support': '#005cc5',
        'variable': '#e36209',
        'markup.heading': '#005cc5',
        'markup.quote': '#22863a',
        'markup.inline.raw': '#005cc5',
        'markup.deleted': '#b31d28',
        'markup.inserted': '#22863a',
        'markup.changed': '#e36209',
      },
    ),
    _theme(
      id: 'github-dark',
      label: 'GitHub Dark',
      brightness: Brightness.dark,
      colors: {
        'editor.background': '#24292e',
        'editor.foreground': '#e1e4e8',
        'editorLineNumber.foreground': '#444d56',
        'diffEditor.insertedTextBackground': '#28a74530',
        'diffEditor.removedTextBackground': '#d73a4930',
      },
      tokens: {
        '': '#e1e4e8',
        'comment': '#6a737d',
        'constant': '#79b8ff',
        'entity': '#b392f0',
        'entity.name.tag': '#85e89d',
        'keyword': '#f97583',
        'string': '#9ecbff',
        'support': '#79b8ff',
        'variable': '#ffab70',
        'markup.heading': '#79b8ff',
        'markup.quote': '#85e89d',
        'markup.inline.raw': '#79b8ff',
        'markup.deleted': '#fdaeb7',
        'markup.inserted': '#85e89d',
        'markup.changed': '#ffab70',
      },
    ),
    _theme(
      id: 'vitesse-light',
      label: 'Vitesse Light',
      brightness: Brightness.light,
      colors: {
        'editor.background': '#ffffff',
        'editor.foreground': '#393a34',
        'editorLineNumber.foreground': '#393a3450',
        'diffEditor.insertedTextBackground': '#1c6b4830',
        'diffEditor.removedTextBackground': '#ab595940',
      },
      tokens: {
        '': '#393a34',
        'comment': '#a0ada0',
        'constant': '#a65e2b',
        'entity': '#59873a',
        'entity.name.tag': '#1e754f',
        'entity.name.function': '#59873a',
        'keyword': '#1e754f',
        'string': '#b56959',
        'support': '#998418',
        'property': '#998418',
        'variable': '#b07d48',
        'keyword.operator': '#ab5959',
        'markup.heading': '#1c6b48',
        'markup.quote': '#2e808f',
      },
    ),
    _theme(
      id: 'vitesse-dark',
      label: 'Vitesse Dark',
      brightness: Brightness.dark,
      colors: {
        'editor.background': '#121212',
        'editor.foreground': '#dbd7caee',
        'editorLineNumber.foreground': '#dedcd550',
        'diffEditor.insertedTextBackground': '#4d937550',
        'diffEditor.removedTextBackground': '#ab595950',
      },
      tokens: {
        '': '#dbd7caee',
        'comment': '#758575dd',
        'constant': '#c99076',
        'entity': '#80a665',
        'entity.name.tag': '#4d9375',
        'entity.name.function': '#80a665',
        'keyword': '#4d9375',
        'string': '#c98a7d',
        'support': '#b8a965',
        'property': '#b8a965',
        'variable': '#bd976a',
        'keyword.operator': '#cb7676',
        'markup.heading': '#4d9375',
        'markup.quote': '#5d99a9',
      },
    ),
    _theme(
      id: 'min-light',
      label: 'Minimal Light',
      brightness: Brightness.light,
      colors: {
        'editor.background': '#ffffff',
        'editor.foreground': '#212121',
        'editorLineNumber.foreground': '#CCC',
        'diffEditor.insertedTextBackground': '#b7e7a44b',
        'diffEditor.removedTextBackground': '#e597af52',
      },
      tokens: {
        '': '#212121',
        'keyword.operator': '#242628eff',
        'string': '#2b5581',
        'comment': '#c2c3c5',
        'constant.numeric': '#1976D2',
        'keyword': '#D32F2F',
        'variable.parameter.function': '#FF9800',
        'support.function': '#6f42c1',
        'entity.name.tag': '#22863a',
        'strong': '#6f42c1',
        'markup.underline.link': '#22863a',
      },
    ),
    _theme(
      id: 'min-dark',
      label: 'Minimal Dark',
      brightness: Brightness.dark,
      colors: {
        'editor.background': '#1f1f1f',
        'editorLineNumber.foreground': '#727272',
        'diffEditor.insertedTextBackground': '#3a632a4b',
        'diffEditor.removedTextBackground': '#88063852',
      },
      tokens: {
        '': '#b392f0',
        'support.function': '#b392f0',
        'string': '#9db1c5',
        'comment': '#6b737c',
        'constant.language': '#79b8ff',
        'constant.numeric': '#f8f8f8',
        'keyword': '#f97583',
        'variable.parameter.function': '#FF9800',
        'entity.name.type': '#b392f0',
        'entity.name.tag': '#ffab70',
        'strong': '#FF7A84',
      },
    ),
    _theme(
      id: 'github-light-high-contrast',
      label: 'GitHub HC Light',
      brightness: Brightness.light,
      colors: {
        'editor.background': '#ffffff',
        'editor.foreground': '#0e1116',
        'editorLineNumber.foreground': '#88929d',
        'diffEditor.insertedTextBackground': '#43c66380',
        'diffEditor.removedTextBackground': '#ee5a5d66',
      },
      tokens: {
        '': '#0e1116',
        'comment': '#66707b',
        'constant': '#023b95',
        'entity.name': '#702c00',
        'entity.name.tag': '#024c1a',
        'keyword': '#a0111f',
        'string': '#032563',
        'support': '#023b95',
        'variable': '#702c00',
        'markup.heading': '#023b95',
        'markup.quote': '#024c1a',
        'markup.deleted': '#6e011a',
        'markup.inserted': '#024c1a',
      },
    ),
    _theme(
      id: 'github-dark-high-contrast',
      label: 'GitHub HC Dark',
      brightness: Brightness.dark,
      colors: {
        'editor.background': '#0a0c10',
        'editor.foreground': '#f0f3f6',
        'editorLineNumber.foreground': '#9ea7b3',
        'diffEditor.insertedTextBackground': '#26cd4d4d',
        'diffEditor.removedTextBackground': '#ff94924d',
      },
      tokens: {
        '': '#f0f3f6',
        'comment': '#bdc4cc',
        'constant': '#91cbff',
        'entity.name': '#ffb757',
        'entity.name.tag': '#72f088',
        'keyword': '#ff9492',
        'string': '#addcff',
        'support': '#91cbff',
        'variable': '#ffb757',
        'markup.heading': '#91cbff',
        'markup.quote': '#72f088',
        'markup.deleted': '#ffb1af',
        'markup.inserted': '#72f088',
      },
    ),
    _theme(
      id: 'catppuccin-latte',
      label: 'Catppuccin Latte',
      brightness: Brightness.light,
      colors: {
        'editor.background': '#eff1f5',
        'editor.foreground': '#4c4f69',
        'editorLineNumber.foreground': '#8c8fa1',
        'diffEditor.insertedTextBackground': '#40a02b33',
        'diffEditor.removedTextBackground': '#d20f3933',
      },
      tokens: {
        '': '#4c4f69',
        'comment': '#7c7f93',
        'constant': '#fe640b',
        'entity.name': '#8839ef',
        'entity.name.tag': '#1e66f5',
        'keyword': '#8839ef',
        'string': '#40a02b',
        'support': '#1e66f5',
        'variable': '#e64553',
        'markup.heading': '#d20f39',
        'markup.quote': '#ea76cb',
        'markup.deleted': '#d20f39',
        'markup.inserted': '#40a02b',
      },
    ),
    _theme(
      id: 'catppuccin-mocha',
      label: 'Catppuccin Mocha',
      brightness: Brightness.dark,
      colors: {
        'editor.background': '#1e1e2e',
        'editor.foreground': '#cdd6f4',
        'editorLineNumber.foreground': '#7f849c',
        'diffEditor.insertedTextBackground': '#a6e3a133',
        'diffEditor.removedTextBackground': '#f38ba833',
      },
      tokens: {
        '': '#cdd6f4',
        'comment': '#9399b2',
        'constant': '#fab387',
        'entity.name': '#cba6f7',
        'entity.name.tag': '#89b4fa',
        'keyword': '#cba6f7',
        'string': '#a6e3a1',
        'support': '#89b4fa',
        'variable': '#eba0ac',
        'markup.heading': '#f38ba8',
        'markup.quote': '#f5c2e7',
        'markup.deleted': '#f38ba8',
        'markup.inserted': '#a6e3a1',
      },
    ),
  ];

  static CodeThemeDefinition byId(String? id, Brightness brightness) {
    final fallback = brightness == Brightness.dark ? 'github-dark' : 'github-light';
    return all.firstWhere(
      (theme) => theme.id == (id ?? fallback),
      orElse: () => all.firstWhere((theme) => theme.id == fallback),
    );
  }

  static CodeThemeDefinition fromContext(BuildContext context) {
    final prefs = ClientPreferencesScope.maybeOf(context);
    final brightness = Theme.of(context).brightness;
    final id = brightness == Brightness.dark
        ? prefs?.darkCodeThemeId
        : prefs?.lightCodeThemeId;
    return byId(id, brightness);
  }

  static String labelFor(String id) =>
      all.firstWhere((theme) => theme.id == id, orElse: () => all.first).label;
}

class CodeTokenSpan {
  const CodeTokenSpan(this.scope, this.start, this.end);
  final String scope;
  final int start;
  final int end;
}

/// A small deterministic TextMate-like projection using the official token
/// colors. It intentionally keeps the source untouched and only paints spans.
class CodeSyntaxHighlighter implements SyntaxHighlighter {
  CodeSyntaxHighlighter(this.theme, this.fontSize);

  final CodeThemeDefinition theme;
  final double fontSize;

  static final _tokens = RegExp(
      r'''(//[^\r\n]*|/\*[\s\S]*?\*/|#[^\r\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'|\b\d+(?:\.\d+)?\b|\b(?:true|false|null|void|class|extends|implements|import|export|from|return|if|else|for|while|switch|case|break|continue|new|final|const|var|let|function|async|await|try|catch|throw|with|as|in|is|def|fn|pub|struct|enum|interface|type|select|where|insert|update|delete)\b|\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\()|[{}()\[\];,.])''');

  @override
  TextSpan format(String source) {
    final base = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.5,
      color: theme.foreground,
    );
    final children = <TextSpan>[];
    var cursor = 0;
    for (final match in _tokens.allMatches(source)) {
      if (match.start > cursor) {
        children.add(TextSpan(text: source.substring(cursor, match.start)));
      }
      final value = match.group(0)!;
      children.add(TextSpan(
        text: value,
        style: TextStyle(color: theme.colorFor(_scopeFor(value, source, match))),
      ));
      cursor = match.end;
    }
    if (cursor < source.length) {
      children.add(TextSpan(text: source.substring(cursor)));
    }
    return TextSpan(style: base, children: children);
  }

  String _scopeFor(String value, String source, RegExpMatch match) {
    if (value.startsWith('//') ||
        value.startsWith('/*') ||
        value.startsWith('#')) {
      return 'comment';
    }
    if (value.startsWith('"') || value.startsWith("'")) return 'string';
    if (RegExp(r'^\d').hasMatch(value)) return 'constant.numeric';
    if (RegExp(r'^[A-Za-z_]').hasMatch(value)) {
      if (const {'true', 'false', 'null'}.contains(value)) {
        return 'constant';
      }
      if (RegExp(r'^(?:void|class|extends|implements|import|export|from|return|if|else|for|while|switch|case|break|continue|new|final|const|var|let|function|async|await|try|catch|throw|with|as|in|is|def|fn|pub|struct|enum|interface|type|select|where|insert|update|delete)$')
          .hasMatch(value)) {
        return 'keyword';
      }
      return 'entity.name.function';
    }
    return 'punctuation';
  }
}

/// Replaces flutter_markdown's default `<pre>` horizontal-only renderer with
/// the same preference-aware renderer used by file and diff views.
class CodeMarkdownBuilder extends MarkdownElementBuilder {
  CodeMarkdownBuilder({
    required this.theme,
    required this.fontSize,
    required this.showLineNumbers,
    required this.wrapLongLines,
  });

  final CodeThemeDefinition theme;
  final double fontSize;
  final bool showLineNumbers;
  final bool wrapLongLines;

  @override
  bool isBlockElement() => true;

  @override
  Widget? visitElementAfterWithContext(
    BuildContext context,
    md.Element element,
    TextStyle? preferredStyle,
    TextStyle? parentStyle,
  ) {
    return CodeViewer(
      source: element.textContent,
      theme: theme,
      fontSize: fontSize,
      showLineNumbers: showLineNumbers,
      wrapLongLines: wrapLongLines,
      selectionEnabled: false,
    );
  }
}

class CodeViewer extends StatelessWidget {
  const CodeViewer({
    super.key,
    required this.source,
    required this.theme,
    required this.fontSize,
    required this.showLineNumbers,
    required this.wrapLongLines,
    this.selectionEnabled = true,
    this.padding = const EdgeInsets.all(12),
  });

  final String source;
  final CodeThemeDefinition theme;
  final double fontSize;
  final bool showLineNumbers;
  final bool wrapLongLines;
  final bool selectionEnabled;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final child = ColoredBox(
      color: theme.background,
      child: Padding(padding: padding, child: _body(context)),
    );
    // UI preference scaling must not multiply code a second time. The system
    // accessibility scaler still applies here, including nonlinear scaling.
    final systemMedia = media.copyWith(
      textScaler: ClientTextScaler.systemScaler(media.textScaler),
    );
    return MediaQuery(
      data: systemMedia,
      child: selectionEnabled ? SelectionArea(child: child) : child,
    );
  }

  Widget _body(BuildContext context) {
    final highlighter = CodeSyntaxHighlighter(theme, fontSize);
    final base = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.5,
      color: theme.foreground,
    );
    final code = selectionEnabled
        ? SelectableText.rich(
            highlighter.format(source),
            maxLines: null,
            textAlign: TextAlign.left,
          )
        : Text.rich(
            highlighter.format(source),
            softWrap: true,
            textAlign: TextAlign.left,
          );
    final lineCount = source.split('\n').length;
    final numberText = List<String>.generate(
      lineCount,
      (index) => '${index + 1}${index + 1 == lineCount ? '' : '\n'}',
    ).join();
    final numbers = showLineNumbers
        ? SelectionContainer.disabled(
            child: SizedBox(
              width: _lineNumberWidth(lineCount),
              child: Text(
                numberText,
                textAlign: TextAlign.right,
                style: base.copyWith(color: theme.lineNumberForeground),
              ),
            ),
          )
        : const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      if (wrapLongLines) {
        final numberWidth = _lineNumberWidth(lineCount);
        final contentWidth = (constraints.maxWidth -
                numberWidth -
                (showLineNumbers ? 12 : 0))
            .clamp(1.0, double.infinity)
            .toDouble();
        final wrappedCode = Padding(
          padding: EdgeInsets.only(
            left: showLineNumbers ? numberWidth + 12 : 0,
          ),
          child: code,
        );
        return SizedBox(
          width: constraints.maxWidth,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              wrappedCode,
              if (showLineNumbers)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: numberWidth,
                  child: CustomPaint(
                    painter: _LineNumberPainter(
                      source: source,
                      span: highlighter.format(source),
                      style: base,
                      width: contentWidth,
                      color: theme.lineNumberForeground,
                      textScaler: MediaQuery.textScalerOf(context),
                    ),
                  ),
                ),
            ],
          ),
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicWidth(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              numbers,
              if (showLineNumbers) const SizedBox(width: 12),
              code,
            ],
          ),
        ),
      );
    });
  }

  double _lineNumberWidth(int lineCount) =>
      (lineCount.toString().length * fontSize * .62).clamp(24, 72).toDouble();
}

class CodeDiffViewer extends StatelessWidget {
  const CodeDiffViewer({
    super.key,
    required this.hunks,
    required this.theme,
    required this.fontSize,
    required this.showLineNumbers,
    required this.wrapLongLines,
    this.showHeaders = true,
  });

  final List<FileChangesHunk> hunks;
  final CodeThemeDefinition theme;
  final double fontSize;
  final bool showLineNumbers;
  final bool wrapLongLines;
  final bool showHeaders;

  @override
  Widget build(BuildContext context) {
    final document = _buildDocument();
    final base = TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize,
      height: 1.5,
      color: theme.foreground,
    );
    final code = SelectableText.rich(
      TextSpan(style: base, children: document.spans),
      maxLines: null,
    );
    final gutterWidth = _gutterWidth(document.numberPairs);
    final media = MediaQuery.of(context);
    final body = LayoutBuilder(builder: (context, constraints) {
      if (wrapLongLines) {
        final contentWidth = (constraints.maxWidth -
                gutterWidth -
                (showLineNumbers ? 12 : 0))
            .clamp(1.0, double.infinity)
            .toDouble();
        return SizedBox(
          width: constraints.maxWidth,
          child: Stack(
            fit: StackFit.passthrough,
            children: [
              Padding(
                padding: EdgeInsets.only(
                  left: showLineNumbers ? gutterWidth + 12 : 0,
                ),
                child: code,
              ),
              if (showLineNumbers)
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: gutterWidth,
                  child: CustomPaint(
                    painter: _DiffLineNumberPainter(
                      source: document.source,
                      numberPairs: document.numberPairs,
                      style: base,
                      width: contentWidth,
                      color: theme.lineNumberForeground,
                      textScaler: MediaQuery.textScalerOf(context),
                    ),
                  ),
                ),
            ],
          ),
        );
      }
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: IntrinsicWidth(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (showLineNumbers)
                SelectionContainer.disabled(
                  child: SizedBox(
                    width: gutterWidth,
                    child: Text(
                      document.numberText,
                      textAlign: TextAlign.right,
                      style: base.copyWith(color: theme.lineNumberForeground),
                    ),
                  ),
                ),
              if (showLineNumbers) const SizedBox(width: 12),
              code,
            ],
          ),
        ),
      );
    });
    return MediaQuery(
      data: media.copyWith(
        textScaler: ClientTextScaler.systemScaler(media.textScaler),
      ),
      child: ColoredBox(
        color: theme.background,
        child: SelectionArea(child: body),
      ),
    );
  }

  _DiffRenderDocument _buildDocument() {
    final spans = <TextSpan>[];
    final pairs = <({int? oldLine, int? newLine})?>[];
    final sourceLines = <String>[];

    void append(
      String text,
      TextStyle style, {
      ({int? oldLine, int? newLine})? pair,
    }) {
      spans.add(TextSpan(text: text, style: style));
      sourceLines.add(text);
      pairs.add(pair);
    }

    for (final hunk in hunks) {
      if (hunk.rangeLabel != null) {
        append(
          hunk.rangeLabel!,
          TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: theme.colorFor('meta.diff.range'),
          ),
        );
      }
      if (showHeaders && !hunk.isTextRange) {
        append(
          '@@ -${hunk.oldStart},${hunk.oldLines} '
          '+${hunk.newStart},${hunk.newLines} @@',
          TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize,
            height: 1.5,
            fontWeight: FontWeight.w600,
            color: theme.colorFor('meta.diff.range'),
          ),
        );
      }
      var oldLine = hunk.oldStart;
      var newLine = hunk.newStart;
      for (final line in hunk.lines) {
        final isRemoved = line.startsWith('-');
        final isAdded = line.startsWith('+');
        final isContext = line.startsWith(' ');
        final pair = hunk.isTextRange
            ? null
            : (
                oldLine: isRemoved || isContext ? oldLine++ : null,
                newLine: isAdded || isContext ? newLine++ : null,
              );
        final isMarker = line.startsWith('\\');
        final lineColor = isRemoved
            ? theme.colorFor('markup.deleted')
            : isAdded
                ? theme.colorFor('markup.inserted')
                : isMarker
                    ? theme.lineNumberForeground
                    : theme.foreground;
        append(
          line,
          TextStyle(
            fontFamily: 'monospace',
            fontSize: fontSize,
            height: 1.5,
            color: lineColor,
            backgroundColor: isRemoved
                ? theme.removedBackground
                : isAdded
                    ? theme.insertedBackground
                    : null,
          ),
          pair: pair,
        );
      }
    }
    return _DiffRenderDocument(
      source: sourceLines.join('\n'),
      spans: [
        for (var index = 0; index < sourceLines.length; index++)
          TextSpan(
            text:
                '${sourceLines[index]}${index + 1 == sourceLines.length ? '' : '\n'}',
            style: spans[index].style,
          ),
      ],
      numberPairs: pairs,
    );
  }

  double _gutterWidth(List<({int? oldLine, int? newLine})?> pairs) {
    var maxDigits = 1;
    for (final pair in pairs) {
      for (final value in [pair?.oldLine, pair?.newLine]) {
        if (value != null) {
          maxDigits = maxDigits > value.toString().length
              ? maxDigits
              : value.toString().length;
        }
      }
    }
    return (maxDigits * fontSize * .62 * 2).clamp(76, 112).toDouble();
  }
}

class _DiffRenderDocument {
  const _DiffRenderDocument({
    required this.source,
    required this.spans,
    required this.numberPairs,
  });

  final String source;
  final List<TextSpan> spans;
  final List<({int? oldLine, int? newLine})?> numberPairs;

  String get numberText => numberPairs
      .map((pair) => '${pair?.oldLine ?? ''}    ${pair?.newLine ?? ''}')
      .join('\n');
}

class _DiffLineNumberPainter extends CustomPainter {
  const _DiffLineNumberPainter({
    required this.source,
    required this.numberPairs,
    required this.style,
    required this.width,
    required this.color,
    required this.textScaler,
  });

  final String source;
  final List<({int? oldLine, int? newLine})?> numberPairs;
  final TextStyle style;
  final double width;
  final Color color;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final paragraph = TextPainter(
      text: TextSpan(style: style, text: source),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: width);
    final metrics = paragraph.computeLineMetrics();
    final starts = <int>[0];
    for (var i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == 10) starts.add(i + 1);
    }
    for (var index = 0; index < starts.length; index++) {
      final pair = index < numberPairs.length ? numberPairs[index] : null;
      if (pair == null) continue;
      final caret = paragraph.getOffsetForCaret(
        TextPosition(offset: starts[index].clamp(0, source.length).toInt()),
        Rect.zero,
      );
      final metric = _nearestMetric(metrics, caret.dy);
      if (metric == null) continue;
      _paintNumber(
        canvas,
        '${pair.oldLine ?? ''}',
        size.width / 2,
        metric.baseline,
      );
      _paintNumber(
        canvas,
        '${pair.newLine ?? ''}',
        size.width,
        metric.baseline,
      );
    }
  }

  void _paintNumber(Canvas canvas, String value, double right, double baseline) {
    final number = TextPainter(
      text: TextSpan(text: value, style: style.copyWith(color: color)),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: right);
    final numberBaseline = number.computeLineMetrics().first.baseline;
    number.paint(canvas, Offset(right - number.width, baseline - numberBaseline));
  }

  LineMetrics? _nearestMetric(List<LineMetrics> metrics, double top) {
    if (metrics.isEmpty) return null;
    var best = metrics.first;
    var distance = (best.baseline - best.ascent - top).abs();
    for (final metric in metrics.skip(1)) {
      final candidateDistance = (metric.baseline - metric.ascent - top).abs();
      if (candidateDistance < distance) {
        best = metric;
        distance = candidateDistance;
      }
    }
    return best;
  }

  @override
  bool shouldRepaint(covariant _DiffLineNumberPainter oldDelegate) =>
      oldDelegate.source != source ||
      oldDelegate.width != width ||
      oldDelegate.style != style ||
      oldDelegate.color != color ||
      oldDelegate.textScaler != textScaler ||
      oldDelegate.numberPairs != numberPairs;
}


/// Paints one number for each logical source line while the selectable source
/// remains a single paragraph. TextPainter metrics account for wrapped visual
/// lines, so a wrapped line does not push the following source number upward.
class _LineNumberPainter extends CustomPainter {
  const _LineNumberPainter({
    required this.source,
    required this.span,
    required this.style,
    required this.width,
    required this.color,
    required this.textScaler,
  });

  final String source;
  final TextSpan span;
  final TextStyle style;
  final double width;
  final Color color;
  final TextScaler textScaler;

  @override
  void paint(Canvas canvas, Size size) {
    final paragraph = TextPainter(
      text: span,
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout(maxWidth: width);
    final metrics = paragraph.computeLineMetrics();
    final starts = <int>[0];
    for (var i = 0; i < source.length; i++) {
      if (source.codeUnitAt(i) == 10 && i + 1 <= source.length) {
        starts.add(i + 1);
      }
    }
    for (var logicalLine = 0; logicalLine < starts.length; logicalLine++) {
      final start = starts[logicalLine].clamp(0, source.length).toInt();
      final caret = paragraph.getOffsetForCaret(
        TextPosition(offset: start),
        Rect.zero,
      );
      final metric = _nearestMetric(metrics, caret.dy);
      if (metric == null) continue;
      final number = TextPainter(
        text: TextSpan(
          text: '${logicalLine + 1}',
          style: style.copyWith(color: color),
        ),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout(maxWidth: size.width);
      final numberBaseline = number.computeLineMetrics().first.baseline;
      number.paint(
        canvas,
        Offset(size.width - number.width, metric.baseline - numberBaseline),
      );
    }
  }

  LineMetrics? _nearestMetric(List<LineMetrics> metrics, double top) {
    if (metrics.isEmpty) return null;
    var best = metrics.first;
    var distance = (best.baseline - best.ascent - top).abs();
    for (final metric in metrics.skip(1)) {
      final candidateDistance =
          (metric.baseline - metric.ascent - top).abs();
      if (candidateDistance < distance) {
        best = metric;
        distance = candidateDistance;
      }
    }
    return best;
  }

  @override
  bool shouldRepaint(covariant _LineNumberPainter oldDelegate) =>
      oldDelegate.source != source ||
      oldDelegate.width != width ||
      oldDelegate.style != style ||
      oldDelegate.color != color ||
      oldDelegate.textScaler != textScaler;
}
