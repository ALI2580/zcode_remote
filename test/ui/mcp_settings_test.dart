import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/mcp_catalog.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/ui/mcp_settings.dart';

import '../ui/fake_features.dart';

void main() {
  testWidgets('MCP page renders installed rows and separates status actions',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (method == 'loadMcpFromUserDirectory') {
        return {
          'servers': [
            {
              'id': 'user:docs:',
              'name': 'docs-server',
              'source': 'zcodeagentmcp',
              'scope': 'user',
              'enabled': true,
              'config': {
                'type': 'stdio',
                'command': 'node',
                'args': ['server.js'],
              },
            },
            {
              'id': 'plugin:browser',
              'name': 'browser-tools',
              'source': 'plugin',
              'scope': 'user',
              'rawDescription': 'plugin row',
              'description': 'Provided by browser-use',
              'config': {'type': 'http'},
            },
          ]
        };
      }
      if (method == 'listWorkspaceMcpServerStatuses') {
        final mode = (args.single as Map)['mode'];
        expect(mode, 'connect');
        return {
          'statuses': [
            {'name': 'docs-server', 'status': 'connected', 'toolCount': 2}
          ]
        };
      }
      return {};
    };
    final catalog = McpCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'fake'},
      scopeKey: 'device|workspace',
      workspacePath: 'D:/Project',
    );
    addTearDown(catalog.dispose);
    await catalog.loadConfigs();
    await catalog.refreshStatus();

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: McpSettingsPage(
          catalog: catalog,
          scope: 'user',
          onScopeChanged: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('docs-server'), findsOneWidget);
    expect(
        tester
            .widget<Semantics>(
                find.byKey(const ValueKey('mcp-status-user:docs:')))
            .properties
            .label,
        'Connected');
    expect(find.text('Installed'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcp-refresh')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('mcp-enabled-user:docs:')), findsOneWidget);
  });

  testWidgets('MCP form toggles to JSON and saves a streamable HTTP config',
      (tester) async {
    final bridge = FeatureBridge();
    final saves = <Map<String, dynamic>>[];
    bridge.channels.handler = (channel, method, args) {
      if (method == 'saveMcpToUserDirectory') {
        saves.add((args.single as Map).cast<String, dynamic>());
        return {'success': true};
      }
      if (method == 'loadMcpFromUserDirectory') return {'servers': []};
      return {'statuses': []};
    };
    final catalog = McpCatalog(
      session: bridge,
      scope: const {},
      scopeKey: 'fake',
    );
    addTearDown(catalog.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: McpSettingsPage(catalog: catalog, scope: 'user'),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('mcp-create')));
    await tester.pumpAndSettle();
    expect(find.text('New MCP server'), findsOneWidget);
    await tester.tap(find.text('JSON'));
    await tester.pump();
    final editor = find.byKey(const ValueKey('mcp-json-editor'));
    await tester.enterText(editor,
        '{"stream-server":{"type":"streamableHttp","url":"https://example.test/mcp","timeoutMs":12.9}}');
    await tester.tap(find.byKey(const ValueKey('mcp-save')));
    await tester.pumpAndSettle();
    expect(saves, hasLength(1));
    expect(saves.single['action'], 'upsert');
    expect((saves.single['config'] as Map)['type'], 'streamableHttp');
    expect((saves.single['config'] as Map)['timeoutMs'], 12);
  });

  testWidgets('MCP page projects verified plugin MCP capabilities read-only',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (method == 'loadMcpFromUserDirectory') return {'servers': []};
      if (method == 'listWorkspaceMcpServerStatuses') {
        return {
          'statuses': [
            {
              'name': 'plugin:Browser:tabs',
              'pluginId': 'browser@example',
              'runtimeServerName': 'plugin:Browser:tabs',
              'status': 'connected',
              'toolCount': 4,
            }
          ]
        };
      }
      return {};
    };
    final catalog = McpCatalog(
      session: bridge,
      scope: const {},
      scopeKey: 'fake',
    );
    final plugins = PluginCatalog(bridge: bridge, scope: const {});
    plugins.items = [
      CatalogPlugin(
        id: 'browser@example',
        name: 'Browser',
        marketplace: 'official',
        installed: true,
        info: const {
          'enabled': true,
          'mcpServerNames': ['tabs'],
          'declaredMcpServerNames': ['plugin:Browser:tabs'],
          'hostMcpServerNames': <String>[],
        },
      ),
    ];
    addTearDown(() {
      plugins.dispose();
      catalog.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: McpSettingsPage(catalog: catalog, pluginCatalog: plugins),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Browser'), findsOneWidget);
    expect(find.text('tabs'), findsOneWidget);
    expect(find.byKey(const ValueKey('mcp-enabled-browser@example:tabs')),
        findsNothing);
    expect(
        tester
            .widget<Semantics>(
                find.byKey(const ValueKey('mcp-status-browser@example:tabs')))
            .properties
            .label,
        'Connected');
  });
}
