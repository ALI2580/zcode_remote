import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:record/record.dart';
import 'package:zcode_remote/ui/voice_model_manager.dart';
import 'package:zcode_remote/voice/voice_errors.dart';
import 'package:zcode_remote/voice/voice_model_store_native.dart';
import 'package:zcode_remote/voice/voice_models.dart';
import 'package:zcode_remote/voice/voice_transcriber_sherpa.dart';
import 'package:zcode_remote/voice/voice_transcriber_worker.dart';

import 'voice_known_audio_test.dart' show decodePcm16MonoWave;

const _enabled = bool.fromEnvironment('VOICE_RESPONSIVENESS_REVIEW');
const _download = bool.fromEnvironment('VOICE_REVIEW_DOWNLOAD_MODEL');

class _KnownPcmRecorder implements VoiceAudioRecorder {
  _KnownPcmRecorder(Float32List samples) {
    final bytes = ByteData(samples.length * 2);
    for (var i = 0; i < samples.length; i++) {
      bytes.setInt16(i * 2, (samples[i] * 32767).round(), Endian.little);
    }
    pcm = bytes.buffer.asUint8List();
  }
  late final Uint8List pcm;
  final controller = StreamController<Uint8List>();
  @override
  Future<bool> hasPermission() async => true;
  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    scheduleMicrotask(() => controller.add(pcm));
    return controller.stream;
  }

  @override
  Future<void> stop() async {
    await controller.close();
  }

  @override
  Future<void> cancel() async {
    await controller.close();
  }

  @override
  Future<void> dispose() async {
    await controller.close();
  }
}

class _ObservedWorker implements VoiceInferenceWorker {
  final worker = SherpaVoiceWorker();
  Completer<void>? nextDecode;
  @override
  Future<void> load({required String modelId, required String directory}) =>
      worker.load(modelId: modelId, directory: directory);
  @override
  Future<String> decode(Float32List samples) {
    nextDecode?.complete();
    nextDecode = null;
    return worker.decode(samples);
  }

  @override
  Future<void> release() => worker.release();
  @override
  Future<void> close() => worker.close();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('review: real model cold and warm inference leaves UI responsive',
      (tester) async {
    final environment = await const MethodChannel('zcode_remote/attachments')
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa');
    final store = VoiceModelStore();
    final model = voiceModelById('whisper-tiny-en');
    if (!await store.isDownloaded(model) && _download) {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: ListView(children: [
          VoiceModelManager(models: [model]),
        ])),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Download'));
      final downloadTimer = Stopwatch()..start();
      while (!await store.isDownloaded(model) &&
          downloadTimer.elapsed < const Duration(minutes: 6)) {
        await tester.pump(const Duration(milliseconds: 200));
        if (find.text('Retry').evaluate().isNotEmpty) {
          fail(
              'Model manager reported a download failure; inspect the device.');
        }
      }
    }
    expect(await store.isDownloaded(model), isTrue,
        reason: 'The model benchmark requires a downloaded QA model.');
    final previousModel = await store.enabledModelId();
    await store.setEnabled(model);
    final audio =
        await rootBundle.load('integration_test/fixtures/known_audio.wav');
    final samples = decodePcm16MonoWave(audio);
    // A fresh store keeps the cold sample honest: setEnabled above must not
    // prewarm the verification cache used by the first measured inference.
    final observedWorker = _ObservedWorker();
    final transcriber = SherpaVoiceTranscriber(
      store: VoiceModelStore(),
      worker: observedWorker,
      recorderFactory: () => _KnownPcmRecorder(samples),
    );
    final tapCount = ValueNotifier<int>(0);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: tapCount,
          builder: (context, count, child) => Center(
            child: TextButton(
              key: const ValueKey('review-responsive-button'),
              onPressed: () => tapCount.value++,
              child: Text('UI actions: $count'),
            ),
          ),
        ),
      ),
    ));

    try {
      for (final phase in ['cold', 'warm']) {
        final stopwatch = Stopwatch()..start();
        var previousTick = 0;
        var maxTimerGap = 0;
        var ticks = 0;
        var frames = 0;
        var maxBuildMicros = 0;
        var maxRasterMicros = 0;
        void timings(List<FrameTiming> values) {
          for (final value in values) {
            frames++;
            if (value.buildDuration.inMicroseconds > maxBuildMicros) {
              maxBuildMicros = value.buildDuration.inMicroseconds;
            }
            if (value.rasterDuration.inMicroseconds > maxRasterMicros) {
              maxRasterMicros = value.rasterDuration.inMicroseconds;
            }
          }
        }

        WidgetsBinding.instance.addTimingsCallback(timings);
        final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
          final current = stopwatch.elapsedMilliseconds;
          final gap = current - previousTick;
          if (gap > maxTimerGap) maxTimerGap = gap;
          previousTick = current;
          ticks++;
        });
        var completed = false;
        String? text;
        Object? error;
        final inference = transcriber.transcribeSamples(samples).then((value) {
          text = value;
        }, onError: (Object value) {
          error = value;
        }).whenComplete(() => completed = true);
        var actionsDuringInference = 0;
        try {
          while (!completed && stopwatch.elapsed < const Duration(minutes: 2)) {
            await tester.pump(const Duration(milliseconds: 20));
            if (!completed) {
              await tester
                  .tap(find.byKey(const ValueKey('review-responsive-button')));
              actionsDuringInference++;
            }
          }
          await inference.timeout(const Duration(seconds: 5));
          final finalGap = stopwatch.elapsedMilliseconds - previousTick;
          if (finalGap > maxTimerGap) maxTimerGap = finalGap;
          debugPrint('VOICE_REVIEW ${jsonEncode({
                'phase': phase,
                'model': model.id,
                'device': environment?['packageName'],
                'elapsedMs': stopwatch.elapsedMilliseconds,
                'timerTicks': ticks,
                'maxTimerGapMs': maxTimerGap,
                'uiActionsWhilePending': actionsDuringInference,
                'frames': frames,
                'maxBuildMicros': maxBuildMicros,
                'maxRasterMicros': maxRasterMicros,
                'knownAudioMatched':
                    text?.toLowerCase().contains('known') ?? false,
                'failureType': error?.runtimeType.toString(),
              })}');
          expect(error, isNull);
          expect(text?.toLowerCase(), contains('known'));
          expect(actionsDuringInference, greaterThan(0));
          expect(maxTimerGap, lessThan(750),
              reason: 'A multi-second native inference must not stall the UI.');
          expect(tester.takeException(), isNull);
        } finally {
          timer.cancel();
          WidgetsBinding.instance.removeTimingsCallback(timings);
        }
      }
      // Actual Android sherpa inference driven by a known PCM stream. This
      // deliberately does not claim to validate the physical microphone.
      var preview = '';
      final previewTimer = Stopwatch()..start();
      await transcriber.start(onPartial: (value) => preview = value);
      var previewUiActions = 0;
      while (preview.isEmpty &&
          previewTimer.elapsed < const Duration(seconds: 10)) {
        await tester.pump(const Duration(milliseconds: 20));
        await tester
            .tap(find.byKey(const ValueKey('review-responsive-button')));
        previewUiActions++;
      }
      expect(preview.toLowerCase(), contains('known'));
      final stopTimer = Stopwatch()..start();
      final stoppedText = await transcriber.stop();
      expect(stoppedText.toLowerCase(), contains('known'));
      expect(transcriber.isRecording, isFalse);
      debugPrint('VOICE_REVIEW ${jsonEncode({
            'phase': 'preview-and-stop',
            'audioSource': 'known PCM fixture, not microphone',
            'previewMs': previewTimer.elapsedMilliseconds -
                stopTimer.elapsedMilliseconds,
            'stopMs': stopTimer.elapsedMilliseconds,
            'previewUiActions': previewUiActions,
            'previewMatched': true,
            'finalMatched': true,
          })}');

      final decodeStarted = Completer<void>();
      observedWorker.nextDecode = decodeStarted;
      final cancelledRun = transcriber.transcribeSamples(samples).then<Object>(
            (value) => value,
            onError: (Object error) => error,
          );
      final cancelDeadline = Stopwatch()..start();
      while (!decodeStarted.isCompleted &&
          cancelDeadline.elapsed < const Duration(seconds: 5)) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      expect(decodeStarted.isCompleted, isTrue);
      await tester.pump(const Duration(milliseconds: 20));
      final cancelTimer = Stopwatch()..start();
      await transcriber.cancel();
      final cancelMs = cancelTimer.elapsedMilliseconds;
      final cancelledResult = await cancelledRun;
      expect(
          cancelledResult,
          isA<VoiceTranscriberException>().having(
              (error) => error.kind, 'kind', VoiceFailureKind.cancelled));
      expect(cancelMs, lessThan(250));
      debugPrint('VOICE_REVIEW ${jsonEncode({
            'phase': 'cancel-after-decode-dispatched',
            'cancelMs': cancelMs,
            'lateTextRejected': true,
          })}');
    } finally {
      await transcriber.dispose();
      if (previousModel == null) {
        await store.disable(model);
      } else {
        await store.setEnabled(voiceModelById(previousModel));
      }
      await tester.pumpWidget(const SizedBox.shrink());
      tapCount.dispose();
    }
  }, skip: !_enabled, timeout: const Timeout(Duration(minutes: 12)));
}
