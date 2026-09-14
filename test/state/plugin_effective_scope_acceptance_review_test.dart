import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';

import '../support/review_channel_bridge.dart';

void main() {
  test(
      'review: workspace override writes selected scope for a user-installed plugin',
      () async {
    final bridge = ReviewChannelBridge();
    final writes = <Map<String, dynamic>>[];
    var enabled = true;
    bridge.channels.handler = (_, method, args) {
      if (method == 'listPlugins') {
        return {
          'plugins': [
            {
              'id': 'inherited@synthetic',
              'name': 'inherited',
              'marketplace': 'synthetic',
              'enabled': enabled,
              'scope': 'user',
              'enabledSource': 'user',
              'packageStatus': 'ok',
            }
          ]
        };
      }
      if (method == 'getPluginsOverview') {
        return {
          'installedPlugins': [
            {'id': 'inherited@synthetic', 'scope': 'user'}
          ]
        };
      }
      if (method == 'setPluginEnabled') {
        final payload = Map<String, dynamic>.from(args.single as Map);
        writes.add(payload);
        enabled = payload['enabled'] == true;
        return {'success': true};
      }
      return <String, dynamic>{};
    };
    final catalog = PluginCatalog(
        bridge: bridge,
        selectedScope: 'workspace',
        scope: const {
          'workspaceIdentity': 'workspace',
          'workspacePath': 'D:/Synthetic'
        });
    try {
      await catalog.refresh();
      expect(catalog.items.single.installScope, 'user');
      expect(await catalog.enable(catalog.items.single, false), isTrue);
      expect(writes.single['scope'], 'workspace',
          reason:
              'Official HXt passes configScope to setEnabled; install location does not choose the override scope.');
    } finally {
      catalog.dispose();
    }
  });
}
