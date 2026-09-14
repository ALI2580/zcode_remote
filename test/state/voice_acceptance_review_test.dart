import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/voice_input.dart';
import 'package:zcode_remote/voice/voice_transcriber.dart';

import '../ui/fake_workspace.dart';

class _DelayedVoice extends VoiceTranscriber {
  final starts = <Completer<void>>[];
  final stops = <Completer<String>>[];
  final partials = <void Function(String)?>[];
  int cancelCalls = 0;

  @override
  Future<void> start({void Function(String)? onPartial}) {
    partials.add(onPartial);
    final result = Completer<void>();
    starts.add(result);
    return result.future;
  }

  @override
  Future<String> stop() {
    final result = Completer<String>();
    stops.add(result);
    return result.future;
  }

  @override
  Future<void> cancel() async { cancelCalls++; }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ComposerStore store;
  late ComposerController composer;
  late _DelayedVoice transcriber;
  late VoiceInputController voice;

  setUp(() async {
    store = ComposerStore();
    final bridge = FakeBridge();
    composer = store.obtain(
      transport: bridge.conversationTransport,
      deviceId: 'review-device',
      workspaceKey: 'review-workspace',
      sessionId: 'A',
    );
    final state = ConversationState();
    state.applyFrame({
      'toSeq': 1,
      'payload': {'kind': 'snapshot', 'snapshot': composerSnapshotFixture},
    }, onGap: () => fail('unexpected gap'));
    composer.bind(state);
    await composer.loadOptions();
    transcriber = _DelayedVoice();
    voice = VoiceInputController(composer: composer, transcriber: transcriber);
  });

  tearDown(() {
    voice.dispose();
    store.dispose();
  });

  test('review: cancel final recognition on same draft rejects late text', () async {
    final starting = voice.start();
    transcriber.starts.single.complete();
    await starting;
    composer.input.text = 'retained draft';
    final stopping = voice.stop();
    await voice.cancel();
    transcriber.stops.single.complete('cancelled transcript');
    await stopping;
    expect(composer.input.text, 'retained draft');
    expect(voice.phase, VoiceInputPhase.idle);
  });

  test('review: cancelled pending start cannot resurrect recording', () async {
    final starting = voice.start();
    await voice.cancel();
    transcriber.starts.single.complete();
    await starting;
    expect(voice.phase, VoiceInputPhase.idle);
  });

  test('review: stale partial and stop cannot overwrite a restarted run', () async {
    final firstStart = voice.start();
    transcriber.starts.single.complete();
    await firstStart;
    final firstStop = voice.stop();
    await voice.cancel();
    final secondStart = voice.start();
    transcriber.starts.last.complete();
    await secondStart;
    transcriber.partials.last?.call('new preview');
    transcriber.partials.first?.call('old preview');
    final preview = voice.partial;
    transcriber.stops.first.complete('old final');
    await firstStop;
    expect(preview, 'new preview');
    expect(voice.phase, VoiceInputPhase.recording);
    expect(composer.input.text, isEmpty);
  });

  test('review: old pending start cannot cancel the newer recording', () async {
    final oldStart = voice.start();
    await voice.cancel();
    final currentStart = voice.start();
    transcriber.starts.last.complete();
    await currentStart;
    transcriber.starts.first.complete();
    await oldStart;
    expect(transcriber.cancelCalls, 1,
        reason: 'Only explicit cancellation owns the recorder cleanup.');
    expect(voice.phase, VoiceInputPhase.recording);
  });
}
