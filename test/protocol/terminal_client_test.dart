import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/ipc_codec.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/terminal.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';

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

  void fireEvent(String event, dynamic payload) {
    final id =
        listeners.entries.firstWhere((entry) => entry.value.event == event).key;
    final writer = ValueWriter();
    encodeValue(writer, [ChannelClient.resEventFire, id]);
    encodeValue(writer, payload);
    channels.handleMessage(writer.toBytes());
  }

  @override
  Future<void> waitHealthy(
          {Duration timeout = const Duration(seconds: 45)}) async =>
      Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('create/write/resize/dispose encode official terminal channel calls',
      () async {
    final bridge = _Bridge();
    bridge.responses['create'] = {
      'id': 'term-1',
      'shell': 'C:/Program Files/Git/bin/bash.exe',
      'fontFamily': 'monospace',
      'fontSize': 13,
      'theme': {'background': '#161616'},
      'fontFamilySource': 'system',
      'windowsPty': {'backend': 'conpty', 'buildNumber': 19045},
    };
    final client = TerminalClient(session: bridge);
    final created = await client.create(
      cols: 100,
      rows: 30,
      cwd: 'D:/WorkSpace/ZcodeRemote',
    );

    expect(created.id, 'term-1');
    expect(created.shell, contains('bash.exe'));
    expect(created.fontSize, 13);
    expect(created.windowsPty?['backend'], 'conpty');
    expect(bridge.calls.first.method, 'create');
    expect(bridge.calls.first.args, [
      {
        'cols': 100,
        'rows': 30,
        'cwd': 'D:/WorkSpace/ZcodeRemote',
      }
    ]);

    await client.write(id: 'term-1', data: 'ls\r');
    await client.resize(id: 'term-1', cols: 120, rows: 40);
    await client.dispose(id: 'term-1');
    expect(bridge.calls.map((e) => e.method).toList(), [
      'create',
      'write',
      'resize',
      'dispose',
    ]);
    expect(bridge.calls[1].args, [
      {'id': 'term-1', 'data': 'ls\r'}
    ]);
    expect(bridge.calls[2].args, [
      {'id': 'term-1', 'cols': 120, 'rows': 40}
    ]);
    expect(bridge.calls[3].args, [
      {'id': 'term-1'}
    ]);
    bridge.channels.dispose();
  });

  test('attaches output and exit streams with the terminal id', () async {
    final bridge = _Bridge();
    bridge.responses['create'] = {'id': 'term-1'};
    final client = TerminalClient(session: bridge);
    await client.create(cols: 80, rows: 24);

    final output = <String>[];
    final exits = <Object?>[];
    final disposeOutput = client.onData('term-1', output.add);
    final disposeExit = client.onExit('term-1', exits.add);
    while (bridge.listeners.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    bridge.fireEvent('onDynamicData', 'hello\r\n');
    bridge.fireEvent('onDynamicExit', 0);

    expect(output, ['hello\r\n']);
    expect(exits, [0]);
    expect(bridge.listeners.values.map((e) => e.event).toList(), [
      'onDynamicData',
      'onDynamicExit',
    ]);
    expect(bridge.listeners.values.every((e) => e.arg == 'term-1'), isTrue);

    disposeOutput();
    disposeExit();
    expect(bridge.listeners, isEmpty);
    bridge.channels.dispose();
  });

  test('rejects a create response without terminal id', () async {
    final bridge = _Bridge();
    bridge.responses['create'] = {'shell': 'bash'};
    final client = TerminalClient(session: bridge);
    await expectLater(
      client.create(cols: 80, rows: 24),
      throwsA(isA<TerminalFormatException>()),
    );
    bridge.channels.dispose();
  });
}
