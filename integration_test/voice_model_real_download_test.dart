import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/voice/voice_model_store_native.dart';
import 'package:zcode_remote/voice/voice_models.dart';

const realDownload = bool.fromEnvironment('VOICE_REAL_DOWNLOAD');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real voice model download enables and unloads cleanly',
      (tester) async {
    final environment = await const MethodChannel('zcode_remote/attachments')
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa',
        reason: 'Run only with ZCODE_ANDROID_QA=true; never use .dev data.');
    if (!realDownload) {
      return;
    }

    // Whisper Tiny is the smallest catalog archive (about 118 MB compressed)
    // and only needs three extracted files, so it is safe for a one-off
    // isolated .qa download. We deliberately keep the model on device after
    // the run for later F1.3/F1.5 work.
    final model = voiceModelById('whisper-tiny-en');
    final store = VoiceModelStore();
    if (!await store.isDownloaded(model)) {
      final download = store.download(model);
      await tester.pump();
      await download;
    }

    expect(await store.isDownloaded(model), isTrue);
    expect(store.progress[model.id], anyOf(isNull, 1));
    final dir = await store.directory(model);
    final sizes = <String, int>{
      for (final relative in model.files)
        relative: await File('${dir.path}/$relative').length(),
    };
    debugPrint('Real voice model ${model.id} file bytes: $sizes');
    for (final relative in model.files) {
      final file = File('${dir.path}/$relative');
      expect(await file.exists(), isTrue, reason: '$relative must exist');
      expect(await file.length(), greaterThan(0), reason: '$relative is empty');
    }

    expect(await store.enabledModelId(), anyOf(isNull, model.id));
    await store.setEnabled(model);
    expect(await store.enabledModelId(), model.id);
    await store.disable(model);
    expect(await store.enabledModelId(), isNull);
    expect(await store.isDownloaded(model), isTrue);
  }, timeout: const Timeout(Duration(minutes: 20)));
}
