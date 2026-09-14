import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/remote_agent_catalogs.dart';
import '../support/review_channel_bridge.dart';

void main() {
  test(
      'review: a committed write with failed readback is refreshed before the next write',
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
          'location': {'source': 'zcode', 'scope': 'user'},
        }
    ];
    var reads = 0;
    var failReadback = true;
    bridge.channels.handler = (_, method, args) {
      if (method == 'loadHooks') {
        reads++;
        if (reads == 2 && failReadback) {
          failReadback = false;
          throw StateError('synthetic readback failure');
        }
        return {'hooks': server};
      }
      if (method == 'saveHooks') {
        server = ((args.single as Map)['hooks'] as List)
            .whereType<Map>()
            .map((row) => row.cast<String, dynamic>())
            .toList();
      }
      return {'hooks': server};
    };

    final catalog = HooksCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'review'},
      scopeKey: 'device|review',
    );
    addTearDown(catalog.dispose);
    await catalog.refresh();

    await catalog.setEnabled(catalog.items.first, false);
    expect(catalog.items.first.enabled, isTrue);
    expect(catalog.saveError('toggle-a'), isA<StateError>());

    await catalog.setEnabled(catalog.items[1], false);
    expect(
      {for (final row in server) row['id']: row['enabled']},
      {'a': false, 'b': false},
    );
    expect(
      {for (final row in catalog.items) row.id: row.enabled},
      {'a': false, 'b': false},
    );
    expect(catalog.saveError('toggle-b'), isNull);
  });

  test('review: an uncertain save response is refreshed before the next write',
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
          'location': {'source': 'zcode', 'scope': 'user'},
        }
    ];
    var failSaveResponse = true;
    bridge.channels.handler = (_, method, args) {
      if (method == 'loadHooks') return {'hooks': server};
      if (method == 'saveHooks') {
        server = ((args.single as Map)['hooks'] as List)
            .whereType<Map>()
            .map((row) => row.cast<String, dynamic>())
            .toList();
        if (failSaveResponse) {
          failSaveResponse = false;
          throw StateError('synthetic response lost after commit');
        }
      }
      return {'hooks': server};
    };
    final catalog = HooksCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'review'},
      scopeKey: 'device|review',
    );
    addTearDown(catalog.dispose);
    await catalog.refresh();

    await catalog.setEnabled(catalog.items.first, false);
    expect(server.first['enabled'], isFalse);
    expect(catalog.items.first.enabled, isTrue);

    await catalog.setEnabled(catalog.items[1], false);
    expect(
      {for (final row in server) row['id']: row['enabled']},
      {'a': false, 'b': false},
    );
  });
}
