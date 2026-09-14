/// Official `conversationFileChangesV4` payload.
///
/// The preferred response is the documented review payload:
/// `{files, additions, deletions, state, items}`. Synthetic and older
/// transports may expose `{fileChanges: [...]}`, where each turn contains
/// `{turnIndex, snapshots, fileState}`; snapshots can still be aggregated for
/// a review list, but hunks remain unavailable unless explicitly supplied.
library;

import 'dart:convert';

class FileChangesHunk {
  final int oldStart;
  final int oldLines;
  final int newStart;
  final int newLines;
  final List<String> lines;

  /// True when this hunk was computed from a text range rather than a
  /// confirmed file patch.  Text-range hunks must not imply absolute file
  /// positions in the UI.
  final bool isTextRange;

  /// True when the bounded diff could not retain every changed line.
  final bool truncated;

  /// True when supplied patch structure and visible lines disagree.
  final bool partial;
  final bool oldHasTrailingNewline;
  final bool newHasTrailingNewline;
  final String? rangeLabel;

  const FileChangesHunk({
    required this.oldStart,
    required this.oldLines,
    required this.newStart,
    required this.newLines,
    required this.lines,
    this.isTextRange = false,
    this.truncated = false,
    this.partial = false,
    this.oldHasTrailingNewline = false,
    this.newHasTrailingNewline = false,
    this.rangeLabel,
  });
}

/// A tool edit rendered from an explicitly supplied patch or from the exact
/// old/new text range carried by the tool call.
///
/// The latter is deliberately a range view: it is not a projection of the
/// whole file and therefore has no absolute file line numbers.
class ToolInlineDiff {
  final String path;
  final List<FileChangesHunk> hunks;
  final bool fromPatch;
  final bool truncated;
  final bool partial;

  const ToolInlineDiff({
    required this.path,
    required this.hunks,
    required this.fromPatch,
    required this.truncated,
    this.partial = false,
  });
}

class FileContentRef {
  final String field;
  final String refId;
  final String hash;
  final int fullBytes;
  final int previewBytes;

  const FileContentRef({
    required this.field,
    required this.refId,
    required this.hash,
    required this.fullBytes,
    required this.previewBytes,
  });
}

class FileChangeItem {
  final String path;
  final int additions;
  final int deletions;
  final int writeCount;
  final List<String> toolNames;
  final List<FileChangesHunk> patches;
  final List<FileContentRef> contentRefs;
  final bool hasContent;
  final bool looksBinary;
  final bool statsComplete;
  final List<String> problems;

  const FileChangeItem({
    required this.path,
    required this.additions,
    required this.deletions,
    required this.writeCount,
    required this.toolNames,
    required this.patches,
    required this.contentRefs,
    required this.hasContent,
    required this.looksBinary,
    this.statsComplete = true,
    required this.problems,
  });
}

class FileChangesResult {
  final int files;
  final int additions;
  final int deletions;
  final String? state;
  final String? fileState;
  final List<FileChangeItem> items;
  final bool statsComplete;
  final List<String> problems;

  const FileChangesResult({
    required this.files,
    required this.additions,
    required this.deletions,
    required this.state,
    required this.fileState,
    required this.items,
    this.statsComplete = true,
    required this.problems,
  });
}

class FileChangesFormatException implements Exception {
  final String message;

  const FileChangesFormatException(this.message);

  @override
  String toString() => 'FileChangesFormatException: $message';
}

class FileRewindPreviewFile {
  final String path;
  final String? action;
  final int operationCount;
  final List<String> toolNames;
  final String? reason;
  final String? message;
  final String? currentHash;
  final String? expectedHash;

  const FileRewindPreviewFile({
    required this.path,
    required this.operationCount,
    required this.toolNames,
    this.action,
    this.reason,
    this.message,
    this.currentHash,
    this.expectedHash,
  });
}

class FileRewindPreview {
  final bool canApply;
  final List<FileRewindPreviewFile> safeFiles;
  final List<FileRewindPreviewFile> unsafeFiles;
  final List<FileRewindPreviewFile> ignoredFiles;
  final List<String> problems;

  const FileRewindPreview({
    required this.canApply,
    required this.safeFiles,
    required this.unsafeFiles,
    required this.ignoredFiles,
    required this.problems,
  });
}

class FileRewindApplyResult {
  final String status;
  final String? reasonCode;
  final String? message;
  final bool? applied;
  final String? response;
  final FileRewindPreview? preview;
  final List<String> problems;

  const FileRewindApplyResult({
    required this.status,
    required this.reasonCode,
    required this.message,
    required this.applied,
    required this.response,
    required this.preview,
    required this.problems,
  });
}

const _allowedStates = {'active', 'reverted'};
const _applyStatuses = {
  'accepted',
  'rejected',
  'stale',
  'duplicate',
  'noop',
  'failed'
};
const _rewindReasons = {
  'bash_ignored',
  'checkpoint_missing',
  'checkpoint_unreadable',
  'external_modified',
  'file_read_failed',
  'unsupported_checkpoint'
};
const _rewindActions = {'restore', 'delete'};

FileRewindPreview parseFileRewindPreview(Object? raw) {
  final root = _unwrap(raw);
  if (root == null) {
    throw const FileChangesFormatException('rewind preview is not an object');
  }
  final canApply = root['canApply'];
  if (canApply is! bool) {
    throw const FileChangesFormatException('canApply missing or invalid');
  }
  final safeFiles =
      _parseRewindFiles(root['safeFiles'], 'safeFiles', _rewindActions);
  final unsafeFiles =
      _parseRewindFiles(root['unsafeFiles'], 'unsafeFiles', _rewindReasons);
  final ignoredFiles =
      _parseRewindFiles(root['ignoredFiles'], 'ignoredFiles', {'bash_ignored'});
  final problems = <String>[
    if (safeFiles == null) 'safeFiles missing or invalid',
    if (unsafeFiles == null) 'unsafeFiles missing or invalid',
    if (ignoredFiles == null) 'ignoredFiles missing or invalid',
  ];
  return FileRewindPreview(
    canApply: canApply,
    safeFiles: safeFiles ?? const [],
    unsafeFiles: unsafeFiles ?? const [],
    ignoredFiles: ignoredFiles ?? const [],
    problems: problems,
  );
}

FileRewindApplyResult parseFileRewindApply(Object? raw) {
  final root = _unwrap(raw);
  if (root == null) {
    throw const FileChangesFormatException('rewind result is not an object');
  }
  final status = root['status'];
  if (status is! String || !_applyStatuses.contains(status)) {
    throw const FileChangesFormatException('status missing or invalid');
  }
  final result = root['result'];
  final resultMap = result is Map ? result.cast<String, dynamic>() : null;
  if (resultMap == null || resultMap['type'] != 'applyFileRewind') {
    throw const FileChangesFormatException('unsupported rewind result');
  }
  final previewRaw = resultMap['preview'];
  final applied = resultMap['applied'];
  final response = resultMap['response'];
  FileRewindPreview? preview;
  if (previewRaw != null) preview = parseFileRewindPreview(previewRaw);
  return FileRewindApplyResult(
    status: status,
    reasonCode:
        root['reasonCode'] is String ? root['reasonCode'] as String : null,
    message: root['message'] is String ? root['message'] as String : null,
    applied: applied is bool ? applied : null,
    response: response is String ? response : null,
    preview: preview,
    problems: [
      if (applied != null && applied is! bool) 'applied invalid',
      if (response != null && response is! String) 'response invalid',
    ],
  );
}

List<FileRewindPreviewFile>? _parseRewindFiles(
    Object? raw, String field, Set<String> allowedReasons) {
  if (raw == null) return null;
  if (raw is! List) return null;
  final files = <FileRewindPreviewFile>[];
  var allValid = true;
  for (final item in raw) {
    if (item is! Map) continue;
    final map = item.cast<String, dynamic>();
    final path = map['path'] as String?;
    final operationCount = _readNonNegativeInt(map['operationCount']);
    final reason = map['reason'] as String?;
    if (path == null ||
        path.isEmpty ||
        operationCount == null ||
        (reason != null && !allowedReasons.contains(reason))) {
      allValid = false;
      continue;
    }
    final action = map['action'] as String?;
    if (action != null && !_rewindActions.contains(action)) {
      allValid = false;
      continue;
    }
    files.add(FileRewindPreviewFile(
      path: path,
      action: action,
      operationCount: operationCount,
      toolNames: _readStringList(map['toolNames']),
      reason: reason,
      message: map['message'] is String ? map['message'] as String : null,
      currentHash:
          map['currentHash'] is String ? map['currentHash'] as String : null,
      expectedHash:
          map['expectedHash'] is String ? map['expectedHash'] as String : null,
    ));
  }
  return allValid ? files : null;
}

/// Parses a file-changes RPC result without inventing missing fields.
FileChangesResult parseFileChanges(Object? raw) {
  final root = _unwrap(raw);
  if (root == null) {
    throw const FileChangesFormatException('result is not an object');
  }

  final items = root['items'] is List
      ? _parseReviewItems(root['items'] as List)
      : _parseSnapshotTurns(root['fileChanges']);
  final problemCount = items.fold<int>(0, (n, e) => n + e.problems.length);
  final additions = _readNonNegativeInt(root['additions']) ??
      items.fold<int>(0, (n, e) => n + e.additions);
  final deletions = _readNonNegativeInt(root['deletions']) ??
      items.fold<int>(0, (n, e) => n + e.deletions);
  final declaredStats = _readNonNegativeInt(root['additions']) != null &&
      _readNonNegativeInt(root['deletions']) != null;
  final files = _readNonNegativeInt(root['files']) ?? items.length;
  final state = root['state'] as String?;
  final snapshotFileState = _snapshotFileState(root['fileChanges']);
  final problems = <String>[
    if (_readNonNegativeInt(root['files']) == null) 'files missing or invalid',
    if (_readNonNegativeInt(root['additions']) == null)
      'additions missing or invalid',
    if (_readNonNegativeInt(root['deletions']) == null)
      'deletions missing or invalid',
    if (state != null && !_allowedStates.contains(state))
      'unsupported file state: $state',
  ];

  return FileChangesResult(
    files: files,
    additions: additions,
    deletions: deletions,
    state: _allowedStates.contains(state) ? state : null,
    fileState: const {'applied', 'reverted'}.contains(snapshotFileState)
        ? snapshotFileState
        : null,
    items: items,
    problems: [
      ...problems,
      if (problemCount > 0) '$problemCount invalid item field(s)',
      if (!declaredStats && items.any((item) => !item.statsComplete))
        'additions/deletions are partial because a displayed diff was bounded',
    ],
    statsComplete: declaredStats || items.every((item) => item.statsComplete),
  );
}

Map<String, dynamic>? _unwrap(Object? raw) {
  if (raw is! Map) return null;
  final direct = raw.cast<String, dynamic>();
  if (direct['items'] is List ||
      direct['fileChanges'] != null ||
      direct['canApply'] is bool ||
      direct['status'] is String) {
    return direct;
  }
  final result = raw['result'];
  if (result is Map) return result.cast<String, dynamic>();
  final payload = raw['payload'];
  if (payload is Map) return payload.cast<String, dynamic>();
  return null;
}

int? _readNonNegativeInt(Object? value) {
  if (value is! num || (value is double && !value.isFinite)) return null;
  final parsed = value.toInt();
  if (parsed < 0 || parsed != value) return null;
  return parsed;
}

List<String> _readStringList(Object? value) {
  if (value is! List) return const [];
  return value.whereType<String>().toList(growable: false);
}

List<FileChangeItem> _parseReviewItems(List rawItems) {
  final items = <FileChangeItem>[];
  for (final raw in rawItems) {
    if (raw is! Map) continue;
    final map = raw.cast<String, dynamic>();
    final path = map['path'] as String?;
    final additions = _readNonNegativeInt(map['additions']);
    final deletions = _readNonNegativeInt(map['deletions']);
    final writeCount = _readNonNegativeInt(map['writeCount']);
    final patches = _parsePatches(map['patches']);
    final contentRefs = _parseContentRefs(map['contentRefs']);
    final validCounters =
        additions != null && deletions != null && writeCount != null;
    final problems = <String>[
      if (path == null || path.isEmpty) 'path missing or invalid',
      if (additions == null) 'additions missing or invalid',
      if (deletions == null) 'deletions missing or invalid',
      if (writeCount == null) 'writeCount missing or invalid',
      if (map['patches'] != null && patches == null) 'invalid patches',
      if (map['contentRefs'] != null && contentRefs == null)
        'invalid contentRefs',
      if (patches != null &&
          patches.any((hunk) => hunk.partial || hunk.truncated))
        'patch display is partial',
    ];
    final hasContent = patches != null && patches.isNotEmpty ||
        (map['beforeContent'] is String? && map['afterContent'] is String);
    items.add(FileChangeItem(
      path: path ?? '',
      additions: additions ?? 0,
      deletions: deletions ?? 0,
      writeCount: writeCount ?? 0,
      toolNames: _readStringList(map['toolNames']),
      patches: patches ?? const [],
      contentRefs: contentRefs ?? const [],
      hasContent: hasContent,
      looksBinary: _looksBinary(map),
      statsComplete: validCounters &&
          (map['patches'] == null ||
              (patches != null &&
                  patches.every((hunk) => !hunk.partial && !hunk.truncated))),
      problems: problems,
    ));
  }
  items.sort((a, b) => a.path.compareTo(b.path));
  return items;
}

List<FileChangesHunk>? _parsePatches(Object? raw) {
  if (raw == null) return null;
  if (raw is! List) return null;
  final hunks = <FileChangesHunk>[];
  var malformed = false;
  for (final rawHunk in raw) {
    if (rawHunk is! Map) {
      malformed = true;
      continue;
    }
    final hunk = rawHunk.cast<String, dynamic>();
    final oldStart = _readNonNegativeInt(hunk['oldStart']);
    final oldLines = _readNonNegativeInt(hunk['oldLines']);
    final newStart = _readNonNegativeInt(hunk['newStart']);
    final newLines = _readNonNegativeInt(hunk['newLines']);
    final lines = hunk['lines'];
    if (oldStart == null ||
        oldLines == null ||
        newStart == null ||
        newLines == null ||
        lines is! List) {
      malformed = true;
      continue;
    }
    if (lines.any((line) =>
        line is! String ||
        line.isEmpty ||
        !const ['+', '-', ' ', '\\'].contains(line[0]))) {
      malformed = true;
      continue;
    }
    hunks.add(_makePatchHunk(
      oldStart: oldStart,
      oldLines: oldLines,
      newStart: newStart,
      newLines: newLines,
      lines: lines.whereType<String>().toList(growable: false),
    ));
  }
  return malformed
      ? null
      : _boundHunksByBudget(
          hunks,
          maxOutputLines: 400,
          maxOutputChars: 100000,
        );
}

List<FileContentRef>? _parseContentRefs(Object? raw) {
  if (raw == null) return null;
  if (raw is! List) return null;
  final refs = <FileContentRef>[];
  for (final rawRef in raw) {
    if (rawRef is! Map) continue;
    final ref = rawRef.cast<String, dynamic>();
    final field = ref['field'] as String?;
    final refId = ref['refId'] as String?;
    final hash = ref['hash'] as String?;
    final fullBytes = _readNonNegativeInt(ref['fullBytes']);
    final previewBytes = _readNonNegativeInt(ref['previewBytes']);
    if (field == null ||
        refId == null ||
        hash == null ||
        fullBytes == null ||
        previewBytes == null) {
      continue;
    }
    refs.add(FileContentRef(
      field: field,
      refId: refId,
      hash: hash,
      fullBytes: fullBytes,
      previewBytes: previewBytes,
    ));
  }
  return refs;
}

bool _looksBinary(Map<String, dynamic> map) {
  final before = map['beforeContent'];
  final after = map['afterContent'];
  return _hasNul(before) || _hasNul(after);
}

bool _hasNul(Object? value) =>
    value is String && String.fromCharCodes(value.codeUnits).contains('\x00');

String? _snapshotFileState(Object? rawTurns) {
  if (rawTurns is! List) return null;
  String? state;
  for (final rawTurn in rawTurns) {
    if (rawTurn is! Map) continue;
    final value = rawTurn['fileState'];
    if (value is String) state = value;
  }
  return state;
}

List<FileChangeItem> _parseSnapshotTurns(Object? rawTurns) {
  if (rawTurns == null) return const [];
  if (rawTurns is! List) return const [];
  final entries = <String, _SnapshotEntry>{};
  for (final rawTurn in rawTurns) {
    if (rawTurn is! Map) continue;
    final turn = rawTurn.cast<String, dynamic>();
    final snapshots = turn['snapshots'];
    if (snapshots is! List) continue;
    for (final rawSnapshot in snapshots) {
      if (rawSnapshot is! Map) continue;
      final snapshot = rawSnapshot.cast<String, dynamic>();
      final path = snapshot['path'] as String?;
      if (path == null || path.isEmpty) continue;
      final current = entries.putIfAbsent(
        path,
        () => _SnapshotEntry(
          before: snapshot['beforeContent'] as String?,
          after: snapshot['afterContent'] as String?,
        ),
      );
      current.writeCount += _readNonNegativeInt(snapshot['writeCount']) ?? 0;
      current.hasRaw = true;
      final refs = _parseContentRefs(snapshot['contentRefs']);
      if (refs != null) current.contentRefs.addAll(refs);
      final after = snapshot['afterContent'];
      if (after is String) current.after = after;
    }
  }

  final items = <FileChangeItem>[];
  for (final path in entries.keys.toList()..sort()) {
    final entry = entries[path]!;
    final hunk = entry.hasRaw && entry.after != null
        ? buildDiffHunks(before: entry.before ?? '', after: entry.after!)
        : const <FileChangesHunk>[];
    var additions = 0;
    var deletions = 0;
    for (final h in hunk) {
      additions += h.lines.where((l) => l.startsWith('+')).length;
      deletions += h.lines.where((l) => l.startsWith('-')).length;
    }
    final statsComplete = hunk.every((h) => !h.truncated && !h.partial);
    items.add(FileChangeItem(
      path: path,
      additions: additions,
      deletions: deletions,
      writeCount: entry.writeCount,
      toolNames: const [],
      patches: hunk,
      contentRefs: List.unmodifiable(entry.contentRefs),
      hasContent: entry.after != null,
      looksBinary: _hasNul(entry.before) || _hasNul(entry.after),
      statsComplete: statsComplete,
      problems: [
        if (!entry.hasRaw) 'snapshot missing',
        if (entry.after == null) 'afterContent missing or unavailable',
        if (!statsComplete)
          'additions/deletions are partial because the displayed diff was bounded',
      ],
    ));
  }
  return items;
}

class _SnapshotEntry {
  String? before;
  String? after;
  int writeCount = 0;
  bool hasRaw = false;
  final contentRefs = <FileContentRef>[];

  _SnapshotEntry({required this.before, required this.after});
}

/// Builds one compatibility hunk from an exact text range or file snapshot.
///
/// Existing callers expect a single hunk. New callers that need separate
/// edits should use [buildDiffHunks], which preserves independent change
/// blocks instead of joining distant replacements.
FileChangesHunk buildDiffHunk({
  required String before,
  required String after,
  int context = 3,
  bool isTextRange = false,
  int maxDiffCells = 20000,
  int maxOutputLines = 400,
  int maxOutputChars = 100000,
  String? rangeLabel,
}) {
  final hunks = buildDiffHunks(
    before: before,
    after: after,
    context: context,
    isTextRange: isTextRange,
    maxDiffCells: maxDiffCells,
    maxOutputLines: maxOutputLines,
    maxOutputChars: maxOutputChars,
    rangeLabel: rangeLabel,
  );
  return hunks.isEmpty
      ? FileChangesHunk(
          oldStart: _splitLines(before).isEmpty ? 0 : 1,
          oldLines: 0,
          newStart: _splitLines(after).isEmpty ? 0 : 1,
          newLines: 0,
          lines: const [],
          isTextRange: isTextRange,
          rangeLabel: rangeLabel,
        )
      : hunks.first;
}

/// Computes bounded line hunks while retaining actual text-range context.
///
/// A common prefix/suffix is removed before LCS, so large unchanged file
/// content never enters the matrix. If the changed middle exceeds the cell or
/// output budget, the returned hunk explicitly carries [FileChangesHunk.truncated]
/// and only displays real edge lines; truncation metadata is kept separate
/// from the actual edit lines.
List<FileChangesHunk> buildDiffHunks({
  required String before,
  required String after,
  int context = 3,
  bool isTextRange = false,
  int maxDiffCells = 20000,
  int maxOutputLines = 400,
  int maxOutputChars = 100000,
  String? rangeLabel,
}) {
  final oldLines = _splitLines(before);
  final newLines = _splitLines(after);
  final oldTrailing = _hasTrailingNewline(before);
  final newTrailing = _hasTrailingNewline(after);
  final safeContext = context < 0 ? 0 : context;
  final safeCells = maxDiffCells < 1 ? 1 : maxDiffCells;
  final safeOutput = maxOutputLines < 1 ? 1 : maxOutputLines;

  var prefix = 0;
  while (prefix < oldLines.length &&
      prefix < newLines.length &&
      oldLines[prefix] == newLines[prefix]) {
    prefix++;
  }
  var suffix = 0;
  while (suffix < oldLines.length - prefix &&
      suffix < newLines.length - prefix &&
      oldLines[oldLines.length - suffix - 1] ==
          newLines[newLines.length - suffix - 1]) {
    suffix++;
  }

  final middleOld = oldLines.sublist(prefix, oldLines.length - suffix);
  final middleNew = newLines.sublist(prefix, newLines.length - suffix);
  final trailingOnlyChange = middleOld.isEmpty &&
      middleNew.isEmpty &&
      oldTrailing != newTrailing &&
      oldLines.isNotEmpty &&
      newLines.isNotEmpty;
  if (trailingOnlyChange) {
    final lineBudget = maxOutputLines < 1 ? 1 : maxOutputLines;
    final visibleLines = lineBudget == 1
        ? <String>['-${oldLines.last}']
        : <String>['-${oldLines.last}', '+${newLines.last}'];
    return [
      FileChangesHunk(
        oldStart: oldLines.length,
        oldLines: 1,
        newStart: newLines.length,
        newLines: 1,
        lines: visibleLines,
        isTextRange: isTextRange,
        truncated: lineBudget == 1,
        oldHasTrailingNewline: oldTrailing,
        newHasTrailingNewline: newTrailing,
        rangeLabel: rangeLabel,
      )
    ];
  }
  final oldForDiff = trailingOnlyChange ? [oldLines.last] : middleOld;
  final newForDiff = trailingOnlyChange ? [newLines.last] : middleNew;
  final hasTextChange = oldForDiff.isNotEmpty || newForDiff.isNotEmpty;
  if (!hasTextChange && oldTrailing == newTrailing) return const [];

  var prefixContext = prefix == 0 ? 0 : safeContext.clamp(0, prefix).toInt();
  var suffixContext = suffix == 0 ? 0 : safeContext.clamp(0, suffix).toInt();
  final contextBudget = safeOutput > 2 ? safeOutput - 2 : 0;
  if (prefixContext + suffixContext > contextBudget) {
    prefixContext = prefixContext.clamp(0, contextBudget ~/ 2).toInt();
    suffixContext =
        suffixContext.clamp(0, contextBudget - prefixContext).toInt();
  }
  final displayBudget = safeOutput - prefixContext - suffixContext;
  final ops = <_DiffOp>[];
  for (var i = prefix - prefixContext; i < prefix; i++) {
    ops.add(_DiffOp(_DiffOpKind.equal, oldLines[i]));
  }

  var truncated = false;
  if (oldForDiff.length * newForDiff.length > safeCells ||
      oldForDiff.length + newForDiff.length > displayBudget) {
    truncated = true;
    ops.addAll(_boundedReplacementOps(
      oldForDiff,
      newForDiff,
      maxOutputLines: displayBudget,
    ));
  } else {
    ops.addAll(_diffOps(oldForDiff, newForDiff));
  }
  final suffixStart = newLines.length - suffix;
  for (var i = suffixStart;
      i < suffixStart + suffixContext && i < newLines.length;
      i++) {
    if (i >= 0 && i < newLines.length) {
      ops.add(_DiffOp(_DiffOpKind.equal, newLines[i]));
    }
  }

  final changes = [
    for (var i = 0; i < ops.length; i++)
      if (ops[i].kind != _DiffOpKind.equal) i,
  ];
  if (changes.isEmpty) return const [];

  final groups = <List<int>>[];
  var group = <int>[changes.first];
  for (final index in changes.skip(1)) {
    if (index - group.last <= safeContext * 2 + 1) {
      group.add(index);
    } else {
      groups.add(group);
      group = <int>[index];
    }
  }
  groups.add(group);

  final baseOld = prefix - prefixContext + 1;
  final baseNew = prefix - prefixContext + 1;
  final result = <FileChangesHunk>[];
  for (final changeGroup in groups) {
    final start =
        (changeGroup.first - safeContext).clamp(0, ops.length).toInt();
    final end =
        (changeGroup.last + safeContext + 1).clamp(0, ops.length).toInt();
    var oldNumber = baseOld;
    var newNumber = baseNew;
    for (var i = 0; i < start; i++) {
      switch (ops[i].kind) {
        case _DiffOpKind.delete:
          oldNumber++;
        case _DiffOpKind.insert:
          newNumber++;
        case _DiffOpKind.equal:
          oldNumber++;
          newNumber++;
      }
    }
    final oldStart = oldNumber;
    final newStart = newNumber;
    final lines = <String>[];
    for (var i = start; i < end; i++) {
      final op = ops[i];
      switch (op.kind) {
        case _DiffOpKind.delete:
          lines.add('-${op.text}');
        case _DiffOpKind.insert:
          lines.add('+${op.text}');
        case _DiffOpKind.equal:
          lines.add(' ${op.text}');
      }
    }
    result.add(FileChangesHunk(
      oldStart: oldStart,
      oldLines:
          lines.where((l) => l.startsWith('-') || l.startsWith(' ')).length,
      newStart: newStart,
      newLines:
          lines.where((l) => l.startsWith('+') || l.startsWith(' ')).length,
      lines: List.unmodifiable(lines),
      isTextRange: isTextRange,
      truncated: truncated,
      oldHasTrailingNewline: oldTrailing,
      newHasTrailingNewline: newTrailing,
      rangeLabel: rangeLabel,
    ));
  }
  return _boundHunksByBudget(
    result,
    maxOutputLines: safeOutput,
    maxOutputChars: maxOutputChars,
  );
}

List<String> _splitLines(String value) {
  if (value.isEmpty) return const [];
  final normalized = value.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  if (lines.length > 1 && lines.last.isEmpty) lines.removeLast();
  return lines;
}

bool _hasTrailingNewline(String value) =>
    value.endsWith('\n') || value.endsWith('\r');

List<_DiffOp> _boundedReplacementOps(
    List<String> oldLines, List<String> newLines,
    {required int maxOutputLines}) {
  final totalBudget = maxOutputLines.clamp(1, 1 << 30).toInt();
  if (totalBudget == 1) {
    if (oldLines.isNotEmpty) {
      return [_DiffOp(_DiffOpKind.delete, oldLines.first)];
    }
    if (newLines.isNotEmpty) {
      return [_DiffOp(_DiffOpKind.insert, newLines.first)];
    }
    return const [];
  }
  final sharedBudget = totalBudget ~/ 2;
  final ops = <_DiffOp>[];
  void addSide(List<String> lines, _DiffOpKind kind) {
    final budget = oldLines.isEmpty
        ? totalBudget
        : newLines.isEmpty
            ? totalBudget
            : sharedBudget;
    if (lines.length <= budget) {
      ops.addAll(lines.map((line) => _DiffOp(kind, line)));
      return;
    }
    final edge = (budget ~/ 2).clamp(1, budget).toInt();
    ops.addAll(lines.take(edge).map((line) => _DiffOp(kind, line)));
    ops.addAll(
        lines.skip(lines.length - edge).map((line) => _DiffOp(kind, line)));
  }

  addSide(oldLines, _DiffOpKind.delete);
  addSide(newLines, _DiffOpKind.insert);
  return ops;
}

/// Applies a second budget to the rendered hunk payload. Line budgets alone
/// cannot protect the widget tree from one very long changed line or from a
/// patch containing many separate hunks. Every retained character belongs to
/// the original line; omission is represented only by [truncated] metadata.
List<FileChangesHunk> _boundHunksByBudget(
  List<FileChangesHunk> hunks, {
  required int maxOutputLines,
  required int maxOutputChars,
}) {
  final lineBudget = maxOutputLines < 1 ? 1 : maxOutputLines;
  final charBudget = maxOutputChars < 1 ? 1 : maxOutputChars;
  var usedLines = 0;
  var usedChars = 0;
  final bounded = <FileChangesHunk>[];
  for (final hunk in hunks) {
    if (usedLines >= lineBudget || usedChars >= charBudget) break;
    final remainingLines = lineBudget - usedLines;
    final remainingChars = charBudget - usedChars;
    final visible = <String>[];
    var cut = hunk.truncated;
    var visibleChars = 0;
    for (var lineIndex = 0; lineIndex < hunk.lines.length; lineIndex++) {
      final line = hunk.lines[lineIndex];
      if (visible.length >= remainingLines) {
        cut = true;
        break;
      }
      final room = remainingChars - visibleChars;
      if (room <= 0) {
        cut = true;
        break;
      }
      final remainingInputLines = hunk.lines.length - lineIndex;
      final lineRoom = remainingInputLines > 1
          ? (room ~/ remainingInputLines).clamp(1, room).toInt()
          : room;
      if (line.length <= lineRoom) {
        visible.add(line);
        visibleChars += line.length;
      } else {
        visible.add(line.substring(0, lineRoom));
        visibleChars += lineRoom;
        cut = true;
      }
    }
    if (visible.isEmpty) break;
    usedLines += visible.length;
    usedChars += visible.fold<int>(0, (sum, line) => sum + line.length);
    bounded.add(FileChangesHunk(
      oldStart: hunk.oldStart,
      oldLines: hunk.oldLines,
      newStart: hunk.newStart,
      newLines: hunk.newLines,
      lines: List.unmodifiable(visible),
      isTextRange: hunk.isTextRange,
      truncated: cut,
      partial: hunk.partial,
      oldHasTrailingNewline: hunk.oldHasTrailingNewline,
      newHasTrailingNewline: hunk.newHasTrailingNewline,
      rangeLabel: hunk.rangeLabel,
    ));
    if (cut) break;
  }
  return bounded;
}

enum _DiffOpKind { equal, delete, insert }

class _DiffOp {
  final _DiffOpKind kind;
  final String text;
  const _DiffOp(this.kind, this.text);
}

List<_DiffOp> _diffOps(List<String> a, List<String> b) {
  final lcs = List.generate(a.length + 1, (_) => List.filled(b.length + 1, 0));
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lcs[i][j] = a[i] == b[j]
          ? lcs[i + 1][j + 1] + 1
          : lcs[i + 1][j] > lcs[i][j + 1]
              ? lcs[i + 1][j]
              : lcs[i][j + 1];
    }
  }
  final ops = <_DiffOp>[];
  var i = 0;
  var j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      ops.add(_DiffOp(_DiffOpKind.equal, a[i++]));
      j++;
    } else if (lcs[i + 1][j] >= lcs[i][j + 1]) {
      ops.add(_DiffOp(_DiffOpKind.delete, a[i++]));
    } else {
      ops.add(_DiffOp(_DiffOpKind.insert, b[j++]));
    }
  }
  while (i < a.length) {
    ops.add(_DiffOp(_DiffOpKind.delete, a[i++]));
  }
  while (j < b.length) {
    ops.add(_DiffOp(_DiffOpKind.insert, b[j++]));
  }
  return ops;
}

const _toolOldKeys = [
  'oldText',
  'old_string',
  'oldString',
  'before',
  'old_content',
  'oldContent',
];
const _toolNewKeys = [
  'newText',
  'new_text',
  'newString',
  'new_string',
  'after',
  'new_content',
  'newContent',
  'content',
];
const _toolContentKeys = [
  'content',
  'newText',
  'new_text',
  'newString',
  'new_string',
  'text',
  'fileContent',
  'file_content',
  'contents',
  'code',
];
const _toolPathKeys = [
  'path',
  'filePath',
  'file_path',
  'targetPath',
  'target_path',
  'filename',
  'file',
];

/// Extracts the official edit-tool payload without guessing a file snapshot.
///
/// The source precedence follows the captured web client: a confirmed patch
/// wins over old/new text, and sources are checked in input/output/raw order.
/// A malformed explicit patch returns null so the caller can retain the raw
/// arguments instead of displaying an invented diff.
ToolInlineDiff? parseToolInlineDiff(Map<String, dynamic> row) {
  final sources = _toolSources(row);
  final path = _toolPath(sources) ?? '';
  final directPatchSources = <Map<String, dynamic>>[];
  final nestedPatchSources = <Map<String, dynamic>>[];
  for (final source in sources) {
    if (_hasPatchField(source) && _patchField(source) != null) {
      directPatchSources.add(source);
    }
    if (nestedPatchSources.isNotEmpty) continue;
    for (final key in const ['edits', 'operations', 'replacements']) {
      final value = source[key];
      if (value is List) {
        final beforeCount = nestedPatchSources.length;
        for (final item in value.whereType<Map>()) {
          final edit = _asStringMap(item);
          if (_hasPatchField(edit) && _patchField(edit) != null) {
            nestedPatchSources.add(edit);
          }
        }
        if (nestedPatchSources.length > beforeCount) break;
      }
    }
  }
  final patchSources = directPatchSources.isNotEmpty
      ? [directPatchSources.first]
      : nestedPatchSources;
  if (patchSources.isNotEmpty) {
    final patches = <FileChangesHunk>[];
    for (final source in patchSources) {
      final parsed = _parseToolPatch(_patchField(source));
      if (parsed == null) return null;
      patches.addAll(parsed);
    }
    final boundedPatches = _boundHunksByBudget(
      patches,
      maxOutputLines: 400,
      maxOutputChars: 100000,
    );
    final resolvedPath =
        path.isNotEmpty ? path : _patchPath(_patchField(patchSources.first));
    if (resolvedPath.isEmpty) return null;
    return ToolInlineDiff(
      path: resolvedPath,
      hunks: List.unmodifiable(boundedPatches),
      fromPatch: true,
      truncated: boundedPatches.length < patches.length ||
          boundedPatches.any((hunk) => hunk.truncated),
      partial: boundedPatches.any((hunk) => hunk.partial),
    );
  }

  final family = _toolFamily(row['toolName']);
  final edits = <Map<String, dynamic>>[];
  Map<String, dynamic>? authoritativeEditSource;
  for (final source in sources) {
    for (final key in const ['edits', 'operations', 'replacements']) {
      final value = source[key];
      if (value is List && value.whereType<Map>().isNotEmpty) {
        authoritativeEditSource = source;
        edits.addAll(value.whereType<Map>().map(_asStringMap));
        break;
      }
    }
    if (authoritativeEditSource != null) break;
  }

  final hunks = <FileChangesHunk>[];
  var sawText = false;
  var truncated = false;
  var rangeIndex = 0;
  void appendPair(Map<String, dynamic> source, (String, String) pair) {
    sawText = true;
    final oldText = pair.$1;
    final newText = pair.$2;
    final sourceTruncated = source['truncated'] == true;
    final rangeLabel = edits.length > 1 ? '编辑 ${++rangeIndex}' : null;
    final built = buildDiffHunks(
      before: oldText,
      after: newText,
      isTextRange: true,
      rangeLabel: rangeLabel,
    );
    hunks.addAll(built);
    truncated = truncated || sourceTruncated || built.any((h) => h.truncated);
  }

  if (edits.isNotEmpty) {
    for (final source in edits) {
      final pair = _toolTextPair(source, family);
      if (pair != null) appendPair(source, pair);
    }
  } else {
    // inputText/raw are often encoded backups of the same input. The web
    // client takes the first valid source; aggregating all copies duplicates
    // one edit in the rendered diff.
    for (final source in sources) {
      final pair = _toolTextPair(source, family);
      if (pair == null) continue;
      appendPair(source, pair);
      break;
    }
  }
  if (!sawText || path.isEmpty) return null;
  final boundedHunks = _boundHunksByBudget(
    hunks,
    maxOutputLines: 400,
    maxOutputChars: 100000,
  );
  return ToolInlineDiff(
    path: path,
    hunks: List.unmodifiable(boundedHunks),
    fromPatch: false,
    truncated: truncated ||
        boundedHunks.length < hunks.length ||
        boundedHunks.any((hunk) => hunk.truncated),
    partial: false,
  );
}

List<Map<String, dynamic>> _toolSources(Map<String, dynamic> row) {
  final sources = <Map<String, dynamic>>[];
  void add(Object? value) {
    if (value is Map) sources.add(_asStringMap(value));
  }

  add(row['input']);
  final inputText = row['inputText'];
  if (inputText is String && inputText.isNotEmpty) {
    try {
      add(jsonDecode(inputText));
    } on FormatException {
      // The raw argument remains available in the expanded row.
    }
  }
  add(row['output']);
  final output = row['output'];
  if (output is Map) {
    add(output['raw']);
    add(output['rawOutput']);
  }
  final raw = row['raw'];
  add(raw);
  if (raw is Map) add(raw['rawOutput']);
  add(row['rawOutput']);
  return sources;
}

Map<String, dynamic> _asStringMap(Map value) =>
    value.map((key, value) => MapEntry(key.toString(), value));

String? _toolPath(List<Map<String, dynamic>> sources) {
  for (final source in sources) {
    for (final key in _toolPathKeys) {
      final value = source[key];
      if (value is String && value.isNotEmpty) return value;
    }
  }
  return null;
}

String _toolFamily(Object? value) {
  final name = value is String
      ? value.toLowerCase().replaceAll(RegExp(r'[-_]'), '')
      : '';
  if (name == 'write' || name == 'writefile' || name == 'filewrite') {
    return 'write';
  }
  if (name == 'delete' || name == 'deletefile') return 'delete';
  return 'edit';
}

bool _hasPatchField(Map<String, dynamic> source) =>
    source.containsKey('patch') ||
    source.containsKey('patches') ||
    source.containsKey('unifiedDiff') ||
    source.containsKey('unified_diff');

Object? _patchField(Map<String, dynamic> source) {
  for (final key in const ['patch', 'patches', 'unifiedDiff', 'unified_diff']) {
    if (source.containsKey(key)) return source[key];
  }
  return null;
}

String _patchPath(Object? raw) {
  if (raw is Map) {
    final map = _asStringMap(raw);
    for (final key in _toolPathKeys) {
      if (map[key] is String && (map[key] as String).isNotEmpty) {
        return map[key] as String;
      }
    }
  }
  return '';
}

List<FileChangesHunk>? _parseToolPatch(Object? raw) {
  if (raw is String) return _parseUnifiedPatch(raw);
  if (raw is List) {
    final hunks = <FileChangesHunk>[];
    for (final item in raw) {
      final parsed = _parseToolPatch(item);
      if (parsed == null) return null;
      hunks.addAll(parsed);
    }
    return hunks;
  }
  if (raw is! Map) return null;
  final map = _asStringMap(raw);
  if (map['patches'] != null) return _parseToolPatch(map['patches']);
  if (map['hunks'] != null) return _parseToolPatch(map['hunks']);
  final oldStart = _readNonNegativeInt(map['oldStart']);
  final oldLines = _readNonNegativeInt(map['oldLines']);
  final newStart = _readNonNegativeInt(map['newStart']);
  final newLines = _readNonNegativeInt(map['newLines']);
  final lines = map['lines'];
  if (oldStart == null ||
      oldLines == null ||
      newStart == null ||
      newLines == null ||
      lines is! List ||
      lines.any((line) =>
          line is! String ||
          line.isEmpty ||
          !const ['+', '-', ' ', '\\'].contains(line[0]))) {
    return null;
  }
  return [
    _makePatchHunk(
      oldStart: oldStart,
      oldLines: oldLines,
      newStart: newStart,
      newLines: newLines,
      lines: lines.cast<String>(),
    )
  ];
}

FileChangesHunk _makePatchHunk({
  required int oldStart,
  required int oldLines,
  required int newStart,
  required int newLines,
  required List<String> lines,
}) {
  final actualOldLines = lines
      .where((line) => line.startsWith('-') || line.startsWith(' '))
      .length;
  final actualNewLines = lines
      .where((line) => line.startsWith('+') || line.startsWith(' '))
      .length;
  final partial = actualOldLines != oldLines || actualNewLines != newLines;
  final bounded = _boundPatchLines(lines, maxOutputLines: 400);
  final candidate = FileChangesHunk(
    oldStart: oldStart,
    oldLines: oldLines,
    newStart: newStart,
    newLines: newLines,
    lines: List.unmodifiable(bounded.lines),
    truncated: bounded.truncated,
    partial: partial,
  );
  if (candidate.lines.isEmpty) return candidate;
  return _boundHunksByBudget(
    [candidate],
    maxOutputLines: 400,
    maxOutputChars: 100000,
  ).single;
}

({List<String> lines, bool truncated}) _boundPatchLines(List<String> lines,
    {required int maxOutputLines}) {
  if (lines.length <= maxOutputLines) {
    return (lines: lines, truncated: false);
  }
  final edge = maxOutputLines ~/ 2;
  return (
    lines: <String>[...lines.take(edge), ...lines.skip(lines.length - edge)],
    truncated: true,
  );
}

List<FileChangesHunk>? _parseUnifiedPatch(String raw) {
  if (raw.isEmpty) return const [];
  final lines = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final hunks = <FileChangesHunk>[];
  int? oldStart;
  int? oldLines;
  int? newStart;
  int? newLines;
  final body = <String>[];
  void finish() {
    if (oldStart == null ||
        oldLines == null ||
        newStart == null ||
        newLines == null) {
      return;
    }
    hunks.add(_makePatchHunk(
      oldStart: oldStart,
      oldLines: oldLines,
      newStart: newStart,
      newLines: newLines,
      lines: body,
    ));
    body.clear();
  }

  final header = RegExp(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@');
  for (var lineIndex = 0; lineIndex < lines.length; lineIndex++) {
    final line = lines[lineIndex];
    final match = header.firstMatch(line);
    if (match != null) {
      finish();
      oldStart = int.parse(match.group(1)!);
      oldLines = int.tryParse(match.group(2) ?? '1');
      newStart = int.parse(match.group(3)!);
      newLines = int.tryParse(match.group(4) ?? '1');
      continue;
    }
    if (oldStart == null) {
      if (line.startsWith('diff ') ||
          line.startsWith('index ') ||
          line.startsWith('--- ') ||
          line.startsWith('+++ ')) {
        continue;
      }
      if (line.isEmpty) continue;
      return null;
    }
    if (line.isEmpty && lineIndex == lines.length - 1) {
      continue;
    }
    if (line.isEmpty) {
      body.add(' ');
    } else if (const ['+', '-', ' ', '\\'].contains(line[0])) {
      body.add(line);
    } else {
      return null;
    }
  }
  finish();
  return hunks.isEmpty ? null : hunks;
}

(String, String)? _toolTextPair(Map<String, dynamic> source, String family) {
  final old = _findTextValue(source, _toolOldKeys);
  final next = _findTextValue(source, _toolNewKeys);
  if (old != null && next != null) return (old, next);
  if (family == 'write' && next != null) return ('', next);
  if (family == 'delete' && old != null) return (old, '');
  // A write payload often uses only `content`, which is already in the new
  // key list. Do not treat an arbitrary result text as a file range for edits.
  if (family == 'write') {
    final content = _findTextValue(source, _toolContentKeys);
    if (content != null) return ('', content);
  }
  return null;
}

String? _findTextValue(Map<String, dynamic> source, List<String> keys) {
  for (final key in keys) {
    if (!source.containsKey(key)) continue;
    final value = source[key];
    if (value == null) return '';
    if (value is String) return value;
    return null;
  }
  return null;
}
