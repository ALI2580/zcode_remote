import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_notification_controller.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/notification_settings_page.dart';
import '../notifications/fake_notification_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });
  Future<void> gesture(WidgetTester tester, String method,
      [double? progress]) async {
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/backgesture',
      const StandardMethodCodec().encodeMethodCall(MethodCall(
          method,
          progress == null
              ? null
              : {
                  'touchOffset': [100.0, 300.0],
                  'progress': progress,
                  'swipeEdge': 0
                })),
      (_) {},
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'predictive back previews, cancels and commits the actual settings route',
      (tester) async {
    final controller =
        TaskNotificationController(platform: FakeNotificationPlatform());
    await tester.pumpWidget(ZcodeRemoteApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: Center(
                      child: TextButton(
                          child: const Text('打开系统设置'),
                          onPressed: () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => NotificationSettingsPage(
                                      controller: controller))))),
                ))));
    await tester.tap(find.text('打开系统设置'));
    await tester.pumpAndSettle();
    expect(find.text('任务通知与上岛'), findsOneWidget);
    final origin = tester.getTopLeft(find.text('任务通知与上岛'));
    await gesture(tester, 'startBackGesture', 0);
    await gesture(tester, 'updateBackGestureProgress', .4);
    expect(tester.getTopLeft(find.text('任务通知与上岛')).dx, greaterThan(origin.dx));
    await gesture(tester, 'cancelBackGesture');
    expect(find.text('任务通知与上岛'), findsOneWidget);
    await gesture(tester, 'startBackGesture', 0);
    await gesture(tester, 'updateBackGestureProgress', .6);
    await gesture(tester, 'commitBackGesture');
    expect(find.text('任务通知与上岛'), findsNothing);
    expect(find.text('打开系统设置'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
    await controller.settled;
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
