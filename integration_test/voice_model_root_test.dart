import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/voice/voice_model_store_native.dart';
import 'package:zcode_remote/voice/voice_models.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('voice models use the native per-app files root',
      (tester) async {
    final environment = await const MethodChannel('zcode_remote/attachments')
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa',
        reason:
            'Run only with ZCODE_ANDROID_QA=true; never touch production data.');

    final root = await const MethodChannel('zcode_remote/platform')
        .invokeMethod<String>('voiceModelsRoot');
    expect(root, isNotNull);
    expect(root, isNotEmpty);
    expect(root, contains('com.zcoderemote.zcode_remote.qa'));
    expect(root, anyOf(contains('/Android/data/'), contains('/data/user/0/')));

    final store = VoiceModelStore();
    final model = voiceModels.first;
    final dir = await store.directory(model);
    expect(dir.path, startsWith('$root/voice-models'));
    await dir.create(recursive: true);
    expect(await dir.exists(), isTrue);
    expect(await store.isDownloaded(model), isFalse);

    await dir.delete(recursive: true);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
