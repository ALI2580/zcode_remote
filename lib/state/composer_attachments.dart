import 'dart:async';
import 'package:flutter/foundation.dart';
import '../protocol/conversation.dart';
import '../protocol/id.dart';

class PickedAttachment {
  const PickedAttachment(
      {required this.name,
      required this.mime,
      required this.size,
      required this.read,
      this.recovery,
      this.unavailable = false});
  final String name, mime;
  final int size;
  final Future<Uint8List> Function() read;
  final Map<String, dynamic>? recovery;
  final bool unavailable;
  Map<String, dynamic> toJson() =>
      {'name': name, 'mime': mime, 'size': size, ...?recovery};
}

enum AttachmentPhase { waitingSession, uploading, ready, failed }

class AttachmentUnavailable implements Exception {
  const AttachmentUnavailable();
  @override
  String toString() => 'Selected attachment is unavailable';
}

class ComposerAttachment {
  ComposerAttachment(this.file, {String? id})
      : id = id ?? generateUuid(),
        unavailable = file.unavailable;
  final String id;
  final PickedAttachment file;
  AttachmentPhase phase = AttachmentPhase.waitingSession;
  double progress = 0;
  Uint8List? bytes;
  Map<String, dynamic>? descriptor;
  bool cancelled = false;
  bool tooLarge = false;
  bool unavailable;
  int retries = 0;
  Map<String, dynamic> toJson() => {
        'id': id,
        'file': file.toJson(),
        'phase': phase.name,
        if (descriptor != null) 'descriptor': descriptor
      };
}

class ComposerAttachments extends ChangeNotifier {
  ComposerAttachments({required this.transport, required this.ensureSession});
  final ConversationTransport transport;
  final Future<String> Function() ensureSession;
  final items = <ComposerAttachment>[];
  final _running = <String>{};
  bool _disposed = false;
  bool get busy => _running.isNotEmpty;
  bool get pending => items.any((e) => e.phase != AttachmentPhase.ready);
  List<Map<String, dynamic>> get descriptors => [
        for (final item in items)
          if (item.descriptor != null) item.descriptor!
      ];

  void add(Iterable<PickedAttachment> files) {
    if (_disposed) return;
    for (final file in files) {
      final entry = ComposerAttachment(file);
      if (file.size > 20 * 1024 * 1024) {
        entry.phase = AttachmentPhase.failed;
        entry.tooLarge = true;
      }
      if (entry.unavailable) entry.phase = AttachmentPhase.failed;
      items.add(entry);
    }
    _notify();
    _drain();
  }

  void restore(
      List<PickedAttachment> files, List<Map<String, dynamic>> states) {
    if (_disposed) return;
    for (var index = 0; index < files.length; index++) {
      final state =
          index < states.length ? states[index] : const <String, dynamic>{};
      final entry = ComposerAttachment(files[index],
          id: state['id'] is String ? state['id'] : null);
      entry.tooLarge = entry.file.size > 20 * 1024 * 1024;
      if (entry.file.unavailable ||
          entry.tooLarge ||
          state['phase'] == 'failed') {
        entry.phase = AttachmentPhase.failed;
      } else if (state['phase'] == 'ready' &&
          state['descriptor'] is Map &&
          (state['descriptor'] as Map)['ref'] is String &&
          ((state['descriptor'] as Map)['ref'] as String).isNotEmpty) {
        entry.descriptor =
            Map<String, dynamic>.from(state['descriptor'] as Map);
        entry.phase = AttachmentPhase.ready;
        entry.progress = 1;
      }
      items.add(entry);
    }
    _notify();
    _drain();
  }

  void retry(ComposerAttachment entry) {
    if (_disposed ||
        !items.contains(entry) ||
        entry.tooLarge ||
        entry.unavailable ||
        _running.contains(entry.id)) {
      return;
    }
    entry.phase = AttachmentPhase.waitingSession;
    entry.progress = 0;
    entry.cancelled = false;
    _notify();
    _drain();
  }

  void remove(ComposerAttachment entry) {
    entry.cancelled = true;
    items.remove(entry);
    _notify();
  }

  void accepted(Set<String> ids) {
    for (final entry in items.where((e) => ids.contains(e.id)).toList()) {
      remove(entry);
    }
  }

  void restartUploads() {
    if (_disposed || busy) return;
    for (final entry in items) {
      if (entry.unavailable || entry.tooLarge) continue;
      entry.descriptor = null;
      entry.phase = AttachmentPhase.waitingSession;
      entry.progress = 0;
      entry.retries = 0;
    }
    _notify();
    _drain();
  }

  Future<Uint8List> preview(ComposerAttachment entry) async {
    if (entry.bytes != null) return entry.bytes!;
    try {
      final bytes = await entry.file.read();
      if (!_disposed && items.contains(entry)) {
        entry.bytes = bytes;
        _notify();
      }
      return bytes;
    } catch (_) {
      if (!_disposed && items.contains(entry)) {
        entry.unavailable = true;
        entry.phase = AttachmentPhase.failed;
        _notify();
      }
      throw const AttachmentUnavailable();
    }
  }

  void _drain() {
    if (_disposed) return;
    for (final entry in items) {
      if (_running.length >= 2) break;
      if (entry.phase != AttachmentPhase.waitingSession ||
          !_running.add(entry.id)) {
        continue;
      }
      unawaited(_upload(entry));
    }
  }

  Future<void> _upload(ComposerAttachment entry) async {
    bool current() => !_disposed && !entry.cancelled && items.contains(entry);
    try {
      final session = await ensureSession();
      if (!current()) return;
      entry.phase = AttachmentPhase.uploading;
      _notify();
      final bytes = entry.bytes ?? await entry.file.read();
      if (!current()) return;
      if (bytes.length > 20 * 1024 * 1024) {
        entry.tooLarge = true;
        throw StateError('attachment too large');
      }
      entry.bytes = bytes;
      final descriptor = await transport.attachmentPut(session,
          fileName: entry.file.name,
          mime: entry.file.mime,
          bytes: bytes,
          isCancelled: () => !current(),
          onProgress: (progress) {
            if (current()) {
              entry.progress = progress;
              _notify();
            }
          });
      if (!current()) return;
      if (descriptor['ref'] is! String ||
          (descriptor['ref'] as String).isEmpty) {
        throw StateError('attachment reference missing');
      }
      entry.descriptor = descriptor;
      entry.phase = AttachmentPhase.ready;
      entry.progress = 1;
    } catch (error) {
      if (!current()) return;
      if (error is AttachmentUnavailable) entry.unavailable = true;
      entry.phase = AttachmentPhase.failed;
      if (error is TimeoutException && entry.retries++ < 1) {
        await Future<void>.delayed(const Duration(milliseconds: 500));
        if (current()) entry.phase = AttachmentPhase.waitingSession;
      }
    } finally {
      _running.remove(entry.id);
      _notify();
      _drain();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final entry in items) {
      entry.cancelled = true;
    }
    super.dispose();
  }
}
