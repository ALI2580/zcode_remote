import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_notification_controller.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'fake_notification_platform.dart';
import 'task_progress_test.dart' show sourceA, sourceB, entry;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  Future<TaskNotificationController> enabled(
      FakeNotificationPlatform platform) async {
    final controller = TaskNotificationController(platform: platform);
    await controller.initialize();
    await controller.setEnabled(true);
    await controller.settled;
    platform.events.clear();
    return controller;
  }

  test(
      'one device finishing never stops the other device progress notification',
      () async {
    final platform = FakeNotificationPlatform();
    final controller = await enabled(platform);
    controller.update(sourceA, [entry('running')]);
    controller.update(sourceB, [entry('running')]);
    controller.setForeground(true);
    await controller.settled;
    expect(platform.events.last['title'], '2 个任务运行中');
    platform.events.clear();
    controller.update(sourceA, [entry('completed')]);
    controller.setForeground(true);
    await controller.settled;
    expect(platform.events.where((event) => event['type'] == 'stop'), isEmpty);
    expect(platform.events.last['title'], '1 个任务运行中');
    expect((platform.events.last['target'] as TaskTarget).deviceId, 'device-B');
    controller.update(sourceB, [entry('completed')]);
    await controller.settled;
    expect(platform.events.last['type'], 'stop');
    controller.dispose();
    await controller.settled;
  });
  test('disable invalidates a queued trailing progress update', () async {
    final platform = FakeNotificationPlatform();
    final controller = await enabled(platform);
    controller.update(sourceA, [entry('running')]);
    await controller.setEnabled(false);
    await controller.settled;
    expect(
        platform.events.where((event) => event['type'] == 'progress'), isEmpty);
    expect(platform.events.last['type'], 'stop');
    controller.dispose();
    await controller.settled;
  });
  test('a late permission result cannot undo a later disable action', () async {
    final platform = FakeNotificationPlatform();
    final controller = TaskNotificationController(platform: platform);
    await controller.initialize();
    platform.permission = Completer<bool>();
    final enabling = controller.setEnabled(true);
    await Future<void>.delayed(Duration.zero);
    await controller.setEnabled(false);
    platform.permission!.complete(true);
    expect(await enabling, isFalse);
    expect(controller.enabled, isFalse);
    controller.dispose();
    await controller.settled;
  });
  test(
      'notification tap during cold initialization waits for navigation handler',
      () async {
    final target = sourceB.target(entry('running'));
    final platform = FakeNotificationPlatform()..launchTarget = target;
    final controller = TaskNotificationController(platform: platform);
    await controller.initialize();
    final received = <TaskTarget>[];
    controller.onTap = received.add;
    expect(received.single.key, target.key);
    controller.onTap = received.add;
    expect(received, hasLength(1));
    controller.dispose();
    await controller.settled;
  });
  test('user dismissal disables monitoring instead of reposting', () async {
    final platform = FakeNotificationPlatform();
    final controller = await enabled(platform);
    platform.dismiss!();
    await Future<void>.delayed(Duration.zero);
    await controller.settled;
    expect(controller.enabled, isFalse);
    expect(
        (await SharedPreferences.getInstance())
            .getBool(TaskNotificationController.preferenceKey),
        isFalse);
    controller.update(sourceA, [entry('running')]);
    controller.setForeground(true);
    await controller.settled;
    expect(
        platform.events.where((event) => event['type'] == 'progress'), isEmpty);
    controller.dispose();
    await controller.settled;
  });
  test('background updates cannot request starting a new foreground service',
      () async {
    final platform = FakeNotificationPlatform();
    final controller = await enabled(platform);
    controller.update(sourceA, [entry('running')]);
    controller.setForeground(true);
    controller.setForeground(false);
    await controller.settled;
    expect(platform.events.last['allowStart'], isFalse);
    controller.dispose();
    await controller.settled;
  });
}
