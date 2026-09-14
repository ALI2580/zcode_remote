import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/voice_input.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import 'package:zcode_remote/voice/voice_transcriber.dart';

import 'fake_workspace.dart';

class _PreviewRecorder extends VoiceTranscriber {
  void Function(String)? partial;
  @override
  Future<void> start({void Function(String)? onPartial}) async {
    partial = onPartial;
  }

  @override
  Future<String> stop() async => '';
  @override
  Future<void> cancel() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  for (final draft in const [
    'Keep draft',
    'Keep draft\nSecond line\nThird line\nFourth line\nFifth line\nSixth line'
  ]) {
    testWidgets(
        'review: recording preview and cancel fit a landscape keyboard (${draft.contains('\n') ? 'multiline' : 'single line'})',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(844, 390);
      tester.view.viewInsets = const FakeViewPadding(bottom: 220);
      addTearDown(tester.view.reset);
      final preferences = ClientPreferences();
      await preferences.setLanguage('en');
      await preferences.setTextScale(1.4);
      final bridge = FakeBridge();
      final store = ComposerStore();
      final composer = store.obtain(
          transport: bridge.conversationTransport,
          deviceId: 'review',
          workspaceKey: 'workspace',
          sessionId: 'task');
      final subscription = await bridge.conversationTransport.subscribe('task');
      composer.bind(subscription.state);
      await composer.loadOptions();
      composer.input.text = draft;
      final recorder = _PreviewRecorder();
      final voice =
          VoiceInputController(composer: composer, transcriber: recorder);
      try {
        await tester.pumpWidget(ZcodeRemoteApp(
            preferences: preferences,
            home: Scaffold(
                body: Column(children: [
              const SizedBox(height: 48, child: Text('Task header')),
              const Expanded(child: SizedBox.expand()),
              ComposerBar(controller: composer, voiceInput: voice),
            ]))));
        await tester.pumpAndSettle();
        await voice.start();
        recorder.partial
            ?.call('A real controller preview while the keyboard is open.');
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final cancel = find.byKey(const ValueKey('composer-voice-cancel'));
        expect(cancel, findsOneWidget);
        expect(tester.getRect(cancel).bottom, lessThanOrEqualTo(170));
        await tester.tap(cancel);
        await tester.pumpAndSettle();
        expect(voice.phase, VoiceInputPhase.idle);
        expect(composer.input.text, draft);
        expect(bridge.conversationTransport.sent, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        voice.dispose();
        await subscription.dispose();
        store.dispose();
        preferences.dispose();
      }
    });
  }
}
