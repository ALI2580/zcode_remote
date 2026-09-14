import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/voice_input.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import 'package:zcode_remote/ui/voice_input_button.dart';
import 'package:zcode_remote/voice/voice_model_store_native.dart';
import 'package:zcode_remote/voice/voice_models.dart';

import '../test/ui/fake_workspace.dart';

const _enabled = bool.fromEnvironment('VOICE_NATIVE_COMPOSER_REVIEW');
const _modelId = 'whisper-tiny-en';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native Composer voice inserts draft text and revokes old scope',
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
            'VOICE_NATIVE_COMPOSER_REVIEW skipped; pass --dart-define=VOICE_NATIVE_COMPOSER_REVIEW=true to enable.');
        return;
      }

      final cacheDirectory = environment?['cacheDirectory'] as String?;
      expect(cacheDirectory, isNotNull,
          reason: 'The .qa environment must expose its cache directory.');
      final configuredRunId =
          const String.fromEnvironment('VOICE_NATIVE_COMPOSER_RUN_ID');
      final runId = configuredRunId.trim().isEmpty
          ? 'run-${DateTime.now().millisecondsSinceEpoch}'
          : configuredRunId.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final runDirectory =
          Directory('${cacheDirectory!}/native-composer-voice/$runId');
      expect(await runDirectory.exists(), isFalse,
          reason: 'Use a new cache run directory for every native review.');
      await runDirectory.create(recursive: true);

      final model = voiceModelById(_modelId);
      final modelStore = VoiceModelStore();
      expect(
        await modelStore.isDownloaded(model),
        isTrue,
        reason: 'The native Composer review requires the existing QA model; '
            'it never downloads a model automatically.',
      );
      final previousModel = await modelStore.enabledModelId();
      await modelStore.setEnabled(model);

      final preferences = ClientPreferences();
      await preferences.load();
      final originalTheme = preferences.theme;
      final originalLanguage = preferences.language;
      final originalTextScale = preferences.textScale;
      final originalUiFontSize = preferences.uiFontSizePx;

      final bridge = FakeBridge();
      final composers = ComposerStore();
      final composer = composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'native-composer-review',
        workspaceKey: 'workspace-a',
        sessionId: 'task-a',
      );
      final subscription =
          await bridge.conversationTransport.subscribe('task-a');
      composer.bind(subscription.state);
      await composer.loadOptions();
      const originalDraft = '保留原有草稿';
      composer.input.text = originalDraft;

      final secondComposer = composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'native-composer-review',
        workspaceKey: 'workspace-b',
        sessionId: 'task-b',
      );
      final secondSubscription =
          await bridge.conversationTransport.subscribe('task-b');
      secondComposer.bind(secondSubscription.state);
      await secondComposer.loadOptions();
      const nextDraft = '新工作区草稿';

      final boundary = GlobalKey();
      final manifestEntries = <Map<String, String>>[];

      Future<void> writeManifest() async {
        final file = File('${runDirectory.path}/manifest.tsv');
        final rows = <String>[
          'frame\tevidence\tcondition\tvoicePhase\tpartialNonEmpty\t'
              'draftLength\tfinalTextLength\tnonEmptyResult\tsource\t'
              'transportSent\tunverified',
          for (final entry in manifestEntries)
            [
              entry['frame'],
              entry['evidence'],
              entry['condition'],
              entry['voicePhase'],
              entry['partialNonEmpty'],
              entry['draftLength'],
              entry['finalTextLength'],
              entry['nonEmptyResult'],
              entry['source'],
              entry['transportSent'],
              entry['unverified'],
            ].join('\t'),
        ];
        await file.writeAsString('${rows.join('\n')}\n');
      }

      String phaseName(VoiceInputPhase phase) => phase.name;

      VoiceInputController currentVoice() {
        final finder = find.byType(VoiceInputButton);
        expect(finder, findsOneWidget,
            reason: 'ComposerBar must expose its real VoiceInputButton.');
        return tester.widget<VoiceInputButton>(finder).voice;
      }

      Future<void> pumpUntil(
        bool Function() condition,
        String description, {
        Duration timeout = const Duration(seconds: 30),
      }) async {
        final watch = Stopwatch()..start();
        while (!condition()) {
          if (watch.elapsed >= timeout) {
            fail('Timed out waiting for $description.');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> capture(
        String frame,
        String condition, {
        required VoiceInputController voice,
        int? finalTextLength,
      }) async {
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            expect(data, isNotNull);
            final path = '${runDirectory.path}/$frame.png';
            await File(path).writeAsBytes(data!.buffer.asUint8List());
            final entry = <String, String>{
              'frame': frame,
              'evidence': path,
              'condition': condition,
              'voicePhase': phaseName(voice.phase),
              'partialNonEmpty': '${voice.partial.isNotEmpty}',
              'draftLength': '${voice.composer.input.text.length}',
              'finalTextLength': '${finalTextLength ?? 0}',
              'nonEmptyResult': '${(finalTextLength ?? 0) > 0}',
              'source':
                  'native ComposerBar with default SherpaVoiceTranscriber',
              'transportSent': '${bridge.conversationTransport.sent.length}',
              'unverified':
                  'no speech accuracy claim; no official native screenshot comparison',
            };
            manifestEntries.add(entry);
            await writeManifest();
            debugPrint('NATIVE_COMPOSER_IMAGE ${jsonEncode(entry)}');
          } finally {
            image.dispose();
          }
        });
      }

      Widget composerSurface(ComposerController controller) => RepaintBoundary(
            key: boundary,
            child: ZcodeRemoteApp(
              preferences: preferences,
              home: Scaffold(
                body: Column(
                  children: [
                    const Expanded(
                        child: Center(child: Text('Composer voice QA'))),
                    ComposerBar(controller: controller),
                  ],
                ),
              ),
            ),
          );

      final phaseSamples = <String>{};
      var partialSeen = false;
      void sample(VoiceInputController voice) {
        phaseSamples.add(phaseName(voice.phase));
        partialSeen = partialSeen || voice.partial.isNotEmpty;
      }

      Future<void> waitForPhase(VoiceInputPhase target, String description) {
        return pumpUntil(() {
          final voice = currentVoice();
          sample(voice);
          return voice.phase == target;
        }, description);
      }

      Future<int> keepRecordingFor(Duration duration) async {
        final watch = Stopwatch()..start();
        while (watch.elapsed < duration) {
          sample(currentVoice());
          await tester.pump(const Duration(milliseconds: 100));
        }
        return watch.elapsedMilliseconds;
      }

      try {
        await preferences.setLanguage('zh');
        await preferences.setTheme(ThemeMode.dark);
        await preferences.setTextScale(1);
        await tester.pumpWidget(composerSurface(composer));
        await tester.pump(const Duration(milliseconds: 100));

        final voiceButton = find.byKey(const ValueKey('composer-voice'));
        expect(voiceButton, findsOneWidget);
        await tester.tap(voiceButton);
        await waitForPhase(VoiceInputPhase.recording, 'cold recording');
        final coldRecordingMs =
            await keepRecordingFor(const Duration(milliseconds: 3000));
        final recordingVoice = currentVoice();
        sample(recordingVoice);
        await capture(
            'recording', 'real microphone recording phase ${coldRecordingMs}ms',
            voice: recordingVoice);
        expect(find.byKey(const ValueKey('voice-status')), findsOneWidget,
            reason: 'A real recording must expose its visible status area.');
        expect(recordingVoice.partial, isNotEmpty,
            reason:
                'The native Sherpa run must produce a real partial preview.');
        expect(find.byKey(const ValueKey('voice-preview')), findsOneWidget,
            reason: 'The real model partial must be visible in the Composer.');
        expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('voice-preview')))
                .data,
            recordingVoice.partial,
            reason: 'The preview must display the current model partial.');
        expect(
            find.byKey(const ValueKey('composer-voice-cancel')), findsOneWidget,
            reason:
                'A real recording must expose a visible cancellation action.');

        await tester.tap(voiceButton);
        await tester.pump(const Duration(milliseconds: 20));
        final recognizingVoice = currentVoice();
        sample(recognizingVoice);
        final recognizingObserved = phaseSamples.contains('recognizing');
        await waitForPhase(
            VoiceInputPhase.idle, 'final recognition completion');
        final finalTextLength =
            mathMaxZero(composer.input.text.length - originalDraft.length);
        expect(composer.input.text.startsWith(originalDraft), isTrue,
            reason:
                'Final recognition must preserve the existing draft prefix.');
        await capture('stop', 'stop and final recognition completed',
            voice: currentVoice(), finalTextLength: finalTextLength);

        final draftBeforeCancel = composer.input.text;
        await tester.tap(voiceButton);
        await waitForPhase(VoiceInputPhase.recording, 'second recording');
        final cancelRecordingMs =
            await keepRecordingFor(const Duration(milliseconds: 600));
        final cancelVoice = currentVoice();
        sample(cancelVoice);
        expect(
            find.byKey(const ValueKey('composer-voice-cancel')), findsOneWidget,
            reason: 'The second recording must expose visible cancellation.');
        await tester.tap(find.byKey(const ValueKey('composer-voice-cancel')));
        await tester.pump(const Duration(milliseconds: 1200));
        expect(cancelVoice.phase, VoiceInputPhase.idle);
        expect(composer.input.text, draftBeforeCancel,
            reason: 'Cancelling a real recording must preserve the draft.');
        await capture('cancel', 'second real recording cancelled',
            voice: cancelVoice, finalTextLength: 0);

        final draftBeforeScopeChange = composer.input.text;
        await tester.tap(voiceButton);
        await waitForPhase(VoiceInputPhase.recording, 'scope-change recording');
        final scopeRecordingMs =
            await keepRecordingFor(const Duration(milliseconds: 600));
        final oldVoice = currentVoice();
        sample(oldVoice);
        secondComposer.input.text = nextDraft;
        await tester.pumpWidget(composerSurface(secondComposer));
        await tester.pump(const Duration(milliseconds: 100));
        await pumpUntil(() => currentVoice().phase == VoiceInputPhase.idle,
            'new ComposerBar idle after source change',
            timeout: const Duration(seconds: 10));
        await tester.pump(const Duration(milliseconds: 1200));
        expect(composer.input.text, draftBeforeScopeChange,
            reason:
                'The old voice run must not alter the old draft after scope change.');
        expect(secondComposer.input.text, nextDraft,
            reason: 'A changed workspace must retain its own draft.');
        expect(currentVoice().phase, VoiceInputPhase.idle);
        await capture('changed-source', 'ComposerController workspace changed',
            voice: currentVoice(), finalTextLength: 0);

        expect(bridge.conversationTransport.sent, isEmpty,
            reason: 'Voice review must never send a conversation message.');
        expect(manifestEntries.length, 4);
        debugPrint('NATIVE_COMPOSER_SUMMARY ${jsonEncode({
              'model': _modelId,
              'phaseSamples': phaseSamples.toList()..sort(),
              'recognizingObserved': recognizingObserved,
              'partialNonEmpty': partialSeen,
              'finalTextLength': finalTextLength,
              'draftPrefixPreserved':
                  composer.input.text.startsWith(originalDraft),
              'cancelDraftPreserved': composer.input.text == draftBeforeCancel,
              'changedSourceDraftPreserved':
                  secondComposer.input.text == nextDraft,
              'recordingDurationsMs': {
                'cold': coldRecordingMs,
                'cancel': cancelRecordingMs,
                'changedSource': scopeRecordingMs,
              },
              'transportSent': bridge.conversationTransport.sent.length,
              'audioSource':
                  'native AudioRecorder microphone stream via default SherpaVoiceTranscriber',
              'syntheticTransport': true,
              'transcriptionAccuracyClaim': false,
              'path': '${runDirectory.path}/manifest.tsv',
            })}');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(milliseconds: 100));
        await subscription.dispose();
        await secondSubscription.dispose();
        composers.dispose();
        await preferences.setTheme(originalTheme);
        await preferences.setLanguage(originalLanguage);
        await preferences.setUiFontSizePx(originalUiFontSize);
        await preferences.setTextScale(originalTextScale);
        await preferences.settled;
        preferences.dispose();
        if (previousModel == null) {
          await modelStore.disable(model);
        } else {
          await modelStore.setEnabled(voiceModelById(previousModel));
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

int mathMaxZero(int value) => value < 0 ? 0 : value;
