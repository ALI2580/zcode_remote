import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/composer_store.dart';

import '../ui/fake_workspace.dart';

WorkspacePrep _prep(String name) => WorkspacePrep.fromRaw({
      'configOptions': [
        {
          'id': 'model',
          'name': 'Model',
          'category': 'model',
          'type': 'select',
          'currentValue': 'review/m1',
          'options': [
            {
              'value': 'review/m1',
              'name': name,
              'modelProviderId': 'review',
              'modelProviderName': 'Review',
            }
          ],
        }
      ],
    });

void main() {
  test('refreshScope updates sibling panes and isolates another device',
      () async {
    final first = FakeBridge();
    final second = FakeBridge();
    var firstName = 'Before';
    first.conversationTransport.prepHandler = () async => _prep(firstName);
    second.conversationTransport.prepHandler = () async => _prep('Other');
    final store = ComposerStore();
    addTearDown(store.dispose);

    final main = store.obtain(
        transport: first.conversationTransport,
        deviceId: 'device-a',
        workspaceKey: 'workspace',
        sessionId: 'main');
    final side = store.obtain(
        transport: first.conversationTransport,
        deviceId: 'device-a',
        workspaceKey: 'workspace',
        sessionId: 'side');
    final other = store.obtain(
        transport: second.conversationTransport,
        deviceId: 'device-b',
        workspaceKey: 'workspace',
        sessionId: 'main');
    await Future.wait([main.loadOptions(), side.loadOptions(), other.loadOptions()]);
    main.input.text = 'keep main';
    side.input.text = 'keep side';
    firstName = 'After';

    await store.refreshScope(deviceId: 'device-a', workspaceKey: 'workspace');

    expect(main.options.models.single.name, 'After');
    expect(side.options.models.single.name, 'After');
    expect(other.options.models.single.name, 'Other');
    expect(main.input.text, 'keep main');
    expect(side.input.text, 'keep side');
  });

  test('a late prepare cannot update a controller replaced in the same scope',
      () async {
    final bridge = FakeBridge();
    final replacementBridge = FakeBridge();
    final pending = Completer<WorkspacePrep>();
    bridge.conversationTransport.prepHandler = () => pending.future;
    replacementBridge.conversationTransport.prepHandler =
        () async => _prep('Replacement');
    final store = ComposerStore();
    addTearDown(store.dispose);
    final old = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'device-a',
        workspaceKey: 'workspace',
        sessionId: 'main');
    final refreshing = store.refreshScope(
        deviceId: 'device-a', workspaceKey: 'workspace');
    final replacement = store.obtain(
        transport: replacementBridge.conversationTransport,
        deviceId: 'device-a',
        workspaceKey: 'workspace',
        sessionId: 'main');
    await replacement.loadOptions();
    pending.complete(_prep('Late old result'));
    await refreshing;

    expect(identical(old, replacement), isFalse);
    expect(replacement.options.models.single.name, 'Replacement');
  });
}
