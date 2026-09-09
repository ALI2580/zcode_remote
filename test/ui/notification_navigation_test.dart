import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/notification_platform.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/home_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'warm notification tap schedules navigation even while Flutter is idle',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidTaskNotifications.channel,
        (call) async {
      if (call.method == 'capabilities') {
        return {'allowed': false, 'promotedSupported': false};
      }
      return null;
    });
    final preferences = ClientPreferences();
    await preferences.setLanguage('zh');
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: HomePage(
            store: DeviceStore(requireEncryption: false),
            preferences: preferences)));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    await messenger.handlePlatformMessage(
        AndroidTaskNotifications.channel.name,
        const StandardMethodCodec().encodeMethodCall(MethodCall(
            'onTap',
            jsonEncode({
              'deviceId': 'removed-device',
              'workspaceKey': 'workspace',
              'sessionId': 'task',
              'title': '测试任务',
            }))),
        (_) {});
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(find.text('对应设备不可用，请重新添加连接链接'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    messenger.setMockMethodCallHandler(AndroidTaskNotifications.channel, null);
    preferences.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
