import 'dart:async';
import 'package:flutter/widgets.dart';
import '../protocol/conversation.dart';
import 'composer_input.dart';

class ComposerReferences extends ChangeNotifier {
  ComposerReferences(
      {required this.input,
      required this.transport,
      required this.preparation,
      required this.session,
      this.sessionCatalog,
      DateTime Function()? now})
      : _now = now ?? DateTime.now {
    input.addListener(_editingChanged);
  }
  final ComposerInput input;
  final ConversationTransport transport;
  final WorkspacePrep? Function() preparation;
  final String? Function() session;
  final Future<List<Map<String, dynamic>>> Function(bool allWorkspaces)?
      sessionCatalog;
  final DateTime Function() _now;
  DateTime? _filesLoadedAt;
  final _cache = <String, List<ComposerReference>>{};
  final _loading = <String>{};
  final failed = <String>{};
  final _missRefresh = <String, String>{};
  ComposerTrigger? trigger;
  String? _dismissed, _scope;
  int selected = 0;
  int _generation = 0;
  bool _disposed = false;
  bool get open => trigger != null;
  bool get loading => _categories.any(_loading.contains);
  List<String> get _categories => switch (trigger?.trigger) {
        '@' => ['files', 'plugins', 'sessions'],
        '#' => ['sessions-all'],
        r'$' => ['skills'],
        _ => [],
      };
  void updateScope() {
    if (_scope == session()) return;
    _scope = session();
    invalidate();
  }

  void invalidate() {
    _generation++;
    _cache.clear();
    _loading.clear();
    failed.clear();
    _missRefresh.clear();
    _filesLoadedAt = null;
    _editingChanged();
  }

  void dismiss() {
    _dismissed = '${input.text}\u0000${input.selection.baseOffset}';
    trigger = null;
    _notify();
  }

  void insertTrigger(String symbol) {
    final selection = input.selection.isValid
        ? input.selection
        : TextSelection.collapsed(offset: input.text.length);
    final prefix = selection.start > 0 &&
            !RegExp(r'\s').hasMatch(input.text[selection.start - 1])
        ? ' '
        : '';
    input.value = TextEditingValue(
        text: input.text
            .replaceRange(selection.start, selection.end, '$prefix$symbol'),
        selection: TextSelection.collapsed(
            offset: selection.start + prefix.length + symbol.length));
  }

  void _editingChanged() {
    if (_disposed) return;
    final next = '${input.text}\u0000${input.selection.baseOffset}';
    if (_dismissed == next) return;
    _dismissed = null;
    final wasOpen = trigger != null;
    trigger = ComposerTrigger.parse(input.value);
    if (!wasOpen &&
        trigger?.trigger == '@' &&
        !_loading.contains('files') &&
        _filesLoadedAt != null &&
        (_now().difference(_filesLoadedAt!) >= const Duration(seconds: 30) ||
            '${transport.scope['workspaceIdentity'] ?? ''}'
                .trim()
                .isNotEmpty)) {
      _cache.remove('files');
      failed.remove('files');
      _missRefresh.remove('files');
    }
    selected = 0;
    for (final category in _categories) {
      if (!_cache.containsKey(category) && !_loading.contains(category)) {
        unawaited(_load(category));
      } else if (category == 'files' &&
          !_loading.contains(category) &&
          !failed.contains(category) &&
          trigger!.query.isNotEmpty &&
          _filtered(category).isEmpty &&
          _missRefresh[category] != trigger!.query) {
        _missRefresh[category] = trigger!.query;
        unawaited(_load(category));
      }
    }
    _notify();
  }

  List<ComposerReference> _filtered(String category) {
    final query = trigger?.query.trim().toLowerCase() ?? '';
    int? rank(ComposerReference entry) {
      if (query.isEmpty) return 0;
      int? score(String raw) {
        final text = raw.trim().toLowerCase();
        if (text.isEmpty) return null;
        if (text.startsWith(query)) return text.length - query.length;
        final index = text.indexOf(query);
        if (index >= 0) return 100 + index;
        var cursor = 0, score = 200;
        for (final letter in query.split('')) {
          final next = text.indexOf(letter, cursor);
          if (next < 0) return null;
          score += next - cursor;
          cursor = next + 1;
        }
        return score + text.length - query.length;
      }

      final weighted = [
        (entry.label, 0),
        (entry.category == 'skills' ? entry.label : entry.value, 25),
        (entry.description, 100),
        for (final keyword in entry.keywords) (keyword, 300),
      ];
      final scores = [
        for (final item in weighted)
          if (score(item.$1) case final int value) value + item.$2
      ];
      return scores.isEmpty ? null : scores.reduce((a, b) => a < b ? a : b);
    }

    final entries = category == 'commands'
        ? [
            for (final command
                in preparation()?.slashCommands ?? const <SlashCommand>[])
              ComposerReference(
                  id: 'command:${command.name}',
                  category: 'commands',
                  label: command.name.replaceFirst(RegExp(r'^/+'), ''),
                  value: command.name.replaceFirst(RegExp(r'^/+'), ''),
                  description: command.description)
          ]
        : _cache[category] ?? const <ComposerReference>[];
    final ordered = [
      for (var i = 0; i < entries.length; i++)
        if (rank(entries[i]) case final int score)
          (entry: entries[i], score: score, index: i)
    ]..sort((a, b) {
        if (query.isEmpty &&
            category == 'files' &&
            a.entry.directory != b.entry.directory) {
          return a.entry.directory ? 1 : -1;
        }
        return a.score == b.score
            ? a.index.compareTo(b.index)
            : a.score.compareTo(b.score);
      });
    final result = ordered.map((e) => e.entry).toList();
    return category == 'files' && query.isEmpty
        ? result.take(10).toList()
        : result.take(1000).toList();
  }

  List<ComposerReference> get entries => trigger?.trigger == '/'
      ? _filtered('commands')
      : [for (final category in _categories) ..._filtered(category)];
  void move(int direction) {
    final values = entries;
    if (values.isEmpty) return;
    for (var n = 0; n < values.length; n++) {
      selected = (selected + direction + values.length) % values.length;
      if (!values[selected].disabled) break;
    }
    _notify();
  }

  bool pick([ComposerReference? entry]) {
    final request = trigger;
    final values = entries;
    final item = entry ??
        (values.isEmpty ? null : values[selected.clamp(0, values.length - 1)]);
    if (request == null ||
        item == null ||
        item.disabled ||
        !values.contains(item)) {
      return false;
    }
    final current = ComposerTrigger.parse(input.value);
    if (current?.range != request.range ||
        current?.trigger != request.trigger) {
      return false;
    }
    input.insertReference(request.range, item);
    return true;
  }

  Future<void> retry() async {
    await Future.wait([for (final category in _categories) _load(category)]);
  }

  Future<void> _load(String category) async {
    if (!_loading.add(category)) return;
    final generation = _generation;
    failed.remove(category);
    _notify();
    try {
      final raw = switch (category) {
        'files' => await transport.workspaceFiles(),
        'skills' => await transport.skillReferences(session()),
        'plugins' => await transport.pluginReferences(session()),
        _ => await (sessionCatalog?.call(category == 'sessions-all') ??
            transport.sessionReferences()),
      };
      if (_disposed || generation != _generation) return;
      final entries = <ComposerReference>[];
      final names = <String>{};
      final sorted = List<Map<String, dynamic>>.from(raw);
      if (category == 'skills') {
        sorted.sort((a, b) {
          int order(dynamic value) =>
              switch (value) { 'workspace' => 0, 'plugin' => 1, _ => 2 };
          return order(a['scope']).compareTo(order(b['scope']));
        });
      }
      for (final item in sorted) {
        String text(String key) =>
            item[key] is String ? (item[key] as String).trim() : '';
        if (category == 'files') {
          final path = text('relativePath');
          if (path.isEmpty) continue;
          entries.add(ComposerReference(
              id: 'file:$path',
              category: 'files',
              label: text('name'),
              value: path,
              description: path,
              keywords: [path, text('path')],
              directory: item['type'] == 'directory'));
        } else if (category == 'skills') {
          final name = text('name');
          if (name.isEmpty || !names.add(name) || item['enabled'] == false) {
            continue;
          }
          entries.add(ComposerReference(
              id: 'skill:${text('id')}',
              category: 'skills',
              label: name,
              value: text('path'),
              scope: text('scope'),
              description: text('description')));
        } else if (category == 'plugins') {
          final id = text('pluginId');
          if (item['enabled'] != true ||
              !RegExp(r'^[A-Za-z0-9][A-Za-z0-9._-]*@[A-Za-z0-9][A-Za-z0-9._-]*$')
                  .hasMatch(id)) {
            continue;
          }
          entries.add(ComposerReference(
              id: 'plugin:$id',
              category: 'plugins',
              label: text('name'),
              value: id,
              description: text('description'),
              disabled: item['conflictingPluginIds'] is List &&
                  (item['conflictingPluginIds'] as List).isNotEmpty));
        } else {
          final id =
              text('sessionId').isNotEmpty ? text('sessionId') : text('taskId');
          if (id.isEmpty || item['migrationSource'] != null || !names.add(id)) {
            continue;
          }
          entries.add(ComposerReference(
              id: 'session:$id',
              category: 'sessions',
              label: text('title').isEmpty ? id : text('title'),
              value: id,
              description: text('workspacePath')));
        }
      }
      _cache[category] = entries;
      if (category == 'files') _filesLoadedAt = _now();
    } catch (_) {
      if (!_disposed && generation == _generation) {
        failed.add(category);
        _cache[category] ??= [];
      }
    } finally {
      if (!_disposed && generation == _generation) {
        _loading.remove(category);
        _notify();
      }
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    input.removeListener(_editingChanged);
    super.dispose();
  }
}
