import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/remote_agent_catalogs.dart';

import '../ui/fake_features.dart';

void main() {
  test(
      'review: an old subagent write does not block or clear a new scope write',
      () async {
    final bridge = FeatureBridge();
    final gates = <Completer<void>>[];
    final row = {
      'id': 'review',
      'name': 'review',
      'scope': 'user',
      'source': 'user',
      'enabled': true
    };
    bridge.channels.handler = (channel, method, args) {
      if (method == 'setEnabled') {
        final gate = Completer<void>();
        gates.add(gate);
        return gate.future;
      }
      return {
        'capability': {'supported': true, 'userScopeAvailable': true},
        'agents': [row],
        'pluginAgents': []
      };
    };
    final catalog = SubagentsCatalog(
        session: bridge,
        scope: const {'workspaceIdentity': 'A'},
        scopeKey: 'device|A');
    try {
      await catalog.refresh();
      final first = catalog.setEnabled(catalog.items.single, enabled: false);
      expect(gates, hasLength(1));
      catalog.updateScope(
          nextScope: const {'workspaceIdentity': 'B'},
          nextScopeKey: 'device|B');
      await catalog.refresh();
      final second = catalog.setEnabled(catalog.items.single, enabled: false);
      expect(gates, hasLength(2),
          reason: 'Pending keys must include the source generation.');
      gates.first.complete();
      await first;
      expect(catalog.isOperating('enabled:review'), isTrue,
          reason: 'The old finally must not remove the new operation.');
      gates.last.complete();
      await second;
      expect(catalog.isOperating('enabled:review'), isFalse);
    } finally {
      for (final gate in gates) {
        if (!gate.isCompleted) gate.complete();
      }
      catalog.dispose();
    }
  });
}
