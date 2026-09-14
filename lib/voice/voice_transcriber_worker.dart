import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

/// A single long-lived isolate owning all sherpa FFI objects.
///
/// Only model identifiers, paths, and copied sample buffers cross this
/// boundary. Native recognizer/stream pointers never leave the worker.
abstract interface class VoiceInferenceWorker {
  Future<void> load({required String modelId, required String directory});
  Future<String> decode(Float32List samples);
  Future<void> release();
  Future<void> close();
}

class SherpaVoiceWorker implements VoiceInferenceWorker {
  SherpaVoiceWorker();

  Isolate? _isolate;
  ReceivePort? _receivePort;
  StreamSubscription<dynamic>? _subscription;
  SendPort? _sendPort;
  Completer<void>? _starting;
  final Map<int, Completer<dynamic>> _pending = {};
  int _nextRequest = 0;
  bool _closed = false;
  bool _closing = false;
  Object? _failure;

  Future<void> _ensureStarted() async {
    if (_sendPort != null) return;
    if (_closed || _closing) throw StateError('voice worker disposed');
    final failure = _failure;
    if (failure != null) throw failure;
    final running = _starting;
    if (running != null) return running.future;

    final start = Completer<void>();
    _starting = start;
    final receive = ReceivePort();
    _receivePort = receive;
    _subscription = receive.listen(_handleMessage);
    try {
      final isolate = await Isolate.spawn<_WorkerBootstrap>(
        _voiceWorkerMain,
        _WorkerBootstrap(receive.sendPort),
        debugName: 'zcode-voice-worker',
      );
      if (_closing || _closed) {
        isolate.kill(priority: Isolate.immediate);
        throw StateError('voice worker closing');
      }
      _isolate = isolate;
      isolate.addErrorListener(receive.sendPort);
      await start.future;
    } catch (error, stack) {
      if (!start.isCompleted) start.completeError(error, stack);
      rethrow;
    } finally {
      _starting = null;
    }
  }

  void _handleMessage(dynamic message) {
    if (message is SendPort && _sendPort == null) {
      _sendPort = message;
      final start = _starting;
      if (start != null && !start.isCompleted) start.complete();
      return;
    }
    if (message is List && message.length >= 2) {
      final error = '${message.first}';
      final stack = message.length > 1 ? '${message[1]}' : '';
      final failure = VoiceWorkerException(error, stack);
      _failure = failure;
      _sendPort = null;
      final start = _starting;
      if (start != null && !start.isCompleted) {
        start.completeError(failure);
      }
      _failPending(failure);
      return;
    }
    if (message is! Map) return;
    final id = message['id'];
    if (id is! int) return;
    final completer = _pending.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (message['ok'] == true) {
      completer.complete(message['result']);
    } else {
      completer.completeError(VoiceWorkerException(
        '${message['error'] ?? 'voice worker request failed'}',
        '${message['stack'] ?? ''}',
      ));
    }
  }

  void _failPending(Object error) {
    final pending = List<Completer<dynamic>>.from(_pending.values);
    _pending.clear();
    for (final completer in pending) {
      if (!completer.isCompleted) completer.completeError(error);
    }
  }

  Future<dynamic> _request(String action, [Map<String, dynamic>? data]) async {
    await _ensureStarted();
    final send = _sendPort;
    if (send == null) throw StateError('voice worker unavailable');
    final id = ++_nextRequest;
    final completer = Completer<dynamic>();
    _pending[id] = completer;
    send.send(<String, dynamic>{'id': id, 'action': action, ...?data});
    return completer.future;
  }

  @override
  Future<void> load(
      {required String modelId, required String directory}) async {
    await _request('load', {'modelId': modelId, 'directory': directory});
  }

  @override
  Future<String> decode(Float32List samples) async {
    final result = await _request('decode', {'samples': samples});
    return result is String ? result.trim() : '';
  }

  @override
  Future<void> release() async {
    if (_closed || _sendPort == null) return;
    await _request('release');
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closing = true;
    try {
      if (_sendPort != null) {
        // shutdown frees the recognizer before the worker closes its port.
        await _request('shutdown');
      }
    } catch (_) {
      // The isolate may already have failed. The native object is owned by it.
    } finally {
      _failPending(StateError('voice worker closed'));
      // A normal shutdown exits naturally after `_freeRecognizer`. If the
      // worker failed before becoming ready, killing the startup isolate is
      // safe because no recognizer has been created there yet.
      if (_sendPort == null && _starting != null) {
        _isolate?.kill(priority: Isolate.immediate);
      }
      await _subscription?.cancel();
      _receivePort?.close();
      _isolate = null;
      _sendPort = null;
      _closed = true;
      _closing = false;
    }
  }
}

class VoiceWorkerException implements Exception {
  VoiceWorkerException(this.message, this.stack);
  final String message;
  final String stack;

  @override
  String toString() => message;
}

class _WorkerBootstrap {
  const _WorkerBootstrap(this.parent);
  final SendPort parent;
}

@pragma('vm:entry-point')
Future<void> _voiceWorkerMain(_WorkerBootstrap bootstrap) async {
  final receive = ReceivePort();
  bootstrap.parent.send(receive.sendPort);
  final runtime = _WorkerRuntime(bootstrap.parent, receive);
  Future<void> queue = Future<void>.value();
  receive.listen((message) {
    queue = queue.then((_) => runtime.handle(message));
  });
}

class _WorkerRuntime {
  _WorkerRuntime(this.parent, this.receive);

  final SendPort parent;
  final ReceivePort receive;
  sherpa.OfflineRecognizer? recognizer;
  String? modelId;
  String? directory;
  bool bindingsReady = false;

  Future<void> handle(dynamic message) async {
    if (message is! Map) return;
    final id = message['id'];
    if (id is! int) return;
    try {
      final action = message['action'];
      final result = switch (action) {
        'load' =>
          await _load('${message['modelId']}', '${message['directory']}'),
        'decode' => _decode(message['samples']),
        'release' => _release(),
        'shutdown' => _shutdown(),
        _ => throw StateError('unknown voice worker action: $action'),
      };
      parent.send({'id': id, 'ok': true, 'result': result});
    } catch (error, stack) {
      parent.send({
        'id': id,
        'ok': false,
        'error': '$error',
        'stack': '$stack',
      });
    }
  }

  Future<Object?> _load(String nextId, String nextDirectory) async {
    if (recognizer != null && modelId == nextId && directory == nextDirectory) {
      return null;
    }
    _freeRecognizer();
    if (!bindingsReady) {
      await sherpa.initBindingsAsync();
      bindingsReady = true;
    }
    recognizer = sherpa.OfflineRecognizer(
      _config(nextId, nextDirectory),
    );
    modelId = nextId;
    directory = nextDirectory;
    return null;
  }

  String _decode(dynamic rawSamples) {
    final current = recognizer;
    if (current == null) throw StateError('voice recognizer is not loaded');
    final values = rawSamples is Float32List
        ? rawSamples
        : Float32List.fromList(List<double>.from(rawSamples as List));
    if (values.isEmpty) return '';
    final stream = current.createStream();
    try {
      stream.acceptWaveform(samples: values, sampleRate: 16000);
      current.decode(stream);
      return current.getResult(stream).text.trim();
    } finally {
      stream.free();
    }
  }

  Object? _release() {
    _freeRecognizer();
    return null;
  }

  void _freeRecognizer() {
    recognizer?.free();
    recognizer = null;
    modelId = null;
    directory = null;
  }

  Object? _shutdown() {
    _freeRecognizer();
    receive.close();
    return null;
  }

  sherpa.OfflineRecognizerConfig _config(String id, String dir) {
    final tokens =
        id == 'whisper-tiny-en' ? '$dir/tiny.en-tokens.txt' : '$dir/tokens.txt';
    final base = sherpa.OfflineModelConfig(
      tokens: tokens,
      numThreads: 2,
      debug: false,
      modelType: id == 'whisper-tiny-en' ? 'whisper' : '',
      senseVoice: id == 'sensevoice'
          ? sherpa.OfflineSenseVoiceModelConfig(
              model: '$dir/model.int8.onnx', language: 'auto')
          : const sherpa.OfflineSenseVoiceModelConfig(),
      zipformerCtc: id == 'zipformer-zh'
          ? sherpa.OfflineZipformerCtcModelConfig(model: '$dir/model.int8.onnx')
          : const sherpa.OfflineZipformerCtcModelConfig(),
      fireRedAsrCtc: id == 'firered-zh-en'
          ? sherpa.OfflineFireRedAsrCtcModelConfig(
              model: '$dir/model.int8.onnx')
          : const sherpa.OfflineFireRedAsrCtcModelConfig(),
      whisper: id == 'whisper-tiny-en'
          ? sherpa.OfflineWhisperModelConfig(
              encoder: '$dir/tiny.en-encoder.int8.onnx',
              decoder: '$dir/tiny.en-decoder.int8.onnx')
          : const sherpa.OfflineWhisperModelConfig(),
      qwen3Asr: id == 'qwen3-asr-06b'
          ? sherpa.OfflineQwen3AsrModelConfig(
              convFrontend: '$dir/conv_frontend.onnx',
              encoder: '$dir/encoder.int8.onnx',
              decoder: '$dir/decoder.int8.onnx',
              tokenizer: '$dir/tokenizer/tokenizer.json')
          : const sherpa.OfflineQwen3AsrModelConfig(),
      funasrNano: id == 'fun-asr-nano'
          ? sherpa.OfflineFunAsrNanoModelConfig(
              encoderAdaptor: '$dir/encoder_adaptor.int8.onnx',
              llm: '$dir/llm.int8.onnx',
              embedding: '$dir/embedding.int8.onnx',
              tokenizer: '$dir/Qwen3-0.6B/tokenizer.json')
          : const sherpa.OfflineFunAsrNanoModelConfig(),
    );
    return sherpa.OfflineRecognizerConfig(model: base);
  }
}
