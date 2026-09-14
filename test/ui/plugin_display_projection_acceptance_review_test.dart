import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/mcp_catalog.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/state/skills_catalog.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/mcp_settings.dart';
import 'package:zcode_remote/ui/skills_settings.dart';

import 'fake_features.dart';

void main() {
  for (final page in ['skills', 'mcp']) {
    testWidgets(
        'review: $page uses plugin display names rather than category names',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(1180, 1200);
      addTearDown(tester.view.reset);
      final preferences = ClientPreferences();
      await preferences.setLanguage('en');
      final bridge = FeatureBridge();
      bridge.channels.handler = (channel, method, args) {
        if (channel == Channels.skills) {
          return {
            'count': 999,
            'capability': {'supported': true, 'count': 999},
            'skills': [
              for (final name in ['alpha', 'beta'])
                {
                  'id': '$name-skill',
                  'name': '$name-skill',
                  'path': 'D:/Synthetic/$name/SKILL.md',
                  'scope': 'plugin',
                  'pluginId': '$name@synthetic',
                  'pluginName': name,
                  'pluginMarketplace': 'synthetic',
                  'enabled': true,
                }
            ]
          };
        }
        if (method == 'loadMcpFromUserDirectory') return {'servers': []};
        return <String, dynamic>{};
      };
      final plugins = PluginCatalog(bridge: bridge, scope: const {});
      plugins.items = [
        for (final name in ['alpha', 'beta'])
          CatalogPlugin(
              id: '$name@synthetic',
              name: name,
              marketplace: 'synthetic',
              installed: true,
              info: {
                'enabled': true,
                'scope': 'user',
                'listing': {
                  'category': 'browser',
                  'displayName':
                      name == 'alpha' ? 'Alpha default' : 'Browser Beta',
                  if (name == 'alpha')
                    'displayNameI18n': {'en-US': 'Browser Alpha'},
                },
                'declaredMcpServerNames': ['$name-mcp'],
                'mcpServerNames': ['plugin:$name:$name-mcp'],
              })
      ];
      final skills = SkillsCatalog(
          transport: bridge.conversationTransport,
          scopeKey: 'review',
          workspacePath: 'D:/Synthetic');
      final mcp =
          McpCatalog(session: bridge, scope: const {}, scopeKey: 'review');
      try {
        await tester.pumpWidget(ZcodeRemoteApp(
            preferences: preferences,
            home: Scaffold(
                body: SingleChildScrollView(
                    child: page == 'skills'
                        ? SkillsSettingsPage(
                            catalog: skills, pluginCatalog: plugins)
                        : McpSettingsPage(
                            catalog: mcp, pluginCatalog: plugins)))));
        await tester.pumpAndSettle();
        expect(find.text('Browser Alpha'), findsOneWidget,
            reason:
                'Official jy/ky uses locale-compatible displayNameI18n first.');
        expect(find.text('Browser Beta'), findsOneWidget,
            reason:
                'Two plugins in the same category retain distinct display names.');
        if (page == 'skills') {
          expect(find.text('Skills 2'), findsOneWidget,
              reason:
                  'Official DXt counts visible local plus plugin rows, not an unrelated capability count.');
          await tester.enterText(
              find.byKey(const ValueKey('skills-search')), 'beta-skill');
          await tester.pumpAndSettle();
          expect(find.text('Skills 1'), findsOneWidget);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        skills.dispose();
        mcp.dispose();
        plugins.dispose();
        preferences.dispose();
      }
    });
  }
}
