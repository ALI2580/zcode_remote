import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/channel_client.dart';
import '../protocol/zemote_client.dart';

enum RemoteSettingsStatus { idle, loading, loaded, error }

/// Read-only projection of the official `settingService.get()` snapshot.
///
/// Writes intentionally stay outside this controller until each remote-control
/// setting has an independently verified update payload and failure contract.
class RemoteSettingsSnapshot {
  RemoteSettingsSnapshot({
    this.values = const {},
    this.providerFamilyDomain,
    this.providerFamilyModes = const {},
    this.providerFamilySelectedKeys = const {},
    this.embeddedBrowserAllowInsecureCertificates,
    this.repoSnapshotIndexingEnabled,
    this.instantGrepIndexingEnabled,
    this.askUserQuestionAutoResolutionEnabled,
    this.memoryEnabled,
    this.taskAutoArchiveEnabled,
    this.taskAutoArchiveOlderThanDays,
    this.messageStreamShowReasoning,
    this.messageStreamShowTodos,
    this.modelIoFullRetentionEnabled,
    this.zcodeInteractionBehavior,
    this.terminalInheritSystemProfile,
    this.terminalFontFamily,
    this.integratedTerminalShellMode,
    this.integratedTerminalShellId,
    this.integratedTerminalShellLabel,
    this.integratedTerminalShellDialect,
    this.integratedTerminalShellPath,
    this.nativeSearchEnhancementsEnabled,
    this.httpProxy,
    this.httpProxyNoProxy,
    this.httpProxyCaCertPath,
    this.toolGroupingExploreEnabled,
    this.toolGroupingTerminalEnabled,
    this.toolGroupingChangesEnabled,
  });

  factory RemoteSettingsSnapshot.fromRaw(Object? raw) {
    final map =
        raw is Map ? raw.cast<String, dynamic>() : const <String, dynamic>{};
    Map<String, String> stringMap(String key) => map[key] is Map
        ? (map[key] as Map).map((key, value) =>
            MapEntry('$key', value is String ? value : '$value'))
        : const {};
    final snapshot = RemoteSettingsSnapshot(
      values: map,
      providerFamilyDomain: map['providerFamilyDomain'] is String
          ? map['providerFamilyDomain'] as String
          : null,
      providerFamilyModes: stringMap('modelProviderFamilyModes'),
      providerFamilySelectedKeys: stringMap('modelProviderFamilySelectedKeys'),
      repoSnapshotIndexingEnabled: map['repoSnapshotIndexingEnabled'] is bool
          ? map['repoSnapshotIndexingEnabled'] as bool
          : null,
      instantGrepIndexingEnabled:
          map['instantGrepIndexingEnabled'] is bool
              ? map['instantGrepIndexingEnabled'] as bool
              : null,
      embeddedBrowserAllowInsecureCertificates:
          map['embeddedBrowserAllowInsecureCertificates'] is bool
              ? map['embeddedBrowserAllowInsecureCertificates'] as bool
              : null,
      askUserQuestionAutoResolutionEnabled:
          map['askUserQuestionAutoResolutionEnabled'] is bool
              ? map['askUserQuestionAutoResolutionEnabled'] as bool
              : null,
      memoryEnabled:
          map['memoryEnabled'] is bool ? map['memoryEnabled'] as bool : null,
      taskAutoArchiveEnabled: map['taskAutoArchiveEnabled'] is bool
          ? map['taskAutoArchiveEnabled'] as bool
          : null,
      taskAutoArchiveOlderThanDays: map['taskAutoArchiveOlderThanDays'] is num
          ? (map['taskAutoArchiveOlderThanDays'] as num).toInt()
          : null,
      messageStreamShowReasoning:
          map['messageStreamShowReasoning'] is bool
              ? map['messageStreamShowReasoning'] as bool
              : null,
      messageStreamShowTodos: map['messageStreamShowTodos'] is bool
          ? map['messageStreamShowTodos'] as bool
          : null,
      modelIoFullRetentionEnabled: map['modelIoFullRetentionEnabled'] is bool
          ? map['modelIoFullRetentionEnabled'] as bool
          : null,
      zcodeInteractionBehavior: map['zcodeInteractionBehavior'] is String
          ? map['zcodeInteractionBehavior'] as String
          : null,
      terminalInheritSystemProfile:
          map['terminalInheritSystemProfile'] is bool
              ? map['terminalInheritSystemProfile'] as bool
              : null,
      terminalFontFamily: map['terminalFontFamily'] is String
          ? map['terminalFontFamily'] as String
          : null,
      nativeSearchEnhancementsEnabled:
          map['nativeSearchEnhancementsEnabled'] is bool
              ? map['nativeSearchEnhancementsEnabled'] as bool
              : null,
      httpProxy:
          map['httpProxy'] is String ? map['httpProxy'] as String : null,
      httpProxyNoProxy: map['httpProxyNoProxy'] is String
          ? map['httpProxyNoProxy'] as String
          : null,
      httpProxyCaCertPath: map['httpProxyCaCertPath'] is String
          ? map['httpProxyCaCertPath'] as String
          : null,
      toolGroupingExploreEnabled: map['toolGroupingExploreEnabled'] is bool
          ? map['toolGroupingExploreEnabled'] as bool
          : null,
      toolGroupingTerminalEnabled: map['toolGroupingTerminalEnabled'] is bool
          ? map['toolGroupingTerminalEnabled'] as bool
          : null,
      toolGroupingChangesEnabled: map['toolGroupingChangesEnabled'] is bool
          ? map['toolGroupingChangesEnabled'] as bool
          : null,
    );
    _applyIntegratedTerminalShell(
        snapshot, map['integratedTerminalShell']);
    return snapshot;
  }

  /// Official integratedTerminalShell is an object `{mode, ...shell}`; a
  /// missing or non-map value stays fully unknown instead of implying
  /// `auto`. Filled from [RemoteSettingsSnapshot.fromRaw].
  static void _applyIntegratedTerminalShell(
      RemoteSettingsSnapshot snapshot, Object? raw) {
    if (raw is! Map) return;
    snapshot.integratedTerminalShellMode =
        raw['mode'] is String ? raw['mode'] as String : null;
    snapshot.integratedTerminalShellId =
        raw['id'] is String ? raw['id'] as String : null;
    snapshot.integratedTerminalShellLabel =
        raw['label'] is String ? raw['label'] as String : null;
    snapshot.integratedTerminalShellDialect =
        raw['dialect'] is String ? raw['dialect'] as String : null;
    snapshot.integratedTerminalShellPath =
        raw['path'] is String ? raw['path'] as String : null;
  }

  final Map<String, dynamic> values;
  final String? providerFamilyDomain;
  final Map<String, String> providerFamilyModes;
  final Map<String, String> providerFamilySelectedKeys;
  final bool? embeddedBrowserAllowInsecureCertificates;
  final bool? repoSnapshotIndexingEnabled;
  final bool? instantGrepIndexingEnabled;
  final bool? messageStreamShowReasoning;
  final bool? messageStreamShowTodos;
  final bool? modelIoFullRetentionEnabled;
  final String? zcodeInteractionBehavior;
  final bool? askUserQuestionAutoResolutionEnabled;
  final bool? memoryEnabled;
  final bool? taskAutoArchiveEnabled;
  final int? taskAutoArchiveOlderThanDays;

  // Official defaults (`??` in the general-section component) are applied by
  // the UI, not here: a missing key must stay distinguishable from a stored
  // value.
  final bool? terminalInheritSystemProfile;
  final String? terminalFontFamily;
  final bool? nativeSearchEnhancementsEnabled;
  final String? httpProxy;
  final String? httpProxyNoProxy;
  final String? httpProxyCaCertPath;
  final bool? toolGroupingExploreEnabled;
  final bool? toolGroupingTerminalEnabled;
  final bool? toolGroupingChangesEnabled;

  /// Runtime consumers use the same defaults as the official general
  /// settings pane. Keep nullable wire values above so a failed/partial read
  /// never masquerades as a persisted value, while these helpers provide the
  /// effective value for rendering.
  bool get showReasoning => messageStreamShowReasoning ?? true;
  bool get showTodos => messageStreamShowTodos ?? false;
  bool get groupExplore => toolGroupingExploreEnabled ?? true;
  bool get groupTerminal => toolGroupingTerminalEnabled ?? true;
  bool get groupChanges => toolGroupingChangesEnabled ?? false;

  // Integrated shell is a nested object; filled in [fromRaw] after the
  // constructor so the raw shape does not leak into call sites.
  String? integratedTerminalShellMode;
  String? integratedTerminalShellId;
  String? integratedTerminalShellLabel;
  String? integratedTerminalShellDialect;
  String? integratedTerminalShellPath;

  bool get isEmpty => values.isEmpty;
}

class RemoteSettingsController extends ChangeNotifier {
  RemoteSettingsController({required this.session, required this.scopeKey}) {
    session.degraded.addListener(_onConnectionChanged);
    session.recovered.addListener(_onConnectionRecovered);
  }

  final BridgeSession session;
  final String scopeKey;

  int _generation = 0;
  Future<void>? _pending;
  bool _disposed = false;
  final Set<String> _savingKeys = {};
  final Map<String, Object?> _saveErrors = {};
  final Map<String, Object?> _lastAttempts = {};

  RemoteSettingsStatus status = RemoteSettingsStatus.idle;
  RemoteSettingsSnapshot snapshot = RemoteSettingsSnapshot();
  Object? error;

  bool get remoteOperationsAvailable => session.degraded.value == null;

  void _onConnectionChanged() {
    _generation++;
    if (!_disposed) notifyListeners();
  }

  void _onConnectionRecovered() {
    _generation++;
    if (!_disposed) unawaited(refresh());
  }

  bool isSaving(String key) => _savingKeys.contains(key);

  Object? saveError(String key) => _saveErrors[key];

  /// The most recent value attempted for `key` — used to retry a failed
  /// write with the user's intended value, not the stale server value.
  Object? lastAttempt(String key) => _lastAttempts[key];

  /// Official `settingService.update(patch)`. The read-back after a
  /// successful call is the only source of visible state; a failed write
  /// keeps the previous snapshot so the UI never shows a change that did
  /// not happen.
  Future<void> update(String key, Object? value) async {
    await updatePatch({key: value});
  }

  /// Some official toggles write several keys in one call (e.g. the
  /// indexing switch also sets its user-configured flag). The patch is
  /// deduplicated as a whole and retried as a whole.
  Future<void> updatePatch(Map<String, Object?> patch) async {
    if (patch.isEmpty) return;
    final patchKey = patch.keys.join('|');
    if (_disposed || _savingKeys.contains(patchKey)) return;
    if (!remoteOperationsAvailable) {
      _saveErrors[patchKey] = 'remote connection unavailable';
      _lastAttempts[patchKey] = Map<String, Object?>.from(patch);
      notifyListeners();
      return;
    }
    final generation = _generation;
    _savingKeys.add(patchKey);
    _saveErrors.remove(patchKey);
    _lastAttempts[patchKey] = Map<String, Object?>.from(patch);
    notifyListeners();
    try {
      await session.channels.call(
        'setting',
        'update',
        [patch],
        timeout: const Duration(seconds: 20),
      );
      if (_disposed ||
          generation != _generation ||
          !remoteOperationsAvailable) {
        return;
      }
      await refresh();
    } catch (value) {
      if (_disposed) return;
      _saveErrors[patchKey] = value;
    } finally {
      _savingKeys.remove(patchKey);
      if (!_disposed) notifyListeners();
    }
  }

  /// Deprecated one-shot team upgrade. The full official migration now
  /// lives in [migrateProviderFamilySelections] and runs from the workspace
  /// shell startup path.
  Future<bool> migrateTeamSelectedKeys() async {
    final migrated = await migrateProviderFamilySelections(
        session: session, upgradeTeamPlan: true);
    return migrated.isNotEmpty;
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    final pending = _pending;
    if (pending != null) return pending;
    final generation = ++_generation;
    status = RemoteSettingsStatus.loading;
    notifyListeners();

    Future<void>? operationFuture;
    Future<void> operation() async {
      try {
        if (!remoteOperationsAvailable) {
          if (!_disposed && generation == _generation) {
            status = RemoteSettingsStatus.error;
            error = 'remote connection unavailable';
          }
          return;
        }
        final raw = await session.channels.call(
          'setting',
          'get',
          const [],
          timeout: const Duration(seconds: 20),
        );
        if (_disposed || generation != _generation) return;
        snapshot = RemoteSettingsSnapshot.fromRaw(raw);
        status = RemoteSettingsStatus.loaded;
        error = null;
      } catch (value) {
        if (_disposed || generation != _generation) return;
        status = RemoteSettingsStatus.error;
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

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    session.degraded.removeListener(_onConnectionChanged);
    session.recovered.removeListener(_onConnectionRecovered);
    super.dispose();
  }
}

const List<String> _providerFamilies = ['zai', 'bigmodel'];

String _defaultFamilyKey(String family, String mode) => mode == 'oauth'
    ? 'coding-plan:builtin:$family-coding-plan'
    : 'preset:builtin:$family';

String _decodeKeyPart(String value) {
  try {
    return Uri.decodeComponent(value).trim();
  } on FormatException {
    return value.trim();
  }
}

/// Official T1t key validity: in apiKey mode only the family preset key;
/// otherwise the coding-plan key, the start-plan key or a fully identified
/// team key (`team-plan:<provider>:<productId>:<org>:<project>`).
bool _isValidFamilyKey(String family, String mode, String key) {
  if (mode == 'apiKey') return key == 'preset:builtin:$family';
  if (key == 'coding-plan:builtin:$family-coding-plan' ||
      key == 'coding-plan:builtin:$family-start-plan') {
    return true;
  }
  final prefix = 'team-plan:builtin:$family-coding-plan:';
  if (!key.startsWith(prefix)) return false;
  final parts =
      key.substring(prefix.length).split(':').map(_decodeKeyPart).toList();
  return parts.length >= 3 && parts.take(3).every((part) => part.isNotEmpty);
}

String? _trimmedString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;

/// Official jB team-key selection: the first subscribed product whose
/// product-level or per-project identity is usable; `unavailable` API keys
/// and empty organization/project values are skipped.
String? _firstTeamKey(Object? raw, String family) {
  final products = raw is Map && raw['productList'] is List
      ? (raw['productList'] as List).whereType<Map>()
      : const Iterable<Map>.empty();
  for (final product in products) {
    if (product['subscribed'] != true) continue;
    final productId = _trimmedString(product['productId']);
    if (productId == null) continue;
    final projects = product['teamProjects'] is List &&
            (product['teamProjects'] as List).isNotEmpty
        ? (product['teamProjects'] as List).whereType<Map>()
        : <Map>[product];
    for (final project in projects) {
      if (project['apiKeyStatus'] == 'unavailable') continue;
      final organization = _trimmedString(project['organizationId']);
      final projectKey = _trimmedString(project['projectId']);
      if (organization == null || projectKey == null) continue;
      return 'team-plan:builtin:$family-coding-plan:'
          '${[productId, organization, projectKey].map(Uri.encodeComponent).join(':')}';
    }
  }
  return null;
}

final Map<BridgeSession, Future<List<String>>> _familyMigrations = {};

/// Official A1t startup migration (remote Root, after restoring the OAuth
/// login state). D1t rewrites invalid family keys to the mode default with
/// one read-merge-write update; a just-reset oauth key may then upgrade to
/// the first subscribed team key (k1t) behind a pre-write re-read so a
/// newer remote value is never overwritten. Pricing failures keep the
/// reset default. Returns the domains whose keys were rewritten.
Future<List<String>> migrateProviderFamilySelections({
  required BridgeSession session,
  required bool upgradeTeamPlan,
}) {
  final inFlight = _familyMigrations[session];
  if (inFlight != null) return inFlight;
  // The block body matters: Map.remove returns the removed future, and a
  // whenComplete callback that returns that future would wait on itself.
  final future = _runFamilyMigration(session, upgradeTeamPlan)
      .whenComplete(() {
    _familyMigrations.remove(session);
  });
  _familyMigrations[session] = future;
  return future;
}

Future<List<String>> _runFamilyMigration(
    BridgeSession session, bool upgradeTeamPlan) async {
  Future<Object?> call(String method, [List<Object?> args = const []]) =>
      session.degraded.value == null
          ? session.channels.call('setting', method, args,
              timeout: const Duration(seconds: 20))
          : Future<Object?>.error(StateError('remote connection unavailable'));

  Map<String, dynamic> readSettings(Object? raw) =>
      raw is Map ? raw.cast<String, dynamic>() : <String, dynamic>{};

  Map<String, String> stringMap(Map<String, dynamic> settings, String key) =>
      settings[key] is Map
          ? (settings[key] as Map).cast<String, dynamic>().map(
              (key, value) => MapEntry(key, value is String ? value : ''))
          : const <String, String>{};

  // Official D1t: unset modes never migrate; invalid keys are reset to the
  // current mode default.
  final settings = readSettings(await call('get'));
  final modes = stringMap(settings, 'modelProviderFamilyModes');
  final selected = stringMap(settings, 'modelProviderFamilySelectedKeys');
  final resetDomains = <String>[];
  final resetKeys = Map<String, String>.of(selected);
  for (final family in _providerFamilies) {
    final mode = modes[family];
    if (mode == null || mode.isEmpty) continue;
    if (_isValidFamilyKey(family, mode, selected[family] ?? '')) continue;
    resetKeys[family] = _defaultFamilyKey(family, mode);
    resetDomains.add(family);
  }
  if (resetDomains.isNotEmpty) {
    await call('update', [
      {'modelProviderFamilySelectedKeys': resetKeys}
    ]);
  }

  // Official k1t: only just-reset oauth keys upgrade to a team key.
  if (upgradeTeamPlan) {
    for (final family in resetDomains) {
      if (modes[family] != 'oauth') continue;
      final String? teamKey;
      try {
        if (session.degraded.value != null) continue;
        teamKey = _firstTeamKey(
            await session.channels.call(
              Channels.codingPlanSubscription,
              'getEnterprisePricing',
              [
                {'authenticated': true, 'family': family}
              ],
              timeout: const Duration(seconds: 20),
            ),
            family);
      } catch (_) {
        continue;
      }
      if (teamKey == null) continue;
      final latest = readSettings(await call('get'));
      final latestKeys = stringMap(latest, 'modelProviderFamilySelectedKeys');
      if (latestKeys[family] != 'coding-plan:builtin:$family-coding-plan') {
        continue;
      }
      await call('update', [
        {
          'modelProviderFamilySelectedKeys':
              Map<String, String>.of(latestKeys)..[family] = teamKey
        }
      ]);
    }
  }
  return resetDomains;
}
