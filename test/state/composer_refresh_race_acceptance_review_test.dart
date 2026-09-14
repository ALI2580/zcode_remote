import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/composer_store.dart';

import '../ui/fake_workspace.dart';

WorkspacePrep _prep(String label) => WorkspacePrep.fromRaw({
      'configOptions': [
        {
          'id': 'model',
          'category': 'model',
          'type': 'select',
          'currentValue': 'review/model',
          'options': [
            {
              'value': 'review/model',
              'name': label,
              'modelProviderId': 'review',
              'modelProviderName': 'Review'
            }
          ]
        }
      ],
    });

void main() {
  test('review: a late refresh cannot replace newer main and side catalogs',
      () async {
    final bridge = FakeBridge();
    final store = ComposerStore();
    addTearDown(store.dispose);
    final main = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'd',
        workspaceKey: 'w',
        sessionId: 'main');
    final side = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'd',
        workspaceKey: 'w',
        sessionId: 'side');
    main.input.text = 'unsent main';
    side.input.text = 'unsent side';
    final stale = Completer<WorkspacePrep>();
    final fresh = Completer<WorkspacePrep>();
    var calls = 0;
    bridge.conversationTransport.prepHandler =
        () => ++calls == 1 ? stale.future : fresh.future;
    final first = store.refreshScope(deviceId: 'd', workspaceKey: 'w');
    final second = store.refreshScope(deviceId: 'd', workspaceKey: 'w');
    fresh.complete(_prep('After second save'));
    await second;
    stale.complete(_prep('After first save'));
    await first;
    expect(calls, 2,
        reason: 'Each refresh shares one prepare across siblings.');
    expect(main.options.models.single.name, 'After second save');
    expect(side.options.models.single.name, 'After second save');
    expect(main.input.text, 'unsent main');
    expect(side.input.text, 'unsent side');
  });

  test(
      'review: refreshed old transport does not update its replacement controller',
      () async {
    final bridge = FakeBridge();
    final replacement = FakeBridge();
    final store = ComposerStore();
    addTearDown(store.dispose);
    store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'd',
        workspaceKey: 'w',
        sessionId: 'main');
    final stale = Completer<WorkspacePrep>();
    bridge.conversationTransport.prepHandler = () => stale.future;
    final refresh = store.refreshScope(deviceId: 'd', workspaceKey: 'w');
    store.disconnect('d');
    replacement.conversationTransport.prepHandler =
        () async => _prep('New bridge');
    final current = store.obtain(
        transport: replacement.conversationTransport,
        deviceId: 'd',
        workspaceKey: 'w',
        sessionId: 'main');
    await current.loadOptions();
    stale.complete(_prep('Old bridge'));
    await refresh;
    expect(current.options.models.single.name, 'New bridge');
  });
}
