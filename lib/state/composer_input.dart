import 'package:flutter/material.dart';

String _labelEscape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('[', r'\[').replaceAll(']', r'\]');
String _targetEscape(String value) =>
    value.replaceAll(r'\', r'\\').replaceAll('>', r'\>');
String _target(String value) => value.startsWith('/') ||
        value.startsWith('./') ||
        value.startsWith('../') ||
        value.startsWith('#') ||
        RegExp(r'^[a-zA-Z][a-zA-Z\d+.-]*:').hasMatch(value)
    ? value
    : './$value';

class ComposerReference {
  const ComposerReference(
      {required this.id,
      required this.category,
      required this.label,
      required this.value,
      this.description = '',
      this.scope = '',
      this.keywords = const [],
      this.directory = false,
      this.disabled = false});
  final String id, category, label, value, description, scope;
  final List<String> keywords;
  final bool directory, disabled;
  String get display => '${switch (category) {
        'skills' => r'$',
        'sessions' => '#',
        'commands' => '/',
        _ => '@'
      }}$label';
  String get markdown => switch (category) {
        'files' =>
          '[${_labelEscape(label)}](${_targetEscape(_target(directory ? '${value.replaceAll(RegExp(r'[\\/]+$'), '')}/' : value))})',
        'skills' => value.isEmpty
            ? '\$$label'
            : '[${_labelEscape('\$$label')}](${_targetEscape(_target(value))})',
        'sessions' => label.isEmpty || label == value
            ? '#$value'
            : '[${_labelEscape('#$label')}](#${_targetEscape(value)})',
        'plugins' =>
          '[${_labelEscape('@$label')}](plugin://${_targetEscape(value)})',
        'commands' => '/$value',
        _ => '@$label',
      };
}

class _InputReference {
  const _InputReference(this.start, this.end, this.reference);
  final int start, end;
  final ComposerReference reference;
  _InputReference shift(int delta) =>
      _InputReference(start + delta, end + delta, reference);
}

class ComposerInputSnapshot {
  const ComposerInputSnapshot(this.value, this._references);
  final TextEditingValue value;
  final List<_InputReference> _references;
  Map<String, dynamic> toJson() => {
        'text': value.text,
        'selection': [value.selection.baseOffset, value.selection.extentOffset],
        'references': [
          for (final token in _references)
            {
              'start': token.start,
              'end': token.end,
              'id': token.reference.id,
              'category': token.reference.category,
              'label': token.reference.label,
              'value': token.reference.value,
              'description': token.reference.description,
              'directory': token.reference.directory,
              'scope': token.reference.scope,
              'keywords': token.reference.keywords,
            }
        ],
      };
  static ComposerInputSnapshot? fromJson(Object? raw) {
    if (raw is! Map || raw['text'] is! String) return null;
    final text = raw['text'] as String;
    var selection = TextSelection.collapsed(offset: text.length);
    if (raw['selection'] case final List values
        when values.length == 2 && values.every((v) => v is int)) {
      selection = TextSelection(
          baseOffset: (values[0] as int).clamp(0, text.length),
          extentOffset: (values[1] as int).clamp(0, text.length));
    }
    final tokens = <_InputReference>[];
    if (raw['references'] case final List entries) {
      for (final item in entries.whereType<Map>()) {
        final start = item['start'], end = item['end'];
        if (start is! int ||
            end is! int ||
            start < 0 ||
            end <= start ||
            end > text.length ||
            tokens.isNotEmpty && start < tokens.last.end) {
          continue;
        }
        if (['id', 'category', 'label', 'value']
            .any((key) => item[key] is! String)) {
          continue;
        }
        final reference = ComposerReference(
            id: item['id'],
            category: item['category'],
            label: item['label'],
            value: item['value'],
            description:
                item['description'] is String ? item['description'] : '',
            scope: item['scope'] is String ? item['scope'] : '',
            directory: item['directory'] == true,
            keywords: item['keywords'] is List
                ? (item['keywords'] as List).whereType<String>().toList()
                : const []);
        if (text.substring(start, end) != reference.display) continue;
        tokens.add(_InputReference(start, end, reference));
      }
    }
    return ComposerInputSnapshot(
        TextEditingValue(text: text, selection: selection), tokens);
  }
}

/// Visible mention labels remain atomic; wire text uses the official Markdown
/// encoding. Offsets always refer to the visible editor text, including IME.
class ComposerInput extends TextEditingController {
  final _references = <_InputReference>[];
  bool _inserting = false;
  ComposerInputSnapshot get snapshot =>
      ComposerInputSnapshot(value, List.of(_references));
  void restore(ComposerInputSnapshot snapshot) {
    _references
      ..clear()
      ..addAll(snapshot._references);
    _inserting = true;
    try {
      value = snapshot.value;
    } finally {
      _inserting = false;
    }
  }

  String get markdown {
    final out = StringBuffer();
    var offset = 0;
    for (final token in _references) {
      out.write(text.substring(offset, token.start));
      out.write(token.reference.markdown);
      offset = token.end;
    }
    out.write(text.substring(offset));
    return out.toString();
  }

  int get referenceCount => _references.length;
  int get contextReferenceCount =>
      _references.where((e) => e.reference.category != 'commands').length;
  void insertReference(TextRange range, ComposerReference reference) {
    if (reference.disabled || !range.isValid || range.end > text.length) return;
    final label = reference.display;
    final oldTokens = List<_InputReference>.from(_references);
    final oldText = text;
    final oldValue = value;
    final delta = label.length + 1 - (range.end - range.start);
    _references.clear();
    for (final token in oldTokens) {
      if (token.end <= range.start) {
        _references.add(token);
      } else if (token.start >= range.end) {
        _references.add(token.shift(delta));
      }
    }
    _references.add(
        _InputReference(range.start, range.start + label.length, reference));
    _references.sort((a, b) => a.start.compareTo(b.start));
    _inserting = true;
    try {
      value = TextEditingValue(
          text: oldText.replaceRange(range.start, range.end, '$label '),
          selection:
              TextSelection.collapsed(offset: range.start + label.length + 1));
    } finally {
      _inserting = false;
    }
    if (value == oldValue) notifyListeners();
  }

  @override
  set value(TextEditingValue next) {
    final old = super.value;
    if (!_inserting && old.text != next.text && _references.isNotEmpty) {
      var start = 0;
      while (start < old.text.length &&
          start < next.text.length &&
          old.text[start] == next.text[start]) {
        start++;
      }
      var oldEnd = old.text.length, newEnd = next.text.length;
      while (oldEnd > start &&
          newEnd > start &&
          old.text[oldEnd - 1] == next.text[newEnd - 1]) {
        oldEnd--;
        newEnd--;
      }
      final replacement = next.text.substring(start, newEnd);
      final originalStart = start, originalEnd = oldEnd;
      for (final token in _references) {
        final overlaps = start == oldEnd
            ? start > token.start && start < token.end
            : start < token.end && oldEnd > token.start;
        if (overlaps) {
          if (start > token.start) start = token.start;
          if (oldEnd < token.end) oldEnd = token.end;
        }
      }
      if (start != originalStart || oldEnd != originalEnd) {
        next = TextEditingValue(
            text: old.text.replaceRange(start, oldEnd, replacement),
            selection:
                TextSelection.collapsed(offset: start + replacement.length));
      }
      final delta = next.text.length - old.text.length;
      final updated = <_InputReference>[];
      for (final token in _references) {
        if (token.end <= start) {
          updated.add(token);
        } else if (token.start >= oldEnd) {
          updated.add(token.shift(delta));
        }
      }
      _references
        ..clear()
        ..addAll(updated);
    }
    super.value = next;
  }

  @override
  TextSpan buildTextSpan(
      {required BuildContext context,
      TextStyle? style,
      required bool withComposing}) {
    if (_references.isEmpty) {
      return super.buildTextSpan(
          context: context, style: style, withComposing: withComposing);
    }
    final parts = <InlineSpan>[];
    final scheme = Theme.of(context).colorScheme;
    final composing = value.composing;
    final showComposing = withComposing &&
        composing.isValid &&
        !composing.isCollapsed &&
        composing.end <= text.length;
    final boundaries = {
      0,
      text.length,
      for (final token in _references) ...[token.start, token.end],
      if (showComposing) ...[composing.start, composing.end],
    }.toList()
      ..sort();
    for (var i = 0; i < boundaries.length - 1; i++) {
      final start = boundaries[i], end = boundaries[i + 1];
      final mention =
          _references.any((token) => token.start <= start && token.end >= end);
      final composingPart =
          showComposing && start >= composing.start && end <= composing.end;
      parts.add(TextSpan(
          text: text.substring(start, end),
          style: TextStyle(
              backgroundColor:
                  mention ? scheme.onSurface.withValues(alpha: .08) : null,
              fontWeight: mention ? FontWeight.w500 : null,
              decoration: composingPart ? TextDecoration.underline : null)));
    }
    return TextSpan(style: style, children: parts);
  }
}

class ComposerTrigger {
  const ComposerTrigger(this.trigger, this.query, this.range);
  final String trigger, query;
  final TextRange range;
  static ComposerTrigger? parse(TextEditingValue value) {
    if (!value.selection.isValid ||
        !value.selection.isCollapsed ||
        value.composing.isValid && !value.composing.isCollapsed) {
      return null;
    }
    final end = value.selection.end;
    if (end > value.text.length) return null;
    final match = RegExp(r'(^|\s)([/@$#¥￥])([^\s/@$#¥￥]*)$')
        .firstMatch(value.text.substring(0, end));
    if (match == null) return null;
    final symbol = match.group(2)!;
    return ComposerTrigger(
        symbol == '¥' || symbol == '￥' ? r'$' : symbol,
        match.group(3)!,
        TextRange(start: match.start + match.group(1)!.length, end: end));
  }
}
