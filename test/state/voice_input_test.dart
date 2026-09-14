import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/voice_input.dart';
import 'package:zcode_remote/voice/voice_transcriber.dart';

import '../ui/fake_workspace.dart';

void snapshot(ConversationState state, Map<String, dynamic> patch) {
  state.applyFrame({
    'toSeq': state.seq + 1,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {...composerSnapshotFixture, ...patch}
    }
  }, onGap: () => fail('unexpected gap'));
}

class FakeTranscriber extends VoiceTranscriber {
  final startGate = Completer<void>();
  final stopGate = Completer<String>();
  bool cancelled = false;
  bool disposed = false;
  bool settled = false;
  void Function(String)? onPartial;

  @override
  Future<void> start({void Function(String text)? onPartial}) async {
    this.onPartial = onPartial;
    await startGate.future;
  }

  @override
  Future<String> stop() => stopGate.future;

  @override
  Future<void> cancel() async {
    cancelled = true;
    if (!settled) {
      settled = true;
      if (!startGate.isCompleted) startGate.complete();
      if (!stopGate.isCompleted) stopGate.complete('late result');
    }
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    if (!stopGate.isCompleted) stopGate.complete('late result');
  }
}

class DeniedTranscriber extends VoiceTranscriber {
  @override
  Future<void> start({void Function(String text)? onPartial}) async {
    throw StateError('没有麦克风权限');
  }
}

class RestartableTranscriber extends VoiceTranscriber {
  final starts = <Completer<void>>[];
  final partials = <void Function(String)?>[];
  int cancelCalls = 0;

  @override
  Future<void> start({void Function(String text)? onPartial}) {
    final gate = Completer<void>();
    starts.add(gate);
    partials.add(onPartial);
    return gate.future;
  }

  @override
  Future<String> stop() async => '';

  @override
  Future<void> cancel() async {
    cancelCalls++;
    final pending = starts.where((gate) => !gate.isCompleted);
    for (final gate in pending) {
      gate.complete();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ComposerStore store;
  late FakeBridge bridge;
  late ComposerController controller;
  late ConversationState state;

  setUp(() async {
    store = ComposerStore();
    bridge = FakeBridge();
    controller = store.obtain(
      transport: bridge.conversationTransport,
      deviceId: 'A',
      workspaceKey: 'workspace',
      sessionId: 'task',
    );
    state = ConversationState();
    snapshot(state, {});
    controller.bind(state);
    await controller.loadOptions();
  });

  tearDown(() => store.dispose());

  test('recognition result is inserted into the initiating draft only',
      () async {
    final transcriber = FakeTranscriber();
    final voice =
        VoiceInputController(composer: controller, transcriber: transcriber);
    final starting = voice.start();
    await Future<void>.delayed(Duration.zero);
    expect(voice.phase, VoiceInputPhase.requesting);
    transcriber.startGate.complete();
    await starting;
    expect(voice.phase, VoiceInputPhase.recording);

    transcriber.onPartial?.call('你好');
    expect(voice.partial, '你好');
    transcriber.stopGate.complete('你好世界');
    await voice.stop();

    expect(controller.input.text, '你好世界');
    expect(bridge.conversationTransport.sent, isEmpty);
    expect(voice.phase, VoiceInputPhase.idle);
    expect(voice.partial, isEmpty);
  });

  test('scope switch cancels and discards a late recognition result', () async {
    final transcriber = FakeTranscriber();
    final voice =
        VoiceInputController(composer: controller, transcriber: transcriber);
    final starting = voice.start();
    await Future<void>.delayed(Duration.zero);
    transcriber.startGate.complete();
    await starting;

    final stopping = voice.stop();
    await Future<void>.delayed(Duration.zero);
    expect(voice.phase, VoiceInputPhase.recognizing);

    controller.sessionId = 'next-task';
    // ignore: invalid_use_of_protected_member
    controller.notifyListeners();
    await Future<void>.delayed(Duration.zero);
    await stopping;

    expect(transcriber.cancelled, isTrue);
    expect(controller.input.text, isEmpty);
    expect(bridge.conversationTransport.sent, isEmpty);
    expect(voice.phase, VoiceInputPhase.idle);
  });

  test('recording errors are visible and leave the draft unchanged', () async {
    final voice = VoiceInputController(
      composer: controller,
      transcriber: DeniedTranscriber(),
    );
    await voice.start();
    expect(voice.phase, VoiceInputPhase.error);
    expect(voice.error, '没有麦克风权限');
    expect(controller.input.text, isEmpty);
    expect(bridge.conversationTransport.sent, isEmpty);
  });

  test('dispose cancels a pending recognition and never writes late text',
      () async {
    final transcriber = FakeTranscriber();
    final voice =
        VoiceInputController(composer: controller, transcriber: transcriber);
    final starting = voice.start();
    await Future<void>.delayed(Duration.zero);
    transcriber.startGate.complete();
    await starting;

    final stopping = voice.stop();
    await Future<void>.delayed(Duration.zero);
    voice.dispose();
    await stopping;

    expect(transcriber.disposed, isTrue);
    expect(controller.input.text, isEmpty);
    expect(bridge.conversationTransport.sent, isEmpty);
  });

  test('same-scope restart ignores the previous partial callback', () async {
    final transcriber = RestartableTranscriber();
    final voice =
        VoiceInputController(composer: controller, transcriber: transcriber);
    final first = voice.start();
    await Future<void>.delayed(Duration.zero);
    transcriber.starts.first.complete();
    await first;
    await voice.cancel();

    final second = voice.start();
    await Future<void>.delayed(Duration.zero);
    transcriber.starts[1].complete();
    await second;
    transcriber.partials.first?.call('旧 partial');
    expect(voice.partial, isEmpty);
    transcriber.partials[1]?.call('新 partial');
    expect(voice.partial, '新 partial');
  });

  test('cancelled pending start cannot cancel its replacement run', () async {
    final transcriber = RestartableTranscriber();
    final voice =
        VoiceInputController(composer: controller, transcriber: transcriber);
    final first = voice.start();
    await Future<void>.delayed(Duration.zero);
    await voice.cancel();
    await first;
    expect(transcriber.cancelCalls, 1);

    final second = voice.start();
    await Future<void>.delayed(Duration.zero);
    transcriber.starts[1].complete();
    await second;
    expect(voice.phase, VoiceInputPhase.recording);
    expect(transcriber.cancelCalls, 1);
  });
}
