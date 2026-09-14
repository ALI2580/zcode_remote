import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/update/install_apk.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android install handoff opens the system installer',
      (tester) async {
    await tester.pumpWidget(const ZcodeRemoteApp(
        home: Scaffold(body: Center(child: Text('F2.3 安装交接验证')))));
    await tester.pumpAndSettle();

    const channel = MethodChannel('zcode_remote/attachments');
    final environment =
        await channel.invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa',
        reason:
            'Run only with ZCODE_ANDROID_QA=true; never use production data.');

    const missingPath =
        '/data/data/com.zcoderemote.zcode_remote.qa/cache/missing.apk';
    expect(await installApk(missingPath), isFalse);

    const apkPath =
        '/data/data/com.zcoderemote.zcode_remote.qa/cache/zcode-qa-install.apk';
    expect(await installApk(apkPath), isTrue,
        reason: 'FileProvider-backed install intent should launch.');
    await Future<void>.delayed(const Duration(seconds: 3));
  }, timeout: const Timeout(Duration(minutes: 3)));
}
