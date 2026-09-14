import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/terminal.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/terminal_session.dart';
import 'package:zcode_remote/state/terminal_sessions.dart';
import 'package:zcode_remote/ui/terminal_panel.dart';
import 'package:zcode_remote/ui/terminal_renderer.dart';
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
  final creates = <({int cols, int rows, String? cwd})>[];
  final writes = <({String id, String data})>[];
  final resizes = <({String id, int cols, int rows})>[];
  final disposed = <String>[];
  void Function(String data)? outputListener;
  void Function(Object? exitCode)? exitListener;

  _FakeClient() : super(session: _FakeSession());

  @override
  Future<TerminalCreateResult> create({
    required int cols,
    required int rows,
    String? cwd,
  }) async {
    creates.add((cols: cols, rows: rows, cwd: cwd));
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
    writes.add((id: id, data: data));
  }

  @override
  Future<void> resize({
    required String id,
    required int cols,
    required int rows,
  }) async {
    resizes.add((id: id, cols: cols, rows: rows));
  }

  @override
  Future<void> dispose({required String id}) async {
    disposed.add(id);
  }

  @override
  void Function() onData(String id, void Function(String data) listener) {
    outputListener = listener;
    return () {};
  }

  @override
  void Function() onExit(String id, void Function(Object? exitCode) listener) {
    exitListener = listener;
    return () {};
  }
}

void main() {
  test('terminal theme and style mirror the official profile mapping', () {
    final theme = terminalThemeFor(Brightness.dark, {
      'background': '#ffffff',
      'foreground': '#ffffff',
      'cursor': '#ffffff',
      'red': '#010203',
      'selectionBackground': '#11111122',
    });
    expect(theme.background, const Color(0xFF161616));
    expect(theme.foreground, const Color(0xFFDEDEDE));
    expect(theme.cursor, const Color(0xFFF8F8F8));
    expect(theme.red, const Color(0xFF010203));
    expect(theme.selection, const Color(0x22111111));

    final style = terminalStyleFor(fontFamily: 'custom', fontSize: 14);
    expect(style.fontFamily, 'custom');
    expect(style.fontSize, 14);
    expect(style.fontFamilyFallback, contains('Consolas'));
  });

  testWidgets(
      'terminal panel opens, renders output and sends real terminal data',
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

    expect(controller.status, TerminalSessionStatus.ready);
    expect(client.creates, hasLength(1));
    expect(client.creates.single.cwd, 'D:/WorkSpace/ZcodeRemote');
    expect(client.creates.single.cols, greaterThan(0));
    expect(client.creates.single.rows, greaterThan(0));
    expect(client.resizes, isNotEmpty);
    expect(find.text('/bin/bash'), findsOneWidget);

    client.outputListener?.call('你好\r\n');
    await tester.pumpAndSettle();
    expect(controller.output, '你好\r\n');
    expect(find.byType(TerminalView), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'ls');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(client.writes.last.data, 'ls\r');
    expect(find.byType(TextField), findsOneWidget);

    await tester.enterText(find.byType(TextField), '你好');
    await tester.tap(find.text('发送'));
    await tester.pumpAndSettle();
    expect(client.writes.last.data, '你好\r');

    await tester.tap(find.text('Ctrl+C'));
    await tester.pumpAndSettle();
    expect(client.writes.last.data, '\u0003');
  });

  testWidgets('large terminal output is bounded and renders the retained tail',
      (tester) async {
    final client = _FakeClient();
    final controller = TerminalSessionController(
      client: client,
      cwd: 'D:/WorkSpace/ZcodeRemote',
      maxBufferChars: 4096,
    );
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

    client.outputListener?.call('${'x' * 10000}END-MARKER');
    await tester.pumpAndSettle();

    expect(controller.output, hasLength(4096));
    expect(controller.output.endsWith('END-MARKER'), isTrue);
    expect(find.byType(TerminalView), findsOneWidget);
  });

  testWidgets('xterm renderer consumes ANSI and forwards terminal input',
      (tester) async {
    final client = _FakeClient();
    final controller = TerminalSessionController(
        client: client, cwd: 'D:/WorkSpace/ZcodeRemote');
    addTearDown(controller.dispose);
    final renderer = TerminalOutputRenderer(controller);
    addTearDown(renderer.dispose);

    await controller.open();
    await tester.pump();

    client.outputListener?.call('\u001b[31m你好\u001b[0m\r\n');
    await tester.pump();

    final rendered = renderer.terminal.buffer.toString();
    expect(rendered, contains('你好'));
    expect(rendered.contains('\u001b'), isFalse);

    renderer.terminal.textInput('q');
    await tester.pump();
    expect(client.writes.last.data, 'q');
  });

  testWidgets('terminal panel closes and removes listeners on dispose',
      (tester) async {
    final client = _FakeClient();
    final controller = TerminalSessionController(
        client: client, cwd: 'D:/WorkSpace/ZcodeRemote');
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

    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(client.disposed, ['term-1']);
    expect(controller.status, TerminalSessionStatus.idle);
    controller.dispose();
  });

  testWidgets('workspace terminal tabs stay alive across drawer switches',
      (tester) async {
    final client = _FakeClient();
    final workspace = TerminalWorkspaceSessions(
      client: client,
      cwd: 'D:/WorkSpace/ZcodeRemote',
    );
    addTearDown(() => workspace.disposeAll());

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: TerminalDrawer(
          client: client,
          cwd: 'D:/WorkSpace/ZcodeRemote',
          visible: true,
          workspace: workspace,
          onCloseDrawer: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(workspace.activeController!.status, TerminalSessionStatus.ready);
    expect(find.text('终端'), findsOneWidget);
    expect(find.byTooltip('新建终端标签'), findsWidgets);
    expect(find.byTooltip('关闭终端抽屉'), findsWidgets);
    // The created tab is labelled by its shell, per the official chrome.
    expect(find.text('/bin/bash'), findsOneWidget);

    await tester.tap(find.byTooltip('新建终端标签').last);
    await tester.pumpAndSettle();
    expect(workspace.activeIndex, 1);
    expect(workspace.controllers, hasLength(2));
    expect(client.creates, hasLength(2));
    // The drawer is visible, so the new active tab opens its PTY right away.
    expect(workspace.activeController!.status, TerminalSessionStatus.ready);
    // Only the active tab carries the close control, per the official chrome.
    expect(find.byTooltip('关闭终端标签'), findsOneWidget);

    // Both tabs share the fake shell label, so target the first (tab 1).
    await tester.tap(find.text('/bin/bash').first);
    await tester.pumpAndSettle();
    expect(workspace.activeIndex, 0);
    expect(client.creates, hasLength(2));

    await tester.tap(find.byTooltip('关闭终端标签').last);
    await tester.pumpAndSettle();
    expect(workspace.controllers, hasLength(1));
    expect(workspace.activeIndex, 0);
    expect(client.disposed, ['term-1']);
  });
}
