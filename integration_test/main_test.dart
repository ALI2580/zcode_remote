import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/connection_params.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';

/// Read-only integration probe (project-cognition: 集成测试只做只读探针).
/// Connects to a real desktop (URL via `--dart-define=ZEMOTE_PROBE_URL=...`),
/// pairs, bootstraps, opens the first workspace bridge, subscribes to the
/// sessions-index, then DUMPS the newest task's conversation row structure
/// (kind/rowId/turnId/text length/state) so real-world grouping/ordering can
/// be diagnosed without guessing.
///
/// Without a URL the test SKIPS (CI-safe): nothing is mutated server-side.
void main() {
  test('protocol probe (read-only)', () async {
    final probeUrl = String.fromEnvironment('ZEMOTE_PROBE_URL', defaultValue: '');
    final params = probeUrl.isEmpty ? null : ZemoteConnectionParams.parse(probeUrl);
    if (params == null) {
      // ignore: avoid_print
      print('SKIP: ZEMOTE_PROBE_URL not set. Run with '
          '--dart-define=ZEMOTE_PROBE_URL=<remote-control-url>');
      return;
    }

    final client = ZemoteClient(params);
    await client.connect();
    await client.waitPaired(timeout: const Duration(seconds: 60));
    // ignore: avoid_print
    print('=== paired ===');

    final bootstrap = await client.bootstrap();
    final wsList = bootstrap['workspaces'];
    if (wsList is! List || wsList.isEmpty) {
      // ignore: avoid_print
      print('no workspaces');
      await client.dispose();
      return;
    }
    final w = (wsList.first as Map).cast<String, dynamic>();
    final scope = {
      'workspacePath': w['workspacePath'],
      if (w['workspaceIdentity'] != null)
        'workspaceIdentity': w['workspaceIdentity'],
    };
    final workspaceKey =
        w['workspaceIdentity'] as String? ?? w['workspacePath'] as String;
    final bridge = await client.openBridge(workspaceKey);
    final transport = bridge.conversation(scope);
    // ignore: avoid_print
    print('=== bridge opened: $workspaceKey ===');

    // sessions-index: find the most recently active task.
    final si = await transport.subscribeSessionsIndex();
    final siDeadline = DateTime.now().add(const Duration(seconds: 15));
    while (!si.state.ready && DateTime.now().isBefore(siDeadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    final sessions = si.state.list;
    // ignore: avoid_print
    print('=== sessions-index: ${sessions.length} sessions ===');
    for (final s in sessions.take(10)) {
      // ignore: avoid_print
      print('  ${s.sessionId} | ${s.title} | phase=${s.phase}');
    }

    if (sessions.isEmpty) {
      await client.dispose();
      return;
    }

    // Subscribe to the newest session and dump its row structure.
    final target = sessions.first;
    final sub = await transport.subscribe(target.sessionId);
    final deadline = DateTime.now().add(const Duration(seconds: 15));
    while (sub.state.rows.isEmpty && DateTime.now().isBefore(deadline)) {
      await Future.delayed(const Duration(milliseconds: 200));
    }
    // ignore: avoid_print
    print('=== rows: ${sub.state.rows.length} (totalCount='
        '${sub.state.totalCount}) ===');
    for (final row in sub.state.rows) {
      // ignore: avoid_print
      print('  kind=${row['kind']} rowId=${row['rowId']} '
          'turnId=${row['turnId']} state=${row['state']} '
          'text=${'${row['text'] ?? ''}'.length}ch');
    }

    await sub.dispose();
    await si.dispose();
    await client.dispose();
    // ignore: avoid_print
    print('=== probe done ===');
  }, timeout: const Timeout(Duration(minutes: 3)));
}
