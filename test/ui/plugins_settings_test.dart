import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/ui/plugins_settings.dart';

import 'fake_features.dart';

void main() {
  testWidgets('plugin settings renders scoped installed state and searches',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      expect(channel, Channels.pluginManagement);
      if (method == 'listPlugins') {
        return {
          'plugins': [
            {
              'id': 'workspace-tool@official',
              'name': 'Workspace Tool',
              'marketplace': 'official',
              'enabled': true,
              'scope': 'workspace',
              'packageStatus': 'ok',
            }
          ]
        };
      }
      if (method == 'getPluginsOverview') {
        return {
          'availablePlugins': [
            {
              'id': 'workspace-tool@official',
              'name': 'Workspace Tool',
              'marketplace': 'official',
              'installed': true,
              'description': 'Workspace actions',
            }
          ],
          'installedPlugins': [
            {'id': 'workspace-tool@official', 'scope': 'workspace'}
          ],
          'restorableBuiltins': [],
          'marketplaces': [],
        };
      }
      return <String, dynamic>{};
    };
    final catalog = PluginCatalog(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'review',
          'workspacePath': 'D:/Synthetic',
        },
        selectedScope: 'workspace');
    try {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
              body:
                  PluginsSettingsPage(catalog: catalog, scope: 'workspace'))));
      await tester.pumpAndSettle();
      expect(find.text('Workspace Tool'), findsOneWidget);
      expect(find.text('Plugins 1'), findsOneWidget);

      await tester.enterText(
          find.byKey(const ValueKey('plugins-search')), 'nope');
      await tester.pump();
      expect(find.text('Workspace Tool'), findsNothing);
      expect(find.text('No matching plugins.'), findsOneWidget);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    }
  });

  testWidgets('plugin settings writes the selected workspace scope',
      (tester) async {
    final bridge = FeatureBridge();
    final writes = <Map<String, dynamic>>[];
    var enabled = false;
    bridge.channels.handler = (channel, method, args) {
      expect(channel, Channels.pluginManagement);
      if (method == 'listPlugins') {
        return {
          'plugins': [
            {
              'id': 'toggle@official',
              'name': 'Toggle',
              'marketplace': 'official',
              'enabled': enabled,
              'scope': 'workspace',
              'packageStatus': 'ok',
            }
          ]
        };
      }
      if (method == 'getPluginsOverview') {
        return {
          'availablePlugins': [
            {
              'id': 'toggle@official',
              'name': 'Toggle',
              'marketplace': 'official',
              'installed': true,
            }
          ],
          'installedPlugins': [
            {'id': 'toggle@official', 'scope': 'workspace'}
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
    final catalog = PluginCatalog(
        bridge: bridge,
        scope: const {
          'workspaceIdentity': 'review',
          'workspacePath': 'D:/Synthetic',
        },
        selectedScope: 'workspace');
    try {
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData.light(),
          home: Scaffold(
              body:
                  PluginsSettingsPage(catalog: catalog, scope: 'workspace'))));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('plugin-enabled-toggle@official')));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(writes.single['scope'], 'workspace');
      expect(writes.single['enabled'], isTrue);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    }
  });

  testWidgets('plugin configuration is reachable and uses the confirmed write',
      (tester) async {
    final bridge = FeatureBridge();
    final configurations = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      expect(channel, Channels.pluginManagement);
      if (method == 'listPlugins') {
        return {
          'plugins': [
            {
              'id': 'configured@official',
              'name': 'Configured',
              'marketplace': 'official',
              'enabled': true,
              'packageStatus': 'ok',
              'userConfig': {
                'token': {
                  'type': 'string',
                  'title': 'Token',
                  'sensitive': true,
                }
              }
            }
          ]
        };
      }
      if (method == 'getPluginsOverview') {
        return {
          'availablePlugins': [
            {
              'id': 'configured@official',
              'name': 'Configured',
              'marketplace': 'official',
              'installed': true,
            }
          ],
          'installedPlugins': [
            {'id': 'configured@official', 'scope': 'user'}
          ],
          'restorableBuiltins': [],
          'marketplaces': [],
        };
      }
      if (method == 'configurePlugin') {
        configurations.add(Map<String, dynamic>.from(args.single as Map));
        return <String, dynamic>{'success': true};
      }
      return <String, dynamic>{};
    };
    final catalog = PluginCatalog(bridge: bridge, scope: const {});
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: PluginsSettingsPage(catalog: catalog))));
      await tester.pumpAndSettle();
      await tester.tap(
          find.byKey(const ValueKey('plugin-actions-configured@official')));
      await tester.pumpAndSettle();
      expect(find.text('Configure'), findsOneWidget);
      await tester.tap(find.text('Configure'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plugin-configuration-dialog')),
          findsOneWidget);
      await tester.enterText(find.byType(TextFormField), 'synthetic-value');
      await tester.tap(find.byKey(const ValueKey('plugin-configuration-save')));
      await tester.pumpAndSettle();
      expect(configurations, hasLength(1));
      expect((configurations.single['options'] as Map)['token'],
          'synthetic-value');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    }
  });
}
