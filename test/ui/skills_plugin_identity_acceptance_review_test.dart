import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/state/skills_catalog.dart';
import 'package:zcode_remote/ui/skills_settings.dart';
import 'fake_features.dart';

void main() {
  testWidgets(
      'review: a disabled plugin skill cannot borrow an enabled namesake identity',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, _) {
      if (channel == Channels.skills) {
        return {
          'skills': [
            {
              'id': 'original-skill',
              'name': 'original-skill',
              'scope': 'plugin',
              'path': 'C:/Synthetic/skill.md',
              'pluginId': 'same-name@original',
              'pluginName': 'same-name',
              'pluginMarketplace': 'original',
              'enabled': true
            }
          ]
        };
      }
      if (method == 'listPlugins') {
        return {
          'plugins': [
            for (final marketplace in ['original', 'unrelated'])
              {
                'id': 'same-name@$marketplace',
                'name': 'same-name',
                'marketplace': marketplace,
                'enabled': marketplace == 'unrelated'
              }
          ]
        };
      }
      if (method == 'getPluginsOverview') {
        return {
          'installedPlugins': [
            for (final marketplace in ['original', 'unrelated'])
              {'id': 'same-name@$marketplace', 'scope': 'user'}
          ]
        };
      }
      return <String, dynamic>{};
    };
    final plugins = PluginCatalog(bridge: bridge, scope: const {});
    final skills = SkillsCatalog(
        transport: bridge.conversationTransport,
        scopeKey: 'review',
        workspacePath: 'D:/Synthetic');
    try {
      await plugins.refresh();
      expect(plugins.items, hasLength(2));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SkillsSettingsPage(
                  catalog: skills, pluginCatalog: plugins))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('skill-item-original-skill-plugin')),
          findsNothing,
          reason:
              'The explicit plugin ID identifies the disabled original plugin; an enabled namesake is unrelated.');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      skills.dispose();
      plugins.dispose();
    }
  });
}
