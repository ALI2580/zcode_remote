import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/remote_agent_catalogs.dart';
import '../support/review_channel_bridge.dart';

void main() {
  test(
      'review: hook write readback cannot join a list started before the write',
      () async {
    final bridge = ReviewChannelBridge();
    final staleRead = Completer<Object?>();
    var reads = 0;
    Map<String, dynamic> row = {
      'id': 'a',
      'event': 'Stop',
      'type': 'command',
      'command': 'synthetic',
      'enabled': true,
      'location': {'source': 'zcode', 'scope': 'user'}
    };
    final oldRow = Map<String, dynamic>.from(row);
    bridge.channels.handler = (_, method, args) {
      if (method == 'loadHooks') {
        reads++;
        if (reads == 2) return staleRead.future;
      }
      if (method == 'saveHooks') {
        row = Map<String, dynamic>.from(
            ((args.single as Map)['hooks'] as List).single as Map);
      }
      return {
        'hooks': [row]
      };
    };
    final catalog = HooksCatalog(
        session: bridge,
        scope: const {'workspaceIdentity': 'review'},
        scopeKey: 'device|review');
    addTearDown(catalog.dispose);
    await catalog.refresh();
    final oldRead = catalog.refresh();
    await pumpEventQueue();
    final write = catalog.setEnabled(catalog.items.single, false);
    await pumpEventQueue();
    staleRead.complete({
      'hooks': [oldRow]
    });
    await Future.wait([oldRead, write]);
    expect(row['enabled'], isFalse);
    expect(catalog.items.single.enabled, isFalse,
        reason:
            'A successful write must publish a new authoritative read, not its stale pre-write list.');
  });

  test('review: concurrent hook row changes preserve both whole-list writes',
      () async {
    final bridge = ReviewChannelBridge();
    var server = [
      for (final id in ['a', 'b'])
        <String, dynamic>{
          'id': id,
          'event': 'Stop',
          'type': 'command',
          'command': 'synthetic-$id',
          'enabled': true,
          'location': {'source': 'zcode', 'scope': 'user'}
        }
    ];
    final firstWriteStarted = Completer<void>();
    final releaseFirst = Completer<void>();
    var writes = 0;
    bridge.channels.handler = (_, method, args) async {
      if (method == 'saveHooks') {
        writes++;
        final payload = (args.single as Map)['hooks'] as List;
        final submitted =
            payload.map((e) => Map<String, dynamic>.from(e as Map)).toList();
        if (writes == 1) {
          firstWriteStarted.complete();
          await releaseFirst.future;
        }
        server = submitted;
      }
      return {'hooks': server};
    };
    final catalog = HooksCatalog(
        session: bridge,
        scope: const {'workspaceIdentity': 'review'},
        scopeKey: 'device|review');
    addTearDown(catalog.dispose);
    await catalog.refresh();
    final first = catalog.saveList([
      for (final item in catalog.items)
        item.id == 'a' ? WorkspaceHook.fromRaw(item.withEnabled(false)) : item
    ], errorId: 'a');
    await firstWriteStarted.future;
    final second = catalog.saveList([
      for (final item in catalog.items)
        item.id == 'b' ? WorkspaceHook.fromRaw(item.withEnabled(false)) : item
    ], errorId: 'b');
    await pumpEventQueue();
    releaseFirst.complete();
    await Future.wait([first, second]);
    expect({for (final row in server) row['id']: row['enabled']},
        {'a': false, 'b': false},
        reason:
            'Independent row changes must not overwrite the other row with an old full-list snapshot.');
    expect({for (final row in catalog.items) row.id: row.enabled},
        {'a': false, 'b': false});
  });
}
