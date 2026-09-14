import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/mcp_catalog.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/state/skills_catalog.dart';
import 'package:zcode_remote/ui/mcp_settings.dart';
import 'package:zcode_remote/ui/plugins_settings.dart';
import 'package:zcode_remote/ui/skills_settings.dart';

import 'fake_features.dart';

void main() {
  for (final page in ['plugins', 'mcp', 'skills']) {
    testWidgets(
        'review: $page keeps user-installed capabilities inherited in workspace scope',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 1000);
      addTearDown(tester.view.reset);
      final bridge = FeatureBridge();
      bridge.channels.handler = (channel, method, args) {
        if (method == 'listPlugins') {
          return {
            'plugins': [
              {
                'id': 'inherited@synthetic',
                'name': 'inherited',
                'marketplace': 'synthetic',
                'enabled': true,
                'scope': 'user',
                'enabledSource': 'user',
                'packageStatus': 'ok',
                'declaredMcpServerNames': ['inherited-mcp'],
                'mcpServerNames': ['plugin:inherited:inherited-mcp'],
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
        if (channel == Channels.skills) {
          return {
            'skills': [
              {
                'id': 'inherited-skill',
                'name': 'inherited-skill',
                'scope': 'plugin',
                'path': 'D:/Synthetic/SKILL.md',
                'pluginId': 'inherited@synthetic',
                'pluginName': 'inherited',
                'pluginMarketplace': 'synthetic',
                'enabled': true,
              }
            ]
          };
        }
        if (method == 'loadMcpFromUserDirectory') return {'servers': []};
        return <String, dynamic>{};
      };
      const scope = {
        'workspacePath': 'D:/Synthetic',
        'workspaceIdentity': 'workspace'
      };
      final plugins = PluginCatalog(
          bridge: bridge, scope: scope, selectedScope: 'workspace');
      final mcp = McpCatalog(session: bridge, scope: scope, scopeKey: 'review');
      final skills = SkillsCatalog(
          transport: bridge.conversationTransport,
          scopeKey: 'review',
          workspacePath: 'D:/Synthetic');
      try {
        await plugins.refresh();
        final body = switch (page) {
          'plugins' =>
            PluginsSettingsPage(catalog: plugins, scope: 'workspace'),
          'mcp' => McpSettingsPage(
              catalog: mcp, pluginCatalog: plugins, scope: 'workspace'),
          _ => SkillsSettingsPage(
              catalog: skills, pluginCatalog: plugins, scope: 'workspace'),
        };
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(body: SingleChildScrollView(child: body))));
        await tester.pumpAndSettle();
        final target = switch (page) {
          'plugins' =>
            find.byKey(const ValueKey('plugin-enabled-inherited@synthetic')),
          'mcp' => find.text('inherited-mcp'),
          _ => find.byKey(const ValueKey('skill-item-inherited-skill-plugin')),
        };
        expect(target, findsOneWidget,
            reason:
                'The current configScope projection is authoritative; installation scope does not hide inherited enabled capabilities.');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        plugins.dispose();
        mcp.dispose();
        skills.dispose();
      }
    });
  }
}
