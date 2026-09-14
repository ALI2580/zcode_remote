import 'dart:async';

import 'package:flutter/foundation.dart';
import '../protocol/channel_client.dart';
import '../protocol/zemote_client.dart';

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
    : [];
String _text(dynamic value) => value is String ? value : '';

String _firstText(Iterable<dynamic> values) {
  for (final value in values) {
    final text = _text(value).trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

String _scopeText(dynamic value) {
  final text = value is String ? value.trim().toLowerCase() : '';
  return switch (text) {
    'project' => 'workspace',
    'common' => 'user',
    'workspace' => 'workspace',
    'user' => 'user',
    _ => '',
  };
}

/// Stable identity for one plugin-management request scope.
///
/// Map.toString() depends on insertion order. A canonical representation keeps
/// AppSessions from accidentally reusing a catalog when the bridge supplies
/// the same values in a different order.
String pluginScopeFingerprint(Map<String, dynamic> scope) {
  String encode(dynamic value) {
    if (value is Map) {
      final keys = value.keys.map((key) => '$key').toList()..sort();
      return '{${keys.map((key) => '$key:${encode(value[key])}').join('|')}}';
    }
    if (value is Iterable) return '[${value.map(encode).join('|')}]';
    return '$value';
  }

  return encode(scope);
}

Map<String, dynamic> _freezeScope(Map<String, dynamic> source) {
  dynamic freeze(dynamic value) {
    if (value is Map) {
      return Map.unmodifiable({
        for (final entry in value.entries) '${entry.key}': freeze(entry.value),
      });
    }
    if (value is Iterable) return List.unmodifiable(value.map(freeze));
    return value;
  }

  return Map.unmodifiable({
    for (final entry in source.entries) entry.key: freeze(entry.value),
  });
}

List<String> _strings(dynamic value) => value is List
    ? value
        .whereType<String>()
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty)
        .toList(growable: false)
    : const <String>[];

class CatalogPlugin {
  CatalogPlugin(
      {required this.id,
      required this.name,
      required this.marketplace,
      required this.installed,
      this.restorable = false,
      this.summary = const {},
      this.info = const {},
      this.installedMeta = const {}});
  final String id, name, marketplace;
  final bool installed, restorable;
  final Map<String, dynamic> summary, info, installedMeta;
  Map get listing => summary['listing'] is Map
      ? summary['listing'] as Map
      : info['listing'] is Map
          ? info['listing'] as Map
          : installedMeta['listing'] is Map
              ? installedMeta['listing'] as Map
              : const {};
  String get description => _text(summary['description']).isNotEmpty
      ? _text(summary['description'])
      : _text(info['description']).isNotEmpty
          ? _text(info['description'])
          : _text(installedMeta['description']);
  String get displayName {
    final listingMap = listing;
    return _firstText([
      listingMap['displayName'],
      listingMap['name'],
      info['displayName'],
      summary['displayName'],
      name,
    ]);
  }

  String get category =>
      _text(listing['category']).isEmpty ? 'other' : _text(listing['category']);
  bool get enabled => info.containsKey('enabled')
      ? info['enabled'] == true
      : summary.containsKey('enabled')
          ? summary['enabled'] == true
          : installedMeta['enabled'] == true;

  String get enabledSource {
    for (final value in [
      info['enabledSource'],
      summary['enabledSource'],
      installedMeta['enabledSource'],
    ]) {
      final text = _text(value).trim().toLowerCase();
      if (text == 'workspace' || text == 'user' || text == 'default') {
        return text;
      }
    }
    return 'default';
  }

  bool get packageMissing => [
        info['packageStatus'],
        summary['packageStatus'],
        installedMeta['packageStatus'],
      ].any((value) => _text(value).trim().toLowerCase() == 'missing');

  /// Official settings separates built-ins from installed marketplace items.
  /// A built-in is identified by the official source without an installed
  /// package record; restorable built-ins are reported explicitly.
  bool get builtIn =>
      restorable ||
      (installedMeta.isEmpty &&
          _text(info['source'] ?? summary['source']).trim().toLowerCase() ==
              'official');

  /// MCP declarations are provided by plugin-management listPlugins data.
  /// Keep the three official lists separate because host-provided entries
  /// have different active semantics from declared/runtime entries.
  List<String> get mcpServerNames => _strings(
        info['mcpServerNames'] ??
            info['mcpServers'] ??
            summary['mcpServerNames'] ??
            summary['mcpServers'],
      );
  List<String> get declaredMcpServerNames => _strings(
        info['declaredMcpServerNames'] ?? summary['declaredMcpServerNames'],
      );
  List<String> get hostMcpServerNames => _strings(
        info['hostMcpServerNames'] ?? summary['hostMcpServerNames'],
      );
  String get installScope {
    return explicitInstallScope ?? 'user';
  }

  String? get explicitInstallScope {
    for (final value in [
      installedMeta['scope'],
      info['scope'],
      summary['scope'],
    ]) {
      final normalized = _scopeText(value);
      if (normalized.isNotEmpty) return normalized;
    }
    return null;
  }

  /// Hook declarations are returned by plugin-management's plugin overview
  /// alongside the installed scope. Keep the raw declaration maps intact so
  /// the Hooks settings page can render event/type/matcher/command and source
  /// path without inventing a second hooks RPC.
  List<Map<String, dynamic>> get hookDetails {
    final value = info['hookDetails'] ??
        summary['hookDetails'] ??
        installedMeta['hookDetails'];
    return value is List
        ? value
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
  }

  String? get installedScope {
    return explicitInstallScope;
  }

  String get mcpCapabilitySignature => [
        id,
        installScope,
        enabled ? 'enabled' : 'disabled',
        ...(declaredMcpServerNames.toList()..sort()),
        ...(mcpServerNames.toList()..sort()),
        ...(hostMcpServerNames.toList()..sort()),
      ].join(':');
  bool get canUpdate => const ['update-available', 'version-changed']
      .contains(installedMeta['updateStatus']);

  String get version => _text(installedMeta['version']).isNotEmpty
      ? _text(installedMeta['version'])
      : _text(info['version']).isNotEmpty
          ? _text(info['version'])
          : _text(summary['version']);

  String get author => _text(listing['author']).isNotEmpty
      ? _text(listing['author'])
      : _text(summary['author']).isNotEmpty
          ? _text(summary['author'])
          : _text(info['author']);

  String get rootPath => _firstText([
        info['rootPath'],
        info['path'],
        summary['rootPath'],
        summary['path'],
        installedMeta['rootPath'],
        installedMeta['path'],
      ]);

  String get readme => _firstText([
        info['readme'],
        summary['readme'],
        installedMeta['readme'],
      ]);

  List<Map<String, dynamic>> get components {
    final value = info['components'] ??
        summary['components'] ??
        installedMeta['components'];
    return value is List
        ? value
            .whereType<Map>()
            .map((item) => item.cast<String, dynamic>())
            .toList(growable: false)
        : const <Map<String, dynamic>>[];
  }

  List<String> get warnings {
    final value =
        info['warnings'] ?? summary['warnings'] ?? installedMeta['warnings'];
    return _strings(value);
  }

  String? get icon {
    for (final value in [
      listing['icon'],
      summary['icon'],
      info['icon'],
    ]) {
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    return null;
  }

  Map<String, dynamic> get userConfig {
    for (final value in [
      info['userConfig'],
      summary['userConfig'],
      installedMeta['userConfig'],
    ]) {
      if (value is Map) return value.cast<String, dynamic>();
    }
    return const {};
  }

  Map<String, dynamic> get configuredValues {
    for (final value in [
      info['configuredOptions'],
      info['config'],
      info['configuration'],
      summary['configuredOptions'],
      summary['config'],
      installedMeta['configuredOptions'],
      installedMeta['config'],
    ]) {
      if (value is Map) return value.cast<String, dynamic>();
    }
    return const {};
  }

  Map<String, dynamic> get optionSources {
    for (final value in [
      info['optionSources'],
      info['configuredOptionSources'],
      summary['optionSources'],
      summary['configuredOptionSources'],
      installedMeta['optionSources'],
      installedMeta['configuredOptionSources'],
    ]) {
      if (value is Map) return value.cast<String, dynamic>();
    }
    return const {};
  }
}

/// Official plugin-management cVe/sSt/DM, isolated to one workspace bridge.
class PluginCatalog extends ChangeNotifier {
  PluginCatalog({
    required this.bridge,
    required Map<String, dynamic> scope,
    this.selectedScope,
    this.onConfirmed,
  }) : scope = _freezeScope(scope);
  final BridgeSession bridge;
  final Map<String, dynamic> scope;

  /// Scope selected by the settings page. This is separate from the request
  /// scope (workspacePath/workspaceIdentity) and is used for plugin writes.
  final String? selectedScope;
  final FutureOr<void> Function(PluginCatalog catalog)? onConfirmed;
  List<CatalogPlugin> items = [];
  List<Map<String, dynamic>> marketplaces = [];
  List<Map<String, dynamic>> diagnostics = [];
  bool loading = false, failed = false, _disposed = false;
  String? operation;
  int configurationRevision = 0;
  int _generation = 0;

  String get effectiveScope {
    final explicit = _scopeText(selectedScope);
    if (explicit.isNotEmpty) return explicit;
    for (final value in [
      scope['pluginScope'],
      scope['installScope'],
      scope['scope']
    ]) {
      final normalized = _scopeText(value);
      if (normalized.isNotEmpty) return normalized;
    }
    return 'user';
  }

  String? get workspacePath => scope['workspacePath'] is String &&
          (scope['workspacePath'] as String).trim().isNotEmpty
      ? (scope['workspacePath'] as String).trim()
      : null;

  String? get workspaceIdentity => scope['workspaceIdentity'] is String &&
          (scope['workspaceIdentity'] as String).trim().isNotEmpty
      ? (scope['workspaceIdentity'] as String).trim()
      : null;

  bool get hasWorkspace => workspacePath != null || workspaceIdentity != null;

  Future<dynamic> _call(String method, Map<String, dynamic> values) =>
      bridge.channels.call(
          Channels.pluginManagement,
          method,
          [
            {
              ...scope,
              if (_scopeText(selectedScope).isNotEmpty &&
                  !scope.containsKey('configScope'))
                'configScope': effectiveScope,
              ...values,
            }
          ],
          timeout: const Duration(seconds: 90));

  Future<void> refresh() async {
    final generation = ++_generation;
    loading = true;
    failed = false;
    _notify();
    try {
      final results = await Future.wait(
          [_call('listPlugins', {}), _call('getPluginsOverview', {})]);
      if (_disposed || generation != _generation) return;
      if (results[0] is! Map || results[1] is! Map) {
        throw const FormatException('missing plugin overview');
      }
      final plugins = _maps(results[0]['plugins']);
      final overview = results[1] as Map;
      final effective = {for (final item in plugins) _text(item['id']): item};
      final metadata = {
        for (final item in _maps(overview['installedPlugins']))
          _text(item['id']): item
      };
      final merged = <String, CatalogPlugin>{};
      for (final item in _maps(overview['availablePlugins'])) {
        final id = _text(item['id']);
        if (id.isEmpty) continue;
        final info = effective[id];
        final installedInfo = metadata[id] ?? const <String, dynamic>{};
        merged[id] = CatalogPlugin(
            id: id,
            name: _firstText([
              item['displayName'],
              item['name'],
              (item['listing'] is Map)
                  ? (item['listing'] as Map)['displayName']
                  : null,
              (item['listing'] is Map)
                  ? (item['listing'] as Map)['name']
                  : null,
              info?['name'],
              info?['displayName'],
              installedInfo['name'],
            ]),
            marketplace: _firstText([
              item['marketplace'],
              info?['marketplace'],
              installedInfo['marketplace'],
            ]),
            installed: info?['packageStatus'] == 'missing' ||
                    item['packageStatus'] == 'missing'
                ? false
                : item['installed'] == true || info != null,
            summary: item,
            info: info ?? {},
            installedMeta: installedInfo);
      }
      for (final item in _maps(overview['restorableBuiltins'])) {
        final id = _text(item['id']);
        if (id.isEmpty ||
            merged[id]?.installed == true ||
            effective.containsKey(id)) {
          continue;
        }
        merged[id] = CatalogPlugin(
            id: id,
            name: _firstText([item['name'], item['displayName']]),
            marketplace: _text(item['marketplace']),
            installed: false,
            restorable: true,
            summary: item);
      }
      for (final item in plugins) {
        final id = _text(item['id']);
        if (id.isEmpty || merged.containsKey(id)) continue;
        merged[id] = CatalogPlugin(
            id: id,
            name: _firstText([item['name'], item['displayName']]),
            marketplace: _text(item['marketplace']),
            installed: item['packageStatus'] != 'missing',
            info: item,
            installedMeta: metadata[id] ?? {});
      }
      marketplaces = _maps(overview['marketplaces']);
      diagnostics = [
        ..._maps(results[0]['diagnostics']),
        ..._maps(overview['diagnostics']),
      ];
      items = merged.values.toList();
    } catch (_) {
      if (!_disposed && generation == _generation) failed = true;
    } finally {
      if (!_disposed && generation == _generation) {
        loading = false;
        _notify();
      }
    }
  }

  Future<Map<String, dynamic>> describe(CatalogPlugin item) async {
    final result = await _call('describePlugin', {
      'pluginId': item.id,
      'pluginName': item.name,
      'marketplace': item.marketplace
    });
    if (result is! Map || !_writeSucceeded(result)) {
      throw const FormatException('missing plugin details');
    }
    return result.cast<String, dynamic>();
  }

  Future<bool> mutate(String method, Map<String, dynamic> values) async {
    if (_disposed || operation != null) return false;
    operation =
        '${values['pluginId'] ?? values['pluginName'] ?? values['marketplace'] ?? method}';
    failed = false;
    _notify();
    try {
      final result = await _call(method, values);
      if (_disposed) return false;
      if (!_writeSucceeded(result)) {
        throw StateError('plugin operation failed');
      }
      await refresh();
      if (_disposed || failed) return false;
      configurationRevision++;
      _notify();
      try {
        await onConfirmed?.call(this);
      } catch (_) {
        // The remote readback is authoritative. A projection callback must
        // never turn a confirmed plugin mutation into a false failure.
      }
      return true;
    } catch (_) {
      if (!_disposed) failed = true;
      return false;
    } finally {
      operation = null;
      _notify();
    }
  }

  Future<bool> install(CatalogPlugin item, {String? installScope}) =>
      item.restorable
          ? mutate('restoreBuiltinPlugin', {'pluginId': item.id})
          : mutate('installPlugin', {
              'pluginName': item.name,
              'marketplace': item.marketplace,
              'scope': _scopeText(installScope).isEmpty
                  ? effectiveScope
                  : _scopeText(installScope)
            });
  Future<bool> enable(CatalogPlugin item, bool enabled) => mutate(
      'setPluginEnabled',
      {'pluginId': item.id, 'enabled': enabled, 'scope': effectiveScope});

  /// Clears a workspace override and restores the user/default value.
  Future<bool> resetPluginConfig(CatalogPlugin item) =>
      mutate('resetPluginConfig', {
        'pluginId': item.id,
        'scope': effectiveScope,
      });
  Future<bool> update(CatalogPlugin item) =>
      mutate('updatePlugin', {'pluginId': item.id});
  Future<bool> uninstall(CatalogPlugin item) =>
      mutate('uninstallPlugin', {'pluginId': item.id, 'removeCache': true});

  Future<bool> restore(CatalogPlugin item) =>
      mutate('restoreBuiltinPlugin', {'pluginId': item.id});

  Future<bool> addMarketplace(String source) {
    final value = source.trim();
    if (value.isEmpty) return Future.value(false);
    return mutate('addPluginMarketplace', {'source': value});
  }

  /// Validates a source using the official plugin-management operation. The
  /// call is diagnostic-only and never changes marketplace configuration.
  Future<bool> validateMarketplace(String source) async {
    final value = source.trim();
    if (value.isEmpty || _disposed) return false;
    try {
      final result = await _call('validatePlugin', {'source': value});
      if (result is Map && result['valid'] == false) return false;
      return _writeSucceeded(result);
    } catch (_) {
      return false;
    }
  }

  Future<bool> updateMarketplace([String? marketplace]) => mutate(
        'updatePluginMarketplace',
        marketplace == null || marketplace.trim().isEmpty
            ? <String, dynamic>{}
            : {'marketplace': marketplace.trim()},
      );

  Future<bool> removeMarketplace(String marketplace) =>
      mutate('removePluginMarketplace', {'marketplace': marketplace.trim()});

  Future<bool> configure(CatalogPlugin item, Map<String, dynamic> options,
      {String? scope, List<String> clearOptionKeys = const []}) {
    if (options.isEmpty && clearOptionKeys.isEmpty) return Future.value(true);
    return mutate('configurePlugin', {
      'pluginId': item.id,
      'options': options,
      'scope': _scopeText(scope).isEmpty ? effectiveScope : _scopeText(scope),
      if (clearOptionKeys.isNotEmpty) 'clearOptionKeys': clearOptionKeys,
    });
  }

  bool _writeSucceeded(dynamic result) {
    if (result is! Map) return true;
    if (result['ok'] == false || result['success'] == false) return false;
    return !_maps(result['diagnostics'])
        .any((e) => _text(e['severity']).trim().toLowerCase() == 'error');
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
