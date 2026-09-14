import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/connection_params.dart';
import 'package:zcode_remote/protocol/relay_client.dart';

// Main-agent acceptance uses an actual loopback WebSocket, independently of
// the implementation agent's fake relay and UI fixtures.
class _RelayFixture {
  _RelayFixture(this.server, {Future<void>? upgradeGate}) {
    server.listen((request) async {
      requests++;
      if (!requestArrived.isCompleted) requestArrived.complete();
      await upgradeGate;
      final socket = await WebSocketTransformer.upgrade(request);
      sockets.add(socket);
      socket.listen((raw) {
        final frame = jsonDecode(raw as String) as Map;
        if (frame['type'] == 'auth_init') {
          socket
              .add(jsonEncode({'type': 'auth_ack', 'pair_status': 'matched'}));
        }
      }, onError: (Object _) {});
    });
    relay = RelayClient(ZemoteConnectionParams(
      deviceSid: 'synthetic-independent-review',
      passHash: 'synthetic',
      timestamp: 1,
      source: Uri.parse('http://127.0.0.1:${server.port}'),
    ));
    relay.stateListenable.addListener(() => states.add(relay.state));
    subscription = relay.failures.listen(failures.add);
  }

  final HttpServer server;
  int requests = 0;
  final requestArrived = Completer<void>();
  final sockets = <WebSocket>[];
  final states = <RelayState>[];
  final failures = <RelayFailure>[];
  late final RelayClient relay;
  late final StreamSubscription<RelayFailure> subscription;

  static Future<_RelayFixture> start() async {
    final fixture =
        _RelayFixture(await HttpServer.bind(InternetAddress.loopbackIPv4, 0));
    await fixture.relay.start();
    await _until(() => fixture.relay.state == RelayState.paired);
    return fixture;
  }

  void error(String code) => sockets.last.add(jsonEncode({
        'type': 'error',
        'code': code,
        'message': 'synthetic error',
      }));

  Future<void> dispose() async {
    await relay.dispose();
    await subscription.cancel();
    for (final socket in sockets) {
      unawaited(socket.close());
    }
    await server.close(force: true);
  }
}

Future<void> _until(bool Function() predicate,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      throw TimeoutException('independent acceptance condition not reached');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test(
      'review: immediate retry after cancelling a pending socket starts a new connection',
      () async {
    final gate = Completer<void>();
    final fixture = _RelayFixture(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        upgradeGate: gate.future);
    addTearDown(fixture.dispose);
    final first = fixture.relay.start();
    await fixture.requestArrived.future.timeout(const Duration(seconds: 5));
    await fixture.relay.close();
    final retry = fixture.relay.start();
    gate.complete();
    await Future.wait([first, retry]).timeout(const Duration(seconds: 5));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fixture.requests, 2,
        reason:
            'The cancelled attempt must not suppress the explicitly requested replacement.');
    expect(fixture.relay.state, RelayState.paired);
  });

  test('review: cancel during socket establishment rejects the late connection',
      () async {
    final gate = Completer<void>();
    final fixture = _RelayFixture(
        await HttpServer.bind(InternetAddress.loopbackIPv4, 0),
        upgradeGate: gate.future);
    addTearDown(fixture.dispose);
    final connecting = fixture.relay.start();
    await fixture.requestArrived.future.timeout(const Duration(seconds: 5));
    await fixture.relay.close();
    expect(fixture.relay.state, RelayState.closed);
    gate.complete();
    await connecting;
    await Future<void>.delayed(const Duration(milliseconds: 100));
    expect(fixture.relay.state, RelayState.closed,
        reason:
            'A late socket handshake cannot revive a cancelled connection.');
  });

  test('review: silent heartbeat triggers a fresh relay connection', () async {
    final fixture = await _RelayFixture.start();
    addTearDown(fixture.dispose);
    // The synthetic server pairs but never acknowledges heartbeat queries.
    // Exercise the production heartbeat clock, not a manually assigned state.
    await _until(
        () =>
            fixture.sockets.length == 2 &&
            fixture.relay.state == RelayState.paired,
        timeout: const Duration(seconds: 55));
    expect(fixture.states, contains(RelayState.reconnecting));
  }, timeout: const Timeout(Duration(seconds: 65)));

  for (final code in ['AUTH_FAILED', 'WRONG_PARAM']) {
    test('review: $code after pairing stops automatic recovery', () async {
      final fixture = await _RelayFixture.start();
      addTearDown(fixture.dispose);
      fixture.error(code);
      await _until(() => fixture.failures.isNotEmpty);
      expect(fixture.failures.last.reason, 'invalid-mobile-connection');
      expect(fixture.relay.state, RelayState.error);
      fixture.relay.poke();
      await Future<void>.delayed(const Duration(milliseconds: 1150));
      expect(fixture.sockets, hasLength(1));
      expect(fixture.relay.state, RelayState.error);
    });
  }

  test(
      'review: expired paired credentials remain terminal after foreground poke',
      () async {
    final fixture = await _RelayFixture.start();
    addTearDown(fixture.dispose);
    unawaited(fixture.sockets.last.close(4011, 'synthetic-expired'));
    await _until(() => fixture.failures.isNotEmpty);
    expect(fixture.failures.last.reason, 'session-expired');
    expect(fixture.relay.state, RelayState.error);
    fixture.relay.poke();
    await Future<void>.delayed(const Duration(milliseconds: 1150));
    expect(fixture.sockets, hasLength(1));
  });

  test('review: remote exit reconnects, explicit close stays closed', () async {
    final fixture = await _RelayFixture.start();
    addTearDown(fixture.dispose);
    unawaited(fixture.sockets.last.close(4010, 'synthetic-desktop-exit'));
    await _until(() =>
        fixture.sockets.length == 2 &&
        fixture.relay.state == RelayState.paired);
    expect(fixture.states, contains(RelayState.reconnecting));
    await fixture.relay.close();
    fixture.relay.poke();
    await Future<void>.delayed(const Duration(milliseconds: 1150));
    expect(fixture.sockets, hasLength(2));
    expect(fixture.relay.state, RelayState.closed);
  });
}
