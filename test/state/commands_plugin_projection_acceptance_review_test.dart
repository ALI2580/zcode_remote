import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/state/remote_agent_catalogs.dart';

import '../ui/fake_features.dart';

void main() {
  test('review: command plugin projection follows a delayed shared catalog',
      () async {
    final bridge = FeatureBridge();
    final pluginRead = Completer<Object?>();
    var delayed = true;
    var enabled = true;
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.commands && method == 'list') {
        return {
          'commands': [
            {
              'id': 'plugin-command',
              'name': 'review',
              'source': 'plugin',
              'pluginId': 'demo@official',
              'pluginName': 'Demo',
              'pluginMarketplace': 'official',
            }
          ],
          'capability': {'userScopeAvailable': true},
        };
      }
      if (channel == Channels.pluginManagement && method == 'listPlugins') {
        if (delayed) return pluginRead.future;
        return {
          'plugins': [
            {
              'id': 'demo@official',
              'name': 'Demo',
              'marketplace': 'official',
              'enabled': enabled,
            },
            {
              'id': 'demo@other',
              'name': 'Demo',
              'marketplace': 'other',
              'enabled': true,
            },
          ]
        };
      }
      if (channel == Channels.pluginManagement &&
          method == 'getPluginsOverview') {
        return {
          'availablePlugins': [
            {
              'id': 'demo@official',
              'name': 'Demo',
              'marketplace': 'official',
            }
          ],
          'installedPlugins': [],
          'restorableBuiltins': [],
          'marketplaces': [],
        };
      }
      return <String, dynamic>{};
    };
    final plugins = PluginCatalog(
      bridge: bridge,
      scope: const {'workspaceIdentity': 'synthetic'},
    );
    final commands = CommandsCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'synthetic'},
      scopeKey: 'source',
      pluginCatalog: plugins,
    );
    addTearDown(commands.dispose);
    addTearDown(plugins.dispose);

    await commands.refresh();
    expect(commands.items, hasLength(1));
    expect(commands.visibleItems, isEmpty,
        reason: 'unconfirmed plugin state cannot expose a candidate');

    final pluginRefresh = plugins.refresh();
    await Future<void>.delayed(Duration.zero);
    pluginRead.complete({
      'plugins': [
        {
          'id': 'demo@official',
          'name': 'Demo',
          'marketplace': 'official',
          'enabled': enabled,
        },
        {
          'id': 'demo@other',
          'name': 'Demo',
          'marketplace': 'other',
          'enabled': true,
        },
      ]
    });
    await pluginRefresh;
    expect(commands.visibleItems.map((item) => item.id), ['plugin-command']);

    enabled = false;
    delayed = false;
    // The catalog's notify callback recomputes the projection after a
    // confirmed disabled read; CommandsCatalog itself is not re-read.
    await plugins.refresh();
    expect(commands.visibleItems, isEmpty);

    enabled = true;
    await plugins.refresh();
    expect(commands.visibleItems.map((item) => item.id), ['plugin-command']);
  });
}
