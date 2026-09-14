import 'package:flutter/foundation.dart';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/conversation.dart';

class WorkspaceSearchScope {
  const WorkspaceSearchScope({
    required this.workspaceKey,
    required this.title,
    required this.scope,
  });

  final String workspaceKey;
  final String title;
  final Map<String, dynamic> scope;

  Map<String, dynamic> toWire() => {
        if (scope['workspacePath'] is String)
          'workspacePath': scope['workspacePath'],
        if (scope['workspaceIdentity'] is String)
          'workspaceIdentity': scope['workspaceIdentity'],
      };
}

enum WorkspaceSearchResultKind { conversation, file }

class WorkspaceSearchResult {
  const WorkspaceSearchResult({
    required this.kind,
    required this.workspaceKey,
    required this.workspaceTitle,
    required this.title,
    this.sessionId,
    this.workspacePath,
    this.snippet,
    this.snippetIndex,
    this.filePath,
    this.relativePath,
    this.query,
  });

  final WorkspaceSearchResultKind kind;
  final String workspaceKey;
  final String workspaceTitle;
  final String title;
  final String? sessionId;
  final String? workspacePath;
  final String? snippet;
  final int? snippetIndex;
  final String? filePath;
  final String? relativePath;
  final String? query;
}

class WorkspaceSearchController extends ChangeNotifier {
  WorkspaceSearchController({
    required this.transport,
    required List<WorkspaceSearchScope> scopes,
    this.currentWorkspaceKey,
    this.currentTaskId,
  }) : scopes = List.unmodifiable(scopes);

  final ConversationTransport transport;
  List<WorkspaceSearchScope> scopes;
  final String? currentWorkspaceKey;
  final String? currentTaskId;
  String query = '';
  bool loading = false;
  String? error;
  List<WorkspaceSearchResult> results = const [];
  List<String> history = const [];
  int _generation = 0;
  bool _disposed = false;

  String get _historyKey {
    final scope = scopes
        .where((scope) =>
            scope.workspaceKey ==
            (currentWorkspaceKey ?? scopes.firstOrNull?.workspaceKey))
        .firstOrNull;
    return (scope?.scope['workspaceIdentity'] as String?) ??
        (scope?.scope['workspacePath'] as String?) ??
        (currentWorkspaceKey ?? '');
  }

  Future<void> loadHistory() async {
    if (_disposed) return;
    final prefs = await SharedPreferences.getInstance();
    final raw =
        jsonDecode(prefs.getString('zcode_remote_search_history_v1') ?? '{}');
    final values = raw is Map ? raw[_historyKey] : null;
    if (_disposed) return;
    history = values is List
        ? values
            .whereType<String>()
            .where((value) => value.isNotEmpty)
            .take(12)
            .toList()
        : const [];
    notifyListeners();
  }

  Future<void> recordSelection(String value) async {
    final queryValue = value.trim();
    if (_disposed || queryValue.isEmpty) return;
    final next = [queryValue, ...history.where((item) => item != queryValue)]
        .take(12)
        .toList(growable: false);
    history = next;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final raw =
        jsonDecode(prefs.getString('zcode_remote_search_history_v1') ?? '{}');
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    map[_historyKey] = next;
    await prefs.setString('zcode_remote_search_history_v1', jsonEncode(map));
  }

  Future<void> clearHistory() async {
    if (_disposed) return;
    history = const [];
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    final raw =
        jsonDecode(prefs.getString('zcode_remote_search_history_v1') ?? '{}');
    final map =
        raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    map.remove(_historyKey);
    await prefs.setString('zcode_remote_search_history_v1', jsonEncode(map));
  }

  void updateScopes(List<WorkspaceSearchScope> next) {
    _generation++;
    scopes = List.unmodifiable(next);
  }

  Future<void> search(String value) async {
    if (_disposed) return;
    final generation = ++_generation;
    query = value;
    error = null;
    final normalized = _stripPrefix(value);
    if (normalized.isEmpty) {
      loading = false;
      results = const [];
      notifyListeners();
      return;
    }
    loading = true;
    results = const [];
    notifyListeners();
    final prefix = value.trimLeft().isEmpty ? '' : value.trimLeft()[0];
    final wantConversations = prefix != '@' && prefix != '>';
    final wantFiles = prefix != '#' && prefix != '>';
    final fileScope = scopes
        .where((scope) =>
            scope.workspaceKey ==
            (currentWorkspaceKey ?? scopes.firstOrNull?.workspaceKey))
        .firstOrNull;
    try {
      Map<String, dynamic>? taskRaw;
      List<Map<String, dynamic>>? fileRaw;
      final errors = <String>[];
      if (wantConversations) {
        try {
          taskRaw = await transport.listTaskList(
              workspaceScopes: [for (final scope in scopes) scope.toWire()],
              search: normalized);
        } catch (error) {
          errors.add(error.toString());
        }
      }
      if (wantFiles && fileScope?.scope['workspacePath'] is String) {
        try {
          fileRaw = await transport.workspaceFilesForRoot(
              fileScope!.scope['workspacePath'] as String);
        } catch (error) {
          errors.add(error.toString());
        }
      }
      if (_disposed || generation != _generation) return;
      final next = <WorkspaceSearchResult>[];
      if (taskRaw != null) next.addAll(_parseTasks(taskRaw, normalized));
      if (fileRaw != null && fileScope != null) {
        next.addAll(_parseFiles(fileRaw, fileScope, normalized));
      }
      results = next.take(80).toList(growable: false);
      error = errors.isEmpty ? null : errors.join('\n');
    } catch (e) {
      if (_disposed || generation != _generation) return;
      error = e.toString();
      results = const [];
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        notifyListeners();
      }
    }
  }

  String _stripPrefix(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return '';
    return switch (trimmed[0]) {
      '>' || '#' || '@' => trimmed.substring(1).trim(),
      _ => trimmed,
    };
  }

  List<WorkspaceSearchResult> _parseTasks(Object? raw, String normalized) {
    final list = raw is Map ? raw['items'] : raw;
    if (list is! List) return const [];
    final output = <WorkspaceSearchResult>[];
    final seen = <String>{};
    for (final item in list.whereType<Map>()) {
      final row = item.cast<String, dynamic>();
      final workspaceIdentity = row['workspaceIdentity'] as String? ??
          row['workspacePath'] as String?;
      final workspaceKey = row['workspaceKey'] as String? ?? workspaceIdentity;
      final scope = scopes
          .where((entry) =>
              entry.workspaceKey == workspaceKey ||
              entry.scope['workspaceIdentity'] == workspaceIdentity ||
              entry.scope['workspacePath'] == workspaceIdentity)
          .firstOrNull;
      if (scope == null) continue;
      final sessionId =
          row['sessionId'] as String? ?? row['taskId'] as String? ?? '';
      if (sessionId.isEmpty) continue;
      final snippets = <String>[
        if (row['searchSnippet'] is String) row['searchSnippet'] as String,
        for (final snippet in (row['searchSnippets'] as List? ?? const []))
          if (snippet is String) snippet,
      ];
      if (snippets.isEmpty) snippets.add('');
      for (var index = 0; index < snippets.length; index++) {
        final snippet = snippets[index];
        final key = '${scope.workspaceKey}|$sessionId|$snippet';
        if (!seen.add(key)) continue;
        output.add(WorkspaceSearchResult(
            kind: WorkspaceSearchResultKind.conversation,
            workspaceKey: scope.workspaceKey,
            workspaceTitle: scope.title,
            title: row['title'] as String? ?? '未命名任务',
            sessionId: sessionId,
            workspacePath: scope.scope['workspacePath'] as String?,
            snippet: snippet,
            snippetIndex: snippets.length == 1 ? null : index,
            query: normalized));
      }
    }
    return output;
  }

  List<WorkspaceSearchResult> _parseFiles(
      Object? raw, WorkspaceSearchScope scope, String normalized) {
    if (raw is! List) return const [];
    final terms = normalized.toLowerCase().split(RegExp(r'\s+'));
    final output = <WorkspaceSearchResult>[];
    for (final item in raw.whereType<Map>()) {
      final row = item.cast<String, dynamic>();
      if (row['type'] != null && row['type'] != 'file') continue;
      final relative = row['relativePath'] as String? ??
          row['path'] as String? ??
          row['name'] as String? ??
          '';
      final name = row['name'] as String? ?? relative;
      final haystack = '$name $relative'.toLowerCase();
      if (!terms.every(haystack.contains)) continue;
      output.add(WorkspaceSearchResult(
          kind: WorkspaceSearchResultKind.file,
          workspaceKey: scope.workspaceKey,
          workspaceTitle: scope.title,
          title: name,
          workspacePath: scope.scope['workspacePath'] as String?,
          filePath: row['path'] as String? ?? relative,
          relativePath: relative));
    }
    return output;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
