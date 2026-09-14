import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/channel_client.dart';
import '../protocol/conversation.dart' as protocol;
import '../protocol/zemote_client.dart';

String _skillText(Object? value) => value is String ? value.trim() : '';
Map<String, dynamic> _skillMap(Object? value) => value is Map
    ? Map<String, dynamic>.from(
        value.map((key, value) => MapEntry(key.toString(), value)))
    : <String, dynamic>{};
List<Map<String, dynamic>> _skillMaps(Object? value) => value is List
    ? [
        for (final item in value)
          if (item is Map) _skillMap(item)
      ]
    : const <Map<String, dynamic>>[];

abstract interface class SkillsService {
  Future<Object?> list(
      {required String? workspacePath,
      required String? workspaceIdentity,
      required String provider});
  Future<Object?> setEnabled(
      {required String? workspacePath,
      required String? workspaceIdentity,
      required String provider,
      required String scope,
      required String skillId,
      required bool enabled});
  Future<Object?> deleteSkill(
      {required String? workspacePath,
      required String? workspaceIdentity,
      required String skillId});
}

class ChannelSkillsService implements SkillsService {
  ChannelSkillsService(this.session);
  final BridgeSession session;
  Map<String, dynamic> _scope(String? path, String? identity) => {
        if (_skillText(path).isNotEmpty) 'workspacePath': _skillText(path),
        if (_skillText(identity).isNotEmpty)
          'workspaceIdentity': _skillText(identity),
      };
  @override
  Future<Object?> list(
          {required String? workspacePath,
          required String? workspaceIdentity,
          required String provider}) =>
      session.channels.call(
          Channels.skills,
          'list',
          [
            {..._scope(workspacePath, workspaceIdentity), 'provider': provider}
          ],
          timeout: const Duration(seconds: 30));
  @override
  Future<Object?> setEnabled(
          {required String? workspacePath,
          required String? workspaceIdentity,
          required String provider,
          required String scope,
          required String skillId,
          required bool enabled}) =>
      session.channels.call(
          Channels.skills,
          'setEnabled',
          [
            {
              ..._scope(workspacePath, workspaceIdentity),
              'provider': provider,
              'scope': scope,
              'skillId': skillId,
              'enabled': enabled
            }
          ],
          timeout: const Duration(seconds: 30));
  @override
  Future<Object?> deleteSkill(
          {required String? workspacePath,
          required String? workspaceIdentity,
          required String skillId}) =>
      session.channels.call(
          Channels.skills,
          'deleteSkill',
          [
            {..._scope(workspacePath, workspaceIdentity), 'skillId': skillId}
          ],
          timeout: const Duration(seconds: 30));
}

class SkillEntry {
  SkillEntry(
      {required this.id,
      required this.name,
      required this.path,
      required this.scope,
      this.description,
      this.argumentHint,
      required this.enabled,
      this.version,
      this.slug,
      this.publishedAt,
      this.ownerId,
      this.pluginId,
      this.pluginName,
      this.pluginMarketplace,
      Map<String, dynamic>? metadata,
      Map<String, dynamic>? raw})
      : metadata = Map.unmodifiable(metadata ?? const {}),
        raw = Map.unmodifiable(raw ?? const {});
  factory SkillEntry.fromRaw(Map raw, {Map<String, dynamic>? metadataById}) {
    final map = _skillMap(raw), nested = _skillMap(map['metadata']);
    final meta = <String, dynamic>{
      ...(metadataById ?? const <String, dynamic>{}),
      ...nested
    };
    for (final key in ['version', 'slug', 'publishedAt', 'ownerId']) {
      if (map[key] != null) meta[key] = map[key];
    }
    String val(String key) => _skillText(map[key]);
    String mval(String key) {
      final value = meta[key];
      if (key == 'publishedAt' && value is num) {
        final raw = value.toInt();
        final milliseconds = raw.abs() < 100000000000 ? raw * 1000 : raw;
        final date =
            DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
        return date.toIso8601String();
      }
      return _skillText(value);
    }

    final id = val('id').isEmpty ? val('skillId') : val('id');
    return SkillEntry(
        id: id,
        name: val('name').isEmpty ? val('title') : val('name'),
        path: val('path').isEmpty ? val('filePath') : val('path'),
        scope: val('scope').isEmpty ? 'workspace' : val('scope'),
        description: val('description').isEmpty
            ? (val('summary').isEmpty ? null : val('summary'))
            : val('description'),
        argumentHint: val('argumentHint').isEmpty ? null : val('argumentHint'),
        enabled: map['enabled'] != false,
        version: mval('version').isEmpty ? null : mval('version'),
        slug: mval('slug').isEmpty ? null : mval('slug'),
        publishedAt: mval('publishedAt').isEmpty ? null : mval('publishedAt'),
        ownerId: mval('ownerId').isEmpty ? null : mval('ownerId'),
        pluginId: val('pluginId').isEmpty ? null : val('pluginId'),
        pluginName: val('pluginName').isEmpty ? null : val('pluginName'),
        pluginMarketplace:
            val('pluginMarketplace').isEmpty ? null : val('pluginMarketplace'),
        metadata: meta,
        raw: map);
  }
  final String id, name, path, scope;
  final String? description,
      argumentHint,
      version,
      slug,
      publishedAt,
      ownerId,
      pluginId,
      pluginName,
      pluginMarketplace;
  final bool enabled;
  final Map<String, dynamic> metadata, raw;
  bool get isPlugin =>
      scope == 'plugin' ||
      _skillText(raw['source']) == 'plugin' ||
      pluginId?.trim().isNotEmpty == true ||
      pluginName?.trim().isNotEmpty == true;
  bool get isWritable => !isPlugin && (scope == 'user' || scope == 'workspace');
  String get status => enabled ? 'enabled' : 'disabled';
}

class SkillDiagnostic {
  const SkillDiagnostic(
      {required this.severity,
      required this.code,
      required this.message,
      this.path,
      this.skillName,
      this.raw = const {}});
  factory SkillDiagnostic.fromRaw(Map raw, {String? defaultSeverity}) {
    final map = _skillMap(raw),
        severity = _skillText(map['severity']).isEmpty
            ? (defaultSeverity ?? 'warning')
            : _skillText(map['severity']);
    return SkillDiagnostic(
        severity: severity,
        code: _skillText(map['code']).isEmpty
            ? 'unknown'
            : _skillText(map['code']),
        message: _skillText(map['message']).isEmpty
            ? _skillText(map['detail'])
            : _skillText(map['message']),
        path: _skillText(map['path']).isEmpty ? null : _skillText(map['path']),
        skillName: _skillText(map['skillName']).isEmpty
            ? (_skillText(map['name']).isEmpty ? null : _skillText(map['name']))
            : _skillText(map['skillName']),
        raw: map);
  }
  final String severity, code, message;
  final String? path, skillName;
  final Map<String, dynamic> raw;
  bool get isError => severity.toLowerCase() == 'error';
}

class SkillsListSnapshot {
  const SkillsListSnapshot(
      {required this.skills,
      required this.capability,
      required this.diagnostics,
      required this.metadata,
      required this.raw});
  factory SkillsListSnapshot.fromRaw(Object? value) {
    final map = _skillMap(value), metadata = _skillMap(map['metadata']);
    final rows = <Map<String, dynamic>>[], seen = <String>{};
    void add(Object? source) {
      for (final row in _skillMaps(source)) {
        final id = _skillText(row['id']).isEmpty
            ? _skillText(row['skillId'])
            : _skillText(row['id']);
        final key = id.isEmpty
            ? '${_skillText(row['name'])}:${_skillText(row['path'])}:${rows.length}'
            : id;
        if (seen.add(key)) rows.add(row);
      }
    }

    if (value is List) {
      add(value);
    } else {
      add(map['skills']);
      add(map['userSkills']);
      add(map['workspaceSkills']);
      add(map['pluginSkills']);
    }
    final diagnostics = <SkillDiagnostic>[];
    void addDiagnostics(Object? source, String? severity) {
      for (final row in _skillMaps(source)) {
        diagnostics
            .add(SkillDiagnostic.fromRaw(row, defaultSeverity: severity));
      }
    }

    final rawDiagnostics = map['diagnostics'];
    if (rawDiagnostics is List) addDiagnostics(rawDiagnostics, null);
    if (rawDiagnostics is Map) {
      addDiagnostics(rawDiagnostics['errors'], 'error');
      addDiagnostics(rawDiagnostics['warnings'], 'warning');
      addDiagnostics(rawDiagnostics['issues'], null);
    }
    addDiagnostics(map['errors'], 'error');
    addDiagnostics(map['warnings'], 'warning');
    return SkillsListSnapshot(
        skills: [
          for (final row in rows)
            SkillEntry.fromRaw(row,
                metadataById: _skillMap(metadata[_skillText(row['id'])]))
        ],
        capability: _skillMap(map['capability']),
        diagnostics: diagnostics,
        metadata: metadata,
        raw: map);
  }
  final List<SkillEntry> skills;
  final Map<String, dynamic> capability, metadata, raw;
  final List<SkillDiagnostic> diagnostics;
}

enum SkillsStatus { idle, loading, loaded, error }

/// Full settings catalog for one bridge/workspace source.
class SkillsCatalog extends ChangeNotifier {
  SkillsCatalog(
      {required this.transport,
      required this.scopeKey,
      SkillsService? service,
      Map<String, dynamic>? scope,
      String? workspacePath,
      String? workspaceIdentity,
      this.provider = 'glm',
      this.onComposerRefresh})
      : _service = service ?? ChannelSkillsService(transport.session),
        scope = {
          ...transport.scope,
          ...?scope,
          if (_skillText(workspacePath).isNotEmpty)
            'workspacePath': _skillText(workspacePath),
          if (_skillText(workspaceIdentity).isNotEmpty)
            'workspaceIdentity': _skillText(workspaceIdentity)
        };

  final protocol.ConversationTransport transport;
  SkillsService _service;
  Map<String, dynamic> scope;
  String scopeKey;
  final String provider;
  final FutureOr<void> Function()? onComposerRefresh;
  int _generation = 0, _sourceGeneration = 0, _writeGeneration = 0;
  Future<void>? _pending;
  bool _disposed = false;
  final Map<String, int> _writing = <String, int>{};
  final Map<String, Object?> _operationErrors = <String, Object?>{};

  SkillsStatus status = SkillsStatus.idle;
  List<SkillEntry> items = const [];
  Map<String, dynamic> capability = const {};
  List<SkillDiagnostic> diagnostics = const [];
  Map<String, dynamic> metadata = const {}, rawSnapshot = const {};
  Object? error;
  String? get workspacePath => _skillText(scope['workspacePath']).isEmpty
      ? null
      : _skillText(scope['workspacePath']);
  String? get workspaceIdentity =>
      _skillText(scope['workspaceIdentity']).isEmpty
          ? null
          : _skillText(scope['workspaceIdentity']);
  bool get hasWorkspace => workspacePath?.isNotEmpty == true;
  bool get userScopeAvailable => capability['userScopeAvailable'] == true;
  bool get workspaceScopeAvailable =>
      capability['workspaceScopeAvailable'] != false && hasWorkspace;
  String? get userScopeReason => _reason('userScope');
  String? get workspaceScopeReason => _reason('workspaceScope');
  int get errorCount => diagnostics.where((item) => item.isError).length;
  int get warningCount => diagnostics.length - errorCount;
  String? _reason(String key) {
    final direct = _skillText(capability['${key}Reason']);
    if (direct.isNotEmpty) return direct;
    final nested = _skillMap(capability[key]);
    final reason = _skillText(nested['reason']);
    return reason.isEmpty ? null : reason;
  }

  String _key(String scope, String id) => '$scope\u0000$id';
  bool isWriting(SkillEntry entry) =>
      _writing.containsKey(_key(entry.scope, entry.id));
  Object? operationError(SkillEntry entry) =>
      _operationErrors[_key(entry.scope, entry.id)];

  bool _writeSucceeded(Object? result) {
    if (result is! Map) return true;
    if (result['ok'] == false || result['success'] == false) return false;
    final diagnostics = result['diagnostics'];
    if (diagnostics is List &&
        diagnostics.any((item) =>
            item is Map &&
            _skillText(item['severity']).toLowerCase() == 'error')) {
      return false;
    }
    return true;
  }

  void updateScope(
      {required Map<String, dynamic> nextScope,
      String? nextWorkspacePath,
      String? nextWorkspaceIdentity,
      String? nextScopeKey,
      SkillsService? nextService}) {
    final next = {
      ...nextScope,
      if (_skillText(nextWorkspacePath).isNotEmpty)
        'workspacePath': _skillText(nextWorkspacePath),
      if (_skillText(nextWorkspaceIdentity).isNotEmpty)
        'workspaceIdentity': _skillText(nextWorkspaceIdentity)
    };
    final changed = !_same(scope, next) ||
        (nextScopeKey != null && nextScopeKey != scopeKey) ||
        nextService != null;
    if (_disposed || !changed) return;
    _generation++;
    _sourceGeneration++;
    _pending = null;
    _writing.clear();
    _operationErrors.clear();
    scope = next;
    if (nextScopeKey != null) scopeKey = nextScopeKey;
    if (nextService != null) _service = nextService;
    items = const [];
    capability = const {};
    diagnostics = const [];
    metadata = const {};
    rawSnapshot = const {};
    error = null;
    status = SkillsStatus.idle;
    notifyListeners();
  }

  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future.value();
    final pending = _pending;
    if (pending != null && !force) return pending;
    final generation = ++_generation, source = _sourceGeneration;
    status = SkillsStatus.loading;
    error = null;
    notifyListeners();
    Future<void>? operationFuture;
    Future<void> operation() async {
      try {
        final snapshot = SkillsListSnapshot.fromRaw(await _service.list(
            workspacePath: workspacePath,
            workspaceIdentity: workspaceIdentity,
            provider: provider));
        if (_disposed ||
            generation != _generation ||
            source != _sourceGeneration) {
          return;
        }
        items = snapshot.skills;
        capability = snapshot.capability;
        diagnostics = snapshot.diagnostics;
        metadata = snapshot.metadata;
        rawSnapshot = snapshot.raw;
        status = SkillsStatus.loaded;
        error = null;
      } catch (value) {
        if (_disposed ||
            generation != _generation ||
            source != _sourceGeneration) {
          return;
        }
        status = SkillsStatus.error;
        error = value;
      } finally {
        if (_pending == operationFuture) _pending = null;
        if (!_disposed &&
            generation == _generation &&
            source == _sourceGeneration) {
          notifyListeners();
        }
      }
    }

    operationFuture = operation();
    _pending = operationFuture;
    return operationFuture;
  }

  Future<bool> setEnabled(SkillEntry entry, bool enabled) async {
    if (_disposed || !entry.isWritable) return false;
    final key = _key(entry.scope, entry.id);
    if (_writing.containsKey(key)) return false;
    final source = _sourceGeneration, token = ++_writeGeneration;
    _writing[key] = token;
    _operationErrors.remove(key);
    notifyListeners();
    try {
      final result = await _service.setEnabled(
          workspacePath: workspacePath,
          workspaceIdentity: workspaceIdentity,
          provider: provider,
          scope: entry.scope,
          skillId: entry.id,
          enabled: enabled);
      if (!_writeSucceeded(result)) {
        throw StateError('skills.setEnabled rejected the change');
      }
      if (_disposed || source != _sourceGeneration || _writing[key] != token) {
        return false;
      }
      await refresh(force: true);
      if (_disposed ||
          source != _sourceGeneration ||
          _writing[key] != token ||
          status != SkillsStatus.loaded) {
        return false;
      }
      try {
        await onComposerRefresh?.call();
      } catch (_) {}
      return true;
    } catch (value) {
      if (!_disposed && source == _sourceGeneration && _writing[key] == token) {
        _operationErrors[key] = value;
      }
      return false;
    } finally {
      if (_writing[key] == token) {
        _writing.remove(key);
        if (!_disposed) notifyListeners();
      }
    }
  }

  Future<bool> setEnabledById(String id, bool enabled) async {
    for (final item in items) {
      if (item.id == id) {
        return setEnabled(item, enabled);
      }
    }
    return false;
  }

  Future<bool> deleteSkill(SkillEntry entry) async {
    if (_disposed || !entry.isWritable) return false;
    final key = _key(entry.scope, entry.id);
    if (_writing.containsKey(key)) return false;
    final source = _sourceGeneration, token = ++_writeGeneration;
    _writing[key] = token;
    _operationErrors.remove(key);
    notifyListeners();
    try {
      final result = await _service.deleteSkill(
          workspacePath: workspacePath,
          workspaceIdentity: workspaceIdentity,
          skillId: entry.id);
      if (!_writeSucceeded(result)) {
        throw StateError('skills.deleteSkill rejected the change');
      }
      if (_disposed || source != _sourceGeneration || _writing[key] != token) {
        return false;
      }
      await refresh(force: true);
      if (_disposed ||
          source != _sourceGeneration ||
          _writing[key] != token ||
          status != SkillsStatus.loaded) {
        return false;
      }
      try {
        await onComposerRefresh?.call();
      } catch (_) {}
      return true;
    } catch (value) {
      if (!_disposed && source == _sourceGeneration && _writing[key] == token) {
        _operationErrors[key] = value;
      }
      return false;
    } finally {
      if (_writing[key] == token) {
        _writing.remove(key);
        if (!_disposed) notifyListeners();
      }
    }
  }

  bool _same(Map<String, dynamic> a, Map<String, dynamic> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _sourceGeneration++;
    _pending = null;
    _writing.clear();
    super.dispose();
  }
}
