import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/terminal.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/terminal_sessions.dart';
import 'package:zcode_remote/ui/terminal_panel.dart';
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
  final disposed = <String>[];

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
  Future<void> write({required String id, required String data}) async {}

  @override
  Future<void> resize(
      {required String id, required int cols, required int rows}) async {}

  @override
  Future<void> dispose({required String id}) async {
    disposed.add(id);
  }

  @override
  void Function() onData(String id, void Function(String data) listener) {
    return () {};
  }

  @override
  void Function() onExit(String id, void Function(Object? exitCode) listener) {
    return () {};
  }
}

Future<TerminalWorkspaceSessions> _workspace(TerminalClient client,
    {int tabs = 1}) async {
  final workspace = TerminalWorkspaceSessions(client: client, cwd: 'C:/x');
  for (var i = 0; i < tabs; i++) {
    workspace.add();
  }
  return workspace;
}

Widget _host(TerminalWorkspaceSessions workspace, double width,
        {required VoidCallback onCloseDrawer}) =>
    MaterialApp(
        theme: ZInkTheme.light(),
        home: Scaffold(
            body: Align(
                alignment: Alignment.topCenter,
                child: SizedBox(
                    width: width,
                    height: 160,
                    child: TerminalDrawer(
                        client: workspace.client,
                        cwd: 'C:/x',
                        visible: true,
                        workspace: workspace,
                        onCloseDrawer: onCloseDrawer)))));

void main() {
  testWidgets('compact drawer keeps tab close and header buttons at 48px',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final client = _ReadyClient();
    final workspace = await _workspace(client, tabs: 2);
    addTearDown(workspace.disposeAll);
    var drawerClosed = false;

    await tester.pumpWidget(
        _host(workspace, 390, onCloseDrawer: () => drawerClosed = true));
    await tester.pumpAndSettle();

    // Both header controls are full targets on a phone.
    final newTab = tester.getRect(find.byTooltip('New terminal tab').first);
    final closeDrawer =
        tester.getRect(find.byTooltip('Close terminal drawer').first);
    expect(newTab.height, greaterThanOrEqualTo(48));
    expect(closeDrawer.height, greaterThanOrEqualTo(48));
    expect(closeDrawer.width, greaterThanOrEqualTo(48));

    // The tab close box is a full-height target inside its own tab.
    final tabClose =
        tester.getRect(find.byTooltip('Close terminal tab').first);
    expect(tabClose.height, greaterThanOrEqualTo(48));
    expect(tabClose.width, greaterThanOrEqualTo(36));
    expect(tester.takeException(), isNull);

    // Tapping the active tab's close box closes that tab only.
    await tester.tap(find.byTooltip('Close terminal tab').first,
        warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(client.disposed, hasLength(1));
    expect(drawerClosed, isFalse);
  });

  testWidgets('wide drawer keeps the desktop 24px close box',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final client = _ReadyClient();
    final workspace = await _workspace(client, tabs: 1);
    addTearDown(workspace.disposeAll);

    await tester.pumpWidget(
        _host(workspace, 1180, onCloseDrawer: () {}));
    await tester.pumpAndSettle();

    final tabClose =
        tester.getRect(find.byTooltip('Close terminal tab').first);
    expect(tabClose.width, closeTo(24, 0.1));
    expect(tabClose.height, closeTo(24, 0.1));
    expect(tester.takeException(), isNull);
  });
}
