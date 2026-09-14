import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:record/record.dart';
import 'package:zcode_remote/voice/voice_errors.dart';
import 'package:zcode_remote/voice/voice_download_state.dart';
import 'package:zcode_remote/voice/voice_model_store_native.dart';
import 'package:zcode_remote/voice/voice_models.dart';
import 'package:zcode_remote/voice/voice_transcriber_sherpa.dart';
import 'package:zcode_remote/voice/voice_transcriber_worker.dart';

class _Store implements VoiceModelStore {
  @override
  final progress = <String, double>{};

  @override
  final downloadStates = <String, VoiceDownloadState>{};

  @override
  Future<Directory> directory(VoiceModelInfo model) async =>
      Directory.systemTemp;

  @override
  Future<bool> isDownloaded(VoiceModelInfo model) async => true;

  @override
  Future<String?> enabledModelId() async => 'sensevoice';

  @override
  Future<void> setEnabled(VoiceModelInfo model) async {}

  @override
  Future<void> disable(VoiceModelInfo model) async {}

  @override
  Future<void> download(VoiceModelInfo model) async {}

  @override
  void cancelDownload(VoiceModelInfo model) {}

  @override
  Future<void> delete(VoiceModelInfo model) async {}
}

class _DownloadedNotEnabledStore extends _Store {
  @override
  Future<bool> isDownloaded(VoiceModelInfo model) async =>
      model.id == 'sensevoice';

  @override
  Future<String?> enabledModelId() async => null;
}

class _Worker implements VoiceInferenceWorker {
  final loaded = <String>[];
  final created = <String>[];
  String? current;
  int decodeCount = 0;
  Completer<String>? decodeGate;

  @override
  Future<void> load(
      {required String modelId, required String directory}) async {
    final key = '$modelId:$directory';
    loaded.add(key);
    if (current != key) {
      current = key;
      created.add(key);
    }
  }

  @override
  Future<String> decode(Float32List samples) async {
    decodeCount++;
    final gate = decodeGate;
    if (gate != null) {
      decodeGate = null;
      return gate.future;
    }
    return 'recognized';
  }

  @override
  Future<void> release() async {}

  @override
  Future<void> close() async {}
}

class _Recorder implements VoiceAudioRecorder {
  _Recorder(this.startGate);

  final Completer<Stream<Uint8List>> startGate;
  int cancelCalls = 0;
  bool disposed = false;

  @override
  Future<bool> hasPermission() async => true;

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) =>
      startGate.future;

  @override
  Future<void> stop() async {}

  @override
  Future<void> cancel() async {
    cancelCalls++;
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('worker client reuses the selected model and rejects decode overlap',
      () async {
    final worker = _Worker();
    final transcriber = SherpaVoiceTranscriber(
      store: _Store(),
      worker: worker,
    );
    addTearDown(transcriber.dispose);
    final samples = Float32List.fromList([0.1, 0.2]);

    final gate = Completer<String>();
    worker.decodeGate = gate;
    final first = transcriber.transcribeSamples(samples);
    for (var i = 0; i < 5 && worker.decodeCount == 0; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    await expectLater(
      transcriber.transcribeSamples(samples),
      throwsA(isA<VoiceTranscriberException>()
          .having((error) => error.kind, 'kind', VoiceFailureKind.busy)),
    );
    gate.complete('first');
    expect(await first, 'first');
    expect(await transcriber.transcribeSamples(samples), 'recognized');
    expect(worker.loaded, hasLength(2));
    expect(worker.loaded.first, worker.loaded.last);
    expect(worker.created, hasLength(1));
    expect(worker.decodeCount, 2);
  });

  test('cancelled native start closes only its recorder before restart',
      () async {
    final workers = _Worker();
    final recorders = <_Recorder>[];
    final transcriber = SherpaVoiceTranscriber(
      store: _Store(),
      worker: workers,
      recorderFactory: () {
        final recorder = _Recorder(Completer<Stream<Uint8List>>());
        recorders.add(recorder);
        return recorder;
      },
    );
    addTearDown(transcriber.dispose);

    final first = transcriber.start();
    await Future<void>.delayed(Duration.zero);
    await transcriber.cancel();
    final second = transcriber.start();
    await Future<void>.delayed(Duration.zero);
    recorders[0].startGate.complete(const Stream<Uint8List>.empty());
    await first;
    recorders[1].startGate.complete(const Stream<Uint8List>.empty());
    await second;

    expect(recorders, hasLength(2));
    expect(recorders[0].cancelCalls, 1);
    expect(recorders[0].disposed, isTrue);
    expect(transcriber.isRecording, isTrue);
  });

  test('start reports downloaded but disabled model at the input entry',
      () async {
    final transcriber = SherpaVoiceTranscriber(
      store: _DownloadedNotEnabledStore(),
      worker: _Worker(),
      recorderFactory: () => _Recorder(Completer<Stream<Uint8List>>()),
    );
    addTearDown(transcriber.dispose);

    await expectLater(
      transcriber.start(),
      throwsA(isA<VoiceTranscriberException>().having(
        (error) => error.message,
        'message',
        contains('已下载语音模型但尚未启用'),
      )),
    );
  });
}
