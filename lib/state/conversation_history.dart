import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/conversation.dart';
import 'conversation_view_state.dart';

enum ReadingNotice { historyChanged, anchorMissing }

/// Owns read-only pagination and cold-start reading recovery for one session.
class ConversationHistory extends ChangeNotifier {
  ConversationHistory(
      {required this.transport,
      required this.sessionId,
      required this.state,
      required this.view}) {
    state.addListener(_onState);
  }
  final ConversationTransport transport;
  final String sessionId;
  final ConversationState state;
  final ConversationViewState view;
  Future<HistoryPageResult>? _pending;
  bool _disposed = false, _readingDone = false;
  int _generation = 0;
  bool restoring = false, restoreFailed = false;
  ReadingNotice? notice;
  bool get loading => _pending != null;
  bool get blocksViewport => restoring || restoreFailed;

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void _onState() {
    if (_disposed || !state.ready) return;
    if (view.logEpoch != null && view.logEpoch != state.logEpoch) {
      _returnToLatest(ReadingNotice.historyChanged);
      view.expandedTurns.clear();
    } else if (!_readingDone && !restoring && !restoreFailed) {
      unawaited(restoreReading());
    }
  }

  Future<HistoryPageResult> loadOlder({int limit = 60}) {
    if (_disposed) return Future.value(HistoryPageResult.stale);
    final pending = _pending;
    if (pending != null) return pending;
    if (!state.canLoadOlder) return Future.value(HistoryPageResult.noProgress);
    final cursor = state.oldestRowId!, epoch = state.logEpoch;
    late final Future<HistoryPageResult> request;
    request = _readPage(cursor, epoch, limit).whenComplete(() {
      if (identical(_pending, request)) {
        _pending = null;
        _changed();
      }
    });
    _pending = request;
    _changed();
    return request;
  }

  Future<HistoryPageResult> _readPage(
      int cursor, String? epoch, int limit) async {
    final result = await transport.rowsRange(sessionId,
        beforeRowId: cursor, limit: limit.clamp(1, 200));
    if (_disposed) return HistoryPageResult.stale;
    return state.applyHistoryPage(result,
        beforeRowId: cursor, expectedLogEpoch: epoch);
  }

  Future<void> restoreReading() async {
    if (_disposed || _readingDone || restoring || !state.ready) return;
    if (view.logEpoch != null && view.logEpoch != state.logEpoch) {
      _returnToLatest(ReadingNotice.historyChanged);
      view.expandedTurns.clear();
      return;
    }
    view.logEpoch = state.logEpoch;
    if (view.following || view.anchor == null) {
      _readingDone = true;
      return;
    }
    final target = int.tryParse(view.anchor!);
    if (target == null) {
      _returnToLatest(ReadingNotice.anchorMissing);
      return;
    }
    final generation = ++_generation;
    restoring = true;
    restoreFailed = false;
    _changed();
    try {
      while (!_disposed && generation == _generation && !view.following) {
        if (state.rows.any((row) => row['rowId'] == target)) {
          _readingDone = true;
          return;
        }
        if (!state.canLoadOlder || (state.oldestRowId ?? target) <= target) {
          _returnToLatest(ReadingNotice.anchorMissing);
          return;
        }
        final result = await loadOlder(limit: 200);
        if (_disposed || generation != _generation) return;
        if (result != HistoryPageResult.applied) {
          restoreFailed = true;
          return;
        }
      }
    } catch (_) {
      if (!_disposed && generation == _generation) restoreFailed = true;
    } finally {
      if (!_disposed && generation == _generation) {
        restoring = false;
        _changed();
      }
    }
  }

  void showLatest() => _returnToLatest(null);

  void _returnToLatest(ReadingNotice? reason) {
    _generation++;
    _readingDone = true;
    restoring = false;
    restoreFailed = false;
    notice = reason;
    view
      ..following = true
      ..anchor = null
      ..pixels = 0
      ..anchorOffset = 0
      ..logEpoch = state.logEpoch;
    _changed();
  }

  void dismissNotice() {
    notice = null;
    _changed();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    state.removeListener(_onState);
    super.dispose();
  }
}
