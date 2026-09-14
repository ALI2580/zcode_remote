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

final remoteAParams = ZemoteConnectionParams.parse(
    'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1')!;
final remoteBParams = ZemoteConnectionParams.parse(
    'https://zcode.z.ai/remote/v4?sid=synthetic-B&hash=synthetic&t=1')!;

class TestRelay extends RelayClient {
  TestRelay([ZemoteConnectionParams? relayParams])
      : super(relayParams ?? params);
  final incoming = StreamController<Map<String, dynamic>>.broadcast(sync: true);
  final signal = ValueSignal<RelayState>(RelayState.paired);
  final peers = <String, RpcFrameTransport>{};
  final opens = <Map<String, dynamic>>[];
  final channelCalls = <String>[];
  final channelMethods = <({String bridgeId, String method})>[];
  final subscribeCounts = <String, int>{};
  final unsubscribeCounts = <String, int>{};
  final _eventIds = <String, int>{};
  final _topics = <String, String>{};
  final _pendingSyncFrames = <({
    RpcFrameTransport peer,
    String bridgeId,
    String topic,
    String subId
  })>[];
  int failOpens = 0;
  bool respondToChannels = true;
  bool failUnsubscribe = false;
  bool delaySyncFrames = false;
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
          final args = decodeValue(reader);
          if (header.first == ChannelClient.reqEventListen) {
            _eventIds[id] = header[1] as int;
            final topic = _topics[id];
            final subscriptionId = topic == null
                ? null
                : subscribeCounts[id] == null
                    ? null
                    : 'sub-$id-${subscribeCounts[id]}';
            if (topic != null && subscriptionId != null) {
              scheduleMicrotask(
                  () => _sendSyncFrame(peer, id, topic, subscriptionId));
            }
            return;
          }
          if (header.first != ChannelClient.reqPromise || !respondToChannels) {
            return;
          }
          channelCalls.add(id);
          final method = header[3] as String;
          channelMethods.add((bridgeId: id, method: method));
          var result = <String, Object?>{'bridge': id};
          switch (method) {
            case 'helloConversationV4':
              result = {'connectionId': 'connection-$id'};
            case 'initializeConversationV4':
              result = const {};
            case 'subscribeConversationV4':
              final scope =
                  args is List && args.isNotEmpty && args.single is Map
                      ? (args.single as Map)
                      : const <String, dynamic>{};
              final sessionId =
                  scope['sessionId'] as String? ?? 'synthetic-task';
              _topics[id] = 'conversation/$sessionId';
              final count = (subscribeCounts[id] ?? 0) + 1;
              subscribeCounts[id] = count;
              result = {
                'ack': {
                  'subscriptionId': 'sub-$id-$count',
                  'logEpoch': 'epoch-$id-$count',
                }
              };
            case 'unsubscribeConversationV4':
              unsubscribeCounts[id] = (unsubscribeCounts[id] ?? 0) + 1;
              if (failUnsubscribe) {
                final writer = ValueWriter();
                encodeValue(writer, [ChannelClient.resPromiseError, header[1]]);
                encodeValue(writer, {'message': 'synthetic unsubscribe failure'});
                peer.sendMessage(writer.toBytes());
                return;
              }
              result = const {};
            case 'subscribeSessionsIndexV4':
              final scope =
                  args is List && args.isNotEmpty && args.single is Map
                      ? (args.single as Map)
                      : const <String, dynamic>{};
              _topics[id] =
                  'sessions-index/${scope['workspaceIdentity'] ?? 'synthetic'}';
              final count = (subscribeCounts[id] ?? 0) + 1;
              subscribeCounts[id] = count;
              result = {
                'ack': {
                  'subscriptionId': 'sub-$id-$count',
                  'logEpoch': 'epoch-$id-$count',
                }
              };
            case 'sendConversationCommandV4':
              result = {'status': 'accepted', 'revisionAtDecision': 1};
          }
          final writer = ValueWriter();
          encodeValue(writer, [ChannelClient.resPromiseSuccess, header[1]]);
          encodeValue(writer, result);
          peer.sendMessage(writer.toBytes());
          final topic = _topics[id];
          final subscriptionId =
              topic == null ? null : 'sub-$id-${subscribeCounts[id]}';
          if ((method == 'subscribeConversationV4' ||
                  method == 'subscribeSessionsIndexV4') &&
              topic != null &&
              subscriptionId != null) {
            scheduleMicrotask(
                () => _sendSyncFrame(peer, id, topic, subscriptionId));
          }
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

  void _sendSyncFrame(RpcFrameTransport peer, String bridgeId, String topic,
      String subscriptionId) {
    if (delaySyncFrames) {
      _pendingSyncFrames.add((
        peer: peer,
        bridgeId: bridgeId,
        topic: topic,
        subId: subscriptionId,
      ));
      return;
    }
    final snapshot = topic.startsWith('conversation/')
        ? {
            'logEpoch': 'epoch-$bridgeId-${subscribeCounts[bridgeId]}',
            'rows': {'window': <Object?>[], 'firstRowId': 0, 'totalCount': 0},
            'revision': 0,
          }
        : {
            'workspaceId': 'synthetic',
            'logEpoch': 'epoch-$bridgeId-${subscribeCounts[bridgeId]}',
            'sessions': <Object?>[],
          };
    final frame = {
      'kind': 'complete',
      'topic': topic,
      'subscriptionId': subscriptionId,
      'frame': {
        'topic': topic,
        'subscriptionId': subscriptionId,
        'fromSeq': 0,
        'toSeq': 1,
        'payload': {'kind': 'snapshot', 'snapshot': snapshot},
      },
    };
    final eventId = _eventIds[bridgeId];
    if (eventId == null) return;
    final writer = ValueWriter();
    encodeValue(writer, [ChannelClient.resEventFire, eventId]);
    encodeValue(writer, frame);
    peer.sendMessage(writer.toBytes());
  }

  void flushSyncFrames() {
    final pending = List<
        ({
          RpcFrameTransport peer,
          String bridgeId,
          String topic,
          String subId
        })>.from(_pendingSyncFrames);
    _pendingSyncFrames.clear();
    final delayed = delaySyncFrames;
    delaySyncFrames = false;
    for (final frame in pending) {
      _sendSyncFrame(frame.peer, frame.bridgeId, frame.topic, frame.subId);
    }
    delaySyncFrames = delayed;
  }

  void sendDelta(String bridgeId, String topic, String subscriptionId,
      Map<String, dynamic> payload,
      {int fromSeq = 1, int toSeq = 2}) {
    final eventId = _eventIds[bridgeId];
    final peer = peers[bridgeId];
    if (eventId == null || peer == null) return;
    final frame = {
      'kind': 'complete',
      'topic': topic,
      'subscriptionId': subscriptionId,
      'frame': {
        'topic': topic,
        'subscriptionId': subscriptionId,
        'fromSeq': fromSeq,
        'toSeq': toSeq,
        'payload': {
          'kind': 'deltas',
          'deltas': [payload]
        },
      },
    };
    final writer = ValueWriter();
    encodeValue(writer, [ChannelClient.resEventFire, eventId]);
    encodeValue(writer, frame);
    peer.sendMessage(writer.toBytes());
  }

  void sendSnapshot(String bridgeId, String topic, String subscriptionId,
      {required String epoch, int toSeq = 1}) {
    final eventId = _eventIds[bridgeId];
    final peer = peers[bridgeId];
    if (eventId == null || peer == null) return;
    final snapshot = topic.startsWith('conversation/')
        ? {
            'logEpoch': epoch,
            'rows': {'window': <Object?>[], 'firstRowId': 0, 'totalCount': 0},
            'revision': 0,
          }
        : {
            'workspaceId': 'synthetic',
            'logEpoch': epoch,
            'sessions': <Object?>[],
          };
    final frame = {
      'kind': 'complete',
      'topic': topic,
      'subscriptionId': subscriptionId,
      'frame': {
        'topic': topic,
        'subscriptionId': subscriptionId,
        'fromSeq': 0,
        'toSeq': toSeq,
        'payload': {'kind': 'snapshot', 'snapshot': snapshot},
      },
    };
    final writer = ValueWriter();
    encodeValue(writer, [ChannelClient.resEventFire, eventId]);
    encodeValue(writer, frame);
    peer.sendMessage(writer.toBytes());
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

  test('a failed unsubscribe is compensated before the next subscribe',
      () async {
    final relay = TestRelay();
    final client = ZemoteClient(params, relayClient: relay);
    addTearDown(client.dispose);
    final bridge = await client.openBridge('same-workspace');
    final transport = bridge.conversation(const {});
    final sub = await transport.subscribe('task-leak');
    expect(relay.unsubscribeCounts.values.fold<int>(0, (a, b) => a + b), 0);

    // 退订失败被吞掉时，agent 侧注册会残留并让重复订阅永远等不到 ack。
    relay.failUnsubscribe = true;
    await sub.dispose();
    final totalUnsubscribes =
        relay.unsubscribeCounts.values.fold<int>(0, (a, b) => a + b);
    expect(totalUnsubscribes, 1);

    // 下一次订阅同会话前必须先补发退订。
    relay.failUnsubscribe = false;
    final resub = await transport.subscribe('task-leak');
    final methods = relay.channelMethods.map((m) => m.method).toList();
    final lastUnsub = methods.lastIndexOf('unsubscribeConversationV4');
    final lastSub = methods.lastIndexOf('subscribeConversationV4');
    expect(lastUnsub, isNot(-1), reason: 'leaked unsubscribe must be resent');
    expect(lastUnsub, lessThan(lastSub),
        reason: 'compensation unsubscribe must precede the subscribe');
    await resub.dispose();
    // 正常退订成功后不再补发。
    final sub3 = await transport.subscribe('task-leak');
    final methodsAfter = relay.channelMethods.map((m) => m.method).toList();
    expect(methodsAfter.last, 'subscribeConversationV4');
    await sub3.dispose();
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

  test('two remote identities recover independently and resubscribe locally',
      () async {
    final relayA = TestRelay(remoteAParams);
    final relayB = TestRelay(remoteBParams);
    final clientA = ZemoteClient(remoteAParams, relayClient: relayA);
    final clientB = ZemoteClient(remoteBParams, relayClient: relayB);
    addTearDown(clientA.dispose);
    addTearDown(clientB.dispose);
    final bridgeA = await clientA.openBridge('workspace');
    final bridgeB = await clientB.openBridge('workspace');
    final transportA = bridgeA.conversation({
      'workspaceIdentity': 'workspace-A',
      'workspacePath': 'D:/Remote-A',
    });
    final transportB = bridgeB.conversation({
      'workspaceIdentity': 'workspace-B',
      'workspacePath': 'D:/Remote-B',
    });
    final subA = await transportA.subscribe('same-task-id');
    final subB = await transportB.subscribe('same-task-id');
    final oldSubA = subA.subscriptionId;
    final oldSubB = subB.subscriptionId;
    final bChannels = bridgeB.channels;

    relayA.signal.value = RelayState.reconnecting;
    expect(bridgeA.degraded.value, isNotNull);
    expect(bridgeB.degraded.value, isNull);
    relayA.signal.value = RelayState.paired;
    await settle();
    await settle();
    await settle();
    expect(bridgeA.recovered.value, 1);
    expect(bridgeB.recovered.value, 0);
    expect(bridgeB.channels, same(bChannels));
    expect(subA.subscriptionId, isNot(oldSubA));
    expect(subA.subscriptionId, contains(relayA.opens.last['bridgeSessionId']));
    expect(subB.subscriptionId, oldSubB);
    expect(relayB.opens, hasLength(1));

    relayB.signal.value = RelayState.reconnecting;
    expect(bridgeB.degraded.value, isNotNull);
    expect(bridgeA.degraded.value, isNull);
    relayB.signal.value = RelayState.paired;
    await settle();
    await settle();
    await settle();
    expect(bridgeB.recovered.value, 1);
    expect(bridgeA.recovered.value, 1);
    expect(subB.subscriptionId, isNot(oldSubB));
    expect(subB.subscriptionId, contains(relayB.opens.last['bridgeSessionId']));

    final ackA = await transportA.sendCommand('same-task-id', 'sendText', {
      'text': 'remote A',
    });
    final ackB = await transportB.sendCommand('same-task-id', 'sendText', {
      'text': 'remote B',
    });
    expect(ackA['status'], 'accepted');
    expect(ackB['status'], 'accepted');
    expect(relayA.opens.last['workspaceKey'], 'workspace');
    expect(relayB.opens.last['workspaceKey'], 'workspace');

    await subA.dispose();
    await subB.dispose();
  });

  test(
      'conversation subscription applies live deltas before and after recovery',
      () async {
    final relay = TestRelay();
    final client = ZemoteClient(params, relayClient: relay);
    addTearDown(client.dispose);
    final bridge = await client.openBridge('same-workspace');
    final transport =
        bridge.conversation({'workspaceIdentity': 'same-workspace'});
    final sub = await transport.subscribe('same-task-id');
    await settle();
    await settle();
    expect(sub.state.ready, isTrue);
    final id = bridge.bridge['bridgeSessionId'] as String;
    relay.sendDelta(id, 'conversation/same-task-id', sub.subscriptionId!, {
      'op': 'row.appended',
      'row': {'rowId': 7, 'kind': 'assistantText', 'text': 'live'},
    });
    await settle();
    expect(sub.state.rows.single['text'], 'live');

    relay.signal.value = RelayState.reconnecting;
    relay.signal.value = RelayState.paired;
    await settle();
    await settle();
    await settle();
    expect(bridge.degraded.value, isNull);
    final recoveredId = bridge.bridge['bridgeSessionId'] as String;
    relay.sendDelta(
        recoveredId, 'conversation/same-task-id', sub.subscriptionId!, {
      'op': 'row.appended',
      'row': {'rowId': 8, 'kind': 'assistantText', 'text': 'after'},
    });
    await settle();
    expect(sub.state.rows.last['text'], 'after');
    await sub.dispose();
  });

  test('sessions index subscription applies live deltas after recovery',
      () async {
    final relay = TestRelay();
    final client = ZemoteClient(params, relayClient: relay);
    addTearDown(client.dispose);
    final bridge = await client.openBridge('same-workspace');
    final transport =
        bridge.conversation({'workspaceIdentity': 'same-workspace'});
    final sub = await transport.subscribeSessionsIndex();
    await settle();
    await settle();
    expect(sub.state.ready, isTrue);
    final id = bridge.bridge['bridgeSessionId'] as String;
    relay.sendDelta(id, 'sessions-index/same-workspace', sub.subscriptionId!, {
      'op': 'session.upserted',
      'session': {'sessionId': 'task-live', 'title': 'Live task'},
    });
    await settle();
    expect(sub.state.list.single.sessionId, 'task-live');

    relay.signal.value = RelayState.reconnecting;
    relay.signal.value = RelayState.paired;
    await settle();
    await settle();
    await settle();
    expect(bridge.degraded.value, isNull);
    final recoveredId = bridge.bridge['bridgeSessionId'] as String;
    relay.sendDelta(
        recoveredId, 'sessions-index/same-workspace', sub.subscriptionId!, {
      'op': 'session.upserted',
      'session': {'sessionId': 'task-after', 'title': 'After recovery'},
    });
    await settle();
    expect(
        sub.state.list.any((entry) => entry.sessionId == 'task-after'), isTrue);
    await sub.dispose();
  });

  test('recovery waits for current snapshot and rejects stale or gapped frames',
      () async {
    final relay = TestRelay()..delaySyncFrames = true;
    final client = ZemoteClient(params, relayClient: relay);
    addTearDown(client.dispose);
    final bridge = await client.openBridge('same-workspace');
    final transport =
        bridge.conversation({'workspaceIdentity': 'same-workspace'});
    final sub = await transport.subscribe('same-task-id');
    await settle();
    await settle();
    expect(sub.state.ready, isFalse);
    relay.flushSyncFrames();
    await settle();
    expect(sub.state.ready, isTrue);
    final oldEpoch = 'epoch-${bridge.bridge['bridgeSessionId']}-1';

    relay.signal.value = RelayState.reconnecting;
    relay.signal.value = RelayState.paired;
    await settle();
    await settle();
    await settle();
    expect(bridge.degraded.value, isNotNull);
    final recoveryId = bridge.bridge['bridgeSessionId'] as String;
    final recoverySubId = sub.subscriptionId!;
    relay.sendSnapshot(recoveryId, 'conversation/same-task-id', recoverySubId,
        epoch: oldEpoch);
    relay.sendDelta(
        recoveryId,
        'conversation/same-task-id',
        recoverySubId,
        {
          'op': 'row.appended',
          'row': {'rowId': 99, 'text': 'gap'}
        },
        fromSeq: 999,
        toSeq: 1000);
    await settle();
    expect(bridge.degraded.value, isNotNull);
    relay.flushSyncFrames();
    await settle();
    await settle();
    expect(bridge.degraded.value, isNull);
    await sub.dispose();
  });

  test(
      'cancelling recovery invalidates its loop and prevents late bridge opens',
      () async {
    final relay = TestRelay();
    final client = ZemoteClient(
      params,
      relayClient: relay,
      recoveryRetryDelay: const Duration(milliseconds: 1),
    );
    addTearDown(client.dispose);
    final bridge = await client.openBridge('same-workspace');
    relay.failOpens = 100;
    relay.signal.value = RelayState.reconnecting;
    relay.signal.value = RelayState.paired;
    await settle();
    final beforeClose = relay.opens.length;
    await client.close();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(relay.opens.length, beforeClose);
    expect(bridge.degraded.value, 'user-disconnected');
  });

  test('a kicked client reconnects its original bridge instead of stranding it',
      () async {
    final relay = TestRelay();
    final client = ZemoteClient(params, relayClient: relay);
    addTearDown(client.dispose);
    final bridge = await client.openBridge('same-workspace');
    final oldChannels = bridge.channels;
    bridge.degraded.value = 'kicked';
    relay.signal.value = RelayState.kicked;
    await client.connect();
    await settle();
    await settle();
    await settle();
    expect(bridge.channels, isNot(same(oldChannels)));
    expect(bridge.degraded.value, isNull);
  });
}
