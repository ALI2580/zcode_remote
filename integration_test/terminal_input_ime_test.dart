import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/ipc_codec.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/terminal.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/terminal_session.dart';
import 'package:zcode_remote/ui/terminal_panel.dart';
import 'package:zcode_remote/ui/theme.dart';

class _Bridge implements BridgeSession {
  _Bridge() {
    channels = ChannelClient(sendBody: (body) {
      final reader = ValueReader(body);
      final header = decodeValue(reader) as List;
      final type = header[0] as int;
      final id = header[1] as int;
      if (type == ChannelClient.reqEventListen) {
        final event = header[3] as String;
        decodeValue(reader);
        listeners[id] = event;
        return;
      }
      if (type == ChannelClient.reqEventDispose) {
        listeners.remove(id);
        return;
      }
      final args = decodeValue(reader) as List;
      final method = header[3] as String;
      calls.add((method: method, args: args));
      if (method == 'write') {
        writes.add(args.single['data'] as String);
        unawaited(Future<void>.delayed(const Duration(milliseconds: 60), () {
          final data = writes.last;
          if (listeners.containsValue('onDynamicData')) {
            fireEvent(
                'onDynamicData',
                data.endsWith('\r') ? '$data\n' : '$data\r\n');
          }
        }));
      }
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
  final responses = <String, dynamic>{
    'create': {'id': 'term-ime'},
  };
  final calls = <({String method, List args})>[];
  final writes = <String>[];
  final listeners = <int, String>{};

  void fireEvent(String event, dynamic payload) {
    for (final entry in listeners.entries.where((e) => e.value == event)) {
      final writer = ValueWriter();
      encodeValue(writer, [ChannelClient.resEventFire, entry.key]);
      encodeValue(writer, payload);
      channels.handleMessage(writer.toBytes());
    }
  }

  @override
  Future<void> waitHealthy(
          {Duration timeout = const Duration(seconds: 45)}) async =>
      Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      r'real soft keyboard drives Chinese terminal input on a synthetic service',
      (tester) async {
    final environment = await const MethodChannel('zcode_remote/attachments')
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa',
        reason:
            'Run only with ZCODE_ANDROID_QA=true; never use production data.');
    final bridge = _Bridge();
    final controller = TerminalSessionController(
        client: TerminalClient(session: bridge),
        cwd: 'D:/WorkSpace/ZcodeRemote');
    addTearDown(controller.dispose);
    addTearDown(bridge.channels.dispose);
    final boundary = GlobalKey();

    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            theme: ZInkTheme.light(),
            home: Scaffold(
                appBar:
                    AppBar(title: const Text('D3.3 Terminal IME QA · 合成数据')),
                body: Column(children: [
                  TextButton(onPressed: () {}, child: const Text('结束输入检查')),
                  const Padding(
                      padding: EdgeInsets.all(8),
                      child: Text('请用 Trime 在终端输入框输入「你好」；输入完成后测试会发送。')),
                  Expanded(
                      child: TerminalPanel(
                          client: TerminalClient(session: bridge),
                          cwd: 'D:/WorkSpace/ZcodeRemote',
                          visible: true,
                          controller: controller)),
                ])))));
    await tester.pump();
    final deadline = DateTime.now().add(const Duration(seconds: 2));
    while (controller.status != TerminalSessionStatus.ready) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Synthetic terminal did not open.');
      }
      await tester.pump(const Duration(milliseconds: 50));
    }

    await tester.tap(find.byType(TextField).last);
    await tester.pump(const Duration(milliseconds: 250));
    final inputDeadline = DateTime.now().add(const Duration(minutes: 4));
    var line = '';
    while (line.isEmpty) {
      final input = tester
          .widget<TextField>(find.byType(TextField).last)
          .controller!
          .text;
      if (input == '你好') {
        line = input;
      }
      if (DateTime.now().isAfter(inputDeadline)) {
        fail('Type 你好 in the terminal input with Trime.');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    await controller.write('$line\r');
    await tester.pump(const Duration(milliseconds: 250));
    final echoDeadline = DateTime.now().add(const Duration(seconds: 5));
    while (!controller.output.contains('你好\r\n')) {
      if (DateTime.now().isAfter(echoDeadline)) {
        fail('Terminal send did not echo the real IME input.');
      }
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(controller.output, contains("你好\r\n"));
    expect(bridge.writes, contains("你好\r"));
    expect(bridge.calls.where((call) => call.method == "create"), hasLength(1));
    expect(bridge.calls.where((call) => call.method == "write"), hasLength(1));
    expect(bridge.calls.where((call) => call.method == "dispose"), isEmpty);

    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await render.toImage(pixelRatio: 1);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    await File("${environment!["cacheDirectory"]}/d3.3-terminal-ime.png")
        .writeAsBytes(data!.buffer.asUint8List());
    image.dispose();
    debugPrint(
        "D3.3 IME QA: Chinese soft keyboard input, terminal write and synthetic echo passed.");
  }, timeout: const Timeout(Duration(minutes: 6)));
}
