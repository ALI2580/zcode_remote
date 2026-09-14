import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/voice_input.dart';
import 'package:zcode_remote/ui/theme.dart';
import 'package:zcode_remote/ui/voice_input_button.dart';
import 'package:zcode_remote/voice/voice_transcriber.dart';

import 'fake_workspace.dart';

class _FakeTranscriber extends VoiceTranscriber {
  final startGate = Completer<void>();
  final stopGate = Completer<String>();

  @override
  Future<void> start({void Function(String text)? onPartial}) =>
      startGate.future;

  @override
  Future<String> stop() => stopGate.future;

  @override
  Future<void> cancel() async {
    if (!startGate.isCompleted) startGate.complete();
    if (!stopGate.isCompleted) stopGate.complete('late result');
  }

  @override
  Future<void> dispose() async {
    if (!startGate.isCompleted) startGate.complete();
    if (!stopGate.isCompleted) stopGate.complete('late result');
  }
}

void main() {
  testWidgets('voice button toggles recording, recognizes and shows errors',
      (tester) async {
    final bridge = FakeBridge();
    final store = ComposerStore();
    final controller = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace',
        sessionId: 'task');
    final state = ConversationState();
    state.applyFrame({
      'toSeq': 1,
      'payload': {
        'kind': 'snapshot',
        'snapshot': composerSnapshotFixture,
      },
    }, onGap: () {});
    controller.bind(state);
    await controller.loadOptions();
    final transcriber = _FakeTranscriber();
    final voice =
        VoiceInputController(composer: controller, transcriber: transcriber);
    addTearDown(voice.dispose);
    addTearDown(store.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: Center(
          child: VoiceInputButton(voice: voice),
        ),
      ),
    ));
    expect(find.byIcon(Icons.mic_none), findsOneWidget);

    final starting = voice.start();
    await tester.pump();
    expect(voice.phase, VoiceInputPhase.requesting);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    transcriber.startGate.complete();
    await starting;
    await tester.pump();
    expect(find.byIcon(Icons.stop), findsOneWidget);

    final stopping = voice.stop();
    await tester.pump();
    expect(voice.phase, VoiceInputPhase.recognizing);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    transcriber.stopGate.complete('语音草稿');
    await stopping;
    await tester.pump();
    expect(controller.input.text, '语音草稿');
    expect(find.byIcon(Icons.mic_none), findsOneWidget);
  });
}
