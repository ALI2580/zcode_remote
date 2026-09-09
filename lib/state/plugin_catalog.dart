import 'package:flutter/foundation.dart';
import '../protocol/channel_client.dart';
import '../protocol/zemote_client.dart';

List<Map<String, dynamic>> _maps(dynamic value) => value is List
    ? value.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
    : [];
String _text(dynamic value) => value is String ? value : '';

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
          : const {};
  String get description => _text(summary['description']).isNotEmpty
      ? _text(summary['description'])
      : _text(info['description']);
  String get category =>
      _text(listing['category']).isEmpty ? 'other' : _text(listing['category']);
  bool get enabled => info['enabled'] == true;
  bool get canUpdate => const ['update-available', 'version-changed']
      .contains(installedMeta['updateStatus']);
}

/// Official plugin-management cVe/sSt/DM, isolated to one workspace bridge.
class PluginCatalog extends ChangeNotifier {
  PluginCatalog({required this.bridge, required this.scope});
  final BridgeSession bridge;
  final Map<String, dynamic> scope;
  List<CatalogPlugin> items = [];
  List<Map<String, dynamic>> marketplaces = [];
  bool loading = false, failed = false, _disposed = false;
  String? operation;
  int _generation = 0;
  Future<dynamic> _call(String method, Map<String, dynamic> values) =>
      bridge.channels.call(
          Channels.pluginManagement,
          method,
          [
            {...scope, ...values}
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
        merged[id] = CatalogPlugin(
            id: id,
            name: _text(item['name']),
            marketplace: _text(item['marketplace']),
            installed: info?['packageStatus'] == 'missing'
                ? false
                : item['installed'] == true || info != null,
            summary: item,
            info: info ?? {},
            installedMeta: metadata[id] ?? {});
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
            name: _text(item['name']),
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
            name: _text(item['name']),
            marketplace: _text(item['marketplace']),
            installed: item['packageStatus'] != 'missing',
            info: item,
            installedMeta: metadata[id] ?? {});
      }
      marketplaces = _maps(overview['marketplaces']);
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
    final result = await _call('describePlugin',
        {'pluginName': item.name, 'marketplace': item.marketplace});
    if (result is! Map) throw const FormatException('missing plugin details');
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
      if (result is Map &&
          _maps(result['diagnostics']).any((e) => e['severity'] == 'error')) {
        throw StateError('plugin operation failed');
      }
      await refresh();
      return !failed;
    } catch (_) {
      if (!_disposed) failed = true;
      return false;
    } finally {
      operation = null;
      _notify();
    }
  }

  Future<bool> install(CatalogPlugin item, {String installScope = 'user'}) =>
      item.restorable
          ? mutate('restoreBuiltinPlugin', {'pluginId': item.id})
          : mutate('installPlugin', {
              'pluginName': item.name,
              'marketplace': item.marketplace,
              'scope': installScope
            });
  Future<bool> enable(CatalogPlugin item, bool enabled) => mutate(
      'setPluginEnabled',
      {'pluginId': item.id, 'enabled': enabled, 'scope': 'user'});
  Future<bool> uninstall(CatalogPlugin item) =>
      mutate('uninstallPlugin', {'pluginId': item.id, 'removeCache': true});
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
