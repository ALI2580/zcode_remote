import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/voice/voice_model_store_native.dart';
import 'package:zcode_remote/voice/voice_models.dart';
import 'package:zcode_remote/voice/voice_transcriber_sherpa.dart';

const realAudio = bool.fromEnvironment('VOICE_REAL_AUDIO');

Float32List decodePcm16MonoWave(ByteData data) {
  void expectText(int offset, String value) {
    final text = String.fromCharCodes([
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
      data.getUint8(offset + 3),
    ]);
    if (text != value) throw FormatException('expected $value at $offset');
  }

  expectText(0, 'RIFF');
  expectText(8, 'WAVE');
  var offset = 12;
  int? audioFormat, channels, sampleRate, bitsPerSample;
  Uint8List? pcm;
  while (offset + 8 <= data.lengthInBytes) {
    final id = String.fromCharCodes([
      data.getUint8(offset),
      data.getUint8(offset + 1),
      data.getUint8(offset + 2),
      data.getUint8(offset + 3),
    ]);
    final size = data.getUint32(offset + 4, Endian.little);
    final body = offset + 8;
    if (id == 'fmt ') {
      audioFormat = data.getUint16(body, Endian.little);
      channels = data.getUint16(body + 2, Endian.little);
      sampleRate = data.getUint32(body + 4, Endian.little);
      bitsPerSample = data.getUint16(body + 14, Endian.little);
    } else if (id == 'data') {
      pcm = Uint8List.sublistView(
        data,
        body,
        body + size <= data.lengthInBytes ? body + size : data.lengthInBytes,
      );
    }
    offset = body + size + (size.isOdd ? 1 : 0);
  }
  if (audioFormat != 1 ||
      channels != 1 ||
      sampleRate != 16000 ||
      bitsPerSample != 16 ||
      pcm == null ||
      pcm.length.isOdd) {
    throw FormatException('expected 16 kHz mono PCM16 WAV');
  }
  final values = Float32List(pcm.length ~/ 2);
  final view = ByteData.sublistView(pcm);
  for (var i = 0; i < values.length; i++) {
    values[i] = view.getInt16(i * 2, Endian.little) / 32768.0;
  }
  return values;
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('known audio produces offline model inference', (tester) async {
    final environment = await const MethodChannel('zcode_remote/attachments')
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa',
        reason: 'Run only with ZCODE_ANDROID_QA=true; never use .dev data.');
    if (!realAudio) return;

    const asset = 'integration_test/fixtures/known_audio.wav';
    final bytes = (await rootBundle.load(asset)).buffer.asByteData();
    final samples = decodePcm16MonoWave(bytes);
    expect(samples.length, greaterThan(8000));

    final model = voiceModelById('whisper-tiny-en');
    final store = VoiceModelStore();
    if (!await store.isDownloaded(model)) {
      final download = store.download(model);
      await tester.pump();
      await download;
    }
    expect(await store.isDownloaded(model), isTrue);
    await store.setEnabled(model);

    final transcriber = SherpaVoiceTranscriber(store: store);
    final text = await transcriber.transcribeSamples(samples);
    await transcriber.dispose();
    await store.disable(model);
    debugPrint('Known-audio inference: "$text"');
    expect(text, isNotEmpty);
    expect(text.toLowerCase(), contains('known'));
  }, timeout: const Timeout(Duration(minutes: 20)));
}
