import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:record/record.dart';
import 'package:zcode_remote/voice/voice_model_store_native.dart';
import 'package:zcode_remote/voice/voice_models.dart';
import 'package:zcode_remote/voice/voice_transcriber_sherpa.dart';

const _enabled = bool.fromEnvironment('VOICE_NATIVE_MIC_REVIEW');
const _recordingMs = int.fromEnvironment(
  'VOICE_NATIVE_MIC_DURATION_MS',
  defaultValue: 2200,
);

/// Observes the PCM stream while delegating every operation to record's real
/// AudioRecorder. It never inserts, replaces, or synthesizes audio samples.
class _ObservedNativeRecorder implements VoiceAudioRecorder {
  _ObservedNativeRecorder()
      : _delegate = RecordVoiceAudioRecorder(AudioRecorder());

  final RecordVoiceAudioRecorder _delegate;
  int chunks = 0;
  int byteCount = 0;
  int sampleCount = 0;
  double _sumSquares = 0;
  double peak = 0;
  bool streamStarted = false;
  bool stopCalled = false;
  bool cancelCalled = false;
  bool disposeCalled = false;

  double get rms =>
      sampleCount == 0 ? 0 : math.sqrt(_sumSquares / sampleCount.toDouble());

  bool get silent => sampleCount > 0 && rms < .005;

  @override
  Future<bool> hasPermission() => _delegate.hasPermission();

  @override
  Future<Stream<Uint8List>> startStream(RecordConfig config) async {
    final source = await _delegate.startStream(config);
    streamStarted = true;
    return source.map(_observe);
  }

  Uint8List _observe(Uint8List bytes) {
    chunks++;
    byteCount += bytes.length;
    for (var offset = 0; offset + 1 < bytes.length; offset += 2) {
      final raw = bytes[offset] | (bytes[offset + 1] << 8);
      final signed = raw >= 0x8000 ? raw - 0x10000 : raw;
      final value = signed / 32768.0;
      sampleCount++;
      _sumSquares += value * value;
      final magnitude = value.abs();
      if (magnitude > peak) peak = magnitude;
    }
    return bytes;
  }

  @override
  Future<void> stop() {
    stopCalled = true;
    return _delegate.stop();
  }

  @override
  Future<void> cancel() {
    cancelCalled = true;
    return _delegate.cancel();
  }

  @override
  Future<void> dispose() {
    disposeCalled = true;
    return _delegate.dispose();
  }
}

class _CycleResult {
  const _CycleResult({
    required this.phase,
    required this.startMs,
    required this.stopMs,
    required this.cancelMs,
    required this.lateObservationMs,
    required this.samples,
    required this.bytes,
    required this.chunks,
    required this.rms,
    required this.peak,
    required this.silent,
    required this.partialCallbacks,
    required this.finalTextLength,
    required this.frames,
    required this.maxBuildMicros,
    required this.maxRasterMicros,
    required this.uiPumps,
    required this.maxTimerGapMs,
  });

  final String phase;
  final int startMs;
  final int stopMs;
  final int cancelMs;
  final int lateObservationMs;
  final int samples;
  final int bytes;
  final int chunks;
  final double rms;
  final double peak;
  final bool silent;
  final int partialCallbacks;
  final int finalTextLength;
  final int frames;
  final int maxBuildMicros;
  final int maxRasterMicros;
  final int uiPumps;
  final int maxTimerGapMs;

  Map<String, dynamic> toJson() => {
        'phase': phase,
        'startMs': startMs,
        'stopMs': stopMs,
        'cancelMs': cancelMs,
        'lateObservationMs': lateObservationMs,
        'sampleCount': samples,
        'byteCount': bytes,
        'chunkCount': chunks,
        'rms': rms,
        'peak': peak,
        'silent': silent,
        'partialCallbacks': partialCallbacks,
        'finalTextLength': finalTextLength,
        'frames': frames,
        'maxBuildMicros': maxBuildMicros,
        'maxRasterMicros': maxRasterMicros,
        'uiPumps': uiPumps,
        'maxTimerGapMs': maxTimerGapMs,
        // No transcription accuracy claim is made from microphone audio.
        'transcriptionAccuracyClaim': false,
      };
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native mic recorder and Sherpa transcriber cold/warm/stop/cancel review',
    (tester) async {
      final environment = await const MethodChannel('zcode_remote/attachments')
          .invokeMapMethod<String, dynamic>('environment');
      expect(
        environment?['packageName'],
        'com.zcoderemote.zcode_remote.qa',
        reason: 'Run only against the isolated .qa package.',
      );
      if (!_enabled) {
        debugPrint(
            'VOICE_NATIVE_MIC_REVIEW skipped; pass --dart-define=VOICE_NATIVE_MIC_REVIEW=true to enable.');
        return;
      }

      final cacheDirectory = environment?['cacheDirectory'] as String?;
      final model = voiceModelById('whisper-tiny-en');
      final store = VoiceModelStore();
      expect(
        await store.isDownloaded(model),
        isTrue,
        reason: 'The native microphone review requires the existing QA model; '
            'it never downloads a model automatically.',
      );
      final previousModel = await store.enabledModelId();
      await store.setEnabled(model);

      final recorders = <_ObservedNativeRecorder>[];
      final transcriber = SherpaVoiceTranscriber(
        store: VoiceModelStore(),
        recorderFactory: () {
          final recorder = _ObservedNativeRecorder();
          recorders.add(recorder);
          return recorder;
        },
      );
      final status = ValueNotifier<String>('ready');
      final boundary = GlobalKey();

      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: MaterialApp(
            home: Scaffold(
              appBar: AppBar(title: const Text('Voice native mic QA')),
              body: Center(
                child: ValueListenableBuilder<String>(
                  valueListenable: status,
                  builder: (context, value, child) => Text(
                    value,
                    key: const ValueKey('voice-native-status'),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      Future<void> capture(String name) async {
        if (cacheDirectory == null || cacheDirectory.isEmpty) return;
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            if (data == null) return;
            final path = '$cacheDirectory/$name.png';
            await File(path).writeAsBytes(data.buffer.asUint8List());
            debugPrint('VOICE_NATIVE_UI ${jsonEncode({
                  'phase': name,
                  'path': path,
                  'renderer': 'native Flutter surface',
                  'syntheticTransport': true,
                  'audioSource': 'native AudioRecorder microphone stream',
                })}');
          } finally {
            image.dispose();
          }
        });
      }

      Future<_CycleResult> runCycle(String phase, {required bool stop}) async {
        final probeStart = recorders.length;
        final watch = Stopwatch()..start();
        final frameWatch = <ui.FrameTiming>[];
        var maxBuildMicros = 0;
        var maxRasterMicros = 0;
        var uiPumps = 0;
        var previousTick = 0;
        var maxTimerGapMs = 0;
        var partialCallbacks = 0;
        var partialText = '';
        void onTimings(List<ui.FrameTiming> values) {
          frameWatch.addAll(values);
          for (final value in values) {
            maxBuildMicros =
                math.max(maxBuildMicros, value.buildDuration.inMicroseconds);
            maxRasterMicros =
                math.max(maxRasterMicros, value.rasterDuration.inMicroseconds);
          }
        }

        WidgetsBinding.instance.addTimingsCallback(onTimings);
        final timer = Timer.periodic(const Duration(milliseconds: 20), (_) {
          final current = watch.elapsedMilliseconds;
          final gap = current - previousTick;
          if (gap > maxTimerGapMs) maxTimerGapMs = gap;
          previousTick = current;
        });
        final started = Completer<void>();
        Object? startError;
        StackTrace? startStack;
        status.value = '$phase: starting recorder and model';
        unawaited(transcriber.start(onPartial: (value) {
          partialCallbacks++;
          partialText = value;
          status.value = '$phase: partial result available';
        }).then<void>(
          (_) {
            if (!started.isCompleted) started.complete();
          },
          onError: (Object error, StackTrace stack) {
            startError = error;
            startStack = stack;
            // Complete a normal signal and rethrow after the await below has
            // attached its handler, avoiding an unhandled fast-start failure.
            if (!started.isCompleted) started.complete();
          },
        ));
        try {
          while (!started.isCompleted &&
              watch.elapsed < const Duration(minutes: 2)) {
            await tester.pump(const Duration(milliseconds: 20));
            uiPumps++;
          }
          if (!started.isCompleted) {
            await transcriber.cancel();
            throw TimeoutException('Native recorder start timed out.');
          }
          await started.future;
          if (startError != null) {
            Error.throwWithStackTrace(
                startError!, startStack ?? StackTrace.current);
          }
          final startMs = watch.elapsedMilliseconds;
          status.value = '$phase: recording';
          while (watch.elapsedMilliseconds < startMs + _recordingMs) {
            await tester.pump(const Duration(milliseconds: 20));
            uiPumps++;
          }

          final stopWatch = Stopwatch()..start();
          var stopMs = 0;
          var cancelMs = 0;
          var lateObservationMs = 0;
          String finalText = '';
          if (stop) {
            finalText = await transcriber.stop();
            stopMs = stopWatch.elapsedMilliseconds;
          } else {
            final beforeCancel = partialCallbacks;
            await transcriber.cancel();
            cancelMs = stopWatch.elapsedMilliseconds;
            final lateWatch = Stopwatch()..start();
            await tester.pump(const Duration(milliseconds: 1200));
            lateObservationMs = lateWatch.elapsedMilliseconds;
            expect(
              partialCallbacks,
              beforeCancel,
              reason: 'Cancelled microphone work must not call back later.',
            );
          }
          final probe = recorders
              .skip(probeStart)
              .cast<_ObservedNativeRecorder?>()
              .firstWhere((value) => value!.streamStarted, orElse: () => null);
          expect(probe, isNotNull,
              reason: '$phase did not start a real AudioRecorder stream.');
          final observed = probe!;
          expect(observed.sampleCount, greaterThan(0),
              reason: '$phase produced no PCM samples from the microphone.');
          expect(observed.disposeCalled, isTrue,
              reason: '$phase did not release the recorder session.');
          if (stop) {
            expect(observed.stopCalled, isTrue,
                reason: '$phase did not use the stop path.');
            expect(transcriber.isRecording, isFalse);
          } else {
            expect(observed.cancelCalled, isTrue,
                reason: '$phase did not use the cancel path.');
            expect(transcriber.isRecording, isFalse);
          }
          final result = _CycleResult(
            phase: phase,
            startMs: startMs,
            stopMs: stopMs,
            cancelMs: cancelMs,
            lateObservationMs: lateObservationMs,
            samples: observed.sampleCount,
            bytes: observed.byteCount,
            chunks: observed.chunks,
            rms: observed.rms,
            peak: observed.peak,
            silent: observed.silent,
            partialCallbacks: partialCallbacks,
            finalTextLength: finalText.length,
            frames: frameWatch.length,
            maxBuildMicros: maxBuildMicros,
            maxRasterMicros: maxRasterMicros,
            uiPumps: uiPumps,
            maxTimerGapMs: maxTimerGapMs,
          );
          debugPrint('VOICE_NATIVE_MIC ${jsonEncode({
                ...result.toJson(),
                'model': model.id,
                'devicePackage': environment?['packageName'],
                'partialNonEmpty': partialText.isNotEmpty,
              })}');
          status.value = '$phase: ${result.samples} samples, '
              'rms=${result.rms.toStringAsFixed(4)}';
          await tester.pump();
          return result;
        } finally {
          timer.cancel();
          WidgetsBinding.instance.removeTimingsCallback(onTimings);
        }
      }

      try {
        final cold = await runCycle('cold', stop: true);
        await capture('voice-native-cold-stop');
        final warm = await runCycle('warm', stop: true);
        await capture('voice-native-warm-stop');
        final cancelled = await runCycle('cancel', stop: false);
        await capture('voice-native-cancel');
        expect(cold.samples, greaterThan(0));
        expect(warm.samples, greaterThan(0));
        expect(cancelled.samples, greaterThan(0));
        debugPrint('VOICE_NATIVE_MIC_SUMMARY ${jsonEncode({
              'model': model.id,
              'cold': cold.toJson(),
              'warm': warm.toJson(),
              'cancel': cancelled.toJson(),
              'audioSource': 'native AudioRecorder microphone stream',
              'syntheticTransport': true,
              'transcriptionAccuracyClaim': false,
              'silentRecordingIsLimitation':
                  cold.silent || warm.silent || cancelled.silent,
            })}');
      } finally {
        await transcriber.dispose();
        if (previousModel == null) {
          await store.disable(model);
        } else {
          await store.setEnabled(voiceModelById(previousModel));
        }
        status.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
      }
    },
    timeout: const Timeout(Duration(minutes: 12)),
  );
}
