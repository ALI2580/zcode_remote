import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/connection_params.dart';
import 'package:zcode_remote/protocol/ipc_codec.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/relay_client.dart';
import 'package:zcode_remote/protocol/rpc_transport.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';

final params = ZemoteConnectionParams.parse(
    'https://zcode.z.ai/remote/v4?sid=synthetic-bridge&hash=synthetic&t=1')!;

class TestRelay extends RelayClient {
  TestRelay() : super(params);
  final incoming = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final signal = ValueSignal<RelayState>(RelayState.paired);
  final peers = <String, RpcFrameTransport>{};
  final opens = <Map<String, dynamic>>[];
  final channelCalls = <String>[];
  int failOpens = 0;
  bool respondToChannels = true;
  @override
  Stream<Map<String, dynamic>> get payloads => incoming.stream;
  @override
  ProtocolValueListenable<RelayState> get stateListenable => signal;
  @override
  RelayState get state => signal.value;
  @override
  Future<void> start() async => signal.value = RelayState.paired;

  void initialize(RpcFrameTransport peer) {
    final writer = ValueWriter();
    encodeValue(writer, [ChannelClient.resInitialize]);
    peer.sendMessage(writer.toBytes());
  }

  @override
  void sendPayload(Map<String, dynamic> payload) {
    switch (payload['zcode_type']) {
      case 'workspace-bridge-open':
        opens.add(payload);
        final id = payload['bridgeSessionId'] as String;
        if (failOpens > 0) {
          failOpens--;
          scheduleMicrotask(() => incoming.add({
                'zcode_type': 'workspace-bridge-error',
                'bridgeSessionId': id,
                'error': 'synthetic not ready'
              }));
          return;
        }
        final peer = RpcFrameTransport(
            bridgeSessionId: id,
            bridgeGeneration: payload['bridgeGeneration'] as int,
            recoveryId:
                payload['recoveryId'] as String? ?? 'synthetic-recovery',
            sendPayload: incoming.add);
        peers[id] = peer;
        peer.messages.listen((body) {
          final reader = ValueReader(body);
          final header = decodeValue(reader) as List;
          decodeValue(reader);
          if (header.first != ChannelClient.reqPromise || !respondToChannels) {
            return;
          }
          channelCalls.add(id);
          final writer = ValueWriter();
          encodeValue(writer, [ChannelClient.resPromiseSuccess, header[1]]);
          encodeValue(writer, {'bridge': id});
          peer.sendMessage(writer.toBytes());
        });
        // The legitimate Initialize arrives before the open await continuation.
        scheduleMicrotask(() {
          initialize(peer);
          incoming.add({
            'zcode_type': 'workspace-bridge-ready',
            'bridgeSessionId': id,
            'bridge': {
              'bridgeSessionId': id,
              'bridgeGeneration': payload['bridgeGeneration'],
              'workspaceKey': payload['workspaceKey'],
              'initialTaskId': 'synthetic-task',
              'recoveryId': payload['recoveryId'] ?? 'synthetic-recovery',
            }
          });
        });
      case 'workspace-reconnect-request':
        scheduleMicrotask(() => incoming.add({
              'zcode_type': 'workspace-reconnect-response',
              'requestId': payload['requestId'],
              'workspaceKey': payload['workspaceKey'],
              'success': true
            }));
      case 'rpc-frame':
        peers[payload['bridgeSessionId']]?.acceptPayload(payload);
    }
  }

  @override
  Future<void> dispose() async {
    for (final peer in peers.values) {
      peer.dispose();
    }
    signal.dispose();
    await incoming.close();
    await super.dispose();
  }
}

Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('Initialize before bridge ready is buffered and reaches the channel',
      () async {
    final relay = TestRelay();
    final client = ZemoteClient(params, relayClient: relay);
    addTearDown(client.dispose);
    final bridge = await client.openBridge('same-workspace');
    final reply = await bridge.channels.call('synthetic', 'read', []);
    expect(reply['bridge'], bridge.bridge['bridgeSessionId']);
  });

  test(
      'relay recovery replaces the dead channel stack before reporting healthy',
      () async {
    final relay = TestRelay();
    final client = ZemoteClient(params, relayClient: relay);
    addTearDown(client.dispose);
    final bridge = await client.openBridge('same-workspace');
    final oldChannels = bridge.channels;
    final oldPeer = relay.peers.values.single;
    relay.signal.value = RelayState.reconnecting;
    expect(bridge.degraded.value, isNotNull);
    relay.signal.value = RelayState.paired;
    await settle();
    await settle();
    expect(relay.opens, hasLength(2));
    expect(bridge.channels, isNot(same(oldChannels)));
    expect(bridge.recovered.value, 1);
    expect(bridge.degraded.value, isNull);
    final reply = await bridge.channels.call('synthetic', 'read', []);
    expect(reply['bridge'], relay.opens.last['bridgeSessionId']);
    // A late old-bridge frame must not route into its disposed stream.
    relay.initialize(oldPeer);
    await settle();
    expect(bridge.recovered.value, 1);
  });

  test('disposed bridges reject both new and pending health waits', () async {
    final relay = TestRelay();
    final client = ZemoteClient(params, relayClient: relay);
    addTearDown(client.dispose);
    final bridge = await client.openBridge('same-workspace');
    bridge.degraded.value = 'synthetic offline';
    final pending = expectLater(bridge.waitHealthy(), throwsStateError);
    bridge.dispose();
    await expectLater(bridge.waitHealthy(), throwsStateError);
    await pending;
  });

  test('an active workspace bridge error recovers only its own workspace',
      () async {
    final relay = TestRelay();
    final client = ZemoteClient(params, relayClient: relay);
    addTearDown(client.dispose);
    final a = await client.openBridge('workspace-A');
    final b = await client.openBridge('workspace-B');
    final bChannels = b.channels;
    relay.incoming.add({
      'zcode_type': 'workspace-bridge-error',
      'bridgeSessionId': a.bridge['bridgeSessionId'],
      'reason': 'synthetic fault'
    });
    await settle();
    await settle();
    expect(a.recovered.value, 1);
    expect(b.recovered.value, 0);
    expect(b.channels, same(bChannels));
    expect(relay.opens, hasLength(3));
    expect(relay.opens.last['workspaceKey'], 'workspace-A');
  });

  test('recovery can succeed after more than fifteen failures', () async {
    final relay = TestRelay();
    final client = ZemoteClient(params,
        relayClient: relay,
        recoveryRetryDelay: const Duration(milliseconds: 1));
    addTearDown(client.dispose);
    final bridge = await client.openBridge('same-workspace');
    final recovered = Completer<void>();
    bridge.recovered.addListener(() {
      if (bridge.recovered.value > 0 && !recovered.isCompleted) {
        recovered.complete();
      }
    });
    relay.failOpens = 16;
    relay.signal.value = RelayState.reconnecting;
    relay.signal.value = RelayState.paired;
    await recovered.future.timeout(const Duration(seconds: 2));
    expect(relay.opens, hasLength(18));
    expect(bridge.degraded.value, isNull);
    expect(bridge.recovered.value, 1);
  });
}
