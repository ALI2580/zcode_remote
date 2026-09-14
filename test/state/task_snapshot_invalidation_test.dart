import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_notification_controller.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/state/device_store.dart';

import '../notifications/fake_notification_platform.dart';
import '../ui/fake_workspace.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('task_snapshot_invalidated 标记过期→刷新→清除，重复通知合并', () async {
    final store = DeviceStore(requireEncryption: false);
    await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1');
    final notifications =
        TaskNotificationController(platform: FakeNotificationPlatform());
    final monitor = FakeWorkspaceMonitor(
        bridge: FakeBridge(),
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'),
        notifications: notifications);
    var notifyCount = 0;
    monitor.addListener(() => notifyCount++);

    // 通知到达：标记过期并通知监听者。
    expect(monitor.isSnapshotStale('task-1'), isFalse);
    monitor.handleTaskSnapshotInvalidated('task-1');
    expect(monitor.isSnapshotStale('task-1'), isTrue);
    expect(notifyCount, greaterThanOrEqualTo(1));
    final countAfterFirst = notifyCount;

    // 同一任务重复通知：不再额外标记通知（合并到在途刷新）。
    monitor.handleTaskSnapshotInvalidated('task-1');
    expect(notifyCount, countAfterFirst);

    // 刷新完成后清除过期标记（通道读取在 Fake 下静默失败仍会完成）。
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    expect(monitor.isSnapshotStale('task-1'), isFalse);
    expect(notifyCount, greaterThan(countAfterFirst));

    monitor.dispose();
    await notifications.settled;
  });

  test('空 taskId 为无操作', () async {
    final store = DeviceStore(requireEncryption: false);
    await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1');
    final notifications =
        TaskNotificationController(platform: FakeNotificationPlatform());
    final monitor = FakeWorkspaceMonitor(
        bridge: FakeBridge(),
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Project'
        },
        source: const WorkspaceTaskSource(
            deviceId: 'device',
            deviceLabel: 'Device',
            workspaceKey: 'workspace'),
        notifications: notifications);
    var notifyCount = 0;
    monitor.addListener(() => notifyCount++);

    monitor.handleTaskSnapshotInvalidated('');
    expect(monitor.isSnapshotStale(''), isFalse);
    expect(notifyCount, 0);

    monitor.dispose();
    await notifications.settled;
  });
}
