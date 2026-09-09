import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/connection_params.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/device_session.dart';

class FakeClient extends ZemoteClient {
  FakeClient(super.params, {this.gate, this.failBootstrap = false});
  final Completer<void>? gate;
  final bool failBootstrap;
  int connections = 0;
  int closes = 0;
  @override
  Future<void> connect() async {
    connections++;
    await gate?.future;
  }

  @override
  Future<void> waitPaired(
      {Duration timeout = const Duration(seconds: 60)}) async {}
  @override
  Future<Map<String, dynamic>> bootstrap() async {
    if (failBootstrap) throw StateError('synthetic failure');
    return {
      'workspaces': [
        {'workspaceIdentity': 'shared'}
      ]
    };
  }

  @override
  Future<void> dispose() async {
    closes++;
    await super.dispose();
  }
}

void main() {
  final params = ZemoteConnectionParams.parse(
      'https://zcode.z.ai/remote/v4?sid=synthetic&hash=synthetic&t=1')!;
  test('parallel and listener-reentrant connects share one pending operation',
      () async {
    final gate = Completer<void>();
    final waitingClient = FakeClient(params, gate: gate);
    final session = DeviceSession(params, clientFactory: (_) => waitingClient);
    Future<void>? reentrant;
    session.addListener(() => reentrant ??= session.connect());
    final first = session.connect(), second = session.connect();
    expect(identical(first, second), isTrue);
    expect(identical(first, reentrant), isTrue);
    gate.complete();
    await first;
    expect(waitingClient.connections, 1);
    expect(session.workspaces.single['workspaceIdentity'], 'shared');
    session.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(waitingClient.closes, 1);
  });
  test(
      'closing during a handshake disposes the pending client without a late notification',
      () async {
    final gate = Completer<void>();
    final client = FakeClient(params, gate: gate);
    final session = DeviceSession(params, clientFactory: (_) => client);
    final operation = session.connect();
    final expectation = expectLater(operation, throwsStateError);
    session.dispose();
    gate.complete();
    await expectation;
    expect(client.closes, 1);
    expect(session.client, isNull);
  });
  test('bootstrap failure releases the local client and permits retry',
      () async {
    final first = FakeClient(params, failBootstrap: true),
        next = FakeClient(params);
    int creates = 0;
    final session = DeviceSession(params,
        clientFactory: (_) => creates++ == 0 ? first : next);
    await expectLater(session.connect(), throwsStateError);
    expect(first.closes, 1);
    expect(session.client, isNull);
    await session.connect();
    expect(session.client, same(next));
    session.dispose();
    await Future<void>.delayed(Duration.zero);
    expect(next.closes, 1);
  });
}
