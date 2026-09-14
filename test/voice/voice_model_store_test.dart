import 'dart:io';
import 'dart:async';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/voice/voice_model_store_native.dart';
import 'package:zcode_remote/voice/voice_model_readiness_native.dart';
import 'package:zcode_remote/voice/voice_models.dart';

void main() {
  late Directory root;
  late VoiceModelInfo model;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    root = Directory.systemTemp.createTempSync('zcode-voice-store-');
    model = voiceModelById('sensevoice');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  List<int> archiveBytes({bool complete = true}) {
    final archive = Archive()
      ..add(ArchiveFile(
          '${model.directory}/model.int8.onnx', 16, List.filled(16, 1)));
    if (complete) {
      archive.add(
          ArchiveFile('${model.directory}/tokens.txt', 8, List.filled(8, 2)));
    }
    return BZip2Encoder().encode(TarEncoder().encode(archive));
  }

  test('download validates files then enable and delete manage state',
      () async {
    final bytes = archiveBytes();
    final store = VoiceModelStore(
      root: root,
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.value(bytes), 200,
            contentLength: bytes.length);
      }),
    );

    expect(await store.isDownloaded(model), isFalse);
    await store.download(model);
    expect(await store.isDownloaded(model), isTrue);
    expect(store.progress[model.id], 1);
    expect(await store.enabledModelId(), isNull);
    await store.setEnabled(model);
    expect(await store.enabledModelId(), model.id);
    await store.delete(model);
    expect(await store.isDownloaded(model), isFalse);
    expect(await store.enabledModelId(), isNull);
    expect(Directory('${root.path}/${model.id}').existsSync(), isFalse);
  });

  test('readiness distinguishes missing, downloaded, enabled and corrupt',
      () async {
    final bytes = archiveBytes();
    final store = VoiceModelStore(
      root: root,
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.value(bytes), 200,
            contentLength: bytes.length);
      }),
    );

    expect(await voiceModelAvailability(store, model),
        VoiceModelAvailability.notDownloaded);
    await store.download(model);
    expect(await voiceModelAvailability(store, model),
        VoiceModelAvailability.downloaded);
    await store.setEnabled(model);
    expect(await voiceModelAvailability(store, model),
        VoiceModelAvailability.enabled);
    await File('${root.path}/${model.id}/model.int8.onnx')
        .writeAsBytes(List.filled(16, 9));
    expect(await voiceModelAvailability(store, model),
        VoiceModelAvailability.corrupt);
  });

  test('incomplete archive leaves no usable model directory', () async {
    final bytes = archiveBytes(complete: false);
    final store = VoiceModelStore(
      root: root,
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.value(bytes), 200,
            contentLength: bytes.length);
      }),
    );

    await expectLater(store.download(model), throwsStateError);
    expect(await store.isDownloaded(model), isFalse);
    expect(Directory('${root.path}/${model.id}').existsSync(), isFalse);
    expect(File('${root.path}/${model.id}.download').existsSync(), isFalse);
  });

  test('corrupted archive is cleaned up', () async {
    final store = VoiceModelStore(
      root: root,
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.value(List.filled(64, 0)), 200,
            contentLength: 64);
      }),
    );

    try {
      await store.download(model);
      fail('corrupted archive should not succeed');
    } catch (_) {}
    expect(await store.isDownloaded(model), isFalse);
    expect(Directory('${root.path}/${model.id}').existsSync(), isFalse);
    expect(File('${root.path}/${model.id}.download').existsSync(), isFalse);
  });

  test('same-size file corruption is caught before enable', () async {
    final bytes = archiveBytes();
    final store = VoiceModelStore(
      root: root,
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.value(bytes), 200,
            contentLength: bytes.length);
      }),
    );

    await store.download(model);
    final modelFile = File('${root.path}/${model.id}/model.int8.onnx');
    await modelFile.writeAsBytes(List.filled(16, 9));
    expect(await store.isDownloaded(model), isTrue);
    await expectLater(store.setEnabled(model), throwsStateError);
    expect(await store.enabledModelId(), isNull);
  });

  test('truncated model file is not downloaded', () async {
    final bytes = archiveBytes();
    final store = VoiceModelStore(
      root: root,
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.value(bytes), 200,
            contentLength: bytes.length);
      }),
    );

    await store.download(model);
    final modelFile = File('${root.path}/${model.id}/model.int8.onnx');
    await modelFile.writeAsBytes(List.filled(8, 1));
    expect(await store.isDownloaded(model), isFalse);
    expect(await store.enabledModelId(), isNull);
  });

  test('http failure keeps progress unavailable', () async {
    final store = VoiceModelStore(
      root: root,
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(Stream.value('denied'.codeUnits), 403);
      }),
    );

    await expectLater(store.download(model), throwsStateError);
    expect(await store.isDownloaded(model), isFalse);
    expect(store.progress.containsKey(model.id), isFalse);
  });

  test('mid-download cancel leaves no usable model or temp archive', () async {
    final chunks = StreamController<List<int>>();
    final store = VoiceModelStore(
      root: root,
      client: MockClient.streaming((request, bodyStream) async {
        return http.StreamedResponse(chunks.stream, 200, contentLength: 1000);
      }),
    );
    final future = store.download(model);
    chunks.add(List.filled(10, 0));
    await Future<void>.delayed(Duration.zero);
    store.cancelDownload(model);
    await chunks.close();
    await expectLater(future, throwsStateError);
    expect(await store.isDownloaded(model), isFalse);
    expect(File('${root.path}/${model.id}.download').existsSync(), isFalse);
  });
}
