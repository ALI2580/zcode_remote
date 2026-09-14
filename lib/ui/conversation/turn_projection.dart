// Turn projection for the conversation timeline (S2 extraction from
// `chat_page.dart`): pure functions over the V4 row maps — grouping,
// turn-header stats, work-status labels and the collapse rule. No Flutter
// dependency; widget layers consume these to render the grouped timeline.

/// Official turnHeader duration (bundle BX): activeMs first, then
/// endedAt-startedAt, running uses now-startedAt.
int? turnDurationMs(Map<String, dynamic> row, {required bool running}) {
  final active = (row['activeMs'] as num?)?.toInt();
  if (active != null) return active;
  final startedAt = (row['startedAt'] as num?)?.toInt();
  final endedAt = (row['endedAt'] as num?)?.toInt();
  if (startedAt != null && endedAt != null) {
    return (endedAt - startedAt).clamp(0, 1 << 40);
  }
  if (running && startedAt != null) {
    return (DateTime.now().millisecondsSinceEpoch - startedAt)
        .clamp(0, 1 << 40);
  }
  return null;
}

/// Official turn work-status label (chat.history.*): running = 工作中
/// {duration}, interrupted/failed = 已停止, completed = 已工作 {duration}
/// (or 已处理 when no duration was reported).
String turnWorkLabel({required String state, int? durationMs}) {
  switch (state) {
    case 'running':
    case 'inputStreaming':
      return durationMs == null || durationMs <= 0
          ? '工作中'
          : '工作中 ${formatTurnDuration(durationMs)}';
    case 'completedInterrupted':
    case 'cancelled':
    case 'interrupted':
    case 'failed':
    case 'error':
      return '已停止';
    default:
      return durationMs == null || durationMs <= 0
          ? '已处理'
          : '已工作 ${formatTurnDuration(durationMs)}';
  }
}

/// zh compact duration (chat.history.duration.*): 秒/分/时/天, zero-value
/// trailing units dropped, everything-zero collapses to 0秒.
String formatTurnDuration(int ms) {
  if (ms < 0) ms = 0;
  final duration = Duration(milliseconds: ms);
  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  final parts = <String>[
    if (days > 0) '$days天',
    if (hours > 0) '$hours时',
    if (minutes > 0) '$minutes分',
    if (seconds > 0) '$seconds秒',
  ];
  return parts.isEmpty ? '0秒' : parts.join();
}

String turnWorkLabelEnglish({required String state, int? durationMs}) {
  String duration() {
    if (durationMs == null || durationMs <= 0) return '';
    final seconds = durationMs ~/ 1000;
    if (seconds < 60) return '${seconds}s';
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return remainder == 0 ? '${minutes}m' : '${minutes}m ${remainder}s';
  }

  final value = duration();
  switch (state) {
    case 'running':
    case 'inputStreaming':
      return value.isEmpty ? 'Working' : 'Working $value';
    case 'completedInterrupted':
    case 'cancelled':
    case 'interrupted':
    case 'failed':
    case 'error':
      return 'Stopped';
    default:
      return value.isEmpty ? 'Worked' : 'Worked $value';
  }
}

/// Official default-open rule for a turn's collapsible history: the latest
/// turn stays open while running; a lone turn with no assistant text yet
/// stays open; everything else defaults to collapsed (conversation-page-spec
/// §1). Collapsing keeps only the final assistant summary text.
bool turnDefaultOpen({
  required bool isLastTurn,
  required bool running,
  required bool singleTurn,
  required bool hasAssistantText,
  required bool hasWorkRows,
}) {
  if (isLastTurn && running) return true;
  if (singleTurn && !hasAssistantText && hasWorkRows) return true;
  return false;
}

/// A row whose activity keeps its turn in the "running" state.
bool rowIsActive(Map<String, dynamic> row) {
  if (row['state'] == 'streaming' || row['state'] == 'running') return true;
  if (row['kind'] == 'toolCall') {
    final status = row['status'];
    if (const ['running', 'waiting', 'inputStreaming', 'pendingApproval']
        .contains(status)) {
      return true;
    }
    if (row['requiresInteraction'] == true) return true;
  }
  return false;
}

/// P2-conv deterministic counters: every [conversationTurnGroups] call is
/// one full O(rows) grouping pass. A streaming frame must not recompute
/// groups per notification without need; the counters make that observable
/// in tests and CI.
int chatTurnGroupComputations = 0;
int chatTurnGroupComputeMicros = 0;
bool chatTurnGroupProfiling = false;

/// Groups rows into turns (mirrors the web timeline): a user message starts
/// a new group; assistant text/reasoning/tool rows that follow belong to
/// the same turn and render as ONE message. Consecutive assistant rows merge
/// even if the server bumps `turnId` mid-response (lesson #6).
List<List<Map<String, dynamic>>> conversationTurnGroups(
    List<Map<String, dynamic>> rows) {
  chatTurnGroupComputations++;
  final sw = chatTurnGroupProfiling ? (Stopwatch()..start()) : null;
  final groups = _computeTurnGroups(rows);
  if (sw != null) {
    chatTurnGroupComputeMicros += sw.elapsedMicroseconds;
  }
  return groups;
}

List<List<Map<String, dynamic>>> _computeTurnGroups(
    List<Map<String, dynamic>> rows) {
  final groups = <List<Map<String, dynamic>>>[];
  List<Map<String, dynamic>>? current;
  for (final row in rows) {
    final kind = row['kind'];
    if (kind == 'timelineMarker') {
      current = null;
      groups.add([row]);
      continue;
    }
    final isUser = kind == 'userInput';
    final startsGroup =
        isUser || current == null || current.first['kind'] == 'userInput';
    if (startsGroup) {
      current = [row];
      groups.add(current);
    } else {
      current.add(row);
    }
  }
  return groups;
}

/// Selects one authoritative file-change summary per rendered turn. A
/// `turnHeader.fileChanges` map suppresses legacy `changeSummary` rows even
/// when the reported file count is zero or the wire rows omit `turnId`; only
/// a valid positive file count is returned for display.
List<Map<String, dynamic>> conversationFileChangeSummaryRows(
    List<Map<String, dynamic>> rows) {
  final summaries = <Map<String, dynamic>>[];
  for (final group in conversationTurnGroups(rows)) {
    Map<String, dynamic>? header;
    for (final row in group) {
      if (row['kind'] == 'turnHeader' && row['fileChanges'] is Map) {
        header = row;
      }
    }
    final stats = header == null ? null : turnFileChangeStats(header);
    if (stats != null && stats.files > 0 && header != null) {
      summaries.add(header);
    } else if (header == null) {
      summaries.addAll(group.where((row) => row['kind'] == 'changeSummary'));
    }
  }
  return summaries;
}

class TurnFileChangeStats {
  final int files;
  final int additions;
  final int deletions;
  final String? state;

  const TurnFileChangeStats({
    required this.files,
    required this.additions,
    required this.deletions,
    required this.state,
  });
}

TurnFileChangeStats? turnFileChangeStats(Map<String, dynamic> row) {
  final raw = row['fileChanges'];
  if (raw is! Map) return null;
  final map = raw.cast<String, dynamic>();
  int? nonNegative(Object? value) {
    if (value is! num || !value.isFinite || value < 0) return null;
    final result = value.toInt();
    return result == value ? result : null;
  }

  final files = nonNegative(map['files']);
  final additions = nonNegative(map['additions']);
  final deletions = nonNegative(map['deletions']);
  if (files == null || additions == null || deletions == null || files < 0) {
    return null;
  }
  return TurnFileChangeStats(
    files: files,
    additions: additions,
    deletions: deletions,
    state: map['state'] as String?,
  );
}
