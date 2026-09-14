import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/ipc_codec.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/terminal.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/terminal_session.dart';
import 'package:zcode_remote/ui/terminal_renderer.dart';
import 'package:zcode_remote/ui/theme.dart';
import 'package:xterm/xterm.dart';

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
  testWidgets(
      'terminal create, data, resize, input, exit and dispose use the synthetic channel service',
      (tester) async {
    final bridge = _Bridge();
    bridge.responses['create'] = {
      'id': 'term-synthetic',
      'shell': '/bin/bash',
      'fontFamily': 'monospace',
      'fontSize': 12,
      'theme': {'background': '#161616'},
      'fontFamilySource': 'system',
      'windowsPty': {'backend': 'conpty', 'buildNumber': 19045},
    };

    final client = TerminalClient(session: bridge);
    final controller = TerminalSessionController(
        client: client, cwd: 'D:/WorkSpace/ZcodeRemote');
    final renderer = TerminalOutputRenderer(controller);
    addTearDown(renderer.dispose);
    addTearDown(controller.dispose);
    addTearDown(bridge.channels.dispose);

    final captureDir = Platform.environment['ZCODE_UI_CAPTURE_DIR'];
    final boundary = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: RepaintBoundary(
          key: boundary,
          child: Builder(
            builder: (context) => TerminalView(
              renderer.terminal,
              theme: terminalThemeFor(
                Theme.of(context).colorScheme.brightness,
                controller.theme,
              ),
              textStyle: terminalStyleFor(
                fontFamily: controller.fontFamily,
                fontSize: controller.fontSize,
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();

    controller.cols = renderer.terminal.viewWidth;
    controller.rows = renderer.terminal.viewHeight;
    await controller.open();
    await tester.pump();

    expect(controller.status, TerminalSessionStatus.ready);
    expect(controller.terminalId, 'term-synthetic');
    expect(bridge.calls.first.method, 'create');
    expect(bridge.calls.first.args, [
      {
        'cols': renderer.terminal.viewWidth,
        'rows': renderer.terminal.viewHeight,
        'cwd': 'D:/WorkSpace/ZcodeRemote',
      }
    ]);

    while (bridge.listeners.length < 2) {
      await Future<void>.delayed(Duration.zero);
      await tester.pump();
    }

    bridge.fireEvent('onDynamicData', '\u001b[32m你好\u001b[0m\r\n');
    await tester.pump();
    expect(controller.output, '\u001b[32m你好\u001b[0m\r\n');
    final rendered = renderer.terminal.buffer.toString();
    expect(rendered, contains('你好'));
    expect(rendered.contains('\u001b'), isFalse);

    if (captureDir != null) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 2);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(captureDir).create(recursive: true);
        await File('$captureDir/d3.3-xterm-synthetic-render.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    renderer.terminal.resize(
      renderer.terminal.viewWidth + 1,
      renderer.terminal.viewHeight + 1,
    );
    await tester.pump();
    expect(
      bridge.calls.where((call) => call.method == 'resize'),
      isNotEmpty,
    );
    expect(
      bridge.calls.lastWhere((call) => call.method == 'resize').args,
      [
        {
          'id': 'term-synthetic',
          'cols': renderer.terminal.viewWidth,
          'rows': renderer.terminal.viewHeight,
        }
      ],
    );

    renderer.terminal.textInput('ls\r');
    await tester.pump();
    expect(
      bridge.calls.lastWhere((call) => call.method == 'write').args,
      [
        {'id': 'term-synthetic', 'data': 'ls\r'}
      ],
    );

    bridge.fireEvent('onDynamicExit', 0);
    await tester.pump();
    expect(controller.status, TerminalSessionStatus.exited);
    expect(controller.exitCode, 0);

    await controller.close();
    await tester.pump();
    expect(controller.status, TerminalSessionStatus.idle);
    expect(bridge.calls.last.method, 'dispose');
    expect(bridge.calls.last.args, [
      {'id': 'term-synthetic'}
    ]);
    expect(bridge.listeners, isEmpty);
  });
}
