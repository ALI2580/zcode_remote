import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../protocol/channel_client.dart';
import '../protocol/zemote_client.dart';
import 'plugin_catalog.dart';

enum RemoteAgentCatalogStatus { idle, loading, loaded, error }

String _text(Map raw, String key) =>
    raw[key] is String ? (raw[key] as String).trim() : '';

bool? _bool(Map raw, String key) => raw[key] is bool ? raw[key] as bool : null;

class RemoteAgentEntry {
  const RemoteAgentEntry({
    required this.id,
    required this.title,
    required this.group,
    required this.raw,
    this.subtitle,
    this.enabled,
    this.scope,
    this.source,
    this.tools,
  });

  factory RemoteAgentEntry.fromSubagent(Map raw, {String group = 'agent'}) {
    final map = raw.cast<String, dynamic>();
    final title = _text(map, 'name').isNotEmpty
        ? _text(map, 'name')
        : _text(map, 'title');
    final rawSource = _text(map, 'source');
    final source =
        rawSource.isEmpty && _text(map, 'scope') == 'user' ? 'user' : rawSource;
    return RemoteAgentEntry(
      id: _text(map, 'id').isNotEmpty
          ? _text(map, 'id')
          : _text(map, 'agentId'),
      title: title.isEmpty ? '--' : title,
      group: group,
      subtitle: _text(map, 'description').isEmpty
          ? _text(map, 'summary')
          : _text(map, 'description'),
      enabled: _bool(map, 'enabled'),
      scope: _text(map, 'scope').isEmpty ? null : _text(map, 'scope'),
      source: source.isEmpty ? null : source,
      tools: map['tools'] is List
          ? [
              for (final tool in map['tools'] as List)
                if (tool is String) tool,
            ]
          : null,
      raw: map,
    );
  }

  factory RemoteAgentEntry.fromCommand(
    Map raw, {
    required String group,
  }) {
    final map = raw.cast<String, dynamic>();
    final location = map['location'] is Map
        ? (map['location'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final title = _text(map, 'name').isNotEmpty
        ? _text(map, 'name')
        : _text(map, 'title');
    final commandScope = _text(map, 'scope').isNotEmpty
        ? _text(map, 'scope')
        : _text(location, 'scope');
    final commandSource = _text(map, 'source');
    return RemoteAgentEntry(
      id: _text(map, 'id').isNotEmpty
          ? _text(map, 'id')
          : _text(map, 'commandId'),
      title: title.isEmpty ? '--' : title,
      group: group,
      subtitle: _text(map, 'description'),
      enabled: _bool(map, 'enabled'),
      scope: commandScope.isEmpty ? null : commandScope,
      source: commandSource.isEmpty ? null : commandSource,
      raw: map,
    );
  }

  final String id;
  final String title;
  final String group;
  final String? subtitle;
  final bool? enabled;
  final String? scope;
  final String? source;

  /// `null` means the subagent inherits all tools (official "all tools"
  /// badge); an empty list renders the same badge.
  final List<String>? tools;
  final Map<String, dynamic> raw;

  String get name => _text(raw, 'name').isEmpty ? title : _text(raw, 'name');
  String? get path => _text(raw, 'path').isEmpty ? null : _text(raw, 'path');
  String? get projectPath {
    final direct = _text(raw, 'projectPath');
    if (direct.isNotEmpty) return direct;
    final location = raw['location'];
    if (location is Map) {
      for (final key in const ['projectPath', 'directoryPath', 'path']) {
        final value = _text(location.cast<String, dynamic>(), key);
        if (value.isNotEmpty) return value;
      }
    }
    return null;
  }

  String? get model => _text(raw, 'model').isEmpty ? null : _text(raw, 'model');
  String? get thoughtLevel =>
      _text(raw, 'thoughtLevel').isEmpty ? null : _text(raw, 'thoughtLevel');
  String? get modelOverride =>
      _text(raw, 'modelOverride').isEmpty ? null : _text(raw, 'modelOverride');
  String? get thoughtLevelOverride => _text(raw, 'thoughtLevelOverride').isEmpty
      ? null
      : _text(raw, 'thoughtLevelOverride');

  String? get agentSource => _text(raw, 'agentSource').isEmpty
      ? (source?.isEmpty == true ? null : source)
      : _text(raw, 'agentSource');

  String? get filePath => _text(raw, 'filePath').isEmpty
      ? (_text(raw, 'path').isEmpty ? null : _text(raw, 'path'))
      : _text(raw, 'filePath');

  String? get locationSource {
    final location = raw['location'];
    if (location is Map && location['source'] is String) {
      final value = (location['source'] as String).trim();
      return value.isEmpty ? null : value;
    }
    return null;
  }

  bool get inheritsAllTools =>
      tools == null ||
      tools!.isEmpty ||
      tools!.any((tool) => tool.trim() == '*');

  /// Official `$5` in js-1: builtin rows carry scope or source `built-in`.
  bool get isBuiltIn => scope == 'built-in' || source == 'built-in';

  /// Official `YJt`: plugin profiles carry source `plugin` and stay
  /// read-only. The page's editable user group is guarded separately by Q5.
  bool get isPlugin => !isBuiltIn && (source == 'plugin' || group == 'plugin');
}

/// Official `subagentsService` projection and guarded write surface.
///
/// The catalog deliberately keeps the original row in [RemoteAgentEntry.raw].
/// The form can therefore edit the small documented subset while preserving
/// fields introduced by a newer desktop client.
class SubagentsCatalog extends ChangeNotifier {
  SubagentsCatalog({
    required this.session,
    required this.scope,
    required this.scopeKey,
    this.workspacePath,
    this.scopeKind = 'user',
    this.pluginCatalog,
    this.provider = 'glm',
  });

  final BridgeSession session;
  Map<String, dynamic> scope;
  String scopeKey;
  String? workspacePath;
  String scopeKind;
  PluginCatalog? pluginCatalog;
  final String? provider;

  int _generation = 0;
  int _sourceGeneration = 0;
  Future<void>? _pending;
  bool _disposed = false;

  RemoteAgentCatalogStatus status = RemoteAgentCatalogStatus.idle;
  List<RemoteAgentEntry> items = const [];
  bool? supported;
  Map<String, dynamic>? capability;
  Object? error;

  final Map<String, int> _operatingTokens = <String, int>{};
  final Map<String, Object?> _operationErrors = <String, Object?>{};

  static const defaultTools = <String>[
    'Read',
    'Grep',
    'Glob',
    'Bash',
    'Edit',
    'Write',
    'WebFetch',
    'WebSearch',
    'TodoWrite',
  ];

  bool get userScopeAvailable => capability?['userScopeAvailable'] == true;

  /// Monotonic identity token for the selected device/bridge/workspace scope.
  /// Consumers use it to discard an editor draft when the same catalog object
  /// is retargeted to a new source.
  int get sourceRevision => _sourceGeneration;

  bool canCreate(String targetScope) => targetScope == 'workspace'
      ? workspacePath?.trim().isNotEmpty == true
      : targetScope == 'user' && userScopeAvailable;

  bool isOperating(String id) => _operatingTokens[id] == _sourceGeneration;

  Object? operationError(String id) => _operationErrors[id];

  /// hYt scope projection from the official page. User scope excludes
  /// workspace rows. Workspace scope keeps matching workspace rows and only
  /// accepts a plugin row when its projectPath matches the selected path.
  List<RemoteAgentEntry> get visibleItems => [
        for (final entry in items)
          if (_visibleInScope(entry)) entry,
      ];

  bool _visibleInScope(RemoteAgentEntry entry) {
    if (scopeKind == 'user') return entry.scope != 'workspace';
    if (scopeKind != 'workspace') return true;
    if (entry.isBuiltIn || entry.scope != 'workspace') return false;
    final projectPath = entry.projectPath?.trim();
    final selectedPath = workspacePath?.trim();
    if (entry.isPlugin) {
      return projectPath != null && projectPath == selectedPath;
    }
    return projectPath == null || projectPath == selectedPath;
  }

  /// Q5 in the official bundle: only user-owned, writable user/workspace
  /// rows can be edited or deleted.
  bool canEdit(RemoteAgentEntry entry) =>
      (entry.scope == 'user' || entry.scope == 'workspace') &&
      entry.source == 'user' &&
      entry.raw['readOnly'] != true;

  bool canToggle(RemoteAgentEntry entry) =>
      canEdit(entry) && entry.scope == 'user';

  bool canDelete(RemoteAgentEntry entry) => canEdit(entry);

  /// ZJt in the official bundle limits model overrides to these runtime rows.
  String? builtInOverrideName(RemoteAgentEntry entry) => entry.isBuiltIn &&
          (entry.title == 'general-purpose' || entry.title == 'Explore')
      ? entry.title
      : null;

  /// Change the list source without allowing an in-flight old response to
  /// mutate the new source. The next [refresh] starts a fresh request.
  void updateScope({
    required Map<String, dynamic> nextScope,
    String? nextWorkspacePath,
    String? nextScopeKey,
    String? nextScopeKind,
  }) {
    final sameScope = _sameMap(scope, nextScope) &&
        workspacePath == nextWorkspacePath &&
        (nextScopeKey == null || nextScopeKey == scopeKey) &&
        (nextScopeKind == null || nextScopeKind == scopeKind);
    if (sameScope || _disposed) return;
    _generation++;
    _sourceGeneration++;
    _pending = null;
    scope = Map<String, dynamic>.from(nextScope);
    if (nextScopeKey != null) scopeKey = nextScopeKey;
    workspacePath = nextWorkspacePath;
    if (nextScopeKind != null) scopeKind = nextScopeKind;
    items = const [];
    supported = null;
    capability = null;
    _operationErrors.clear();
    status = RemoteAgentCatalogStatus.idle;
    error = null;
    notifyListeners();
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    final pending = _pending;
    if (pending != null) return pending;
    final generation = ++_generation;
    status = RemoteAgentCatalogStatus.loading;
    notifyListeners();
    Future<void>? operationFuture;
    Future<void> operation() async {
      try {
        final raw = await session.channels.call(
          Channels.subagents,
          'list',
          [_listScope()],
          timeout: const Duration(seconds: 30),
        );
        if (_disposed || generation != _generation) return;
        final map = raw.cast<String, dynamic>();
        // Official YJt: keep non-plugin `agents`, then append pluginAgents.
        // Older synthetic services returned plugin rows in `agents` only; in
        // that compatibility shape preserve the complete server list.
        final rawAgents = map['agents'] is List
            ? (map['agents'] as List).whereType<Map>()
            : const Iterable<Map>.empty();
        final hasPluginSource = map['pluginAgents'] is List;
        final agents = hasPluginSource
            ? rawAgents.where((item) => _text(item, 'source') != 'plugin')
            : rawAgents;
        final pluginAgents = hasPluginSource
            ? (map['pluginAgents'] as List).whereType<Map>()
            : const Iterable<Map>.empty();
        items = [
          for (final item in [...agents, ...pluginAgents])
            RemoteAgentEntry.fromSubagent(item),
        ];
        capability = map['capability'] is Map
            ? (map['capability'] as Map).cast<String, dynamic>()
            : null;
        supported = capability?['supported'] is bool
            ? capability!['supported'] as bool
            : null;
        status = RemoteAgentCatalogStatus.loaded;
        error = null;
      } catch (value) {
        if (_disposed || generation != _generation) return;
        status = RemoteAgentCatalogStatus.error;
        error = value;
      } finally {
        if (_pending == operationFuture) _pending = null;
        if (!_disposed && generation == _generation) notifyListeners();
      }
    }

    operationFuture = operation();
    _pending = operationFuture;
    return operationFuture;
  }

  Map<String, dynamic> _listScope() => {
        ...scope,
        if (workspacePath?.trim().isNotEmpty == true)
          'workspacePath': workspacePath,
        if (provider?.trim().isNotEmpty == true) 'provider': provider,
      };

  Map<String, dynamic> _writeScope({required String targetScope}) => {
        'scope': targetScope,
        if (workspacePath?.trim().isNotEmpty == true)
          'workspacePath': workspacePath,
        if (scope['workspaceIdentity'] != null)
          'workspaceIdentity': scope['workspaceIdentity'],
        if (provider?.trim().isNotEmpty == true) 'provider': provider,
      };

  Future<bool> createAgent({
    required Map<String, dynamic> config,
    required String targetScope,
  }) {
    if (!canCreate(targetScope)) return Future.value(false);
    return _runWrite('create-agent', () async {
      await session.channels.call(
        Channels.subagents,
        'createAgent',
        [
          {
            'config': Map<String, dynamic>.from(config),
            ..._writeScope(targetScope: targetScope),
          }
        ],
        timeout: const Duration(seconds: 30),
      );
    });
  }

  Future<bool> updateAgent(
    RemoteAgentEntry entry, {
    required Map<String, dynamic> config,
  }) {
    if (!canEdit(entry)) return Future.value(false);
    final targetScope = entry.scope == 'workspace' ? 'workspace' : 'user';
    return _runWrite('update:${entry.id}', () async {
      await session.channels.call(
        Channels.subagents,
        'updateAgent',
        [
          {
            'agentId': entry.id,
            'config': Map<String, dynamic>.from(config),
            'oldFilePath': entry.raw['path'] ?? entry.raw['filePath'] ?? '',
            ..._writeScope(targetScope: targetScope),
            if (entry.raw['projectPath'] is String &&
                (entry.raw['projectPath'] as String).trim().isNotEmpty)
              'workspacePath': entry.raw['projectPath'],
          }
        ],
        timeout: const Duration(seconds: 30),
      );
    });
  }

  Future<bool> deleteAgent(RemoteAgentEntry entry) {
    if (!canDelete(entry)) return Future.value(false);
    return _runWrite('delete:${entry.id}', () async {
      await session.channels.call(
        Channels.subagents,
        'deleteAgent',
        [
          {
            'agentId': entry.id,
            'filePath': entry.raw['path'] ?? entry.raw['filePath'] ?? '',
          }
        ],
        timeout: const Duration(seconds: 30),
      );
    });
  }

  Future<bool> setEnabled(RemoteAgentEntry entry, {required bool enabled}) {
    if (!canToggle(entry)) return Future.value(false);
    return _runWrite('enabled:${entry.id}', () async {
      await session.channels.call(
        Channels.subagents,
        'setEnabled',
        [
          {'agentId': entry.id, 'enabled': enabled}
        ],
        timeout: const Duration(seconds: 20),
      );
    });
  }

  Future<bool> setBuiltInModelOverride({
    required RemoteAgentEntry entry,
    String? model,
    String? thoughtLevel,
  }) {
    final name = builtInOverrideName(entry);
    if (name == null) return Future.value(false);
    final normalizedModel = model?.trim();
    final normalizedThought = thoughtLevel?.trim();
    return _runWrite('model:$name', () async {
      await session.channels.call(
        Channels.subagents,
        'setBuiltInModelOverride',
        [
          {
            'agentName': name,
            if (normalizedModel != null && normalizedModel.isNotEmpty)
              'model': normalizedModel,
            if (normalizedThought != null && normalizedThought.isNotEmpty)
              'thoughtLevel': normalizedThought,
          }
        ],
        timeout: const Duration(seconds: 20),
      );
    });
  }

  Future<bool> _runWrite(
    String id,
    Future<void> Function() operation,
  ) async {
    final sourceGeneration = _sourceGeneration;
    if (_disposed || _operatingTokens[id] == sourceGeneration) return false;
    _operatingTokens[id] = sourceGeneration;
    _operationErrors.remove(id);
    notifyListeners();
    try {
      await operation();
      if (_disposed || sourceGeneration != _sourceGeneration) return false;
      await refresh();
      if (_disposed || sourceGeneration != _sourceGeneration) return false;
      if (status == RemoteAgentCatalogStatus.error) {
        throw error ?? StateError('subagents refresh failed');
      }
      return true;
    } catch (value) {
      if (!_disposed && sourceGeneration == _sourceGeneration) {
        _operationErrors[id] = value;
        notifyListeners();
      }
      return false;
    } finally {
      if (_operatingTokens[id] == sourceGeneration) {
        _operatingTokens.remove(id);
        if (!_disposed) notifyListeners();
      }
    }
  }

  static bool _sameMap(Map<String, dynamic> left, Map<String, dynamic> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}

/// Official `commandsService.list()` projection and guarded file write surface.
class CommandsCatalog extends ChangeNotifier {
  CommandsCatalog({
    required this.session,
    required this.scope,
    required this.scopeKey,
    this.workspacePath,
    this.scopeKind = 'user',
    this.pluginCatalog,
  }) {
    pluginCatalog?.addListener(_pluginCatalogChanged);
  }

  final BridgeSession session;
  Map<String, dynamic> scope;
  String scopeKey;
  String? workspacePath;
  String scopeKind;
  PluginCatalog? pluginCatalog;

  int _generation = 0;
  int _sourceGeneration = 0;
  Future<void>? _pending;
  bool _disposed = false;

  RemoteAgentCatalogStatus status = RemoteAgentCatalogStatus.idle;
  List<RemoteAgentEntry> items = const [];
  Map<String, dynamic>? capability;
  Object? error;

  final _savingIds = <String>{};
  final _saveErrors = <String, Object?>{};
  final _writeGenerations = <String, int>{};
  final _confirmedWrites = <String, int>{};

  int get sourceRevision => _sourceGeneration;

  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future.value();
    final pending = _pending;
    if (!force && pending != null) return pending;
    final generation = ++_generation;
    status = RemoteAgentCatalogStatus.loading;
    notifyListeners();
    Future<void>? operationFuture;
    Future<void> operation() async {
      try {
        final raw = await session.channels.call(
          Channels.commands,
          'list',
          [
            {
              ...scope,
              if (workspacePath?.isNotEmpty == true)
                'workspacePath': workspacePath,
            }
          ],
          timeout: const Duration(seconds: 30),
        );
        if (_disposed || generation != _generation) return;
        final map =
            raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};
        capability = map['capability'] is Map
            ? (map['capability'] as Map).cast<String, dynamic>()
            : null;
        final rows = <RemoteAgentEntry>[];
        final merged = <String, Map<String, dynamic>>{};
        final groups = <String, String>{};
        void add(String key, String group) {
          if (map[key] is! List) return;
          for (final item in (map[key] as List).whereType<Map>()) {
            final value = item.cast<String, dynamic>();
            final identity = _commandIdentity(value);
            if (identity == null) {
              rows.add(RemoteAgentEntry.fromCommand(value, group: group));
              continue;
            }
            final existing = merged[identity];
            if (existing == null) {
              merged[identity] = Map<String, dynamic>.from(value);
              groups[identity] = group;
            } else {
              // Auxiliary projections often add enabled/filePath metadata.
              // Merge missing fields while rendering one row per command.
              for (final field in value.entries) {
                if (!existing.containsKey(field.key) ||
                    existing[field.key] == null ||
                    (existing[field.key] is String &&
                        (existing[field.key] as String).isEmpty)) {
                  existing[field.key] = field.value;
                }
              }
              if (groups[identity] == 'all' && group != 'all') {
                groups[identity] = group;
              }
            }
          }
        }

        add('commands', 'all');
        add('userCommands', 'user');
        add('pluginCommands', 'plugin');
        rows.addAll([
          for (final entry in merged.entries)
            RemoteAgentEntry.fromCommand(entry.value,
                group: _commandGroup(entry.value, groups[entry.key] ?? 'all')),
        ]);
        items = rows;
        status = RemoteAgentCatalogStatus.loaded;
        error = null;
      } catch (value) {
        if (_disposed || generation != _generation) return;
        status = RemoteAgentCatalogStatus.error;
        error = value;
      } finally {
        if (_pending == operationFuture) _pending = null;
        if (!_disposed && generation == _generation) notifyListeners();
      }
    }

    operationFuture = operation();
    _pending = operationFuture;
    return operationFuture;
  }

  bool get userScopeAvailable => capability?['userScopeAvailable'] == true;

  bool isSaving(String id) => _savingIds.contains(id);
  Object? saveError(String id) => _saveErrors[id];

  bool writeConfirmed(String id) =>
      _confirmedWrites[id] != null &&
      _confirmedWrites[id] == _writeGenerations[id];

  void updatePluginCatalog(PluginCatalog? next) {
    if (identical(pluginCatalog, next) || _disposed) return;
    pluginCatalog?.removeListener(_pluginCatalogChanged);
    pluginCatalog = next;
    pluginCatalog?.addListener(_pluginCatalogChanged);
    notifyListeners();
  }

  List<RemoteAgentEntry> get visibleItems => [
        for (final item in items)
          if (_visibleInScope(item) && _pluginIsVisible(item)) item,
      ];

  bool _pluginIsVisible(RemoteAgentEntry entry) {
    if (!entry.isPlugin) return true;
    final catalog = pluginCatalog;
    if (catalog == null) return true;
    // The raw commands list is authoritative and stays intact while the
    // shared plugin catalog loads. Recompute this projection when that catalog
    // completes so a delayed plugin response cannot permanently hide a row.
    if (catalog.loading || catalog.failed) return false;
    return _pluginIsEnabled(entry);
  }

  bool _visibleInScope(RemoteAgentEntry entry) {
    if (!entry.isPlugin) {
      final rawAgentSource = _text(entry.raw, 'agentSource');
      if (entry.source != null && entry.source != 'user') return false;
      if (rawAgentSource.isNotEmpty && rawAgentSource != 'zcodeAgent') {
        return false;
      }
    }
    final entryScope = entry.scope?.trim();
    if (entryScope == null || entryScope.isEmpty) return true;
    if (entry.isPlugin) {
      if (scopeKind == 'project' || scopeKind == 'workspace') {
        final projectPath = entry.projectPath?.trim();
        return projectPath == null ||
            projectPath.isEmpty ||
            projectPath == workspacePath?.trim();
      }
      return true;
    }
    if (scopeKind == 'project' || scopeKind == 'workspace') {
      return entryScope == 'project' || entryScope == 'workspace';
    }
    return entryScope == 'user';
  }

  bool canToggle(RemoteAgentEntry entry) =>
      (entry.source == 'user' &&
          (entry.agentSource == 'zcodeAgent' || entry.agentSource == 'user')) ||
      // Older command projections omitted both source fields. Treat that
      // shape as the native list's default for the toggle only; edit/delete
      // still require the verified zcode location below.
      (entry.source == null &&
          (entry.agentSource == null || entry.agentSource == 'user'));

  bool canEdit(RemoteAgentEntry entry) =>
      (entry.source == 'user' ||
          // Some bridge versions put the native source only in agentSource.
          (entry.source == null && entry.agentSource == 'user')) &&
      (entry.agentSource == 'zcodeAgent' || entry.agentSource == 'user') &&
      entry.locationSource == 'zcode' &&
      (entry.scope == 'user' ||
          entry.scope == 'project' ||
          entry.scope == 'workspace') &&
      entry.raw['readOnly'] != true;

  bool canDelete(RemoteAgentEntry entry) => canEdit(entry);

  void updateScope({
    required Map<String, dynamic> nextScope,
    required String nextScopeKey,
    String? nextWorkspacePath,
    String? nextScopeKind,
  }) {
    final kind = nextScopeKind ?? scopeKind;
    if (_sameMap(scope, nextScope) &&
        scopeKey == nextScopeKey &&
        workspacePath == nextWorkspacePath &&
        scopeKind == kind) {
      return;
    }
    if (_disposed) return;
    _generation++;
    _sourceGeneration++;
    _pending = null;
    scope = Map<String, dynamic>.from(nextScope);
    scopeKey = nextScopeKey;
    workspacePath = nextWorkspacePath;
    scopeKind = kind;
    items = const [];
    capability = null;
    error = null;
    status = RemoteAgentCatalogStatus.idle;
    _saveErrors.clear();
    notifyListeners();
  }

  /// Official `setCommandEnabled({agentSource,commandId,filePath,enabled})`.
  Future<void> setEnabled(RemoteAgentEntry entry, {required bool enabled}) {
    if (_disposed || !canToggle(entry) || _savingIds.contains(entry.id)) {
      return Future.value();
    }
    final generation = _nextWriteGeneration(entry.id);
    final sourceGeneration = _sourceGeneration;
    _savingIds.add(entry.id);
    _saveErrors.remove(entry.id);
    notifyListeners();
    Future<void> operation() async {
      try {
        await session.channels.call(
          Channels.commands,
          'setCommandEnabled',
          [
            {
              'agentSource': entry.agentSource ?? 'user',
              'commandId': entry.id,
              'filePath': entry.filePath ?? '',
              'enabled': enabled,
            }
          ],
          timeout: const Duration(seconds: 20),
        );
        if (_disposed ||
            sourceGeneration != _sourceGeneration ||
            generation != _writeGenerations[entry.id]) {
          return;
        }
        _saveErrors.remove(entry.id);
        await _refreshAuthoritative();
      } catch (value) {
        if (_disposed ||
            sourceGeneration != _sourceGeneration ||
            generation != _writeGenerations[entry.id]) {
          return;
        }
        _saveErrors[entry.id] = value;
      } finally {
        if (_savingIds.remove(entry.id) && !_disposed) notifyListeners();
      }
    }

    return operation();
  }

  /// Scope arguments for the official file writers (`PXt` in js-1): the user
  /// level sends no workspace path; project scope requires one.
  Map<String, dynamic> _scopeArgs({required String storageLevel}) => {
        'storageLevel': storageLevel,
        if (storageLevel == 'project' && workspacePath?.isNotEmpty == true)
          'workspacePath': workspacePath,
      };

  /// Official `writeCommandFile({config, agentSource, storageLevel,
  /// workspacePath?})`; the follow-up list read-back is the only source of
  /// visible rows. Failure keeps the old list under [errorId].
  Future<bool> createCommand(Map<String, dynamic> config,
      {String agentSource = 'zcodeAgent',
      required String errorId,
      String? storageLevel}) {
    final level = storageLevel ??
        ((scopeKind == 'project' || scopeKind == 'workspace')
            ? 'project'
            : 'user');
    return _write(errorId, () async {
      await session.channels.call(
          Channels.commands,
          'writeCommandFile',
          [
            {
              'config': config,
              'agentSource': agentSource,
              ..._scopeArgs(storageLevel: level),
            }
          ],
          timeout: const Duration(seconds: 20));
      await _refreshAuthoritative();
    });
  }

  /// Official `updateCommandFile({agentSource, commandId, config,
  /// oldFilePath, storageLevel, workspacePath?})`.
  Future<bool> updateCommand(
      RemoteAgentEntry entry, Map<String, dynamic> config,
      {required String errorId, String? storageLevel}) {
    if (_disposed || !canEdit(entry)) return Future.value(false);
    final level = storageLevel ??
        ((entry.scope == 'project' || entry.scope == 'workspace')
            ? 'project'
            : 'user');
    return _write(errorId, () async {
      await session.channels.call(
          Channels.commands,
          'updateCommandFile',
          [
            {
              'agentSource': entry.agentSource ?? 'user',
              'commandId': entry.id,
              'config': config,
              'oldFilePath': entry.filePath ?? '',
              ..._scopeArgs(storageLevel: level),
            }
          ],
          timeout: const Duration(seconds: 20));
      await _refreshAuthoritative();
    });
  }

  /// Official `deleteCommandFile({agentSource,commandId,filePath})`.
  Future<bool> deleteCommand(RemoteAgentEntry entry,
      {required String errorId}) {
    if (_disposed || !canDelete(entry)) return Future.value(false);
    return _write(errorId, () async {
      await session.channels.call(
          Channels.commands,
          'deleteCommandFile',
          [
            {
              'agentSource': entry.agentSource ?? 'user',
              'commandId': entry.id,
              'filePath': entry.filePath ?? '',
            }
          ],
          timeout: const Duration(seconds: 20));
      await _refreshAuthoritative();
    });
  }

  /// Shared write wrapper: in-flight dedupe per [errorId], late-response
  /// discard via the write generation, error retained for retry.
  Future<bool> _write(String errorId, Future<void> Function() operation) async {
    if (_disposed || _savingIds.contains(errorId)) return false;
    final generation = _nextWriteGeneration(errorId);
    final sourceGeneration = _sourceGeneration;
    _savingIds.add(errorId);
    _saveErrors.remove(errorId);
    _confirmedWrites.remove(errorId);
    notifyListeners();
    try {
      await operation();
      if (_disposed ||
          sourceGeneration != _sourceGeneration ||
          generation != _writeGenerations[errorId]) {
        return false;
      }
      _saveErrors.remove(errorId);
      _confirmedWrites[errorId] = generation;
      return true;
    } catch (value) {
      if (_disposed ||
          sourceGeneration != _sourceGeneration ||
          generation != _writeGenerations[errorId]) {
        return false;
      }
      _saveErrors[errorId] = value;
      return false;
    } finally {
      if (_savingIds.remove(errorId) && !_disposed) notifyListeners();
    }
  }

  Future<void> _refreshAuthoritative() async {
    await refresh(force: true);
    if (status == RemoteAgentCatalogStatus.error) {
      throw error ?? StateError('commands refresh failed');
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _sourceGeneration++;
    pluginCatalog?.removeListener(_pluginCatalogChanged);
    super.dispose();
  }

  void _pluginCatalogChanged() {
    if (!_disposed) notifyListeners();
  }

  int _nextWriteGeneration(String id) {
    final next = (_writeGenerations[id] ?? 0) + 1;
    _writeGenerations[id] = next;
    return next;
  }

  static String? _commandIdentity(Map<String, dynamic> value) {
    final id = _text(value, 'id').isNotEmpty
        ? _text(value, 'id')
        : _text(value, 'commandId');
    if (id.isNotEmpty) return 'id:$id';
    final path = _text(value, 'filePath').isNotEmpty
        ? _text(value, 'filePath')
        : _text(value, 'path');
    if (path.isNotEmpty) return 'path:$path';
    final name = _text(value, 'name');
    return name.isEmpty ? null : 'name:$name';
  }

  static String _commandGroup(Map<String, dynamic> value, String fallback) {
    final location = value['location'];
    final locationSource = location is Map ? _text(location, 'source') : '';
    final source = _text(value, 'source').isNotEmpty
        ? _text(value, 'source')
        : _text(value, 'agentSource');
    if (source == 'plugin' || locationSource == 'plugin') return 'plugin';
    if (source == 'user' ||
        source == 'zcodeAgent' ||
        locationSource == 'zcode') {
      return 'local';
    }
    return fallback;
  }

  static bool _sameMap(Map<String, dynamic> left, Map<String, dynamic> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  bool _pluginIsEnabled(RemoteAgentEntry entry) {
    final catalog = pluginCatalog;
    if (catalog == null) return true;
    final rawId = _text(entry.raw, 'pluginId');
    final rawName = _text(entry.raw, 'pluginName');
    final rawMarketplace = _text(entry.raw, 'pluginMarketplace').isNotEmpty
        ? _text(entry.raw, 'pluginMarketplace')
        : _text(entry.raw, 'marketplace');
    final matches = catalog.items.where((plugin) {
      if (!plugin.enabled) return false;
      if (rawId.isNotEmpty && plugin.id != rawId) return false;
      if (rawMarketplace.isNotEmpty && plugin.marketplace != rawMarketplace) {
        return false;
      }
      if (rawName.isNotEmpty && plugin.name != rawName) return false;
      return rawId.isNotEmpty || rawName.isNotEmpty;
    }).toList();
    if (matches.length == 1) return true;
    if (rawId.isNotEmpty || rawName.isNotEmpty) return false;
    // A legacy plugin row can contain only its display name. Reuse a name
    // only when the enabled catalog has one unique identity for that name.
    final names = catalog.items
        .where((plugin) => plugin.enabled && plugin.name == entry.name)
        .toList();
    return names.length == 1;
  }
}

/// One workspace hook, mirroring the official `hooksService.loadHooks`
/// rows: `{id,event,matcher,type,command,args?,async?,shell?,statusMessage?,
/// timeout,enabled,custom,location{source,scope,directoryPath?}}`.
class WorkspaceHook {
  const WorkspaceHook({
    required this.id,
    required this.event,
    required this.matcher,
    required this.type,
    required this.command,
    required this.enabled,
    required this.raw,
    this.editable,
    this.locationSource,
    this.locationScope,
  });

  factory WorkspaceHook.fromRaw(Map raw) {
    final map = raw.cast<String, dynamic>();
    final location = map['location'] is Map
        ? (map['location'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return WorkspaceHook(
      id: _text(map, 'id').isEmpty ? _text(map, 'name') : _text(map, 'id'),
      event: _text(map, 'event'),
      matcher: _text(map, 'matcher'),
      type: _text(map, 'type'),
      command: _text(map, 'command'),
      enabled: _bool(map, 'enabled') ?? true,
      editable: _bool(map, 'editable'),
      locationSource:
          location['source'] is String ? location['source'] as String : null,
      locationScope:
          location['scope'] is String ? location['scope'] as String : null,
      raw: map,
    );
  }

  /// Official `P7`: editable unless the hook comes from a non-zcode source
  /// (plugin-provided hooks stay read-only).
  bool get isEditable =>
      editable ?? (locationSource == null || locationSource == 'zcode');

  final String id;
  final String event;
  final String matcher;
  final String type;
  final String command;
  final bool enabled;
  final bool? editable;
  final String? locationSource;
  final String? locationScope;
  final Map<String, dynamic> raw;

  /// Form fields exposed by the official hooks page. The raw map remains the
  /// source of truth so fields added by a newer host survive a round trip.
  List<String> get args => raw['args'] is List
      ? [
          for (final value in raw['args'] as List)
            if (value is String) value,
        ]
      : const <String>[];
  bool get isAsync => raw['async'] == true;
  Object? get shell => raw['shell'];
  String get statusMessage => _text(raw, 'statusMessage');
  int get timeout => raw['timeout'] is num
      ? (raw['timeout'] as num).toInt()
      : int.tryParse('${raw['timeout'] ?? ''}') ?? 60;
  Map<String, dynamic>? get custom => raw['custom'] is Map
      ? (raw['custom'] as Map).cast<String, dynamic>()
      : null;
  Map<String, dynamic> get location => raw['location'] is Map
      ? (raw['location'] as Map).cast<String, dynamic>()
      : const <String, dynamic>{};
  String? get directoryPath => location['directoryPath'] is String
      ? location['directoryPath'] as String
      : null;
  String get storageLevel => locationScope == 'project' ? 'project' : 'user';

  /// The trust projection is carried by the host alongside a hook row. Keep
  /// it typed only at the boundary; its digest and identity must be forwarded
  /// unchanged to the existing review controller.
  Map<String, dynamic>? get workspaceHook => raw['workspaceHook'] is Map
      ? (raw['workspaceHook'] as Map).cast<String, dynamic>()
      : null;
  String? get trustState => workspaceHook?['trustState'] is String
      ? workspaceHook!['trustState'] as String
      : null;
  bool get requiresTrust =>
      workspaceHook != null &&
      trustState != null &&
      trustState != 'trusted_persistent';
  String? get bundleDigest => workspaceHook?['bundleDigest'] is String
      ? workspaceHook!['bundleDigest'] as String
      : null;
  String? get hookDeclarationDigest =>
      workspaceHook?['hookDeclarationDigest'] is String
          ? workspaceHook!['hookDeclarationDigest'] as String
          : null;
  String? get reviewItemId => workspaceHook?['reviewItemId'] is String
      ? workspaceHook!['reviewItemId'] as String
      : null;
  String? get workspaceIdentity => workspaceHook?['workspaceIdentity'] is String
      ? workspaceHook!['workspaceIdentity'] as String
      : null;

  Map<String, dynamic> withEnabled(bool value) => {...raw, 'enabled': value};

  /// Official create payload (`WXt` + `UXt` in js-1): fresh `hook-<uuid>`
  /// id, zcode-owned location, type-inapplicable fields absent, empty
  /// optional text fields omitted, timeout 60 / enabled true defaults.
  /// Storage level stays `user`: the settings page scope pill reads 用户
  /// and the project variant (projectPath) has no live capture yet.
  static Map<String, dynamic> buildCreateRaw({
    required String event,
    required String type,
    required String command,
    String? matcher,
    List<String>? args,
    bool? async,
    String? shell,
    String? statusMessage,
    int? timeout,
    bool enabled = true,
    Map<String, dynamic>? custom,
    String storageLevel = 'user',
    String? workspacePath,
    String? directoryPath,
  }) {
    final project =
        storageLevel == 'project' && workspacePath?.trim().isNotEmpty == true;
    return <String, dynamic>{
      'id': 'hook-${_hookUuidV4()}',
      'event': event,
      if (matcher?.trim().isNotEmpty == true) 'matcher': matcher!.trim(),
      'type': type,
      'command': command.trim(),
      if (type == 'process')
        'args': [...?args]
      else ...<String, dynamic>{
        'async': async ?? false,
        if (shell?.trim().isNotEmpty == true) 'shell': shell!.trim(),
      },
      if (statusMessage?.trim().isNotEmpty == true)
        'statusMessage': statusMessage!.trim(),
      'timeout': timeout ?? 60,
      'enabled': enabled,
      if (custom != null && custom.isNotEmpty) 'custom': custom,
      'location': {
        'source': 'zcode',
        'scope': project ? 'project' : 'user',
        'directoryPath': project
            ? (directoryPath?.trim().isNotEmpty == true
                ? directoryPath!.trim()
                : workspacePath!.trim())
            : '',
      },
    };
  }

  /// Official update payload (`GXt` in js-1): keep id/location/enabled
  /// through the original raw, override the form fields, and drop the keys
  /// that stop applying when the type changes (`args` for command hooks,
  /// `async`/`shell` for process hooks).
  Map<String, dynamic> withFormUpdate({
    required String event,
    required String type,
    required String command,
    String? matcher,
    List<String>? args,
    bool? async,
    String? shell,
    String? statusMessage,
    int? timeout,
    Map<String, dynamic>? custom,
    String? storageLevel,
    String? workspacePath,
    String? directoryPath,
  }) {
    final updated = {...raw};
    updated['event'] = event;
    final trimmedMatcher = matcher?.trim() ?? '';
    if (trimmedMatcher.isEmpty) {
      updated.remove('matcher');
    } else {
      updated['matcher'] = trimmedMatcher;
    }
    updated['type'] = type;
    updated['command'] = command.trim();
    if (type == 'process') {
      updated['args'] = [...?args];
      updated
        ..remove('async')
        ..remove('shell');
    } else {
      updated.remove('args');
      updated['async'] = async ?? false;
      final trimmedShell = shell?.trim() ?? '';
      if (trimmedShell.isEmpty) {
        updated.remove('shell');
      } else {
        updated['shell'] = trimmedShell;
      }
    }
    final trimmedStatus = statusMessage?.trim() ?? '';
    if (trimmedStatus.isEmpty) {
      updated.remove('statusMessage');
    } else {
      updated['statusMessage'] = trimmedStatus;
    }
    updated['timeout'] = timeout ?? 60;
    if (custom != null && custom.isNotEmpty) {
      updated['custom'] = custom;
    } else {
      updated.remove('custom');
    }
    if (storageLevel != null && storageLevel != this.storageLevel) {
      final project =
          storageLevel == 'project' && workspacePath?.trim().isNotEmpty == true;
      final nextLocation = <String, dynamic>{...location};
      nextLocation['source'] = locationSource ?? 'zcode';
      nextLocation['scope'] = project ? 'project' : 'user';
      nextLocation['directoryPath'] = project
          ? (directoryPath?.trim().isNotEmpty == true
              ? directoryPath!.trim()
              : workspacePath!.trim())
          : '';
      updated['location'] = nextLocation;
    }
    return updated;
  }
}

/// Official hook ids are `hook-<uuid>`; the bundle uses the platform uuid,
/// so the local form generates a random v4-shaped id.
String _hookUuidV4() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  String hex(int value) => value.toRadixString(16).padLeft(2, '0');
  final octets = [
    bytes.sublist(0, 4).map(hex).join(),
    bytes.sublist(4, 6).map(hex).join(),
    bytes.sublist(6, 8).map(hex).join(),
    bytes.sublist(8, 10).map(hex).join(),
    bytes.sublist(10, 16).map(hex).join(),
  ];
  return octets.join('-');
}

enum _HookIntentKind { add, update, delete }

class _HookIntent {
  const _HookIntent(this.kind, this.id, this.raw);

  final _HookIntentKind kind;
  final String id;
  final Map<String, dynamic>? raw;
}

class _HookListIntent {
  _HookListIntent(this.changes);

  factory _HookListIntent.from(
      List<WorkspaceHook> baseline, List<WorkspaceHook> requested) {
    final before = <String, WorkspaceHook>{
      for (final hook in baseline) hook.id: hook,
    };
    final after = <String, WorkspaceHook>{
      for (final hook in requested) hook.id: hook,
    };
    final changes = <_HookIntent>[];
    for (final hook in baseline) {
      if (!after.containsKey(hook.id)) {
        changes.add(_HookIntent(_HookIntentKind.delete, hook.id, null));
      } else if (!_deepMapEqual(hook.raw, after[hook.id]!.raw)) {
        changes.add(
            _HookIntent(_HookIntentKind.update, hook.id, after[hook.id]!.raw));
      }
    }
    for (final hook in requested) {
      if (!before.containsKey(hook.id)) {
        changes.add(_HookIntent(_HookIntentKind.add, hook.id, hook.raw));
      }
    }
    return _HookListIntent(changes);
  }

  final List<_HookIntent> changes;

  List<WorkspaceHook> apply(List<WorkspaceHook> latest) {
    final result = [...latest];
    for (final change in changes) {
      switch (change.kind) {
        case _HookIntentKind.delete:
          result.removeWhere((hook) => hook.id == change.id);
        case _HookIntentKind.update:
          final index = result.indexWhere((hook) => hook.id == change.id);
          // A previous queued delete wins; an update must never resurrect it.
          if (index >= 0 && change.raw != null) {
            result[index] = WorkspaceHook.fromRaw(change.raw!);
          }
        case _HookIntentKind.add:
          if (change.raw != null &&
              !result.any((hook) => hook.id == change.id)) {
            result.add(WorkspaceHook.fromRaw(change.raw!));
          }
      }
    }
    return result;
  }
}

bool _deepMapEqual(Object? left, Object? right) {
  if (identical(left, right)) return true;
  if (left is Map && right is Map) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_deepMapEqual(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_deepMapEqual(left[index], right[index])) return false;
    }
    return true;
  }
  return left == right;
}

/// Official `hooksService.loadHooks` / `saveHooks` projection. Every
/// mutation (add/update/delete/toggle) is a whole-list `saveHooks` write in
/// the official bundle, so this catalog exposes the loaded list plus a
/// single guarded [saveList] used by the settings page; per-hook semantics
/// (which rows are editable) stay in [WorkspaceHook.isEditable].
class HooksCatalog extends ChangeNotifier {
  HooksCatalog({
    required this.session,
    required this.scope,
    required this.scopeKey,
    this.workspacePath,
  });

  final BridgeSession session;
  final Map<String, dynamic> scope;
  final String scopeKey;
  final String? workspacePath;

  int _generation = 0;
  Future<void>? _pending;
  Future<void> _queueTail = Future<void>.value();
  bool _disposed = false;
  bool _needsFreshReadback = false;
  final Set<String> _savingIds = <String>{};
  final Map<String, Object?> _saveErrors = <String, Object?>{};

  RemoteAgentCatalogStatus status = RemoteAgentCatalogStatus.idle;
  List<WorkspaceHook> items = const [];
  // This list changes only after a successful loadHooks read-back. Mutations
  // replay their intent against it when they leave the queue.
  List<WorkspaceHook> _confirmedItems = const [];
  bool? hooksEnabled;
  Object? error;

  bool isSaving(String id) => _savingIds.contains(id);
  Object? saveError(String id) => _saveErrors[id];

  Future<Object?> _call(String method, Map<String, dynamic> values) =>
      session.channels.call(
          Channels.hooks,
          method,
          [
            {...scope, ...values}
          ],
          timeout: const Duration(seconds: 30));

  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future.value();
    final pending = _pending;
    if (pending != null && !force) return pending;
    // A write read-back must never reuse a loadHooks request that began before
    // saveHooks. Its late response is discarded by the generation check.
    if (force) ++_generation;
    final generation = ++_generation;
    status = RemoteAgentCatalogStatus.loading;
    notifyListeners();
    Future<void>? operationFuture;
    Future<void> operation() async {
      try {
        final raw = await _call('loadHooks', {
          if (workspacePath?.isNotEmpty == true)
            'workspacePath': workspacePath!,
        });
        if (_disposed || generation != _generation) return;
        if (raw is! Map || raw['hooks'] is! List) {
          throw const FormatException('missing hooks list');
        }
        final map = raw.cast<String, dynamic>();
        items = [
          if (map['hooks'] is List)
            for (final item in (map['hooks'] as List).whereType<Map>())
              WorkspaceHook.fromRaw(item),
        ];
        _confirmedItems = List<WorkspaceHook>.unmodifiable(items);
        hooksEnabled =
            map['hooksEnabled'] is bool ? map['hooksEnabled'] as bool : null;
        status = RemoteAgentCatalogStatus.loaded;
        error = null;
      } catch (value) {
        if (_disposed || generation != _generation) return;
        status = RemoteAgentCatalogStatus.error;
        error = value;
      } finally {
        if (_pending == operationFuture) _pending = null;
        if (!_disposed && generation == _generation) notifyListeners();
      }
    }

    operationFuture = operation();
    _pending = operationFuture;
    return operationFuture;
  }

  /// Official `saveHooks({workspacePath, workspaceIdentity, hooks})`: the
  /// whole list is written back, then the read-back refresh is the only
  /// source of visible state. Failure keeps the previous list and records
  /// the error under [errorId] for retry.
  Future<void> saveList(List<WorkspaceHook> hooks,
      {required String errorId}) async {
    if (_disposed || _savingIds.contains(errorId)) return;
    final intent = _HookListIntent.from(_confirmedItems, hooks);
    _savingIds.add(errorId);
    _saveErrors.remove(errorId);
    notifyListeners();
    final operation = _enqueue(() async {
      if (_needsFreshReadback) {
        await refresh(force: true);
        if (status == RemoteAgentCatalogStatus.error) {
          throw error ?? StateError('hook read-back failed');
        }
        _needsFreshReadback = false;
      }
      final replayed = intent.apply(_confirmedItems);
      // A save RPC can apply remotely and fail while returning its response.
      // Mark the confirmation dirty before sending; only a successful fresh
      // read-back may clear it.
      _needsFreshReadback = true;
      await _call('saveHooks', {
        if (workspacePath?.isNotEmpty == true) 'workspacePath': workspacePath!,
        'hooks': [for (final hook in replayed) hook.raw],
      });
      if (_disposed) return;
      await refresh(force: true);
      // refresh() retains the confirmed rows on failure. A write is not
      // considered committed until that read-back succeeds.
      if (status == RemoteAgentCatalogStatus.error) {
        throw error ?? StateError('hook read-back failed');
      }
      _needsFreshReadback = false;
      _saveErrors.remove(errorId);
    });
    try {
      await operation;
    } catch (value) {
      if (!_disposed) _saveErrors[errorId] = value;
    } finally {
      _savingIds.remove(errorId);
      if (!_disposed) notifyListeners();
    }
  }

  /// High-level operations used by the page avoid exposing whole-list details
  /// to callers while retaining [saveList]'s compatibility contract.
  Future<void> setEnabled(WorkspaceHook hook, bool enabled,
          {String? errorId}) =>
      saveList([
        for (final item in items)
          item.id == hook.id
              ? WorkspaceHook.fromRaw(item.withEnabled(enabled))
              : item,
      ], errorId: errorId ?? 'toggle-${hook.id}');

  Future<void> deleteHook(WorkspaceHook hook, {String? errorId}) => saveList(
        [
          for (final item in items)
            if (item.id != hook.id) item
        ],
        errorId: errorId ?? 'delete-${hook.id}',
      );

  Future<void> importHook(WorkspaceHook hook, {String? errorId}) {
    if (workspacePath?.trim().isEmpty != false) {
      return Future<void>.error(StateError('No workspace path set'));
    }
    final location = hook.location;
    final sourceScope =
        location['scope'] is String ? location['scope'] as String : 'user';
    final imported = <String, dynamic>{
      ...hook.raw,
      'id': 'hook-${_hookUuidV4()}',
      'enabled': true,
      'location': {
        ...location,
        'source': 'zcode',
        'scope': sourceScope == 'project' ? 'project' : 'user',
        'directoryPath': workspacePath!.trim(),
      },
    };
    return saveList(
      [...items, WorkspaceHook.fromRaw(imported)],
      errorId: errorId ?? 'import-${hook.id}',
    );
  }

  /// Official no-session trust branch (`grantWithoutSession`): the host
  /// receives only the exact workspace identity and the two confirmed hook
  /// digests. Callers must still treat the response as untrusted until
  /// `accepted == true` is returned.
  Future<Map<String, dynamic>> grantWorkspaceHookTrust(
    WorkspaceHook hook, {
    String? workspaceIdentity,
  }) async {
    final path = workspacePath?.trim() ?? '';
    final requestedIdentity = workspaceIdentity?.trim() ?? '';
    final scopeIdentity = scope['workspaceIdentity'] is String
        ? (scope['workspaceIdentity'] as String).trim()
        : '';
    final identity = requestedIdentity.isNotEmpty
        ? requestedIdentity
        : (scopeIdentity.isNotEmpty ? scopeIdentity : path);
    final hookIdentity = hook.workspaceIdentity?.trim() ?? '';
    final bundleDigest = hook.bundleDigest?.trim() ?? '';
    final declarationDigest = hook.hookDeclarationDigest?.trim() ?? '';
    if (path.isEmpty ||
        identity.isEmpty ||
        hookIdentity.isEmpty ||
        hookIdentity != identity ||
        bundleDigest.isEmpty ||
        declarationDigest.isEmpty) {
      return const {
        'accepted': false,
        'reasonCode': 'workspace_hooks_snapshot_mismatch',
      };
    }
    final values = <String, dynamic>{
      'workspacePath': path,
      if (requestedIdentity.isNotEmpty || scopeIdentity.isNotEmpty)
        'workspaceIdentity': identity,
      'bundleDigest': bundleDigest,
      'hookDeclarationDigest': declarationDigest,
    };
    final raw = await _call('grantWorkspaceHookTrust', values);
    if (raw is! Map || raw['accepted'] is! bool) {
      return const {
        'accepted': false,
        'reasonCode': 'workspace_hooks_trust_invalid_response',
      };
    }
    return raw.cast<String, dynamic>();
  }

  Future<void> updateHook(
    WorkspaceHook hook, {
    required String event,
    required String type,
    required String command,
    String? matcher,
    List<String>? args,
    bool? async,
    String? shell,
    String? statusMessage,
    int? timeout,
    Map<String, dynamic>? custom,
    String? storageLevel,
    String? directoryPath,
    String? errorId,
  }) {
    final updated = hook.withFormUpdate(
      event: event,
      type: type,
      command: command,
      matcher: matcher,
      args: args,
      async: async,
      shell: shell,
      statusMessage: statusMessage,
      timeout: timeout,
      custom: custom,
      storageLevel: storageLevel,
      workspacePath: workspacePath,
      directoryPath: directoryPath,
    );
    return saveList(
      [
        for (final item in items)
          item.id == hook.id ? WorkspaceHook.fromRaw(updated) : item,
      ],
      errorId: errorId ?? 'form-${hook.id}',
    );
  }

  Future<void> createHook({
    required String event,
    required String type,
    required String command,
    String? matcher,
    List<String>? args,
    bool? async,
    String? shell,
    String? statusMessage,
    int? timeout,
    bool enabled = true,
    Map<String, dynamic>? custom,
    String storageLevel = 'user',
    String? directoryPath,
    String? errorId,
  }) {
    final raw = WorkspaceHook.buildCreateRaw(
      event: event,
      type: type,
      command: command,
      matcher: matcher,
      args: args,
      async: async,
      shell: shell,
      statusMessage: statusMessage,
      timeout: timeout,
      enabled: enabled,
      custom: custom,
      storageLevel: storageLevel,
      workspacePath: workspacePath,
      directoryPath: directoryPath,
    );
    return saveList(
      [...items, WorkspaceHook.fromRaw(raw)],
      errorId: errorId ?? 'form-new',
    );
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    final completer = Completer<void>();
    final previous = _queueTail;
    _queueTail = previous.then<void>((_) async {
      try {
        await operation();
        completer.complete();
      } catch (value, stack) {
        if (!completer.isCompleted) completer.completeError(value, stack);
      }
    });
    return completer.future;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
