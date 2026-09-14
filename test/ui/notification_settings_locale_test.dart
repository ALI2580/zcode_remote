import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_notification_controller.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/notification_settings_page.dart';

import '../notifications/fake_notification_platform.dart';

void main() {
  testWidgets('notification settings renders its static surface in English',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = ClientPreferences();
    await preferences.setLanguage('en');
    final controller =
        TaskNotificationController(platform: FakeNotificationPlatform());
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: NotificationSettingsPage(controller: controller),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Task notifications'), findsOneWidget);
      expect(find.text('Task progress notifications'), findsOneWidget);
      expect(find.text('Notification permission'), findsOneWidget);
      expect(find.text('Allowed'), findsOneWidget);
      expect(find.text('任务通知与上岛'), findsNothing);
      expect(find.text('通知权限'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
      await controller.settled;
      preferences.dispose();
    }
  });
}
