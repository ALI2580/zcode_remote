import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/terminal.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/terminal_session.dart';
import 'package:zcode_remote/ui/terminal_panel.dart';
import 'package:zcode_remote/ui/theme.dart';

class _FakeSession implements BridgeSession {
  @override
  final degraded = ValueSignal<String?>(null);
  @override
  final recovered = ValueSignal<int>(0);
  @override
  final recoveryStarting = ValueSignal<int>(0);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _FakeClient extends TerminalClient {
  final writes = <String>[];

  _FakeClient() : super(session: _FakeSession());

  @override
  Future<TerminalCreateResult> create({
    required int cols,
    required int rows,
    String? cwd,
  }) async {
    return TerminalCreateResult(
      id: 'term-1',
      shell: '/bin/bash',
      fontFamily: null,
      fontSize: null,
      theme: null,
      fontFamilySource: null,
      windowsPty: null,
      raw: const {'id': 'term-1'},
    );
  }

  @override
  Future<void> write({required String id, required String data}) async {
    writes.add(data);
  }

  @override
  Future<void> resize(
      {required String id, required int cols, required int rows}) async {}

  @override
  void Function() onData(String id, void Function(String data) listener) =>
      () {};

  @override
  void Function() onExit(String id, void Function(Object? exitCode) listener) =>
      () {};
}

void main() {
  testWidgets('focused terminal control and navigation keys send bytes',
      (tester) async {
    final client = _FakeClient();
    final controller = TerminalSessionController(
        client: client, cwd: 'D:/WorkSpace/ZcodeRemote');
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: TerminalPanel(
          client: client,
          cwd: 'D:/WorkSpace/ZcodeRemote',
          visible: true,
          controller: controller,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField));

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.keyC);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(client.writes.last, '\u0003');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(client.writes.last, '\u001b[A');
  });
}
