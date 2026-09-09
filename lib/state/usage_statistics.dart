import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../protocol/conversation.dart';
import '../protocol/entitlement.dart';
import '../protocol/usage_statistics.dart';
import 'plan_resets.dart';

Future<String> usageTimeZone() async {
  final zone = await const MethodChannel('zcode_remote/platform')
      .invokeMethod<String>('timeZone');
  if (zone == null || zone.isEmpty) throw StateError('time_zone_unavailable');
  return zone;
}

class UsageRead<T> {
  T? snapshot;
  DateTime? fetchedAt;
  bool loading = false, failed = false;
  Future<void>? request;
}

/// One instance per mounted page/transport. Every cache entry is keyed by the
/// selected source, range and IANA time zone; reconnect invalidates all entries.
class UsageStatistics extends ChangeNotifier {
  UsageStatistics(this.transport,
      {Future<String> Function()? timeZone, DateTime Function()? now})
      : _timeZone = timeZone ?? usageTimeZone,
        _now = now ?? DateTime.now {
    transport.session.recovered.addListener(_recovered);
  }
  final ConversationTransport transport;
  final Future<String> Function() _timeZone;
  final DateTime Function() _now;
  final _app = <String, UsageRead<AppUsageSnapshot>>{};
  final _coding = <String, UsageRead<CodingUsageSnapshot>>{};
  String? _zone;
  Future<String>? _zoneRead;
  bool _disposed = false;
  int _generation = 0;
  UsageRange _appRange = UsageRange.week, _codingRange = UsageRange.week;
  UsageRange get range => application ? _appRange : _codingRange;
  EntitlementSource? source;
  bool application = false;
  final _emptyApp = UsageRead<AppUsageSnapshot>();
  final _emptyCoding = UsageRead<CodingUsageSnapshot>();
  bool initializing = false, timeZoneFailed = false;

  String _appKey(UsageRange value) => '${value.wire}:$_zone';
  String _codingKey() => jsonEncode([
        source == null ? null : PlanResets.arguments(source!),
        _codingRange.wire,
        _zone
      ]);
  UsageRead<AppUsageSnapshot> get app => _app[_appKey(_appRange)] ?? _emptyApp;
  UsageRead<AppUsageSnapshot> get lifetime =>
      _app[_appKey(UsageRange.all)] ?? _emptyApp;
  UsageRead<CodingUsageSnapshot> get coding =>
      _coding[_codingKey()] ?? _emptyCoding;
  void select({required bool application, required EntitlementSource? source}) {
    this.application = application;
    this.source = source;
    _notify();
    unawaited(refresh());
  }

  void selectRange(UsageRange next) {
    if (range == next || next == UsageRange.all) return;
    if (application) {
      _appRange = next;
    } else {
      _codingRange = next;
    }
    _notify();
    unawaited(refresh());
  }

  void invalidate() {
    _generation++;
    _app.clear();
    _coding.clear();
    _zone = null;
    _zoneRead = null;
    initializing = false;
    timeZoneFailed = false;
    _notify();
  }

  void _recovered() {
    invalidate();
    unawaited(refresh());
  }

  Future<void> refresh({bool force = false}) async {
    if (_disposed) return;
    final generation = _generation;
    final chosenApplication = application,
        chosenRange = range,
        chosenSource = source;
    if (_zone == null) {
      initializing = true;
      timeZoneFailed = false;
      _notify();
      try {
        final pending = _zoneRead ??= _timeZone();
        final zone = await pending;
        if (_disposed || generation != _generation) return;
        _zone = zone;
      } catch (_) {
        if (!_disposed && generation == _generation) {
          _zoneRead = null;
          timeZoneFailed = true;
        }
        return;
      } finally {
        if (!_disposed && generation == _generation) {
          initializing = false;
          _notify();
        }
      }
    }
    if (chosenApplication != application ||
        chosenRange != range ||
        chosenSource?.key != source?.key) {
      return;
    }
    if (application) {
      await Future.wait(
          [_readApp(UsageRange.all, force), _readApp(range, force)]);
    } else if (source != null && !source!.isStartPlan) {
      final target = source!, key = _codingKey(), zone = _zone!;
      final entry =
          _coding.putIfAbsent(key, UsageRead<CodingUsageSnapshot>.new);
      await _read(entry, force, () async {
        final raw = await transport.codingUsageSnapshot(
            PlanResets.arguments(target), chosenRange.wire, zone);
        final parsed = CodingUsageSnapshot.parse(raw,
            range: chosenRange, providerId: target.providerId);
        if (parsed == null) throw const FormatException('invalid_coding_usage');
        return parsed;
      }, clearOnFailure: true);
    }
  }

  Future<void> _readApp(UsageRange range, bool force) {
    final zone = _zone!;
    final entry =
        _app.putIfAbsent(_appKey(range), UsageRead<AppUsageSnapshot>.new);
    return _read(entry, force, () async {
      final raw = await transport.appUsageSnapshot(range.wire, zone);
      final parsed = AppUsageSnapshot.parse(raw, range: range, timeZone: zone);
      if (parsed == null) throw const FormatException('invalid_app_usage');
      return parsed;
    });
  }

  Future<void> _read<T>(
      UsageRead<T> entry, bool force, Future<T> Function() read,
      {bool clearOnFailure = false}) {
    if (entry.request != null) return entry.request!;
    if (!force &&
        entry.fetchedAt != null &&
        _now().difference(entry.fetchedAt!) < const Duration(seconds: 60)) {
      return Future.value();
    }
    final generation = _generation;
    entry.loading = true;
    entry.failed = false;
    _notify();
    final operation = () async {
      try {
        final value = await read();
        if (_disposed || generation != _generation) return;
        entry.snapshot = value;
        entry.fetchedAt = _now();
      } catch (_) {
        if (_disposed || generation != _generation) return;
        entry.failed = true;
        if (clearOnFailure) {
          entry.snapshot = null;
          entry.fetchedAt = null;
        }
      } finally {
        if (!_disposed && generation == _generation) {
          entry.loading = false;
          _notify();
        }
      }
    }();
    entry.request = operation;
    return operation.whenComplete(() {
      if (identical(entry.request, operation)) entry.request = null;
    });
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    transport.session.recovered.removeListener(_recovered);
    super.dispose();
  }
}
