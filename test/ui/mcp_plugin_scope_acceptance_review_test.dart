import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/mcp_catalog.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/ui/mcp_settings.dart';
import 'fake_features.dart';

void main() {
  testWidgets(
      'review: MCP plugin groups respect installed user and workspace scopes',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 1000);
    addTearDown(tester.view.reset);
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, method, args) {
      final request = args.isNotEmpty && args.single is Map
          ? Map<String, dynamic>.from(args.single as Map)
          : const <String, dynamic>{};
      final configScope =
          request['configScope'] == 'workspace' ? 'workspace' : 'user';
      if (method == 'listPlugins') {
        return {
          'plugins': [
            {
              'id': '$configScope-plugin@synthetic',
              'name': '$configScope-plugin',
              'marketplace': 'synthetic',
              'enabled': true,
              'declaredMcpServerNames': ['$configScope-server'],
              'mcpServerNames': [
                'plugin:$configScope-plugin:$configScope-server'
              ]
            }
          ]
        };
      }
      if (method == 'getPluginsOverview') {
        return {
          'installedPlugins': [
            {'id': '$configScope-plugin@synthetic', 'scope': configScope}
          ]
        };
      }
      return method == 'loadMcpFromUserDirectory'
          ? {'servers': []}
          : {'statuses': []};
    };
    final catalog = McpCatalog(
        session: bridge,
        scope: const {'workspacePath': 'D:/Synthetic'},
        scopeKey: 'workspace');
    PluginCatalog plugins(String scope) => PluginCatalog(
        bridge: bridge,
        scope: const {'workspacePath': 'D:/Synthetic'},
        selectedScope: scope);
    final userPlugins = plugins('user');
    final workspacePlugins = plugins('workspace');
    try {
      await userPlugins.refresh();
      await workspacePlugins.refresh();
      expect(userPlugins.failed, isFalse);
      expect(workspacePlugins.failed, isFalse);
      expect(userPlugins.items, hasLength(1));
      expect(workspacePlugins.items, hasLength(1));
      expect(userPlugins.items.single.declaredMcpServerNames, ['user-server']);
      expect(workspacePlugins.items.single.declaredMcpServerNames,
          ['workspace-server']);
      Widget page(String scope) => MaterialApp(
          home: Scaffold(
              body: McpSettingsPage(
                  key: const ValueKey('same-mcp'),
                  catalog: catalog,
                  pluginCatalog:
                      scope == 'user' ? userPlugins : workspacePlugins,
                  scope: scope)));
      await tester.pumpWidget(page('user'));
      await tester.pumpAndSettle();
      expect(find.text('user-server'), findsOneWidget);
      expect(find.text('workspace-server'), findsNothing,
          reason:
              'Installed scope from plugin overview limits derived MCP groups.');
      await tester.pumpWidget(page('workspace'));
      await tester.pumpAndSettle();
      expect(find.text('workspace-server'), findsOneWidget);
      expect(find.text('user-server'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      userPlugins.dispose();
      workspacePlugins.dispose();
      catalog.dispose();
    }
  });
}
