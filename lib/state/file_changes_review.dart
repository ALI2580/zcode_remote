import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/conversation.dart';
import '../protocol/file_changes.dart';

enum FileChangesStatus { idle, loading, loaded, error }

class FileChangesScope {
  final String deviceId;
  final String workspaceKey;
  final String sessionId;
  final int rowId;
  final Object? entityId;

  const FileChangesScope({
    required this.deviceId,
    required this.workspaceKey,
    required this.sessionId,
    required this.rowId,
    required this.entityId,
  });

  Map<String, dynamic> get target => {
        'rowId': rowId,
        if (entityId != null) 'entityId': entityId,
      };

  String get cacheKey => '$deviceId|$workspaceKey|$sessionId|$rowId|$entityId';
}

class FileChangesReviewController extends ChangeNotifier {
  final ConversationTransport transport;
  final FileChangesScope scope;
  final int Function() revision;
  final String? Function() logEpoch;

  FileChangesStatus status = FileChangesStatus.idle;
  FileChangesResult? result;
  Object? error;
  String? selectedPath;
  bool rewindOpen = false;
  bool rewindLoading = false;
  bool rewindApplying = false;
  FileRewindPreview? rewindPreview;
  Object? rewindError;
  FileRewindApplyResult? rewindResult;
  Object? rewindApplyError;
  int _generation = 0;
  String? _pendingKey;
  Future<FileChangesResult>? _pending;
  int _rewindGeneration = 0;
  Future<FileRewindPreview>? _rewindPending;
  bool _applyPending = false;
  bool _disposed = false;

  FileChangesReviewController({
    required this.transport,
    required this.scope,
    required this.revision,
    required this.logEpoch,
  });

  bool get isCurrent => !_disposed;

  Future<FileChangesResult> load({bool refresh = false}) {
    if (_disposed) return Future.error(StateError('disposed'));
    final key = '${scope.cacheKey}|${revision()}|${logEpoch()}';
    final pending = _pending;
    if (!refresh && pending != null && _pendingKey == key) return pending;

    final generation = ++_generation;
    _pendingKey = key;
    status = FileChangesStatus.loading;
    if (!refresh) {
      selectedPath = null;
    }
    if (result == null || refresh) error = null;
    _discardRewind();
    notifyListeners();

    final operation = () async {
      final logEpochValue = logEpoch();
      final raw = await transport.fileChanges(
        scope.sessionId,
        target: scope.target,
        baseRevision: revision(),
        baseLogEpoch: logEpochValue,
      );
      final parsed = parseFileChanges(raw);
      _accept(generation, parsed);
      return parsed;
    }();
    _pending = operation;
    return operation.catchError((Object e) {
      _fail(generation, e);
      throw e;
    });
  }

  Future<FileChangesResult> retry() => load(refresh: true);

  void openRewind() {
    if (_disposed) return;
    rewindOpen = true;
    unawaited(previewRewind());
  }

  void closeRewind() {
    if (_disposed || !rewindOpen) return;
    rewindOpen = false;
    notifyListeners();
  }

  Future<FileRewindPreview> previewRewind() {
    if (_disposed) return Future.error(StateError('disposed'));
    final pending = _rewindPending;
    if (pending != null) return pending;
    final generation = ++_rewindGeneration;
    rewindLoading = true;
    rewindError = null;
    notifyListeners();

    final operation = () async {
      final raw = await transport.fileRewindPreview(
        scope.sessionId,
        target: scope.target,
        baseRevision: revision(),
        baseLogEpoch: logEpoch(),
      );
      final parsed = parseFileRewindPreview(raw);
      _acceptRewindPreview(generation, parsed);
      return parsed;
    }();
    _rewindPending = operation;
    return operation.catchError((Object e) {
      _failRewindPreview(generation, e);
      throw e;
    });
  }

  Future<FileRewindApplyResult> applyRewind() async {
    if (_disposed) throw StateError('disposed');
    final preview = rewindPreview;
    if (_applyPending || preview == null || !preview.canApply) {
      throw StateError('rewind is not applyable');
    }
    final generation = _rewindGeneration;
    _applyPending = true;
    rewindApplying = true;
    rewindApplyError = null;
    notifyListeners();
    try {
      final raw = await transport.applyFileRewind(
        scope.sessionId,
        scope.target,
      );
      final parsed = parseFileRewindApply(raw);
      _acceptRewindResult(generation, parsed);
      return parsed;
    } catch (e) {
      _failRewindApply(generation, e);
      rethrow;
    } finally {
      _applyPending = false;
      if (rewindApplying) {
        rewindApplying = false;
        if (!_disposed) notifyListeners();
      }
    }
  }

  void select(String? path) {
    if (_disposed || selectedPath == path) return;
    selectedPath = path;
    notifyListeners();
  }

  void _accept(int generation, FileChangesResult value) {
    if (_disposed || generation != _generation) return;
    result = value;
    status = FileChangesStatus.loaded;
    error = null;
    // U21: the summary never auto-selects the first file; opening a specific
    // file's diff is an explicit user action through the review panel.
    if (selectedPath != null &&
        value.items.every((item) => item.path != selectedPath)) {
      selectedPath = null;
    }
    _pending = null;
    _pendingKey = null;
    _discardRewind();
    notifyListeners();
  }

  void _fail(int generation, Object value) {
    if (_disposed || generation != _generation) return;
    status = FileChangesStatus.error;
    error = value;
    _pending = null;
    _pendingKey = null;
    notifyListeners();
  }

  void _acceptRewindPreview(int generation, FileRewindPreview value) {
    if (_disposed || generation != _rewindGeneration) return;
    rewindLoading = false;
    rewindError = null;
    rewindPreview = value;
    _rewindPending = null;
    notifyListeners();
  }

  void _failRewindPreview(int generation, Object value) {
    if (_disposed || generation != _rewindGeneration) return;
    rewindLoading = false;
    rewindError = value;
    _rewindPending = null;
    notifyListeners();
  }

  void _acceptRewindResult(int generation, FileRewindApplyResult value) {
    if (_disposed || generation != _rewindGeneration) return;
    rewindResult = value;
    rewindApplyError = null;
    if (value.status == 'accepted' || value.status == 'duplicate') {
      rewindOpen = false;
    }
    notifyListeners();
  }

  void _failRewindApply(int generation, Object value) {
    if (_disposed || generation != _rewindGeneration) return;
    rewindApplyError = value;
    notifyListeners();
  }

  void _discardRewind() {
    _rewindGeneration++;
    _rewindPending = null;
    rewindOpen = false;
    rewindLoading = false;
    rewindApplying = false;
    rewindPreview = null;
    rewindError = null;
    rewindResult = null;
    rewindApplyError = null;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
