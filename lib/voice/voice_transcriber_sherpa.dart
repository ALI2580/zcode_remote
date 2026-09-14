import 'dart:async';
import 'dart:typed_data';

import 'package:record/record.dart';

import 'voice_errors.dart';
import 'voice_model_store_native.dart';
import 'voice_model_readiness_native.dart';
import 'voice_models.dart';
import 'voice_transcriber.dart';
import 'voice_transcriber_worker.dart';

typedef VoiceAudioRecorderFactory = VoiceAudioRecorder Function();

abstract interface class VoiceAudioRecorder {
  Future<bool> hasPermission();
  Future<Stream<Uint8List>> startStream(RecordConfig config);
  Future<void> stop();
  Future<void> cancel();
  Future<void> dispose();
}

class RecordVoiceAudioRecorder implements VoiceAudioRecorder {
  RecordVoiceAudioRecorder(this._recorder);

  final AudioRecorder _recorder;

  @override
  Future<bool> hasPermission() => _recorder.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) =>
      _recorder.startStream(config);

  @override
  Future<void> stop() => _recorder.stop();

  @override
  Future<void> cancel() => _recorder.cancel();

  @override
  Future<void> dispose() => _recorder.dispose();
}

class _VoiceAudioSession {
  _VoiceAudioSession(this.recorder);

  final VoiceAudioRecorder recorder;
  bool _closed = false;

  Future<void> close({bool stop = false}) async {
    if (_closed) return;
    _closed = true;
    try {
      if (stop) {
        await recorder.stop();
      } else {
        await recorder.cancel();
      }
    } finally {
      await recorder.dispose();
    }
  }
}

/// Offline microphone-to-text transcription. Audio never leaves the device.
///
/// Recording stays on the UI isolate because it is a platform plugin. sherpa
/// binding initialization, model loading and every decode run in the worker.
class SherpaVoiceTranscriber implements VoiceTranscriber {
  SherpaVoiceTranscriber({
    VoiceModelStore? store,
    VoiceInferenceWorker? worker,
    VoiceAudioRecorderFactory? recorderFactory,
  })  : store = store ?? VoiceModelStore(),
        _worker = worker ?? SherpaVoiceWorker(),
        _recorderFactory = recorderFactory ??
            (() => RecordVoiceAudioRecorder(AudioRecorder()));

  final VoiceModelStore store;
  final VoiceInferenceWorker _worker;
  final VoiceAudioRecorderFactory _recorderFactory;
  final _samples = <double>[];
  StreamSubscription<Uint8List>? _audioSub;
  Timer? _previewTimer;
  Future<void>? _previewTask;
  Object? _previewMarker;
  int? _previewOperation;
  bool _previewRequested = false;
  VoiceModelInfo? _model;
  int _epoch = 0;
  bool _starting = false;
  bool _recording = false;
  int? _stopOperation;
  int? _transcribeOperation;
  _VoiceAudioSession? _activeAudio;
  bool _disposed = false;
  void Function(String text)? _onPartial;

  @override
  bool get isRecording => _recording;

  @override
  Future<bool> hasPermission() {
    if (_disposed) return Future.value(false);
    final active = _activeAudio;
    if (active != null) return active.recorder.hasPermission();
    final recorder = _recorderFactory();
    return recorder.hasPermission().whenComplete(recorder.dispose);
  }

  @override
  Future<void> start({void Function(String text)? onPartial}) async {
    if (_disposed) {
      throw const VoiceTranscriberException(
          VoiceFailureKind.cancelled, '语音输入已释放');
    }
    if (_recording ||
        _starting ||
        _stopOperation != null ||
        _transcribeOperation != null) {
      return;
    }
    final operation = ++_epoch;
    _starting = true;
    final audioSession = _VoiceAudioSession(_recorderFactory());
    _activeAudio = audioSession;
    try {
      final id = await store.enabledModelId();
      _checkCurrent(operation);
      if (id == null) {
        throw await _inputModelFailure();
      }
      if (!await audioSession.recorder.hasPermission()) {
        throw const VoiceTranscriberException(
          VoiceFailureKind.permissionDenied,
          '没有麦克风权限，请在系统设置中允许麦克风后重试',
        );
      }
      _checkCurrent(operation);
      final model = voiceModelById(id);
      final directory = await store.directory(model);
      _checkCurrent(operation);
      await _worker.load(modelId: model.id, directory: directory.path);
      _checkCurrent(operation);
      _model = model;
      _samples.clear();
      _onPartial = onPartial;
      final audio = await audioSession.recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: 16000,
        numChannels: 1,
      ));
      if (!_isCurrent(operation)) {
        if (identical(_activeAudio, audioSession)) _activeAudio = null;
        await audioSession.close();
        return;
      }
      _audioSub = audio.listen(_acceptBytes);
      _recording = true;
      _previewTimer = Timer.periodic(
        const Duration(milliseconds: 1400),
        (_) => _schedulePreview(),
      );
    } catch (error) {
      if (identical(_activeAudio, audioSession)) _activeAudio = null;
      await audioSession.close();
      if (_isCurrent(operation)) {
        throw _asVoiceException(error, modelId: _model?.id);
      }
    } finally {
      if (_epoch == operation) _starting = false;
    }
  }

  /// Runs an already-captured audio buffer through the enabled model.
  /// This is intentionally separate from [start]/[stop] so known-audio tests
  /// can prove model inference without claiming that microphone capture works.
  Future<String> transcribeSamples(Float32List samples) async {
    if (_disposed) {
      throw const VoiceTranscriberException(
          VoiceFailureKind.cancelled, '语音输入已释放');
    }
    if (_recording ||
        _starting ||
        _stopOperation != null ||
        _transcribeOperation != null) {
      throw const VoiceTranscriberException(VoiceFailureKind.busy, '语音识别正在进行');
    }
    if (samples.isEmpty) return '';
    final operation = ++_epoch;
    _transcribeOperation = operation;
    try {
      final id = await store.enabledModelId();
      _checkCurrent(operation);
      if (id == null) {
        throw await _inputModelFailure();
      }
      final model = voiceModelById(id);
      final directory = await store.directory(model);
      _checkCurrent(operation);
      await _worker.load(modelId: model.id, directory: directory.path);
      _checkCurrent(operation);
      _model = model;
      final text = await _worker.decode(samples);
      _checkCurrent(operation);
      return text;
    } catch (error) {
      if (!_isCurrent(operation)) {
        throw const VoiceTranscriberException(
            VoiceFailureKind.cancelled, '语音识别已取消');
      }
      throw _asVoiceException(error, modelId: _model?.id);
    } finally {
      if (_transcribeOperation == operation) _transcribeOperation = null;
    }
  }

  void _acceptBytes(Uint8List bytes) {
    if (!_recording) return;
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final value = bytes[i] | (bytes[i + 1] << 8);
      final signed = value >= 0x8000 ? value - 0x10000 : value;
      _samples.add(signed / 32768.0);
    }
  }

  void _schedulePreview() {
    if (!_recording || _disposed || _samples.length < 8000) return;
    final operation = _epoch;
    if (_previewTask != null && _previewOperation == operation) {
      // Keep only the newest snapshot while a decode is in flight.
      _previewRequested = true;
      return;
    }
    final samples = Float32List.fromList(_samples);
    final marker = Object();
    final task = _emitPreview(operation, marker, samples);
    _previewMarker = marker;
    _previewOperation = operation;
    _previewTask = task;
    unawaited(task);
  }

  Future<void> _emitPreview(
      int operation, Object marker, Float32List samples) async {
    try {
      final text = await _worker.decode(samples);
      if (_isCurrent(operation) && _recording && text.isNotEmpty) {
        _onPartial?.call(text);
      }
    } catch (_) {
      // Preview errors never replace the final recognition/error result.
    } finally {
      if (identical(_previewMarker, marker)) {
        _previewTask = null;
        _previewMarker = null;
        _previewOperation = null;
        if (_previewRequested) {
          _previewRequested = false;
          if (_recording && _isCurrent(operation)) _schedulePreview();
        }
      }
    }
  }

  @override
  Future<String> stop() async {
    if (_disposed || !_recording) return '';
    final operation = _epoch;
    _stopOperation = operation;
    _recording = false;
    _previewRequested = false;
    _previewTimer?.cancel();
    _previewTimer = null;
    final subscription = _audioSub;
    _audioSub = null;
    final audioSession = _activeAudio;
    _activeAudio = null;
    try {
      await subscription?.cancel();
      await audioSession?.close(stop: true);
      // Let a queued preview finish before the final decode. The worker is
      // serialized, so the final result cannot be swallowed by preview busy.
      final preview = _previewOperation == operation ? _previewTask : null;
      await preview;
      if (!_isCurrent(operation)) return '';
      final finalSamples = Float32List.fromList(_samples);
      if (finalSamples.isEmpty) return '';
      final text = await _worker.decode(finalSamples);
      if (!_isCurrent(operation)) return '';
      return text;
    } catch (error) {
      if (!_isCurrent(operation)) return '';
      throw _asVoiceException(error, modelId: _model?.id);
    } finally {
      if (_stopOperation == operation) {
        _stopOperation = null;
        if (_epoch == operation) {
          _samples.clear();
          _onPartial = null;
        }
      }
    }
  }

  @override
  Future<void> cancel() async {
    if (_disposed) return;
    ++_epoch;
    _starting = false;
    _stopOperation = null;
    _transcribeOperation = null;
    _recording = false;
    _previewRequested = false;
    _previewMarker = null;
    _previewOperation = null;
    _previewTimer?.cancel();
    _previewTimer = null;
    final subscription = _audioSub;
    _audioSub = null;
    final audioSession = _activeAudio;
    _activeAudio = null;
    _samples.clear();
    _onPartial = null;
    await subscription?.cancel();
    await audioSession?.close();
    // Keep the loaded model resident for the next recording. In-flight
    // worker responses carry the old operation and are ignored by the caller.
  }

  void _checkCurrent(int operation) {
    if (!_isCurrent(operation)) {
      throw const VoiceTranscriberException(
          VoiceFailureKind.cancelled, '语音输入已取消');
    }
  }

  bool _isCurrent(int operation) => !_disposed && _epoch == operation;

  Future<VoiceTranscriberException> _inputModelFailure() async {
    final availability = await voiceModelInputAvailability(store);
    return switch (availability) {
      VoiceModelAvailability.downloaded => const VoiceTranscriberException(
          VoiceFailureKind.modelNotEnabled, '已下载语音模型但尚未启用，请打开模型管理并启用'),
      VoiceModelAvailability.corrupt => const VoiceTranscriberException(
          VoiceFailureKind.modelCorrupt, '语音模型已损坏，请打开模型管理重新下载'),
      VoiceModelAvailability.storageUnavailable =>
        const VoiceTranscriberException(
            VoiceFailureKind.storageUnavailable, '无法读取语音模型存储，请检查应用存储权限后重试'),
      VoiceModelAvailability.notDownloaded => const VoiceTranscriberException(
          VoiceFailureKind.modelNotDownloaded, '尚未下载离线语音模型，请打开模型管理下载'),
      VoiceModelAvailability.enabled => const VoiceTranscriberException(
          VoiceFailureKind.modelUnavailable, '请打开模型管理确认语音模型状态'),
    };
  }

  VoiceTranscriberException _asVoiceException(Object error, {String? modelId}) {
    if (error is VoiceTranscriberException) return error;
    if (error is VoiceModelStoreException) {
      return VoiceTranscriberException(error.kind, error.message,
          modelId: modelId);
    }
    final text = '$error'.replaceFirst(RegExp(r'^Bad state: '), '');
    final lower = text.toLowerCase();
    final kind = lower.contains('permission') || text.contains('权限')
        ? VoiceFailureKind.permissionDenied
        : lower.contains('storage') || text.contains('存储')
            ? VoiceFailureKind.storageUnavailable
            : lower.contains('recognizer') || lower.contains('sherpa')
                ? VoiceFailureKind.modelCorrupt
                : VoiceFailureKind.unknown;
    return VoiceTranscriberException(kind, text, modelId: modelId);
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    ++_epoch;
    _starting = false;
    _stopOperation = null;
    _transcribeOperation = null;
    _recording = false;
    _previewRequested = false;
    _previewMarker = null;
    _previewOperation = null;
    _previewTimer?.cancel();
    _previewTimer = null;
    final subscription = _audioSub;
    _audioSub = null;
    final audioSession = _activeAudio;
    _activeAudio = null;
    await subscription?.cancel();
    await audioSession?.close();
    await _worker.close();
    _samples.clear();
    _onPartial = null;
  }
}
