import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/remote_agent_catalogs.dart';
import '../support/review_channel_bridge.dart';

void main() {
  for (final operation in ['toggle', 'delete']) {
    test('review: command $operation sends the explicit official file identity',
        () async {
      final bridge = ReviewChannelBridge();
      final calls = <(String, List<Object?>)>[];
      final row = <String, dynamic>{
        'id': 'review',
        'name': '/check',
        'agentSource': 'user',
        'filePath': 'C:/Synthetic/commands/check.md',
        'enabled': true,
        'description': 'Do not send this display metadata in a write request',
        'location': {'source': 'zcode', 'scope': 'user'}
      };
      bridge.channels.handler = (_, method, args) {
        calls.add((method, args));
        return {
          'commands': [row],
          'capability': {'userScopeAvailable': true}
        };
      };
      final catalog = CommandsCatalog(
          session: bridge,
          scope: const {'workspaceIdentity': 'workspace'},
          scopeKey: 'device|workspace',
          workspacePath: 'D:/Synthetic');
      addTearDown(catalog.dispose);
      await catalog.refresh();
      final entry = catalog.items.single;
      if (operation == 'toggle') {
        await catalog.setEnabled(entry, enabled: false);
      } else {
        await catalog.deleteCommand(entry, errorId: 'delete-review');
      }
      final method =
          operation == 'toggle' ? 'setCommandEnabled' : 'deleteCommandFile';
      final call = calls.singleWhere((value) => value.$1 == method);
      expect(
          call.$2.single,
          {
            'agentSource': 'user',
            'commandId': 'review',
            'filePath': 'C:/Synthetic/commands/check.md',
            if (operation == 'toggle') 'enabled': false
          },
          reason:
              'Frozen IXt passes commandId and filePath rather than forwarding the display row.');
    });
  }
}
