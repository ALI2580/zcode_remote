import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../protocol/channel_client.dart';
import '../protocol/zemote_client.dart';

const importScopes = <String>['global', 'project'];
const importModes = <String>['symlink', 'copy'];
const importCategories = <String>[
  'skills',
  'commands',
  'plugins',
  'mcpServers'
];

String _text(Object? value) => value is String ? value.trim() : '';

int _count(Object? value) => value is num ? value.toInt() : 0;

Map<String, dynamic> _asMap(Object? value) => value is Map
    ? Map<String, dynamic>.from(
        value.map((key, value) => MapEntry(key.toString(), value)))
    : <String, dynamic>{};

List<Map<String, dynamic>> _maps(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) _asMap(item)
      ]
    : const <Map<String, dynamic>>[];

String importSelectionKey({
  required String agent,
  required String category,
  String? sourceScope,
  required String resourcePath,
}) =>
    jsonEncode({
      'agent': agent,
      'category': category,
      if (sourceScope != null && sourceScope.isNotEmpty)
        'sourceScope': sourceScope,
      'resourcePath': resourcePath,
    });

class ExternalAgentResource {
  const ExternalAgentResource({
    required this.path,
    required this.name,
    required this.importable,
    required this.raw,
    this.version,
  });

  factory ExternalAgentResource.fromRaw(Map raw) {
    final map = _asMap(raw);
    final path = _text(map['path']);
    return ExternalAgentResource(
      path: path,
      name: _text(map['name']).isEmpty ? path : _text(map['name']),
      version: _text(map['version']).isEmpty ? null : _text(map['version']),
      importable: map['importable'] == true,
      raw: map,
    );
  }

  final String path;
  final String name;
  final String? version;
  final bool importable;
  final Map<String, dynamic> raw;
}

class ExternalAgentSourceRoot {
  const ExternalAgentSourceRoot({
    required this.scope,
    required this.path,
    required this.discoveredCount,
    required this.importableCount,
    required this.skippedCount,
    required this.resources,
    required this.raw,
  });

  factory ExternalAgentSourceRoot.fromRaw(
    Map raw, {
    required String scope,
    required String category,
  }) {
    final map = _asMap(raw);
    final resources = _resourcesForCategory(map, category);
    return ExternalAgentSourceRoot(
      scope: _text(map['scope']).isEmpty ? scope : _text(map['scope']),
      path: _text(map['path']),
      discoveredCount: _count(map['discoveredCount']),
      importableCount: _count(map['importableCount']),
      skippedCount: _count(map['skippedCount']),
      resources: resources,
      raw: map,
    );
  }

  final String scope;
  final String path;
  final int discoveredCount;
  final int importableCount;
  final int skippedCount;
  final List<ExternalAgentResource> resources;
  final Map<String, dynamic> raw;

  static List<ExternalAgentResource> _resourcesForCategory(
      Map<String, dynamic> map, String category) {
    final key = switch (category) {
      'skills' => 'skills',
      'commands' => 'commands',
      'plugins' => 'plugins',
      _ => 'mcpServers',
    };
    return [
      for (final item in _maps(map[key])) ExternalAgentResource.fromRaw(item)
    ];
  }
}

class ExternalAgentCategory {
  const ExternalAgentCategory({
    required this.category,
    required this.sourceRoots,
    required this.raw,
  });

  factory ExternalAgentCategory.fromRaw(
    Map raw, {
    required String category,
    required String? workspacePath,
  }) {
    final map = _asMap(raw);
    final roots = <ExternalAgentSourceRoot>[];
    final explicitRoots = _maps(map['sourceRoots']);
    if (explicitRoots.isNotEmpty) {
      roots.addAll([
        for (final root in explicitRoots)
          ExternalAgentSourceRoot.fromRaw(
            root,
            scope: _text(root['scope']).isEmpty
                ? inferImportScope(_text(root['path']), workspacePath)
                : _text(root['scope']),
            category: category,
          )
      ]);
    } else {
      for (final rawPath in (map['sourcePaths'] is List
          ? map['sourcePaths'] as List
          : const <Object?>[])) {
        final source = rawPath is Map
            ? _asMap(rawPath)
            : <String, dynamic>{'path': rawPath};
        final sourceScope = _text(source['scope']).isEmpty
            ? inferImportScope(_text(source['path']), workspacePath)
            : _text(source['scope']);
        roots.add(ExternalAgentSourceRoot.fromRaw(
          source,
          scope: sourceScope,
          category: category,
        ));
      }
      // A few older responses put resources on the category object while
      // returning sourcePaths only as strings. Keep those resources visible.
      if (roots.length == 1 && roots.single.resources.isEmpty) {
        final resources =
            ExternalAgentSourceRoot._resourcesForCategory(map, category);
        if (resources.isNotEmpty) {
          final root = roots.single;
          roots[0] = ExternalAgentSourceRoot(
            scope: root.scope,
            path: root.path,
            discoveredCount: root.discoveredCount,
            importableCount: root.importableCount,
            skippedCount: root.skippedCount,
            resources: resources,
            raw: root.raw,
          );
        }
      }
    }
    return ExternalAgentCategory(
      category: category,
      sourceRoots: roots,
      raw: map,
    );
  }

  final String category;
  final List<ExternalAgentSourceRoot> sourceRoots;
  final Map<String, dynamic> raw;

  int get importableCount => sourceRoots.fold(
      0, (sum, root) => sum + root.resources.where((e) => e.importable).length);
}

class ExternalAgent {
  const ExternalAgent({
    required this.id,
    required this.label,
    required this.categories,
    required this.raw,
  });

  factory ExternalAgent.fromRaw(
    Map raw, {
    required String? workspacePath,
  }) {
    final map = _asMap(raw);
    final id = _text(map['agent']).isNotEmpty
        ? _text(map['agent'])
        : (_text(map['id']).isNotEmpty ? _text(map['id']) : _text(map['name']));
    final categories = <ExternalAgentCategory>[];
    for (final rawCategory in _maps(map['categories'])) {
      final category = _text(rawCategory['category']);
      if (category.isEmpty) continue;
      categories.add(ExternalAgentCategory.fromRaw(
        rawCategory,
        category: category,
        workspacePath: workspacePath,
      ));
    }
    return ExternalAgent(
      id: id,
      label: _text(map['name']).isNotEmpty
          ? _text(map['name'])
          : (id.isEmpty ? 'Unknown agent' : id),
      categories: categories,
      raw: map,
    );
  }

  final String id;
  final String label;
  final List<ExternalAgentCategory> categories;
  final Map<String, dynamic> raw;

  ExternalAgentCategory? category(String value) {
    for (final item in categories) {
      if (item.category == value) return item;
    }
    return null;
  }
}

class ExternalAgentDiscovery {
  const ExternalAgentDiscovery({required this.agents, required this.raw});

  factory ExternalAgentDiscovery.fromRaw(
    Object? value, {
    required String? workspacePath,
  }) {
    final map = _asMap(value);
    return ExternalAgentDiscovery(
      agents: [
        for (final agent in _maps(map['agents']))
          ExternalAgent.fromRaw(agent, workspacePath: workspacePath),
      ],
      raw: map,
    );
  }

  final List<ExternalAgent> agents;
  final Map<String, dynamic> raw;

  int get totalImportableCount => agents.fold(
      0,
      (sum, agent) =>
          sum +
          agent.categories
              .fold(0, (inner, category) => inner + category.importableCount));
}

String inferImportScope(String path, String? workspacePath) {
  if (workspacePath == null || workspacePath.trim().isEmpty) return 'global';
  final normalizedPath = _normalizePath(path);
  final normalizedWorkspace = _normalizePath(workspacePath);
  return normalizedPath == normalizedWorkspace ||
          normalizedPath.startsWith('$normalizedWorkspace/')
      ? 'project'
      : 'global';
}

String _normalizePath(String value) =>
    value.replaceAll('\\', '/').replaceFirst(RegExp(r'/+$'), '').toLowerCase();

class ImportSelection {
  const ImportSelection({
    required this.agent,
    required this.category,
    required this.resourcePath,
    this.sourceScope,
  });

  factory ImportSelection.fromKey(String key) {
    final decoded = jsonDecode(key);
    if (decoded is! Map ||
        decoded['agent'] is! String ||
        decoded['category'] is! String ||
        decoded['resourcePath'] is! String) {
      throw const FormatException('invalid import selection');
    }
    return ImportSelection(
      agent: decoded['agent'] as String,
      category: decoded['category'] as String,
      sourceScope: decoded['sourceScope'] is String
          ? decoded['sourceScope'] as String
          : null,
      resourcePath: decoded['resourcePath'] as String,
    );
  }

  final String agent;
  final String category;
  final String? sourceScope;
  final String resourcePath;

  String get key => importSelectionKey(
        agent: agent,
        category: category,
        sourceScope: sourceScope,
        resourcePath: resourcePath,
      );
}

List<Map<String, dynamic>> buildImportSelections(
  Iterable<String> keys, {
  required String targetScope,
  required String importMode,
}) {
  final grouped = <String, Map<String, dynamic>>{};
  for (final key in keys) {
    ImportSelection selection;
    try {
      selection = ImportSelection.fromKey(key);
    } on Object {
      continue;
    }
    final groupKey = jsonEncode([
      selection.agent,
      selection.category,
      selection.sourceScope,
    ]);
    final payload = grouped.putIfAbsent(groupKey, () {
      final map = <String, dynamic>{
        'agent': selection.agent,
        'category': selection.category,
        'targetScope': targetScope,
        'importMode': importMode,
      };
      if (selection.sourceScope != null && selection.sourceScope!.isNotEmpty) {
        map['sourceScope'] = selection.sourceScope;
      }
      map[switch (selection.category) {
        'skills' => 'skillPaths',
        'commands' => 'commandPaths',
        'plugins' => 'pluginPaths',
        _ => 'mcpServerPaths',
      }] = <String>[];
      return map;
    });
    final pathKey = switch (selection.category) {
      'skills' => 'skillPaths',
      'commands' => 'commandPaths',
      'plugins' => 'pluginPaths',
      _ => 'mcpServerPaths',
    };
    final paths = payload[pathKey] as List<String>;
    if (!paths.contains(selection.resourcePath)) {
      paths.add(selection.resourcePath);
    }
  }
  return grouped.values.toList(growable: false);
}

class ExternalAgentImportTaskResult {
  const ExternalAgentImportTaskResult({required this.raw});

  factory ExternalAgentImportTaskResult.fromRaw(Map raw) =>
      ExternalAgentImportTaskResult(raw: _asMap(raw));

  final Map<String, dynamic> raw;
  String get status => _text(raw['status']);
  String get name => _text(raw['name']);
  String get path => _text(raw['path']);
  String? get version =>
      _text(raw['version']).isEmpty ? null : _text(raw['version']);
  String? get sourceScope =>
      _text(raw['sourceScope']).isEmpty ? null : _text(raw['sourceScope']);
  String? get skipReason =>
      _text(raw['skipReason']).isEmpty ? null : _text(raw['skipReason']);
}

class ExternalAgentImportResult {
  const ExternalAgentImportResult({
    required this.successCount,
    required this.skippedCount,
    required this.failedCount,
    required this.taskResults,
    required this.raw,
  });

  factory ExternalAgentImportResult.fromRaw(Object? value) {
    final map = _asMap(value);
    final taskResults = <ExternalAgentImportTaskResult>[];
    for (final task in _maps(map['taskResults'])) {
      // The official result keeps per-category arrays under each task. Keep
      // the complete response shape while flattening rows for the result UI.
      final nested = <String>[
        'skillResults',
        'commandResults',
        'pluginResults',
        'mcpServerResults',
      ];
      var foundNested = false;
      for (final key in nested) {
        for (final row in _maps(task[key])) {
          taskResults.add(ExternalAgentImportTaskResult.fromRaw(row));
          foundNested = true;
        }
      }
      if (!foundNested && _text(task['status']).isNotEmpty) {
        taskResults.add(ExternalAgentImportTaskResult.fromRaw(task));
      }
    }
    var imported = _count(map['successCount']);
    var skipped = _count(map['skippedCount']);
    var failed = _count(map['failedCount']);
    if (map['successCount'] == null &&
        map['skippedCount'] == null &&
        map['failedCount'] == null) {
      for (final result in taskResults) {
        switch (result.status) {
          case 'imported':
            imported++;
          case 'skipped':
            skipped++;
          case 'failed':
            failed++;
        }
      }
    }
    return ExternalAgentImportResult(
      successCount: imported,
      skippedCount: skipped,
      failedCount: failed,
      taskResults: taskResults,
      raw: map,
    );
  }

  final int successCount;
  final int skippedCount;
  final int failedCount;
  final List<ExternalAgentImportTaskResult> taskResults;
  final Map<String, dynamic> raw;
}

abstract class SettingsSyncService {
  Future<Object?> detect({
    String? workspacePath,
    String? workspaceIdentity,
    required List<String> categories,
    required String intent,
  });

  Future<Object?> importSelected({
    String? workspacePath,
    String? workspaceIdentity,
    required List<Map<String, dynamic>> selections,
  });
}

/// Direct adapter for the verified `settings-sync.detect/importSelected`
/// payloads. Tests can inject [SettingsSyncService] without touching a live
/// attachment.
class ChannelSettingsSyncService implements SettingsSyncService {
  ChannelSettingsSyncService(this.session);

  final BridgeSession session;

  @override
  Future<Object?> detect({
    String? workspacePath,
    String? workspaceIdentity,
    required List<String> categories,
    required String intent,
  }) =>
      session.channels.call(
        Channels.settingsSync,
        'detect',
        [
          {
            if (workspacePath?.trim().isNotEmpty == true)
              'workspacePath': workspacePath!.trim(),
            if (workspaceIdentity?.trim().isNotEmpty == true)
              'workspaceIdentity': workspaceIdentity!.trim(),
            'categories': categories,
            'intent': intent,
          }
        ],
        timeout: const Duration(seconds: 30),
      );

  @override
  Future<Object?> importSelected({
    String? workspacePath,
    String? workspaceIdentity,
    required List<Map<String, dynamic>> selections,
  }) =>
      session.channels.call(
        Channels.settingsSync,
        'importSelected',
        [
          {
            if (workspacePath?.trim().isNotEmpty == true)
              'workspacePath': workspacePath!.trim(),
            if (workspaceIdentity?.trim().isNotEmpty == true)
              'workspaceIdentity': workspaceIdentity!.trim(),
            'selections': selections,
          }
        ],
        timeout: const Duration(seconds: 60),
      );
}

enum ExternalAgentImportStatus {
  idle,
  scanning,
  ready,
  importing,
  complete,
  error
}

/// Flattened `visibleRoots` entry: agent + root + the requested category.
class ExternalAgentRootRow {
  const ExternalAgentRootRow(this.agent, this.root, this.category);

  final ExternalAgent agent;
  final ExternalAgentSourceRoot root;
  final String category;
}

class ExternalAgentImportController extends ChangeNotifier {
  /// One or more `settings-sync` categories. The official onboarding entry
  /// (`settings.onboarding` → 引导) reopens the import dialog with every
  /// category at once; the wire `detect` accepts a category list.
  ExternalAgentImportController({
    required this.service,
    required String category,
    List<String>? categories,
    this.workspacePath,
    this.workspaceIdentity,
  }) : categories = categories ?? [category] {
    for (final value in this.categories) {
      if (!importCategories.contains(value)) {
        throw ArgumentError.value(
            value, 'categories', 'unsupported import category');
      }
    }
  }

  final SettingsSyncService service;
  final List<String> categories;
  String get category => categories.first;
  String? workspacePath;
  String? workspaceIdentity;

  int _generation = 0;
  Future<void>? _pendingScan;
  Future<bool>? _pendingImport;
  bool _disposed = false;
  final Set<String> _selectedKeys = <String>{};
  final Set<String> _expandedSourceKeys = <String>{};

  ExternalAgentImportStatus status = ExternalAgentImportStatus.idle;
  ExternalAgentDiscovery? discovery;
  ExternalAgentImportResult? result;
  Object? error;
  String activeSourceScope = 'global';
  String importTargetScope = 'global';
  String importMode = 'symlink';

  bool get canTargetProject => workspacePath?.trim().isNotEmpty == true;
  Set<String> get selectedKeys => Set.unmodifiable(_selectedKeys);
  Set<String> get expandedSourceKeys => Set.unmodifiable(_expandedSourceKeys);
  int get selectedCount => _selectedKeys.length;
  int get totalImportableCount => discovery?.totalImportableCount ?? 0;

  void updateContext({String? nextWorkspacePath, String? nextIdentity}) {
    if (_disposed) return;
    if (workspacePath == nextWorkspacePath &&
        workspaceIdentity == nextIdentity) {
      return;
    }
    _generation++;
    _pendingScan = null;
    _pendingImport = null;
    workspacePath = nextWorkspacePath;
    workspaceIdentity = nextIdentity;
    _selectedKeys.clear();
    _expandedSourceKeys.clear();
    discovery = null;
    result = null;
    error = null;
    status = ExternalAgentImportStatus.idle;
    if (!canTargetProject) importTargetScope = 'global';
    notifyListeners();
  }

  Future<void> scan() {
    if (_disposed) return Future.value();
    final pending = _pendingScan;
    if (pending != null) return pending;
    final generation = ++_generation;
    status = ExternalAgentImportStatus.scanning;
    error = null;
    result = null;
    notifyListeners();
    Future<void>? future;
    Future<void> operation() async {
      try {
        final raw = await service.detect(
          workspacePath: workspacePath,
          workspaceIdentity: workspaceIdentity,
          categories: categories,
          intent: 'manualImport',
        );
        if (_disposed || generation != _generation) return;
        discovery = ExternalAgentDiscovery.fromRaw(
          raw,
          workspacePath: workspacePath,
        );
        _selectedKeys.clear();
        _expandedSourceKeys.clear();
        activeSourceScope = 'global';
        importTargetScope = canTargetProject ? 'global' : 'global';
        importMode = 'symlink';
        status = ExternalAgentImportStatus.ready;
        error = null;
      } catch (value) {
        if (_disposed || generation != _generation) return;
        status = ExternalAgentImportStatus.error;
        error = value;
        discovery = null;
      } finally {
        if (_pendingScan == future) _pendingScan = null;
        if (!_disposed && generation == _generation) notifyListeners();
      }
    }

    future = operation();
    _pendingScan = future;
    return future;
  }

  /// One flattened discovery row per source root, carrying the requested
  /// category so multi-category onboarding scans render every group.
  List<ExternalAgentRootRow> get visibleRoots {
    final rows = <ExternalAgentRootRow>[];
    final agents = discovery?.agents ?? const <ExternalAgent>[];
    for (final agent in agents) {
      for (final value in categories) {
        final data = agent.category(value);
        if (data == null) continue;
        for (final root in data.sourceRoots) {
          if (root.scope == activeSourceScope) {
            rows.add(ExternalAgentRootRow(agent, root, value));
          }
        }
      }
    }
    return rows;
  }

  String sourceKey(ExternalAgentRootRow row) =>
      '${row.agent.id}:${row.category}:${row.root.scope}:${row.root.path}';

  List<String> resourceKeysFor(ExternalAgentRootRow row) => [
        for (final resource in row.root.resources)
          if (resource.importable && resource.path.isNotEmpty)
            importSelectionKey(
              agent: row.agent.id,
              category: row.category,
              sourceScope: row.root.scope,
              resourcePath: resource.path,
            )
      ];

  bool isSelected(String key) => _selectedKeys.contains(key);

  bool isExpanded(ExternalAgentRootRow row) =>
      _expandedSourceKeys.contains(sourceKey(row));

  void setActiveSourceScope(String value) {
    if (!importScopes.contains(value) || value == activeSourceScope) return;
    activeSourceScope = value;
    notifyListeners();
  }

  void setImportTargetScope(String value) {
    if (value == 'project' && !canTargetProject) return;
    if (!importScopes.contains(value) || value == importTargetScope) return;
    importTargetScope = value;
    notifyListeners();
  }

  void setImportMode(String value) {
    if (!importModes.contains(value) || value == importMode) return;
    importMode = value;
    notifyListeners();
  }

  void toggleExpanded(ExternalAgentRootRow row) {
    final key = sourceKey(row);
    if (!_expandedSourceKeys.add(key)) _expandedSourceKeys.remove(key);
    notifyListeners();
  }

  void toggleSelection(String key) {
    if (_selectionIfImportable(key) == null) return;
    if (!_selectedKeys.add(key)) _selectedKeys.remove(key);
    notifyListeners();
  }

  void setResourceSelection(Iterable<String> keys, bool selected) {
    var changed = false;
    for (final key in keys) {
      if (_selectionIfImportable(key) == null) continue;
      changed = selected
          ? _selectedKeys.add(key) || changed
          : _selectedKeys.remove(key) || changed;
    }
    if (changed) notifyListeners();
  }

  List<String> visibleResourceKeys() =>
      [for (final row in visibleRoots) ...resourceKeysFor(row)];

  ImportSelection? _selectionIfImportable(String key) {
    ImportSelection selection;
    try {
      selection = ImportSelection.fromKey(key);
    } on Object {
      return null;
    }
    if (!categories.contains(selection.category)) return null;
    for (final row in visibleRoots) {
      if (row.agent.id != selection.agent ||
          row.category != selection.category ||
          row.root.scope != selection.sourceScope) {
        continue;
      }
      if (row.root.resources.any((resource) =>
          resource.importable && resource.path == selection.resourcePath)) {
        return selection;
      }
    }
    return null;
  }

  List<Map<String, dynamic>> get selections => buildImportSelections(
        _selectedKeys,
        targetScope: importTargetScope,
        importMode: importMode,
      );

  Future<bool> importSelected() {
    if (_disposed || _selectedKeys.isEmpty) return Future.value(false);
    final pending = _pendingImport;
    if (pending != null) return pending;
    final generation = _generation;
    status = ExternalAgentImportStatus.importing;
    error = null;
    notifyListeners();
    Future<bool>? future;
    Future<bool> operation() async {
      try {
        final raw = await service.importSelected(
          workspacePath: workspacePath,
          workspaceIdentity: workspaceIdentity,
          selections: selections,
        );
        if (_disposed || generation != _generation) return false;
        final map = _asMap(raw);
        if (map['success'] == false && map['error'] != null) {
          throw StateError(_text(map['error']));
        }
        result = ExternalAgentImportResult.fromRaw(raw);
        status = ExternalAgentImportStatus.complete;
        error = null;
        return true;
      } catch (value) {
        if (_disposed || generation != _generation) return false;
        status = ExternalAgentImportStatus.ready;
        error = value;
        // Keep selection intact for retry, matching the official dialog.
        return false;
      } finally {
        if (_pendingImport == future) _pendingImport = null;
        if (!_disposed && generation == _generation) notifyListeners();
      }
    }

    future = operation();
    _pendingImport = future;
    return future;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _pendingScan = null;
    _pendingImport = null;
    super.dispose();
  }
}
