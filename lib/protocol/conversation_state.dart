import 'observable.dart';

enum HistoryPageResult { applied, stale, noProgress }

/// Conversation snapshot + row state, mirrors the official delta
/// application in the web client.
class ConversationState extends ProtocolNotifier {
  Map<String, dynamic>? snapshot;
  List<Map<String, dynamic>> rows = [];
  int seq = 0;
  String? logEpoch;
  int? firstRowId;
  int totalCount = 0;
  bool ready = false;
  bool historyExhausted = false;

  /// rowId -> index into [rows], rebuilt on every structural change
  /// (snapshot, removal, prepend). Rows without a numeric rowId are not
  /// indexed; lookups for a null rowId keep the legacy linear scan that
  /// matched the first row with a null rowId. Duplicate rowIds resolve to
  /// the first occurrence, matching the previous indexWhere semantics.
  /// [rows] must only be mutated through this class or the index goes stale.
  final Map<int, int> _rowIndexByRowId = <int, int>{};

  void _rebuildRowIndex() {
    _rowIndexByRowId.clear();
    for (var i = 0; i < rows.length; i++) {
      final id = (rows[i]['rowId'] as num?)?.toInt();
      if (id != null && !_rowIndexByRowId.containsKey(id)) {
        _rowIndexByRowId[id] = i;
      }
    }
  }

  int _indexOfRow(int? rowId) {
    if (rowId == null) {
      return rows.indexWhere((r) => (r['rowId'] as num?)?.toInt() == null);
    }
    return _rowIndexByRowId[rowId] ?? -1;
  }

  bool applyFrame(
    Map<String, dynamic> frame, {
    required void Function() onGap,
  }) {
    final payload = frame['payload'];
    if (payload is! Map) return false;
    final toSeq = (frame['toSeq'] as num?)?.toInt() ?? seq;

    if (payload['kind'] == 'snapshot') {
      if (payload['snapshot'] is! Map) return false;
      final snap = (payload['snapshot'] as Map).cast<String, dynamic>();
      _applySnapshot(snap, toSeq);
    } else if (payload['kind'] == 'deltas') {
      final fromSeq = (frame['fromSeq'] as num?)?.toInt() ?? seq;
      if (fromSeq != seq) {
        onGap();
        return false;
      }
      final deltas = payload['deltas'];
      if (deltas is List) {
        for (final d in deltas) {
          if (d is Map) _applyDelta(d.cast<String, dynamic>());
        }
      }
      seq = toSeq;
    } else {
      return false;
    }
    ready = true;
    notifyListeners();
    return true;
  }

  void _applySnapshot(Map<String, dynamic> snap, int toSeq) {
    final sameEpoch = logEpoch == snap['logEpoch'];
    if (!sameEpoch) {
      rows = [];
      historyExhausted = false;
    }
    snapshot = snap;
    if (_pendingPatch != null) {
      snapshot = {...snap, ..._pendingPatch!};
      _pendingPatch = null;
    }
    seq = toSeq;
    logEpoch = snap['logEpoch'] as String?;
    final rowsObj = snap['rows'];
    if (rowsObj is Map) {
      final window = rowsObj['window'];
      if (window is List) {
        final windowRows = window
            .whereType<Map>()
            .map((e) => e.cast<String, dynamic>())
            .toList();
        final head = windowRows.isEmpty
            ? null
            : (windowRows.first['rowId'] as num?)?.toInt();
        final lowerBound = (rowsObj['firstRowId'] as num?)?.toInt();
        final older = head == null
            ? <Map<String, dynamic>>[]
            : rows.where((r) {
                final id = (r['rowId'] as num?)?.toInt();
                return id != null &&
                    id < head &&
                    (lowerBound == null || id >= lowerBound);
              }).toList();
        rows = [...older, ...windowRows];
      } else {
        rows = [];
      }
      totalCount = (rowsObj['totalCount'] as num?)?.toInt() ?? rows.length;
      final nextFirst = (rowsObj['firstRowId'] as num?)?.toInt();
      if (nextFirst != null && firstRowId != null && nextFirst < firstRowId!) {
        historyExhausted = false;
      }
      firstRowId = nextFirst;
      _rebuildRowIndex();
    } else {
      rows = [];
      totalCount = 0;
      firstRowId = null;
      _rebuildRowIndex();
    }
  }

  void _applyDelta(Map<String, dynamic> delta) {
    switch (delta['op']) {
      case 'row.appended':
        final row = (delta['row'] as Map).cast<String, dynamic>();
        rows.add(row);
        final appendedId = (row['rowId'] as num?)?.toInt();
        if (appendedId != null && !_rowIndexByRowId.containsKey(appendedId)) {
          _rowIndexByRowId[appendedId] = rows.length - 1;
        }
        totalCount += 1;
        firstRowId ??= appendedId;
        break;
      case 'row.upserted':
        final row = (delta['row'] as Map).cast<String, dynamic>();
        final id = (row['rowId'] as num?)?.toInt();
        final index = _indexOfRow(id);
        if (index != -1) rows[index] = row;
        break;
      case 'row.removed':
        // Mirrors `fke()` in the web client: KEEP rows with
        // rowId < fromRowId (i.e. remove rows >= fromRowId).
        final fromRowId = (delta['fromRowId'] as num?)?.toInt() ?? 0;
        final kept = rows
            .where((r) => ((r['rowId'] as num?)?.toInt() ?? 0) < fromRowId)
            .toList();
        final removed = rows.length - kept.length;
        rows = kept;
        _rebuildRowIndex();
        if (firstRowId != null && fromRowId <= firstRowId!) {
          totalCount = 0;
          firstRowId = null;
        } else {
          totalCount = (totalCount - removed).clamp(0, 1 << 31);
        }
        break;
      case 'row.delta':
        final rowId = (delta['rowId'] as num?)?.toInt();
        final path = delta['path'] as String?;
        final append = delta['append'] as String? ?? '';
        final index = _indexOfRow(rowId);
        if (index != -1) {
          rows[index] = _appendToRow(rows[index], path, append);
        }
        break;
      case 'state.updated':
        final patch = delta['patch'];
        if (patch is Map) {
          if (snapshot != null) {
            snapshot = {...snapshot!, ...patch.cast<String, dynamic>()};
          } else {
            // Patch arrived before the initial snapshot — buffer and
            // merge when the snapshot lands (otherwise config/queue/
            // control updates are silently lost).
            _pendingPatch = {
              ...?_pendingPatch,
              ...patch.cast<String, dynamic>(),
            };
          }
        }
        break;
    }
  }

  Map<String, dynamic>? _pendingPatch;

  /// Optimistic local update (command already accepted; the confirming
  /// `state.updated` frame may lag). Merges into snapshot immediately.
  void optimisticPatch(Map<String, dynamic> patch) {
    if (snapshot == null) return;
    snapshot = {...snapshot!, ...patch};
    notifyListeners();
  }

  /// Optimistically removes an interaction after its command ack. The next
  /// authoritative snapshot/state patch may still restore or remove entries;
  /// this method never invents a replacement request.
  void removePendingInteraction(String interactionId) {
    snapshot?['pendingInteractions'] = pendingInteractions
        .where((item) => '${item['interactionId'] ?? ''}' != interactionId)
        .toList();
    notifyListeners();
  }

  /// Optimistic row edit (e.g. feedback) — mutates the row in place and
  /// notifies; the server row.upserted will confirm.
  void optimisticRowUpdate(num? rowId, Map<String, dynamic> patch) {
    final index = _indexOfRow(rowId?.toInt());
    if (index == -1) return;
    rows[index] = {...rows[index], ...patch};
    notifyListeners();
  }

  /// Optimistic queue removal (sendQueuedNow / deleteQueueItem accepted).
  void optimisticRemoveQueueItem(String queueItemId) {
    final q = queue;
    if (q == null) return;
    final items = (q['items'] as List?)
        ?.where((i) => i is Map && '${i['queueItemId']}' != queueItemId)
        .toList();
    snapshot = {
      ...snapshot!,
      'queue': {...q, 'items': items ?? []},
    };
    notifyListeners();
  }

  /// Mirrors `dke()`: append streamed text to a row field.
  Map<String, dynamic> _appendToRow(
      Map<String, dynamic> row, String? path, String append) {
    switch (path) {
      case 'text':
        if (row['kind'] == 'assistantText' || row['kind'] == 'reasoning') {
          return {...row, 'text': '${row['text'] ?? ''}$append'};
        }
        return row;
      case 'inputText':
        if (row['kind'] == 'toolCall') {
          return {...row, 'inputText': '${row['inputText'] ?? ''}$append'};
        }
        return row;
      case 'output.text':
        if (row['kind'] == 'toolCall' && row['output'] is Map) {
          final output = (row['output'] as Map).cast<String, dynamic>();
          return {
            ...row,
            'output': {...output, 'text': '${output['text'] ?? ''}$append'},
          };
        }
        return row;
      case 'summaryText':
        if (row['kind'] == 'subagent') {
          return {
            ...row,
            'summaryText': '${row['summaryText'] ?? ''}$append',
          };
        }
        return row;
      default:
        return row;
    }
  }

  Map<String, dynamic>? get control =>
      (snapshot?['control'] as Map?)?.cast<String, dynamic>();

  /// Current conversation revision (CAS commands base this on).
  int get revision => (snapshot?['revision'] as num?)?.toInt() ?? 0;

  String get phase => control?['phase'] as String? ?? '';

  bool get canStop => control?['canStop'] == true;

  bool get isRunning => phase == 'running' || phase == 'prewarming';

  /// Session config: {provider, model, thought, thoughtLevels, followupMode,
  /// mode}.
  Map<String, dynamic>? get config =>
      (snapshot?['config'] as Map?)?.cast<String, dynamic>();

  String get currentModel => config?['model'] as String? ?? '';
  String get currentThought => config?['thought'] as String? ?? '';
  String get currentMode => config?['mode'] as String? ?? 'build';
  List<String> get thoughtLevels => config?['thoughtLevels'] is List
      ? (config!['thoughtLevels'] as List).map((e) => '$e').toList()
      : const [];

  /// Held queue: {items: [...], autoDrain}.
  Map<String, dynamic>? get queue =>
      (snapshot?['queue'] as Map?)?.cast<String, dynamic>();

  List<Map<String, dynamic>> get queueItems {
    final items = queue?['items'];
    if (items is! List) return const [];
    return items
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
  }

  bool get autoDrain => queue?['autoDrain'] != false;

  /// Token usage: {contextWindow: {usedTokens, maxTokens, ...}?, cumulative}.
  Map<String, dynamic>? get usage =>
      (snapshot?['usage'] as Map?)?.cast<String, dynamic>();

  /// Older history exists beyond the current window.
  bool get canLoadOlder =>
      !historyExhausted &&
      firstRowId != null &&
      oldestRowId != null &&
      oldestRowId! > firstRowId!;

  /// The cursor for `rowsRange` is the oldest row currently held, not the
  /// snapshot projection head (`firstRowId`).
  int? get oldestRowId =>
      rows.isEmpty ? firstRowId : (rows.first['rowId'] as num?)?.toInt();

  /// Official LTe.loadOlder guards both the log epoch and the held cursor.
  /// atSeq does not replace the live subscription's sequence.
  HistoryPageResult applyHistoryPage(dynamic result,
      {required int beforeRowId, required String? expectedLogEpoch}) {
    if (logEpoch != expectedLogEpoch || oldestRowId != beforeRowId) {
      return HistoryPageResult.stale;
    }
    if (result is! Map ||
        result['rows'] is! List ||
        result['hasMore'] is! bool) {
      throw const FormatException('invalid history page');
    }
    if (result['atLogEpoch'] != logEpoch) return HistoryPageResult.stale;
    final older = <int, Map<String, dynamic>>{};
    for (final raw in result['rows'] as List) {
      if (raw is! Map || raw['rowId'] is! num) {
        throw const FormatException('invalid history row');
      }
      final id = (raw['rowId'] as num).toInt();
      if (id < beforeRowId) older[id] = Map<String, dynamic>.from(raw);
    }
    if (older.isEmpty) return HistoryPageResult.noProgress;
    final sorted = older.keys.toList()..sort();
    historyExhausted = result['hasMore'] == false;
    prependOlderRows([for (final id in sorted) older[id]!], null);
    return HistoryPageResult.applied;
  }

  /// Prepends older rows loaded via rowsRange (deduped by rowId).
  void prependOlderRows(List<Map<String, dynamic>> older, int? newFirstRowId) {
    final existing = rows.map((r) => (r['rowId'] as num?)?.toInt()).toSet();
    final fresh = older
        .where((r) => !existing.contains((r['rowId'] as num?)?.toInt()))
        .toList();
    if (fresh.isNotEmpty) {
      rows = [...fresh, ...rows];
      _rebuildRowIndex();
      firstRowId = newFirstRowId ?? firstRowId;
      notifyListeners();
    } else if (newFirstRowId != null && newFirstRowId != firstRowId) {
      firstRowId = newFirstRowId;
      notifyListeners();
    }
  }

  List<Map<String, dynamic>> get backgroundWorks {
    final list = snapshot?['backgroundWorks'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }

  Map<String, dynamic>? get goal =>
      (snapshot?['goal'] as Map?)?.cast<String, dynamic>();

  Map<String, dynamic>? get plan =>
      (snapshot?['plan'] as Map?)?.cast<String, dynamic>();

  /// Official snapshot schema `zl`: {pendingCount, bundleDigest,
  /// workspaceIdentity?}. This is the admission banner's independent source;
  /// it is not the full `pendingInteractions` review payload.
  Map<String, dynamic>? get workspaceHookAdmission {
    final raw = snapshot?['workspaceHookAdmission'];
    return raw is Map ? raw.cast<String, dynamic>() : null;
  }

  /// inputRouting: {mode: startNow|enqueue|guide|reject|choice, reasonCode?}
  String get inputRoutingMode =>
      (snapshot?['inputRouting'] as Map?)?['mode'] as String? ?? 'startNow';

  List<Map<String, dynamic>> get pendingInteractions {
    final list = snapshot?['pendingInteractions'];
    if (list is! List) return const [];
    return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
  }
}
