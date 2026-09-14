import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xterm/xterm.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/protocol/terminal.dart';
import 'package:zcode_remote/state/terminal_sessions.dart';
import 'package:zcode_remote/ui/shell/shell_layout.dart';
import 'package:zcode_remote/ui/terminal_panel.dart';
import 'package:zcode_remote/ui/terminal_renderer.dart';
import 'package:zcode_remote/ui/theme.dart';

class _LayoutSession implements BridgeSession {
  @override
  final degraded = ValueSignal<String?>(null);
  @override
  final recovered = ValueSignal<int>(0);
  @override
  final recoveryStarting = ValueSignal<int>(0);

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _ReadyClient extends TerminalClient {
  _ReadyClient() : super(session: _LayoutSession());

  int creates = 0;
  final writes = <String>[];
  final resizes = <({String id, int cols, int rows})>[];
  final disposed = <String>[];
  void Function(String data)? outputListener;
  void Function(Object? exitCode)? exitListener;

  @override
  Future<TerminalCreateResult> create({
    required int cols,
    required int rows,
    String? cwd,
  }) async {
    final id = 'terminal-${++creates}';
    return TerminalCreateResult(
      id: id,
      shell: 'PowerShell',
      fontFamily: null,
      fontSize: null,
      theme: null,
      fontFamilySource: null,
      windowsPty: null,
      raw: {'id': id},
    );
  }

  @override
  Future<void> write({required String id, required String data}) async {
    writes.add(data);
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
    return () {
      if (identical(outputListener, listener)) outputListener = null;
    };
  }

  @override
  void Function() onExit(String id, void Function(Object? exitCode) listener) {
    exitListener = listener;
    return () {
      if (identical(exitListener, listener)) exitListener = null;
    };
  }
}

Widget _shell({required Widget bottomPanel}) => MaterialApp(
      theme: ZInkTheme.light(),
      home: WorkspaceShellLayout(
        title: 'Terminal layout',
        project: 'Synthetic workspace',
        sidebar: const SizedBox.shrink(),
        sidebarCollapsed: true,
        onSidebarCollapsed: (_) {},
        conversation: const SizedBox.expand(),
        bottomPanelOpen: true,
        bottomPanel: bottomPanel,
      ),
    );

void main() {
  testWidgets('shell preserves the 320 pixel drawer at a normal height',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_shell(
      bottomPanel: const ColoredBox(
        key: ValueKey('normal-terminal-drawer'),
        color: Colors.black,
      ),
    ));
    await tester.pumpAndSettle();

    final drawer =
        tester.getRect(find.byKey(const ValueKey('normal-terminal-drawer')));
    expect(drawer.height, closeTo(320, 0.1));
    expect(drawer.bottom, closeTo(820, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'actual ready terminal drawer keeps controls reachable when compressed',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(844, 390);
    addTearDown(tester.view.reset);
    final client = _ReadyClient();
    final workspace = TerminalWorkspaceSessions(
      client: client,
      cwd: 'D:/WorkSpace/ZcodeRemote',
    );
    addTearDown(workspace.disposeAll);
    final originalController = workspace.activeController!;
    var closed = false;

    Widget drawer() => MaterialApp(
          locale: const Locale('zh'),
          supportedLocales: const [Locale('zh'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          theme: ZInkTheme.light(),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: 844,
                height: 122,
                child: TerminalDrawer(
                  key: const ValueKey('actual-terminal-drawer'),
                  client: client,
                  cwd: 'D:/WorkSpace/ZcodeRemote',
                  visible: true,
                  workspace: workspace,
                  onCloseDrawer: () => closed = true,
                ),
              ),
            ),
          ),
        );

    await tester.pumpWidget(drawer());
    await tester.pumpAndSettle();

    expect(client.creates, 1);
    expect(workspace.activeController, same(originalController));
    expect(
        tester
            .getRect(find.byKey(const ValueKey('actual-terminal-drawer')))
            .height,
        closeTo(122, 0.1));
    expect(
        find.byKey(const ValueKey('terminal-compact-scroll')), findsOneWidget);
    expect(find.byType(TerminalView), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('发送'), findsOneWidget);

    final renderer = TerminalOutputRenderer(originalController);
    addTearDown(renderer.dispose);
    renderer.terminal.resize(120, 40);
    await tester.pump();
    expect(client.resizes, isNotEmpty);
    expect(tester.takeException(), isNull);

    final input = find.byType(TextField);
    await tester.ensureVisible(input);
    await tester.enterText(input, '你好');
    await tester.ensureVisible(find.text('发送'));
    await tester.tap(find.text('发送'));
    await tester.pump();
    expect(client.writes, contains('你好\r'));

    await tester.tap(find.byTooltip('关闭终端抽屉').last);
    expect(closed, isTrue);

    await tester.pumpWidget(drawer());
    await tester.pumpAndSettle();
    expect(client.creates, 1);
    expect(workspace.activeController, same(originalController));
    expect(tester.takeException(), isNull);
  });
}
