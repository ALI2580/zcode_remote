import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/voice_input.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import 'package:zcode_remote/voice/voice_transcriber.dart';

import 'fake_workspace.dart';

class _PreviewTranscriber extends VoiceTranscriber {
  Completer<void> startGate = Completer<void>();
  Completer<String> stopGate = Completer<String>();
  void Function(String)? onPartial;
  int cancelCalls = 0;

  @override
  Future<void> start({void Function(String text)? onPartial}) async {
    this.onPartial = onPartial;
    await startGate.future;
  }

  @override
  Future<String> stop() => stopGate.future;

  @override
  Future<void> cancel() async {
    cancelCalls++;
    if (!startGate.isCompleted) startGate.complete();
    if (!stopGate.isCompleted) stopGate.complete('');
  }

  @override
  Future<void> dispose() async {
    if (!startGate.isCompleted) startGate.complete();
    if (!stopGate.isCompleted) stopGate.complete('');
  }
}

void main() {
  testWidgets(
      'voice status renders real controller events and stays scoped across source changes',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final bridge = FakeBridge();
    final store = ComposerStore();
    final controller = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace-a',
        sessionId: 'task-a');
    final subscription = await bridge.conversationTransport.subscribe('task-a');
    controller.bind(subscription.state);
    await controller.loadOptions();
    controller.input.text = '保留原有草稿';

    final nextController = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace-b',
        sessionId: 'task-b');
    final nextSubscription =
        await bridge.conversationTransport.subscribe('task-b');
    nextController.bind(nextSubscription.state);
    await nextController.loadOptions();
    nextController.input.text = '新工作区草稿';

    final transcriber = _PreviewTranscriber();
    final voice =
        VoiceInputController(composer: controller, transcriber: transcriber);
    final nextTranscriber = _PreviewTranscriber();
    final nextVoice = VoiceInputController(
        composer: nextController, transcriber: nextTranscriber);
    final preferences = ClientPreferences();
    await preferences.load();
    final originalLanguage = preferences.language;
    final originalTheme = preferences.theme;
    final originalTextScale = preferences.textScale;

    Widget surface(
      ComposerController current,
      VoiceInputController currentVoice,
      double width,
    ) {
      return ZcodeRemoteApp(
        preferences: preferences,
        home: Scaffold(
          body: SizedBox(
            width: width,
            child: ComposerBar(controller: current, voiceInput: currentVoice),
          ),
        ),
      );
    }

    try {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(344, 820);
      addTearDown(tester.view.reset);
      await preferences.setLanguage('zh');
      await preferences.setTheme(ThemeMode.light);
      await preferences.setTextScale(1);
      await tester.pumpWidget(surface(controller, voice, 344));
      await tester.pumpAndSettle();

      final firstStart = voice.start();
      await tester.pump();
      expect(voice.phase, VoiceInputPhase.requesting);
      expect(find.byKey(const ValueKey('voice-status')), findsOneWidget);
      expect(find.text('正在准备语音输入…'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('composer-voice-cancel')), findsOneWidget);

      transcriber.startGate.complete();
      await firstStart;
      await tester.pump();
      expect(voice.phase, VoiceInputPhase.recording);
      expect(find.text('正在录音…'), findsOneWidget);

      transcriber.onPartial?.call('实时模型预览');
      await tester.pump();
      expect(find.byKey(const ValueKey('voice-preview')), findsOneWidget);
      expect(find.text('实时模型预览'), findsOneWidget);
      expect(controller.input.text, '保留原有草稿');
      expect(bridge.conversationTransport.sent, isEmpty);

      await preferences.setLanguage('en');
      await preferences.setTheme(ThemeMode.dark);
      await preferences.setTextScale(1.4);
      tester.view.physicalSize = const Size(390, 820);
      await tester.pumpWidget(surface(nextController, nextVoice, 390));
      await tester.pump();
      await tester.pump();
      expect(transcriber.cancelCalls, 1);
      expect(voice.phase, VoiceInputPhase.idle);
      expect(find.byKey(const ValueKey('voice-status')), findsNothing);
      expect(nextController.input.text, '新工作区草稿');

      final nextStart = nextVoice.start();
      await tester.pump();
      expect(find.text('Preparing voice input…'), findsOneWidget);
      nextTranscriber.startGate.complete();
      await nextStart;
      await tester.pump();
      nextTranscriber.onPartial?.call('new source preview');
      await tester.pump();
      expect(find.byKey(const ValueKey('voice-preview')), findsOneWidget);
      expect(find.text('new source preview'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('composer-voice-cancel')), findsOneWidget);
      tester.view.physicalSize = const Size(344, 820);
      await tester.pump();
      expect(tester.takeException(), isNull,
          reason: 'The busy status must remain readable at the narrow width.');

      final recognizing = nextVoice.stop();
      await tester.pump();
      expect(nextVoice.phase, VoiceInputPhase.recognizing);
      expect(find.text('Recognizing…'), findsOneWidget);
      expect(
          find.byKey(const ValueKey('composer-voice-cancel')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('composer-voice-cancel')));
      await recognizing;
      await tester.pump();
      expect(nextTranscriber.cancelCalls, 1);
      expect(nextVoice.phase, VoiceInputPhase.idle);
      expect(find.byKey(const ValueKey('voice-status')), findsNothing);
      expect(nextController.input.text, '新工作区草稿');
      expect(bridge.conversationTransport.sent, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      voice.dispose();
      nextVoice.dispose();
      await subscription.dispose();
      await nextSubscription.dispose();
      store.dispose();
      await preferences.setLanguage(originalLanguage);
      await preferences.setTheme(originalTheme);
      await preferences.setTextScale(originalTextScale);
      preferences.dispose();
    }
  });
}
