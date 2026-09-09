import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_notification_controller.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/state/app_sessions.dart';
import 'package:zcode_remote/state/device_session.dart';
import 'package:zcode_remote/state/device_store.dart';
import '../notifications/fake_notification_platform.dart';
import '../ui/fake_features.dart';

class CountingSession extends DeviceSession {
  CountingSession(super.params);
  int closes = 0;
  @override
  void dispose() {
    closes++;
    super.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));
  test(
      'switching devices preserves sessions and removing one only disposes that session',
      () async {
    final store = DeviceStore(requireEncryption: false);
    final a = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1');
    final b = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-B&hash=synthetic&t=1');
    final notifications =
        TaskNotificationController(platform: FakeNotificationPlatform());
    final manager = AppSessions(
        store: store,
        notifications: notifications,
        sessionFactory: (device) => CountingSession(device.params!));
    final sa = manager.sessionFor(a) as CountingSession;
    final sb = manager.sessionFor(b) as CountingSession;
    manager.drafts['draft-A'] = '保留草稿';
    expect(manager.sessionFor(a), same(sa));
    expect(sa.closes, 0);
    expect(sb.closes, 0);
    await store.remove(a.id);
    expect(sa.closes, 1);
    expect(sb.closes, 0);
    expect(manager.sessionOf(b.id), same(sb));
    manager.dispose();
    await notifications.settled;
    expect(sb.closes, 1);
  });
  test(
      'changing credentials releases the old runtime while keeping other devices',
      () async {
    final store = DeviceStore(requireEncryption: false);
    const firstUrl =
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1&mid=machine-A';
    final a = await store.addUrl(firstUrl);
    final b = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-B&hash=synthetic&t=1&mid=machine-B');
    final notifications =
        TaskNotificationController(platform: FakeNotificationPlatform());
    final manager = AppSessions(
        store: store,
        notifications: notifications,
        sessionFactory: (device) => CountingSession(device.params!));
    final sa = manager.sessionFor(a) as CountingSession,
        sb = manager.sessionFor(b) as CountingSession;
    final renewed = await store
        .addUrl(firstUrl.replaceFirst('hash=synthetic', 'hash=renewed'));
    expect(renewed.id, a.id);
    expect(sa.closes, 1);
    expect(sb.closes, 0);
    expect(manager.sessionFor(renewed), isNot(same(sa)));
    manager.dispose();
    await notifications.settled;
  });

  test('monitor rejects membership reads started before a live index update',
      () async {
    final bridge = FeatureBridge();
    final notifications =
        TaskNotificationController(platform: FakeNotificationPlatform());
    final monitor = WorkspaceMonitor(
        bridge: bridge,
        scope: const {'workspaceIdentity': 'scope-A'},
        source: const WorkspaceTaskSource(
            deviceId: 'device-A', deviceLabel: 'A', workspaceKey: 'scope-A'),
        notifications: notifications);
    final oldPins = Completer<Object>(), oldArchives = Completer<Object>();
    bridge.channels.handler = (_, method, args) => switch (method) {
          'listPinnedTasks' => oldPins.future,
          'listArchivedTasks' => oldArchives.future,
          _ => [],
        };
    final reading = monitor.refreshTasks();
    monitor.catalog.replaceRemote(monitor.catalog.parseChannel([
      {'taskId': 'pin', 'pinned': true},
      {'taskId': 'archive', 'archived': true}
    ]));
    oldPins.complete([]);
    oldArchives.complete([]);
    await reading;
    expect(monitor.catalog.isPinned('pin'), isTrue);
    expect(monitor.catalog.isArchived('archive'), isTrue);
    bridge.channels.handler = (_, method, args) => [];
    await monitor.refreshTasks();
    expect(monitor.catalog.isPinned('pin'), isFalse);
    expect(monitor.catalog.isArchived('archive'), isFalse);
    expect(
        bridge.channels.calls.every(
            (c) => (c.args.single as Map)['workspaceIdentity'] == 'scope-A'),
        isTrue);
    monitor.dispose();
    bridge.channels.dispose();
    notifications.dispose();
  });
}
