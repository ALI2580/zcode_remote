import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/notifications/notification_platform.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/state/credential_cipher.dart';
import 'package:zcode_remote/ui/app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Android Keystore and notification service integration',
      (tester) async {
    await tester.pumpWidget(const ZcodeRemoteApp(
        home: Scaffold(body: Center(child: Text('Android 系统集成验证')))));
    await tester.pumpAndSettle();
    const plain = 'synthetic-device-credential-for-native-test';
    final encrypted = await CredentialCipher.encrypt(plain);
    expect(encrypted, startsWith('enc:'));
    expect(encrypted, isNot(contains(plain)));
    expect(await CredentialCipher.decrypt(encrypted!), plain);
    expect(await CredentialCipher.encrypt(plain), isNot(encrypted));

    final platform = AndroidTaskNotifications();
    await platform.initialize((_) {}, () {});
    final capabilities = await platform.capabilities();
    expect(capabilities.supported, isTrue);
    final nativeInfo = await AndroidTaskNotifications.channel
        .invokeMapMethod<String, dynamic>('capabilities');
    debugPrint(
        'Android integration: SDK ${nativeInfo?['sdkInt']}, notifications allowed=${capabilities.allowed}');
    // The test never prompts for permissions or sends a desktop command.
    if (capabilities.allowed) {
      const target = TaskTarget(
          deviceId: 'synthetic-device-id',
          workspaceKey: 'synthetic-workspace',
          sessionId: 'synthetic-task',
          title: '系统集成验证');
      try {
        expect(
            await platform.showProgress(
                title: '测试任务进度',
                text: 'Android 系统集成验证',
                shortText: '测试中',
                target: target,
                allowStart: true),
            isTrue);
        bool visible = false;
        for (var attempt = 0; attempt < 30; attempt++) {
          final state = await AndroidTaskNotifications.channel
              .invokeMapMethod<String, dynamic>('capabilities');
          if (state?['progressVisible'] == true) {
            visible = true;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(visible, isTrue);
        debugPrint(
            'Android integration: foreground task notification verified');
        await SystemNavigator.pop();
        bool backgrounded = false;
        for (var attempt = 0; attempt < 30; attempt++) {
          final state = await AndroidTaskNotifications.channel
              .invokeMapMethod<String, dynamic>('capabilities');
          if (state?['foreground'] == false) {
            backgrounded = true;
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(backgrounded, isTrue);
        expect(
            await platform.showProgress(
                title: '测试任务继续运行',
                text: '后台更新验证',
                shortText: '测试中',
                target: target,
                allowStart: false),
            isTrue);
        debugPrint(
            'Android integration: root back retained engine and background updates');
      } finally {
        await platform.stopProgress();
      }
    }
    platform.dispose();
  });
}
