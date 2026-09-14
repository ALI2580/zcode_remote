import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/ui/plugins_settings.dart';

import 'fake_features.dart';

void main() {
  testWidgets('review: sensitive clear is explicit and undoable',
      (tester) async {
    final bridge = FeatureBridge();
    final writes = <Map<String, dynamic>>[];
    bridge.channels.handler = (_, method, args) {
      if (method == 'listPlugins') {
        return {
          'plugins': [
            {
              'id': 'clear@synthetic',
              'name': 'Clear',
              'marketplace': 'synthetic',
              'enabled': true,
              'packageStatus': 'ok',
              'userConfig': {
                'token': {
                  'type': 'string',
                  'title': 'Token',
                  'sensitive': true,
                },
              },
              'configuredOptions': {'token': 'secret'},
              'optionSources': {'token': 'user'},
            }
          ]
        };
      }
      if (method == 'getPluginsOverview') {
        return {
          'availablePlugins': [
            {
              'id': 'clear@synthetic',
              'name': 'Clear',
              'marketplace': 'synthetic',
              'installed': true,
            }
          ],
          'installedPlugins': [
            {'id': 'clear@synthetic', 'scope': 'user'}
          ],
        };
      }
      if (method == 'configurePlugin') {
        writes.add(Map<String, dynamic>.from(args.single as Map));
        return {'success': true};
      }
      return <String, dynamic>{};
    };
    final catalog = PluginCatalog(bridge: bridge, scope: const {});
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: PluginsSettingsPage(catalog: catalog))));
      await tester.pumpAndSettle();
      await tester
          .tap(find.byKey(const ValueKey('plugin-actions-clear@synthetic')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Configure'));
      await tester.pumpAndSettle();
      final clear = find.byKey(const ValueKey('plugin-config-clear-token'));
      expect(clear, findsOneWidget);
      await tester.tap(clear);
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('plugin-configuration-save')));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(writes.single['options'], isEmpty);
      expect(writes.single['clearOptionKeys'], ['token']);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    }
  });
}
