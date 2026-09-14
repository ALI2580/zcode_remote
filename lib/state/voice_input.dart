import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../voice/voice_errors.dart';
import '../voice/voice_transcriber.dart';
import 'composer_controller.dart';

enum VoiceInputPhase { idle, requesting, recording, recognizing, error }

/// Binds one recognition run to the exact composer draft where it started.
/// The result is inserted into that draft and is never sent automatically.
class VoiceInputController extends ChangeNotifier {
  VoiceInputController({
    required this.composer,
    required this.transcriber,
  }) {
    composer.addListener(_scopeChanged);
  }

  final ComposerController composer;
  final VoiceTranscriber transcriber;
  VoiceInputPhase phase = VoiceInputPhase.idle;
  String partial = '';
  String? error;
  VoiceFailureKind? errorKind;
  String? _scopeKey;
  int _generation = 0;
  bool _disposed = false;

  bool get isBusy =>
      phase == VoiceInputPhase.requesting ||
      phase == VoiceInputPhase.recording ||
      phase == VoiceInputPhase.recognizing;

  bool get canManageModels =>
      errorKind == VoiceFailureKind.modelNotDownloaded ||
      errorKind == VoiceFailureKind.modelNotEnabled ||
      errorKind == VoiceFailureKind.modelUnavailable ||
      errorKind == VoiceFailureKind.modelCorrupt ||
      errorKind == VoiceFailureKind.storageUnavailable;

  bool get canRetryPermission => errorKind == VoiceFailureKind.permissionDenied;

  Future<void> start() async {
    if (isBusy || _disposed) return;
    if (!composer.ready) {
      phase = VoiceInputPhase.error;
      error = '语音输入需等待当前会话准备完成';
      errorKind = VoiceFailureKind.sessionNotReady;
      notifyListeners();
      return;
    }
    final generation = ++_generation;
    final scopeKey = composer.key;
    _scopeKey = scopeKey;
    phase = VoiceInputPhase.requesting;
    partial = '';
    error = null;
    errorKind = null;
    notifyListeners();
    try {
      await transcriber.start(
        onPartial: (value) => _onPartial(generation, scopeKey, value),
      );
      if (!_isCurrent(generation, scopeKey)) {
        return;
      }
      phase = VoiceInputPhase.recording;
    } catch (value) {
      if (!_isCurrent(generation, scopeKey)) return;
      final failure = _failure(value);
      if (failure.kind == VoiceFailureKind.cancelled) {
        phase = VoiceInputPhase.idle;
        partial = '';
        notifyListeners();
        return;
      }
      phase = VoiceInputPhase.error;
      error = failure.message;
      errorKind = failure.kind;
    }
    if (_isCurrent(generation, scopeKey)) notifyListeners();
  }

  Future<void> stop() async {
    if (phase != VoiceInputPhase.recording || _disposed) return;
    final generation = ++_generation;
    final scopeKey = _scopeKey;
    phase = VoiceInputPhase.recognizing;
    partial = '';
    error = null;
    errorKind = null;
    notifyListeners();
    String text;
    try {
      text = await transcriber.stop();
    } catch (value) {
      if (!_isCurrent(generation, scopeKey)) return;
      final failure = _failure(value);
      if (failure.kind == VoiceFailureKind.cancelled) {
        phase = VoiceInputPhase.idle;
        notifyListeners();
        return;
      }
      phase = VoiceInputPhase.error;
      error = failure.message;
      errorKind = failure.kind;
      notifyListeners();
      return;
    }
    if (!_isCurrent(generation, scopeKey)) return;
    if (text.isNotEmpty) _insertResult(text);
    phase = VoiceInputPhase.idle;
    partial = '';
    error = null;
    errorKind = null;
    notifyListeners();
  }

  /// Cancellation revokes the draft ownership immediately. The transcriber
  /// cleanup is awaited in the background, so a restart cannot be blocked by
  /// a late native decode or recorder callback.
  Future<void> cancel() async {
    if (!isBusy && phase != VoiceInputPhase.error) return;
    ++_generation;
    phase = VoiceInputPhase.idle;
    partial = '';
    error = null;
    errorKind = null;
    notifyListeners();
    try {
      await transcriber.cancel();
    } catch (_) {}
  }

  void _onPartial(int generation, String? scopeKey, String value) {
    if (!_isCurrent(generation, scopeKey) ||
        phase != VoiceInputPhase.recording) {
      return;
    }
    partial = value;
    notifyListeners();
  }

  void _scopeChanged() {
    if (_disposed || !isBusy || composer.key == _scopeKey) return;
    unawaited(cancel());
  }

  bool _isCurrent(int generation, String? scopeKey) =>
      !_disposed && _generation == generation && composer.key == scopeKey;

  VoiceTranscriberException _failure(Object value) {
    if (value is VoiceTranscriberException) return value;
    final text = '$value'.replaceFirst(RegExp(r'^Bad state: '), '');
    final lower = text.toLowerCase();
    final kind = lower.contains('permission') || text.contains('权限')
        ? VoiceFailureKind.permissionDenied
        : text.contains('模型')
            ? VoiceFailureKind.modelUnavailable
            : VoiceFailureKind.unknown;
    return VoiceTranscriberException(kind, text);
  }

  void _insertResult(String value) {
    final current = composer.input.value;
    final separator =
        current.text.isEmpty || current.text.endsWith(' ') ? '' : ' ';
    final next = '${current.text}$separator$value';
    composer.input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: next.length),
    );
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    ++_generation;
    composer.removeListener(_scopeChanged);
    unawaited(transcriber.dispose());
    super.dispose();
  }
}
