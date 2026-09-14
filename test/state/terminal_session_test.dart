import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/ipc_codec.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/terminal.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/terminal_session.dart';

class _Bridge implements BridgeSession {
  _Bridge() {
    channels = ChannelClient(sendBody: (body) {
      final reader = ValueReader(body);
      final header = decodeValue(reader) as List;
      final type = header[0] as int;
      final id = header[1] as int;
      if (type == ChannelClient.reqEventListen) {
        final event = header[3] as String;
        final arg = decodeValue(reader);
        listeners[id] = (event: event, arg: arg);
        return;
      }
      if (type == ChannelClient.reqEventDispose) {
        listeners.remove(id);
        return;
      }
      final args = decodeValue(reader) as List;
      final method = header[3] as String;
      calls.add((method: method, args: args));
      final writer = ValueWriter();
      encodeValue(writer, [ChannelClient.resPromiseSuccess, id]);
      encodeValue(writer, responses[method]);
      channels.handleMessage(writer.toBytes());
    });
    final writer = ValueWriter();
    encodeValue(writer, [ChannelClient.resInitialize]);
    channels.handleMessage(writer.toBytes());
  }

  @override
  late final ChannelClient channels;
  @override
  final degraded = ValueSignal<String?>(null);
  @override
  final recovered = ValueSignal<int>(0);
  @override
  final recoveryStarting = ValueSignal<int>(0);
  final responses = <String, dynamic>{};
  final calls = <({String method, List args})>[];
  final listeners = <int, ({String event, Object? arg})>{};
  Completer<void>? healthGate;

  void fireEvent(String event, dynamic payload) {
    final id =
        listeners.entries.firstWhere((entry) => entry.value.event == event).key;
    final writer = ValueWriter();
    encodeValue(writer, [ChannelClient.resEventFire, id]);
    encodeValue(writer, payload);
    channels.handleMessage(writer.toBytes());
  }

  void fireById(int id, dynamic payload) {
    final writer = ValueWriter();
    encodeValue(writer, [ChannelClient.resEventFire, id]);
    encodeValue(writer, payload);
    channels.handleMessage(writer.toBytes());
  }

  @override
  Future<void> waitHealthy(
      {Duration timeout = const Duration(seconds: 45)}) async {
    final gate = healthGate;
    if (gate != null) await gate.future.timeout(timeout);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

TerminalSessionController _controller(TerminalClient client,
        {int max = 1024}) =>
    TerminalSessionController(
      client: client,
      cwd: 'D:/WorkSpace/ZcodeRemote',
      maxBufferChars: max,
    );

class _FailingClient extends TerminalClient {
  _FailingClient({required super.session});

  @override
  Future<void> write({required String id, required String data}) async {
    throw StateError('synthetic terminal write rejected');
  }
}

class _FailingDisposeClient extends TerminalClient {
  final disposedIds = <String>[];

  _FailingDisposeClient({required super.session});

  @override
  Future<void> dispose({required String id}) async {
    disposedIds.add(id);
    throw StateError('synthetic terminal dispose rejected');
  }
}

void main() {
  test('terminal open, output, resize, write and exit preserve lifecycle',
      () async {
    final bridge = _Bridge();
    bridge.responses['create'] = {
      'id': 'term-1',
      'shell': '/bin/bash',
    };
    final controller = _controller(TerminalClient(session: bridge));
    await controller.open();

    expect(controller.status, TerminalSessionStatus.ready);
    expect(controller.terminalId, 'term-1');
    expect(bridge.calls.first.method, 'create');
    while (bridge.listeners.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    bridge.fireEvent('onDynamicData', '你好\r\n');
    expect(controller.output, '你好\r\n');

    await controller.resize(newCols: 120, newRows: 40);
    await controller.resize(newCols: 120, newRows: 40);
    await controller.write('ls\r');
    expect(bridge.calls.where((e) => e.method == 'resize'), hasLength(1));
    expect(bridge.calls.last.args, [
      {'id': 'term-1', 'data': 'ls\r'}
    ]);

    bridge.fireEvent('onDynamicExit', 0);
    expect(controller.status, TerminalSessionStatus.exited);
    expect(controller.exitCode, 0);

    await controller.close();
    expect(controller.status, TerminalSessionStatus.idle);
    expect(bridge.calls.last.method, 'dispose');
    expect(bridge.listeners, isEmpty);
    controller.dispose();
    bridge.channels.dispose();
  });

  test('late output after close does not change the terminal state', () async {
    final bridge = _Bridge();
    bridge.responses['create'] = {'id': 'term-1'};
    final controller = _controller(TerminalClient(session: bridge));
    await controller.open();
    expect(controller.canInput, isTrue);

    while (bridge.listeners.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    final listenerId = bridge.listeners.keys.first;
    await controller.close();
    bridge.fireById(listenerId, 'late\r\n');
    bridge.fireById(listenerId, 1);
    expect(controller.output, isEmpty);
    expect(controller.status, TerminalSessionStatus.idle);
    expect(controller.exitCode, isNull);
    controller.dispose();
    bridge.channels.dispose();
  });

  test('create failure keeps retryable terminal state without an id', () async {
    final bridge = _Bridge();
    final controller = _controller(TerminalClient(session: bridge));
    await controller.open();
    expect(controller.status, TerminalSessionStatus.failed);
    expect(controller.terminalId, isNull);
    expect(controller.error, isA<TerminalFormatException>());
    controller.dispose();
    bridge.channels.dispose();
  });

  test('bounded output drops only the oldest text', () async {
    final bridge = _Bridge();
    bridge.responses['create'] = {'id': 'term-1'};
    final controller = _controller(TerminalClient(session: bridge), max: 4);
    await controller.open();
    while (bridge.listeners.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    bridge.fireEvent('onDynamicData', '123456');
    expect(controller.output, '3456');
    controller.dispose();
    bridge.channels.dispose();
  });

  test('a write failure keeps the terminal retryable and exposes the error',
      () async {
    final bridge = _Bridge();
    bridge.responses['create'] = {'id': 'term-1'};
    final controller = _controller(_FailingClient(session: bridge));
    await controller.open();

    expect(controller.status, TerminalSessionStatus.ready);
    await expectLater(
      controller.write('ls\r'),
      throwsA(isA<StateError>()),
    );
    expect(controller.status, TerminalSessionStatus.failed);
    expect(controller.error, isA<StateError>());
    expect(controller.canInput, isFalse);

    controller.dispose();
    bridge.channels.dispose();
  });

  test('rebuilding a failed terminal disposes the previous terminal id',
      () async {
    final bridge = _Bridge();
    bridge.responses['create'] = {'id': 'term-1'};
    final controller = _controller(_FailingClient(session: bridge));
    await controller.open();
    await expectLater(controller.write('ls\r'), throwsA(isA<StateError>()));

    await controller.open();
    expect(controller.status, TerminalSessionStatus.ready);
    expect(controller.terminalId, 'term-1');
    expect(bridge.calls.where((call) => call.method == 'create'), hasLength(2));
    expect(
        bridge.calls.where((call) => call.method == 'dispose'), hasLength(1));

    controller.dispose();
    bridge.channels.dispose();
  });

  test('terminal writes wait for synthetic bridge recovery or fail visibly',
      () async {
    final bridge = _Bridge();
    bridge.responses['create'] = {'id': 'term-1'};
    final controller = _controller(TerminalClient(session: bridge));
    await controller.open();

    bridge.healthGate = Completer<void>();
    final pending = controller.write('after-recovery\r');
    await Future<void>.delayed(Duration.zero);
    expect(bridge.calls.where((call) => call.method == 'write'), isEmpty);
    bridge.healthGate!.complete();
    await pending;
    expect(bridge.calls.where((call) => call.method == 'write'), hasLength(1));

    final unhealthyBridge = _Bridge();
    unhealthyBridge.responses['create'] = {'id': 'term-2'};
    final unhealthyController = _controller(
      TerminalClient(
        session: unhealthyBridge,
        timeout: const Duration(milliseconds: 10),
      ),
    );
    await unhealthyController.open();
    unhealthyBridge.healthGate = Completer<void>();
    await expectLater(
      unhealthyController.write('unreachable\r'),
      throwsA(isA<TimeoutException>()),
    );
    expect(unhealthyController.status, TerminalSessionStatus.failed);
    expect(unhealthyController.error, isA<TimeoutException>());

    unhealthyBridge.healthGate!.complete();
    await unhealthyController.close();
    controller.dispose();
    unhealthyController.dispose();
    bridge.channels.dispose();
    unhealthyBridge.channels.dispose();
  });

  test('bridge recovery closes the old terminal and creates a new session',
      () async {
    final bridge = _Bridge();
    bridge.responses['create'] = {'id': 'term-1'};
    final controller = _controller(TerminalClient(session: bridge));
    await controller.open();
    expect(controller.status, TerminalSessionStatus.ready);
    while (bridge.listeners.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }

    bridge.recovered.value += 1;
    while (!(controller.status == TerminalSessionStatus.ready &&
        bridge.calls.where((call) => call.method == 'create').length == 2 &&
        bridge.listeners.length == 2)) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(controller.status, TerminalSessionStatus.ready);
    expect(controller.output, isEmpty);
    expect(bridge.calls.where((call) => call.method == 'create'), hasLength(2));
    expect(
        bridge.calls.where((call) => call.method == 'dispose'), hasLength(1));
    expect(bridge.listeners, hasLength(2));

    controller.dispose();
    bridge.channels.dispose();
  });

  test('bridge recovery continues when the old terminal dispose fails',
      () async {
    final bridge = _Bridge();
    bridge.responses['create'] = {'id': 'term-1'};
    final client = _FailingDisposeClient(session: bridge);
    final controller = _controller(client);
    await controller.open();
    while (bridge.listeners.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }

    bridge.recovered.value += 1;
    while (!(controller.status == TerminalSessionStatus.ready &&
        bridge.calls.where((call) => call.method == 'create').length == 2 &&
        bridge.listeners.length == 2)) {
      await Future<void>.delayed(Duration.zero);
    }

    expect(controller.status, TerminalSessionStatus.ready);
    expect(controller.output, isEmpty);
    expect(client.disposedIds, hasLength(1));
    expect(bridge.calls.where((call) => call.method == 'create'), hasLength(2));
    expect(bridge.listeners, hasLength(2));

    controller.dispose();
    bridge.channels.dispose();
  });
}
