import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/remote_agent_catalogs.dart';

import '../support/review_channel_bridge.dart';

void main() {
  test(
      'review: command confirmation cannot reuse a read started before the write',
      () async {
    final bridge = ReviewChannelBridge();
    var enabled = true;
    var listCalls = 0;
    final oldRead = Completer<Map<String, dynamic>>();
    Map<String, dynamic> snapshot(bool value) => {
          'commands': [
            {
              'id': 'review-command',
              'name': 'review-command',
              'source': 'user',
              'agentSource': 'zcodeAgent',
              'enabled': value,
              'filePath': 'D:/Synthetic/command.md',
              'location': {'source': 'zcode', 'scope': 'user'},
            }
          ]
        };
    bridge.channels.handler = (_, method, args) {
      if (method == 'list') {
        listCalls++;
        if (listCalls == 2) return oldRead.future;
        return snapshot(enabled);
      }
      if (method == 'setCommandEnabled') {
        enabled = (args.single as Map)['enabled'] == true;
        return <String, dynamic>{};
      }
      return <String, dynamic>{};
    };
    final catalog =
        CommandsCatalog(session: bridge, scope: const {}, scopeKey: 'review');
    try {
      await catalog.refresh();
      final originalEntry = catalog.items.single;
      final pending = catalog.refresh();
      final save = catalog.setEnabled(originalEntry, enabled: false);
      await Future<void>.delayed(Duration.zero);
      oldRead.complete(snapshot(true));
      await Future.wait([pending, save]);
      expect(enabled, isFalse);
      expect(catalog.items.single.enabled, isFalse,
          reason:
              'Only a fresh post-write list can confirm the changed command.');
      expect(listCalls, greaterThanOrEqualTo(3));
    } finally {
      if (!oldRead.isCompleted) oldRead.complete(snapshot(true));
      catalog.dispose();
    }
  });
}
