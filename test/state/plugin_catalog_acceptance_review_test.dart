import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';

import '../ui/fake_features.dart';

void main() {
  test('plugin writes use selected scope and notify only after readback',
      () async {
    final bridge = FeatureBridge();
    var enabled = false;
    final writes = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      expect(channel, Channels.pluginManagement);
      if (method == 'listPlugins') {
        return {
          'plugins': [
            {
              'id': 'scoped@official',
              'name': 'Scoped',
              'marketplace': 'official',
              'enabled': enabled,
              'packageStatus': 'ok',
            }
          ]
        };
      }
      if (method == 'getPluginsOverview') {
        return {
          'availablePlugins': [
            {
              'id': 'scoped@official',
              'name': 'Scoped',
              'marketplace': 'official',
              'installed': true,
            }
          ],
          'installedPlugins': [
            {'id': 'scoped@official', 'scope': 'workspace'}
          ],
          'restorableBuiltins': [],
          'marketplaces': [],
        };
      }
      if (method == 'setPluginEnabled') {
        final value = Map<String, dynamic>.from(args.single as Map);
        writes.add(value);
        enabled = value['enabled'] == true;
        return <String, dynamic>{'success': true};
      }
      return <String, dynamic>{};
    };
    var confirmations = 0;
    final catalog = PluginCatalog(
      bridge: bridge,
      scope: const {'workspaceIdentity': 'review'},
      selectedScope: 'workspace',
      onConfirmed: (_) async => confirmations++,
    );
    try {
      await catalog.refresh();
      final item = catalog.items.single;
      expect(await catalog.enable(item, true), isTrue);
      expect(writes.single['scope'], 'workspace');
      expect(catalog.configurationRevision, 1);
      expect(confirmations, 1);
      expect(catalog.items.single.enabled, isTrue);
    } finally {
      catalog.dispose();
    }
  });

  test('a rejected plugin write keeps the confirmed revision unchanged',
      () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      expect(channel, Channels.pluginManagement);
      if (method == 'listPlugins') {
        return {
          'plugins': [
            {
              'id': 'reject@official',
              'name': 'Reject',
              'marketplace': 'official',
              'enabled': false,
              'packageStatus': 'ok',
            }
          ]
        };
      }
      if (method == 'getPluginsOverview') {
        return {
          'availablePlugins': [
            {
              'id': 'reject@official',
              'name': 'Reject',
              'marketplace': 'official',
              'installed': true,
            }
          ],
          'installedPlugins': [
            {'id': 'reject@official', 'scope': 'user'}
          ],
          'restorableBuiltins': [],
          'marketplaces': [],
        };
      }
      if (method == 'setPluginEnabled') {
        return <String, dynamic>{
          'success': false,
          'diagnostics': [
            {'severity': 'error', 'message': 'synthetic rejection'}
          ]
        };
      }
      return <String, dynamic>{};
    };
    var confirmations = 0;
    final catalog = PluginCatalog(
      bridge: bridge,
      scope: const {},
      onConfirmed: (_) async => confirmations++,
    );
    try {
      await catalog.refresh();
      expect(await catalog.enable(catalog.items.single, true), isFalse);
      expect(catalog.configurationRevision, 0);
      expect(confirmations, 0);
      expect(catalog.items.single.enabled, isFalse);
    } finally {
      catalog.dispose();
    }
  });
}
