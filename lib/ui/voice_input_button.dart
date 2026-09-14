import 'package:flutter/material.dart';

import '../state/client_preferences.dart';
import '../state/voice_input.dart';
import '../voice/voice_errors.dart';
import 'theme.dart';

class VoiceInputButton extends StatelessWidget {
  const VoiceInputButton({
    super.key,
    required this.voice,
    this.onDone,
  });

  final VoiceInputController voice;
  final VoidCallback? onDone;

  Future<void> _toggle() async {
    switch (voice.phase) {
      case VoiceInputPhase.idle:
      case VoiceInputPhase.error:
        await voice.start();
      case VoiceInputPhase.recording:
        await voice.stop();
        onDone?.call();
      case VoiceInputPhase.recognizing:
      case VoiceInputPhase.requesting:
        await voice.cancel();
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: voice,
      builder: (context, _) {
        final ink = ZInk.of(Theme.of(context).colorScheme);
        final busy = voice.phase == VoiceInputPhase.requesting ||
            voice.phase == VoiceInputPhase.recognizing;
        final recording = voice.phase == VoiceInputPhase.recording;
        final english = Localizations.localeOf(context).languageCode != 'zh';
        final message = switch (voice.phase) {
          VoiceInputPhase.idle => uiText(context, '语音输入', 'Voice input'),
          VoiceInputPhase.requesting =>
            uiText(context, '准备语音输入…', 'Preparing voice input…'),
          VoiceInputPhase.recording =>
            uiText(context, '停止并识别', 'Stop and recognize'),
          VoiceInputPhase.recognizing =>
            uiText(context, '正在识别…', 'Recognizing…'),
          VoiceInputPhase.error =>
            voiceFailureMessage(voice.errorKind, english: english) ??
                voice.error ??
                uiText(context, '语音输入失败', 'Voice input failed'),
        };
        return Tooltip(
          message: message,
          child: Semantics(
            button: true,
            label: message,
            child: InkWell(
              key: const ValueKey('composer-voice'),
              onTap: _toggle,
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Center(
                  child: busy
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 1.5, color: ink.text),
                        )
                      : Icon(
                          recording ? Icons.stop : Icons.mic_none,
                          size: 16,
                          color: recording ? ink.warning : ink.text,
                        ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
