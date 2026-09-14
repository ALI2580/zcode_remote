import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_notification_controller.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/protocol/relay_client.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/app_sessions.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/remote_settings.dart';
import '../notifications/fake_notification_platform.dart';
import '../protocol/bridge_recovery_test.dart' as wire;

Future<void> _reconnect(wire.TestRelay relay, BridgeSession bridge) async {
  relay.signal.value = RelayState.reconnecting;
  relay.signal.value = RelayState.paired;
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  while (bridge.recovered.value == 0 || bridge.degraded.value != null) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('review recovery timeout');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  await Future<void>.delayed(const Duration(milliseconds: 20));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'review: leaving a recovering conversation releases its pending health wait',
      () async {
    final relay = wire.TestRelay();
    final client = ZemoteClient(wire.params, relayClient: relay);
    addTearDown(client.dispose);
    final bridge = await client.openBridge('workspace');
    final subscription = await bridge.conversation(
        {'workspaceIdentity': 'workspace'}).subscribe('leaving-task');
    await wire.settle();
    relay.respondToChannels = false;
    relay.signal.value = RelayState.reconnecting;
    relay.signal.value = RelayState.paired;
    await wire.settle();
    await wire.settle();
    await wire.settle();
    expect(bridge.recoveryStarting.value, 1);
    await subscription.dispose();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(bridge.degraded.value, isNull,
        reason:
            'A disposed conversation no longer blocks the surviving workspace recovery.');
  });

  test('review: kicked relay immediately gates the existing workspace',
      () async {
    final relay = wire.TestRelay();
    final client = ZemoteClient(wire.params, relayClient: relay);
    addTearDown(client.dispose);
    final bridge = await client.openBridge('workspace');
    expect(bridge.degraded.value, isNull);
    relay.signal.value = RelayState.kicked;
    expect(bridge.degraded.value, isNotNull,
        reason:
            'A terminal relay failure must disable remote actions even before a retry.');
  });

  test(
      'review: completed recovery leaves composer ready without an extra remote event',
      () async {
    final relay = wire.TestRelay();
    final client = ZemoteClient(wire.params, relayClient: relay);
    final bridge = await client.openBridge('workspace');
    final transport = bridge.conversation({'workspaceIdentity': 'workspace'});
    final subscription = await transport.subscribe('same-task');
    await wire.settle();
    final composers = ComposerStore();
    final composer = composers.obtain(
        transport: transport,
        deviceId: 'review',
        workspaceKey: 'workspace',
        sessionId: 'same-task');
    composer.bind(subscription.state);
    composer.input.text = 'preserved draft';
    addTearDown(() async {
      composers.dispose();
      await subscription.dispose();
      await client.dispose();
    });
    expect(composer.ready, isTrue);
    await _reconnect(relay, bridge);
    expect(composer.input.text, 'preserved draft');
    expect(composer.ready, isTrue,
        reason:
            'The completed recovery event must not invalidate the snapshot that just completed recovery.');
  });

  test(
      'review: completed recovery refreshes remote settings on the new channel',
      () async {
    final relay = wire.TestRelay();
    final client = ZemoteClient(wire.params, relayClient: relay);
    final bridge = await client.openBridge('workspace');
    final settings =
        RemoteSettingsController(session: bridge, scopeKey: 'review');
    addTearDown(() async {
      settings.dispose();
      await client.dispose();
    });
    await settings.refresh();
    expect(settings.status, RemoteSettingsStatus.loaded);
    await _reconnect(relay, bridge);
    expect(settings.status, RemoteSettingsStatus.loaded);
    final newBridgeId = bridge.bridge['bridgeSessionId'];
    expect(
        relay.channelMethods
            .any((c) => c.bridgeId == newBridgeId && c.method == 'get'),
        isTrue);
  });

  test(
      'review: completed recovery refreshes the workspace catalog on the new channel',
      () async {
    final relay = wire.TestRelay();
    final client = ZemoteClient(wire.params, relayClient: relay);
    final bridge = await client.openBridge('workspace');
    final notifications =
        TaskNotificationController(platform: FakeNotificationPlatform());
    final monitor = WorkspaceMonitor(
        bridge: bridge,
        scope: const {'workspaceIdentity': 'workspace'},
        source: const WorkspaceTaskSource(
            deviceId: 'review',
            deviceLabel: 'review',
            workspaceKey: 'workspace'),
        notifications: notifications);
    addTearDown(() async {
      monitor.dispose();
      notifications.dispose();
      await client.dispose();
    });
    await monitor.refreshTasks();
    await _reconnect(relay, bridge);
    final newBridgeId = bridge.bridge['bridgeSessionId'];
    expect(
        relay.channelMethods
            .any((c) => c.bridgeId == newBridgeId && c.method == 'listTasks'),
        isTrue);
  });
}
