import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../protocol/conversation.dart';
import '../protocol/entitlement.dart';
import '../protocol/plan_reset.dart';
import 'runtime_audit.dart';

enum PlanResetPhase { available, processing, completed }

class PlanResetEntry {
  PlanResetEntry();
  PlanResetPhase phase = PlanResetPhase.available;
  String? idempotencyKey;
  String? error;
  int? baselineUsedAt, completedAt;
  int? observedAt;
  bool automatic = false;
  bool quotaOverridePending = false;
  // An accepted call with no confirmed history must only query its status.
  bool awaitingConfirmation = false;
}

class PlanResetScope {
  PlanResetStatus? status;
  int? fetchedAt;
  bool failed = false;
  bool loading = false;
  final entries = <PlanResetType, PlanResetEntry>{};
  Future<bool>? pending;
  Future<bool>? action;
  Future<void>? opportunity;
  String? opportunityKey;
  int nextOpportunityAt = 0;
  final readHistory = <int>{};
  final readingHistory = <int>{};
  final observers = <Object, _ResetObserver>{};
  Timer? timer;
  Future<void>? maintenance;
  bool get busy =>
      entries.values.any((e) => e.phase == PlanResetPhase.processing);
}

class _ResetObserver {
  _ResetObserver(this.refreshEntitlement);
  final Future<void> Function() refreshEntitlement;
  final refreshed = <PlanResetType, int>{};
}

/// One coordinator per transport: main/side chat and usage page share requests
/// and idempotency. Different devices retain different transport identities.
class PlanResets extends ChangeNotifier {
  PlanResets(this.transport,
      {DateTime Function()? now,
      Future<void> Function(Duration)? delay,
      String Function()? newId,
      bool Function()? readOnly})
      : _now = now ?? DateTime.now,
        _delay = delay ?? Future<void>.delayed,
        _newId = newId ?? _uuid,
        _readOnly = readOnly ?? (() => RuntimeAudit.quotaReadOnly);
  static final _shared = Expando<PlanResets>();
  static PlanResets forTransport(ConversationTransport transport) =>
      _shared[transport] ??= PlanResets(transport);
  final ConversationTransport transport;
  final DateTime Function() _now;
  final Future<void> Function(Duration) _delay;
  final String Function() _newId;
  final bool Function() _readOnly;
  bool get readOnly => _readOnly();
  final _scopes = <String, PlanResetScope>{};
  // A reconnect changes account data, but must not replay the same celebration.
  final _observed = <String, Set<String>>{};
  final _celebrated = <String, Set<String>>{};
  int _generation = 0;
  bool _disposed = false;
  int get nowMillis => _now().millisecondsSinceEpoch;
  int get generation => _generation;

  static Map<String, dynamic> arguments(EntitlementSource source) => {
        'preferredProviderId': source.providerId,
        if (source.organizationId != null)
          'organizationId': source.organizationId,
        if (source.projectId != null) 'projectId': source.projectId,
      };
  static String _key(EntitlementSource source) => jsonEncode(arguments(source));
  static bool _eligible(EntitlementSource source) =>
      EntitlementSource.supports(source.providerId) &&
      !source.isStartPlan &&
      !source.needsTeamResolution;
  PlanResetScope state(EntitlementSource source) =>
      _scopes.putIfAbsent(_key(source), PlanResetScope.new);
  bool _current(int generation) => !_disposed && generation == _generation;
  void _notify() {
    if (!_disposed) notifyListeners();
  }

  /// Reauthentication/reconnect clears balances and rejects old completions.
  void invalidate() {
    _generation++;
    for (final scope in _scopes.values) {
      scope.timer?.cancel();
      scope.observers.clear();
    }
    _scopes.clear();
    _notify();
  }

  /// Mounted, foreground surfaces share one five-minute poll per source.
  VoidCallback observe(EntitlementSource source,
      {required Future<void> Function() refreshEntitlement}) {
    if (_disposed || !_eligible(source)) return () {};
    final scope = state(source);
    final token = Object();
    scope.observers[token] = _ResetObserver(refreshEntitlement);
    scope.timer ??= Timer.periodic(const Duration(minutes: 5), (_) {
      unawaited(_maintain(source, scope));
    });
    scheduleMicrotask(() => _maintain(source, scope));
    return () {
      scope.observers.remove(token);
      if (scope.observers.isEmpty) {
        scope.timer?.cancel();
        scope.timer = null;
      }
    };
  }

  Future<void> refreshObserved(EntitlementSource source,
      {bool force = false}) async {
    final scope = state(source);
    if (scope.observers.isEmpty) {
      await refresh(source, force: force);
    } else {
      await _maintain(source, scope, force: force);
    }
  }

  Future<void> _maintain(EntitlementSource source, PlanResetScope scope,
      {bool force = false}) {
    if (scope.maintenance case final pending?) return pending;
    final generation = _generation;
    bool active() => _current(generation) && scope.observers.isNotEmpty;
    final operation = () async {
      if (!active()) return;
      final before = completed(source);
      final wasBusy = scope.busy || scope.action != null;
      if (!await refresh(source, force: force) || !active()) return;
      final after = completed(source);
      final newlyCompleted = after.entries.any((e) => before[e.key] != e.value);
      await _refreshCompletions(source, scope, generation);
      if (!active() ||
          wasBusy ||
          scope.busy ||
          scope.action != null ||
          newlyCompleted) {
        return;
      }
      await requestOpportunity(source);
      if (active() &&
          completed(source).entries.any((e) => after[e.key] != e.value)) {
        await _refreshCompletions(source, scope, generation);
      }
    }();
    scope.maintenance = operation;
    return operation.whenComplete(() {
      if (identical(scope.maintenance, operation)) scope.maintenance = null;
    });
  }

  Future<void> _refreshCompletions(
      EntitlementSource source, PlanResetScope scope, int generation) async {
    bool active() => _current(generation) && scope.observers.isNotEmpty;
    if (!active()) return;
    final after = completed(source);
    if (scope.status?.hasUnreadHistory == true && after.isNotEmpty) {
      await markHistoryRead(source);
    }
    for (final subscriber in scope.observers.entries.toList()) {
      if (!active()) return;
      if (!scope.observers.containsKey(subscriber.key)) continue;
      final observer = subscriber.value;
      if (!after.entries.any((e) => observer.refreshed[e.key] != e.value)) {
        continue;
      }
      try {
        await observer.refreshEntitlement();
        if (active() && scope.observers.containsKey(subscriber.key)) {
          observer.refreshed.addAll(after);
        }
      } catch (_) {
        // A failed entitlement read retries on the next visible observation.
      }
    }
  }

  Future<bool> refresh(EntitlementSource source, {bool force = false}) {
    if (_disposed || !_eligible(source)) return Future.value(false);
    final scope = state(source);
    if (scope.pending case final pending?) return pending;
    if (!force &&
        scope.fetchedAt != null &&
        nowMillis - scope.fetchedAt! < 1500) {
      return Future.value(true);
    }
    final generation = _generation;
    scope.loading = true;
    _notify();
    final operation = () async {
      try {
        final status = PlanResetStatus.parse(
            await transport.planResetStatus(arguments(source)));
        if (!_current(generation)) return false;
        scope.status = status;
        scope.fetchedAt = nowMillis;
        scope.failed = false;
        for (final type in PlanResetType.values) {
          var entry = scope.entries[type];
          final history = status.usedAt[type];
          final otherHistory = status.usedAt[type == PlanResetType.week
              ? PlanResetType.fiveHour
              : PlanResetType.week];
          final unreadLatest = status.hasUnreadHistory &&
              history != null &&
              (otherHistory == null || history >= otherHistory);
          final manual = entry != null &&
              (entry.phase == PlanResetPhase.processing ||
                  entry.idempotencyKey != null ||
                  entry.awaitingConfirmation);
          final confirmedManual =
              manual && history != null && history != entry.baselineUsedAt;
          if (history != null &&
              (confirmedManual || (!manual && unreadLatest))) {
            entry ??= scope.entries.putIfAbsent(type, PlanResetEntry.new);
            final same = entry.phase == PlanResetPhase.completed &&
                entry.completedAt == history;
            final first = _observed
                .putIfAbsent(_key(source), () => {})
                .add('${type.wire}:$history');
            if (!same) {
              entry
                ..observedAt = !manual && first ? nowMillis : null
                ..automatic = !manual
                ..quotaOverridePending = true;
            }
            entry
              ..phase = PlanResetPhase.completed
              ..completedAt = history
              ..idempotencyKey = null
              ..awaitingConfirmation = false
              ..error = null;
          } else if (entry?.phase == PlanResetPhase.completed &&
              !status.hasUnreadHistory &&
              status.available(type, nowMillis).isNotEmpty) {
            entry!.phase = PlanResetPhase.available;
          }
        }
        return true;
      } catch (_) {
        if (_current(generation)) scope.failed = true;
        return false;
      } finally {
        if (_current(generation)) {
          scope.loading = false;
          _notify();
        }
      }
    }();
    scope.pending = operation;
    return operation.whenComplete(() {
      if (identical(scope.pending, operation)) scope.pending = null;
    });
  }

  List<int> available(EntitlementSource source, PlanResetType type) =>
      state(source).entries[type]?.phase == PlanResetPhase.completed
          ? const []
          : state(source).status?.available(type, nowMillis) ?? const [];

  Map<PlanResetType, int> completed(EntitlementSource source) => {
        for (final item in state(source).entries.entries)
          if (item.value.completedAt case final int date) item.key: date,
      };

  bool claimCelebration(EntitlementSource source, PlanResetType type, int at) =>
      _celebrated.putIfAbsent(_key(source), () => {}).add('${type.wire}:$at');

  void acknowledgeEntitlement(
      EntitlementSource source, Map<PlanResetType, int> observedCompletions) {
    for (final item in observedCompletions.entries) {
      final entry = state(source).entries[item.key];
      if (entry?.completedAt == item.value) entry!.quotaOverridePending = false;
    }
    _notify();
  }

  /// Official GF only projects a reset after a changed server history confirms it.
  QuotaLimit? displayLimit(
      EntitlementSource source, PlanResetType type, QuotaLimit? limit) {
    final entry = state(source).entries[type];
    if (limit == null || entry?.completedAt == null) return limit;
    final next = entry!.completedAt! + type.period.inMilliseconds;
    return entry.quotaOverridePending
        ? limit.afterReset(next, refill: true)
        : limit.nextResetTime == null
            ? limit.afterReset(next)
            : limit;
  }

  /// Only a deliberate reset gesture calls this. Status reads never consume.
  Future<bool> use(EntitlementSource source, PlanResetType type) {
    if (_disposed || readOnly || !_eligible(source)) return Future.value(false);
    final scope = state(source);
    if (scope.action != null || scope.busy) return Future.value(false);
    final generation = _generation;
    final operation = () async {
      final entry = scope.entries.putIfAbsent(type, PlanResetEntry.new);
      final retrying =
          entry.idempotencyKey != null || entry.awaitingConfirmation;
      if (!await refresh(source, force: true) || !_current(generation)) {
        return false;
      }
      if (retrying && entry.phase == PlanResetPhase.completed) return true;
      if (entry.awaitingConfirmation) {
        return entry.phase == PlanResetPhase.completed;
      }
      if (entry.phase == PlanResetPhase.completed) {
        // The dialog removes its completed item. A later explicit use may
        // consume another, still authoritative opportunity.
        if (available(source, type).isEmpty) return true;
        entry.phase = PlanResetPhase.available;
      }
      if (available(source, type).isEmpty) return false;
      entry
        ..baselineUsedAt = scope.status?.usedAt[type]
        ..idempotencyKey ??= _newId();
      entry
        ..phase = PlanResetPhase.processing
        ..automatic = false
        ..observedAt = null
        ..error = null;
      _notify();
      try {
        await transport.usePlanReset(arguments(source),
            resetType: type.wire, idempotencyKey: entry.idempotencyKey!);
        if (!_current(generation)) return false;
        entry.awaitingConfirmation = true;
        for (final wait in [0, 250, 750, 1500]) {
          await _delay(Duration(milliseconds: wait));
          if (!_current(generation)) return false;
          await refresh(source, force: true);
          if (!_current(generation)) return false;
          if (entry.phase == PlanResetPhase.completed) return true;
        }
        entry.error = 'unconfirmed';
        return false;
      } catch (_) {
        if (_current(generation)) entry.error = 'failed';
        return false;
      } finally {
        if (_current(generation)) {
          if (entry.phase == PlanResetPhase.processing) {
            entry.phase = PlanResetPhase.available;
          }
          _notify();
        }
      }
    }();
    scope.action = operation;
    return operation.whenComplete(() {
      if (identical(scope.action, operation)) scope.action = null;
      if (_current(generation)) _notify();
    });
  }

  /// Official _Xe/mXe maintenance. Separate from read-only status access so
  /// read-only verification can exercise the UI without granting credits.
  Future<void> requestOpportunity(EntitlementSource source) {
    if (_disposed || readOnly || !_eligible(source)) return Future.value();
    final scope = state(source);
    if (scope.opportunity case final pending?) return pending;
    if (scope.busy || nowMillis < scope.nextOpportunityAt) {
      return Future.value();
    }
    final generation = _generation;
    final id = scope.opportunityKey ?? _newId();
    final operation = () async {
      try {
        final value = PlanResetOpportunity.parse(
            await transport.requestPlanResetOpportunity(arguments(source), id));
        if (!_current(generation)) return;
        scope.nextOpportunityAt = value.nextCheckAt(nowMillis);
        scope.opportunityKey = null;
        if (value.granted) await refresh(source, force: true);
      } catch (error) {
        if (!_current(generation)) return;
        final message = error.toString().toLowerCase();
        final throttled = message.contains('opportunity_throttled') ||
            message.contains('api_error:429');
        final retry = !throttled &&
            (error is TimeoutException ||
                [
                  'api_error:2007',
                  'aborterror',
                  'failed to fetch',
                  'fetch failed',
                  'network error',
                  'network request failed',
                  'timeout',
                  'timed out',
                  'econnreset',
                  'econnrefused',
                  'enotfound',
                  'etimedout',
                  'eai_again',
                ].any(message.contains));
        scope.nextOpportunityAt = nowMillis + (retry ? 300000 : 600000);
        scope.opportunityKey = retry ? id : null;
      }
    }();
    scope.opportunity = operation;
    return operation.whenComplete(() {
      if (identical(scope.opportunity, operation)) scope.opportunity = null;
    });
  }

  Future<void> markHistoryRead(EntitlementSource source) async {
    if (_disposed || readOnly || !_eligible(source)) return;
    final scope = state(source);
    final status = scope.status;
    if (status == null || !status.hasUnreadHistory) return;
    final histories = status.usedAt.values.whereType<int>().toList();
    if (histories.isEmpty) return;
    final latest = histories.reduce(max);
    if (scope.readHistory.contains(latest) ||
        !scope.readingHistory.add(latest)) {
      return;
    }
    final generation = _generation;
    try {
      await transport.markPlanResetHistoryRead(arguments(source));
      if (_current(generation)) scope.readHistory.add(latest);
    } catch (_) {
      // Retain the unread entry so the next observation can retry.
    } finally {
      scope.readingHistory.remove(latest);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    for (final scope in _scopes.values) {
      scope.timer?.cancel();
      scope.observers.clear();
    }
    super.dispose();
  }
}

String _uuid() {
  final random = Random.secure();
  final bytes = List.generate(16, (_) => random.nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
      '${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
}
