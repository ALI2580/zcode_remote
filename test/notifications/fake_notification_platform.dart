import 'dart:async';

import 'package:zcode_remote/notifications/notification_platform.dart';
import 'package:zcode_remote/notifications/task_target.dart';

class FakeNotificationPlatform implements TaskNotificationPlatform {
  final events = <Map<String, Object?>>[];
  bool allowed = true;
  bool dismissed = false;
  Completer<bool>? permission;
  TaskTarget? launchTarget;
  void Function(TaskTarget)? tap;
  void Function()? dismiss;

  @override
  Future<void> initialize(
      void Function(TaskTarget) onTap, void Function() onDismiss) async {
    tap = onTap;
    dismiss = onDismiss;
    if (launchTarget != null) onTap(launchTarget!);
  }

  @override
  Future<NotificationCapabilities> capabilities() async =>
      NotificationCapabilities(
          supported: true,
          allowed: allowed,
          promotedSupported: true,
          promotedAllowed: true,
          dismissed: dismissed);
  @override
  Future<bool> requestPermission() async {
    final result = permission == null ? allowed : await permission!.future;
    if (result) dismissed = false;
    return result;
  }

  @override
  Future<bool> showProgress(
      {required String title,
      required String text,
      required String shortText,
      required TaskTarget target,
      required bool allowStart}) async {
    events.add({
      'type': 'progress',
      'title': title,
      'text': text,
      'target': target,
      'allowStart': allowStart
    });
    return true;
  }

  @override
  Future<void> stopProgress() async {
    events.add({'type': 'stop'});
  }

  @override
  Future<void> showFinished(
      String title, String text, TaskTarget target) async {
    events.add({'type': 'finished', 'title': title, 'target': target});
  }

  @override
  Future<void> openSettings() async {}
  @override
  void dispose() {}
}
