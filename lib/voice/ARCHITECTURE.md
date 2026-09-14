# Voice Module Architecture (F1)

## Overview

Offline speech-to-text using sherpa-onnx models. Pipeline:
1. Audio capture (16kHz PCM mono) via `record` package
2. Inference via a resident worker isolate owning `sherpa_onnx` OfflineRecognizer
3. Result → Composer draft (scoped by device/workspace/session)

## File Structure

```
lib/voice/
├── voice_models.dart           # Model catalog (6 models, verified URLs)
├── voice_model_events.dart     # ChangeNotifier singleton for store updates
├── voice_model_store.dart      # Conditional import barrel
├── voice_model_store_stub.dart # Stub for testing/unsupported platforms
├── voice_model_store_native.dart # Full store (download/enable/disable/delete)
├── voice_transcriber.dart         # Platform-neutral transcription contract
├── voice_transcriber_sherpa.dart  # record + worker client implementation
├── voice_transcriber_worker.dart  # isolate-owned FFI bindings/recognizer
└── voice_errors.dart              # typed failure categories for UI recovery
```

## Model Catalog

| ID | Name | Languages | Files |
|----|------|-----------|-------|
| sensevoice | SenseVoice Small | 中/英/粤/日/韩 | model.int8.onnx, tokens.txt |
| zipformer-zh | Zipformer CTC | 中文 | model.int8.onnx, tokens.txt |
| firered-zh-en | FireRed ASR | 中/英 | model.int8.onnx, tokens.txt |
| whisper-tiny-en | Whisper Tiny | 英语 | tiny.en-encoder.int8.onnx, decoder, tokens |
| qwen3-asr-06b | Qwen3-ASR 0.6B | 多语种 | conv_frontend, encoder, decoder, tokenizer |
| fun-asr-nano | Fun-ASR Nano | 中/英/日 | encoder_adaptor, llm, embedding, tokenizer |

## Data Flow

```
[User taps mic]
    → VoiceTranscriber.start()
    → Check store.enabledModelId() → has model
    → Check recorder.hasPermission()
    → Worker load(model id + directory), reusing the resident recognizer
    → Start AudioRecorder(16kHz, PCM16, mono)
    → Stream audio chunks → accumulate samples
    → Timer 1400ms → serial worker decode (newest snapshot wins) → partial callback
[User stops]
    → VoiceTranscriber.stop()
    → Wait for any preview decode → final worker decode
    → Return full text
    → Clear samples; keep the selected model resident for warm reuse
```

## Scope Isolation (F1.4 requirement)

- Recording session binds to the device/workspace/session at start
- Late recognition results write to the bound session's draft only
- Session/device/workspace switch during recording → cancel recording
- Process interruption → recording auto-stops, no auto-send
- Each start/stop/cancel carries an operation generation. Cancellation clears
  UI ownership immediately; late partials/finals are discarded before draft
  insertion, including same-scope restarts and ABA scope changes.
- The worker serializes load/decode/release. FFI pointers never cross isolates.
  It owns one selected model at a time, frees it on model change and graceful
  transcriber disposal, and keeps it resident between recordings to avoid
  repeated model allocation. A cancelled decode may finish in the worker, but
  its generation is ignored and cannot update the composer.
- Preview decode requests are serialized and coalesced. `stop` waits for the
  in-flight preview before final decode, so preview busy cannot erase the final
  result.

## Dependencies Required (F1.2 blocker)

| Package | Purpose | Status |
|---------|---------|--------|
| archive ^4.0.0 | BZip2+Tar model extraction | Blocked: Developer Mode |
| record | Audio capture | Added to the current app |
| sherpa_onnx | Inference engine | Added to the current app |

Model storage uses the existing Android `voiceModelsRoot` MethodChannel. The
recognition contract is injectable, so state-level scope tests use a fake while
the product uses `SherpaVoiceTranscriber`.

## Test Coverage

- voice_models_test.dart: 3 tests (catalog integrity, lookup, unique IDs)
- state voice tests cover same-scope restart partial isolation and cancelled
  pending-start replacement ownership.
- VoiceModelStore stub: enabledModelId returns null (no model)

## Failure and recovery

`VoiceTranscriberException` classifies missing/disabled models, corrupt model
files, storage failures, microphone permission denial, cancellation, busy
recognition and worker failures. The composer keeps the error visible with a
retry action. Model-related failures expose the existing model manager, whose
manager explicitly distinguishes not downloaded, downloaded but not enabled,
corrupt local content and unavailable storage; repair is always user-triggered.
Permission denial offers retry using
the record plugin's existing permission flow; no new platform channel is
invented. Recognition never sends the draft automatically.
