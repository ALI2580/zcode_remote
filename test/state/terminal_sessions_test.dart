import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/terminal.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/terminal_session.dart';
import 'package:zcode_remote/state/terminal_sessions.dart';

class _Bridge implements BridgeSession {
  @override
  final recovered = ValueSignal<int>(0);
  @override
  final recoveryStarting = ValueSignal<int>(0);

  @override
  Future<void> waitHealthy(
          {Duration timeout = const Duration(seconds: 45)}) async =>
      Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

class _Client extends TerminalClient {
  _Client() : super(session: _Bridge());

  @override
  Future<void> dispose({required String id}) async {}
}

TerminalWorkspaceSessions _workspace(String cwd) =>
    TerminalWorkspaceSessions(client: _Client(), cwd: cwd);

void main() {
  test('terminal tabs are bounded and can be activated or closed', () async {
    final workspace = _workspace('D:/work-one');
    addTearDown(() => workspace.disposeAll());

    expect(workspace.controllers, hasLength(1));
    expect(workspace.canAdd, isTrue);
    final second = workspace.add();
    workspace.activate(0);
    expect(workspace.activeController, isNot(same(second)));
    expect(workspace.activeIndex, 0);

    workspace.activate(1);
    expect(workspace.activeController, same(second));

    await workspace.closeAt(0);
    expect(workspace.controllers, hasLength(1));
    expect(workspace.activeController, same(second));
    expect(workspace.activeIndex, 0);
  });

  test('closing the last terminal tab creates a clean replacement', () async {
    final workspace = _workspace('D:/work-two');
    addTearDown(() => workspace.disposeAll());
    final first = workspace.activeController!;
    first.status = TerminalSessionStatus.ready;
    first.terminalId = 'term-1';

    await workspace.closeAt(0);
    expect(workspace.controllers, hasLength(1));
    expect(workspace.activeController, isNot(same(first)));
    expect(workspace.activeController!.status, TerminalSessionStatus.idle);
    expect(workspace.activeController!.terminalId, isNull);
  });

  test('terminal sessions stay isolated by device and workspace', () {
    final store = TerminalSessionStore();
    addTearDown(store.dispose);
    final client = _Client();

    final aliA = store.workspace(
        deviceId: 'ali', workspaceKey: 'a', client: client, cwd: 'D:/ali-a');
    final aliB = store.workspace(
        deviceId: 'ali', workspaceKey: 'b', client: client, cwd: 'D:/ali-b');
    final rogA = store.workspace(
        deviceId: 'rog', workspaceKey: 'a', client: client, cwd: 'D:/rog-a');

    expect(identical(aliA, aliB), isFalse);
    expect(identical(aliA, rogA), isFalse);
    expect(
      identical(
        store.workspace(
            deviceId: 'ali',
            workspaceKey: 'a',
            client: client,
            cwd: 'D:/ali-a'),
        aliA,
      ),
      isTrue,
    );

    store.forgetDevice('ali');
    expect(
      identical(
        store.workspace(
            deviceId: 'ali',
            workspaceKey: 'a',
            client: client,
            cwd: 'D:/ali-a'),
        aliA,
      ),
      isFalse,
    );
    expect(
      identical(
        store.workspace(
            deviceId: 'rog',
            workspaceKey: 'a',
            client: client,
            cwd: 'D:/rog-a'),
        rogA,
      ),
      isTrue,
    );
  });
}
