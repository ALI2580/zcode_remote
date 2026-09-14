import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/terminal.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/terminal_sessions.dart';
import 'package:zcode_remote/ui/terminal_panel.dart';
import 'package:zcode_remote/ui/theme.dart';
import '../review_capture.dart';

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

class _CaptureClient extends TerminalClient {
  _CaptureClient() : super(session: _LayoutSession());

  int creates = 0;

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
  Future<void> dispose({required String id}) async {}

  @override
  void Function() onData(String id, void Function(String data) listener) {
    return () {};
  }

  @override
  void Function() onExit(String id, void Function(Object? exitCode) listener) {
    return () {};
  }
}

Future<void> _pump(WidgetTester tester, double width, double height) async {
  tester.view.devicePixelRatio = 2;
  tester.view.physicalSize = Size(width * 2, height * 2);
  addTearDown(tester.view.reset);
  final client = _CaptureClient();
  final workspace = TerminalWorkspaceSessions(client: client, cwd: 'C:/x');
  addTearDown(workspace.disposeAll);
  workspace.add();
  await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
          body: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                  width: width,
                  height: 200,
                  child: RepaintBoundary(
                      key: const ValueKey('capture-terminal-drawer'),
                      child: TerminalDrawer(
                          client: client,
                          cwd: 'C:/x',
                          visible: true,
                          workspace: workspace,
                          onCloseDrawer: () {})))))));
  // The xterm view keeps a blinking-cursor ticker running, so a fixed
  // settle window is used instead of pumpAndSettle.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
}

void main() {
  testWidgets('capture compact terminal drawer', (tester) async {

    await _pump(tester, 390, 844);
    await captureReviewFinder(
        tester,
        find.byKey(const ValueKey('capture-terminal-drawer')),
        'terminal-drawer-390');
  });

}
