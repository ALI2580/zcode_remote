import 'dart:async';
import 'package:flutter/widgets.dart';
import '../protocol/conversation.dart';
import '../protocol/entitlement.dart';
import '../protocol/plan_reset.dart';
import 'plan_resets.dart';

class _EntitlementCache {
  const _EntitlementCache(this.snapshot, this.at);
  final EntitlementSnapshot snapshot;
  final DateTime at;
}

class _TeamSourceCache {
  const _TeamSourceCache(this.source, this.at);
  final EntitlementSource source;
  final DateTime at;
}

class _TeamSourceUnavailable implements Exception {}

/// Device/workspace-owned quotas; a provider/team change invalidates pending
/// requests. Access refresh follows official Lke=60s and qke=20s (transport).
class ComposerUsage extends ChangeNotifier with WidgetsBindingObserver {
  ComposerUsage(this.transport, {DateTime Function()? now, PlanResets? resets})
      : _now = now ?? DateTime.now,
        resets = resets ?? PlanResets.forTransport(transport) {
    this.resets.addListener(_notify);
  }
  final ConversationTransport transport;
  final PlanResets resets;
  final DateTime Function() _now;
  final _cache = <String, _EntitlementCache>{};
  final _teamSources = <String, _TeamSourceCache>{};
  String? _provider;
  String? _selectionKey;
  EntitlementSource? source;
  EntitlementSnapshot? snapshot;
  bool loadingSelection = false;
  bool refreshing = false;
  bool failed = false;
  bool sourceUnavailable = false;
  bool _disposed = false;
  int _generation = 0;
  Future<bool>? _selectionRead;
  Future<void>? _request;
  int _visibleSurfaces = 0;
  VoidCallback? _stopObserving;
  String? _observedSource;
  int? _observedGeneration;
  bool _foreground = true;
  bool get eligible =>
      EntitlementSource.supports(_provider) &&
      (loadingSelection || source != null || failed);

  VoidCallback observeResets() {
    if (_disposed) return () {};
    if (_visibleSurfaces++ == 0) {
      WidgetsBinding.instance.addObserver(this);
      final lifecycle = WidgetsBinding.instance.lifecycleState;
      _foreground = lifecycle == null || lifecycle == AppLifecycleState.resumed;
    }
    _syncObservation();
    var released = false;
    return () {
      if (released || _disposed) return;
      released = true;
      if (--_visibleSurfaces == 0) WidgetsBinding.instance.removeObserver(this);
      _syncObservation();
    };
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncObservation();
  }

  void _syncObservation() {
    final target =
        !_disposed && _visibleSurfaces > 0 && _foreground ? source : null;
    if (_observedSource == target?.key &&
        _observedGeneration == resets.generation) {
      return;
    }
    _stopObserving?.call();
    _stopObserving = null;
    _observedSource = target?.key;
    _observedGeneration = resets.generation;
    if (target == null || target.isStartPlan) return;
    _stopObserving = resets.observe(target, refreshEntitlement: () async {
      if (_disposed || source?.key != target.key) return;
      // A quota read begun before the completion cannot acknowledge it.
      if (_request case final pending?) await pending;
      if (_disposed || source?.key != target.key) return;
      await refresh(force: true);
      if (failed) throw StateError('entitlement refresh failed');
    });
  }

  void selectProvider(String? provider) {
    if (_provider == provider || _disposed) return;
    _provider = provider;
    invalidate(clearCache: false);
  }

  void invalidate({bool clearCache = true}) {
    _generation++;
    // A reconnected desktop may now be signed into another account while the
    // family source key still says "coding-plan:<provider>".
    if (clearCache) {
      _cache.clear();
      _teamSources.clear();
      resets.invalidate();
    }
    _selectionKey = null;
    _selectionRead = null;
    _request = null;
    source = null;
    snapshot = null;
    refreshing = false;
    failed = false;
    sourceUnavailable = false;
    loadingSelection = EntitlementSource.supports(_provider);
    _notify();
    if (loadingSelection) unawaited(_readSelection());
  }

  Future<void> refreshResetStatus({bool force = false}) async {
    final selected = source;
    if (selected == null || selected.isStartPlan) return;
    await resets.refreshObserved(selected, force: force);
  }

  QuotaLimit? resetLimit(PlanResetType type) => source == null
      ? null
      : resets.displayLimit(source!, type,
          type == PlanResetType.week ? snapshot?.weekly : snapshot?.fiveHour);

  bool resetVisible(PlanResetType type) {
    final selected = source;
    final limit = resetLimit(type);
    return selected != null &&
        !selected.isStartPlan &&
        limit != null &&
        !limit.isFull &&
        resets.available(selected, type).isNotEmpty;
  }

  int get resetCount => source == null
      ? 0
      : PlanResetType.values
          .where(resetVisible)
          .fold(0, (sum, type) => sum + resets.available(source!, type).length);

  Future<bool> useReset(PlanResetType type, {required String sourceKey}) async {
    if (_disposed || source?.key != sourceKey) return false;
    final generation = _generation;
    // The family selection may have changed remotely since the popup opened.
    await refresh(force: true);
    if (_disposed ||
        generation != _generation ||
        source?.key != sourceKey ||
        failed ||
        resetLimit(type) == null ||
        resetLimit(type)!.isFull) {
      return false;
    }
    final target = source!;
    final result = await resets.use(target, type);
    if (result &&
        !_disposed &&
        generation == _generation &&
        source?.key == sourceKey) {
      await refresh(force: true);
      if (!_disposed && generation == _generation && source?.key == sourceKey) {
        await resets.markHistoryRead(target);
      }
    }
    return result;
  }

  Future<bool> _readSelection() {
    final pending = _selectionRead;
    if (pending != null) return pending;
    final generation = _generation;
    final provider = _provider;
    final operation = () async {
      if (!EntitlementSource.supports(provider)) return false;
      loadingSelection = true;
      sourceUnavailable = false;
      _notify();
      try {
        final settings = await transport.providerFamilySelection();
        if (_disposed || generation != _generation) return false;
        var next = EntitlementSource.resolve(provider, settings);
        if (_selectionKey != next?.key) {
          _selectionKey = next?.key;
          source = null;
          snapshot = null;
          _notify();
        }
        if (next?.needsTeamResolution == true) {
          next = await _resolveTeam(next!, generation);
          if (_disposed || generation != _generation) return false;
        }
        if (next?.key != source?.key) {
          snapshot = next == null ? null : _cache[next.key]?.snapshot;
        }
        source = next;
        failed = false;
        sourceUnavailable = false;
        return true;
      } on _TeamSourceUnavailable {
        if (!_disposed && generation == _generation) {
          source = null;
          snapshot = null;
          failed = true;
          sourceUnavailable = true;
        }
        return false;
      } catch (_) {
        if (!_disposed && generation == _generation) failed = true;
        return false;
      } finally {
        if (!_disposed && generation == _generation) {
          loadingSelection = false;
          _notify();
        }
      }
    }();
    _selectionRead = operation;
    return operation.whenComplete(() {
      if (identical(_selectionRead, operation)) _selectionRead = null;
    });
  }

  Future<EntitlementSource?> _resolveTeam(
      EntitlementSource selected, int generation) async {
    final cached = _teamSources[selected.key];
    if (cached != null &&
        _now().difference(cached.at) < const Duration(seconds: 60)) {
      return cached.source;
    }
    EntitlementSource? resolved;
    try {
      final products = await transport.teamPlanProducts(selected.family);
      if (_disposed || generation != _generation) return null;
      resolved = selected.resolveTeamProducts(products);
    } catch (_) {
      if (_disposed || generation != _generation) return null;
      // Official A2e retains a previously resolved identity when pricing is
      // unavailable. A subsequent quota still has to match this exact scope.
    }
    if (resolved == null && cached != null) return cached.source;
    if (resolved == null) {
      final raw = await transport.entitlementSnapshot(selected.providerId);
      if (_disposed || generation != _generation) return null;
      resolved = selected.resolveTeamSnapshot(EntitlementSnapshot.parse(raw));
    }
    if (resolved == null) throw _TeamSourceUnavailable();
    _teamSources.remove(selected.key);
    _teamSources[selected.key] = _TeamSourceCache(resolved, _now());
    while (_teamSources.length > 8) {
      _teamSources.remove(_teamSources.keys.first);
    }
    return resolved;
  }

  Future<void> refresh({bool force = false}) {
    final pending = _request;
    if (pending != null) return pending;
    final generation = _generation;
    final operation = () async {
      final verified = await _readSelection();
      if (!verified || _disposed || generation != _generation) return;
      final target = source;
      if (target == null) return;
      final completions = resets.completed(target);
      final cached = _cache[target.key];
      if (!force &&
          cached != null &&
          _now().difference(cached.at) < const Duration(seconds: 60)) {
        snapshot = cached.snapshot;
        _notify();
        return;
      }
      refreshing = true;
      failed = false;
      _notify();
      try {
        final raw = await transport.entitlementSnapshot(target.providerId,
            organizationId: target.organizationId, projectId: target.projectId);
        if (_disposed ||
            generation != _generation ||
            source?.key != target.key) {
          return;
        }
        final value = EntitlementSnapshot.parse(raw);
        if (value == null ||
            (!target.accepts(value) && !value.isUnconfiguredSource)) {
          throw const FormatException('entitlement source mismatch');
        }
        snapshot = value;
        _cache[target.key] = _EntitlementCache(value, _now());
        resets.acknowledgeEntitlement(target, completions);
      } catch (_) {
        if (!_disposed &&
            generation == _generation &&
            source?.key == target.key) {
          failed = true;
        }
      } finally {
        if (!_disposed && generation == _generation) {
          refreshing = false;
          _notify();
        }
      }
    }();
    _request = operation;
    return operation.whenComplete(() {
      if (identical(_request, operation)) _request = null;
    });
  }

  void _notify() {
    if (!_disposed) {
      _syncObservation();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _stopObserving?.call();
    if (_visibleSurfaces > 0) WidgetsBinding.instance.removeObserver(this);
    resets.removeListener(_notify);
    super.dispose();
  }
}
