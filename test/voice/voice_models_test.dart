import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/voice/voice_models.dart';

void main() {
  group('VoiceModels', () {
    test('catalog has models with required fields', () {
      expect(voiceModels, isNotEmpty);
      for (final model in voiceModels) {
        expect(model.id, isNotEmpty, reason: '${model.id} missing id');
        expect(model.name, isNotEmpty, reason: '${model.id} missing name');
        expect(model.archiveUrl, startsWith('https://'),
            reason: '${model.id} invalid archive URL');
        expect(model.files, isNotEmpty, reason: '${model.id} missing files');
        expect(model.mainFile, isNotEmpty,
            reason: '${model.id} missing mainFile');
      }
    });

    test('voiceModelById returns correct model', () {
      final model = voiceModelById('sensevoice');
      expect(model.name, 'SenseVoice Small');
      expect(model.files, contains('model.int8.onnx'));
    });

    test('all model IDs are unique', () {
      final ids = voiceModels.map((m) => m.id).toSet();
      expect(ids.length, voiceModels.length);
    });
  });
}
