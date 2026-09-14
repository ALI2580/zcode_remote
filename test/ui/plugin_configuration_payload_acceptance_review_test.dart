import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/ui/plugins_settings.dart';

import 'fake_features.dart';

void main() {
  for (final change in ['none', 'number', 'invalid-number']) {
    testWidgets(
        'review: plugin configuration sends only meaningful edits $change',
        (tester) async {
      final bridge = FeatureBridge();
      final writes = <Map<String, dynamic>>[];
      bridge.channels.handler = (_, method, args) {
        if (method == 'listPlugins') {
          return {
            'plugins': [
              {
                'id': 'review@synthetic',
                'name': 'review',
                'marketplace': 'synthetic',
                'scope': 'user',
                'enabled': true,
                'packageStatus': 'ok',
                'userConfig': {
                  'token': {
                    'type': 'string',
                    'title': 'Token',
                    'sensitive': true
                  },
                  'count': {'type': 'number', 'title': 'Count', 'default': 5},
                  'region': {
                    'type': 'string',
                    'title': 'Region',
                    'default': 'default-region'
                  },
                },
                'configuredOptions': {
                  'count': 8,
                  'region': 'configured-region'
                },
              }
            ]
          };
        }
        if (method == 'getPluginsOverview') {
          return {
            'installedPlugins': [
              {'id': 'review@synthetic', 'scope': 'user'}
            ]
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
            .tap(find.byKey(const ValueKey('plugin-actions-review@synthetic')));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Configure'));
        await tester.pumpAndSettle();
        final token = find.byWidgetPredicate((widget) =>
            widget is TextField && widget.decoration?.labelText == 'Token');
        final count = find.byWidgetPredicate((widget) =>
            widget is TextField && widget.decoration?.labelText == 'Count');
        if (change == 'number') {
          await tester.enterText(token, '');
          await tester.enterText(count, '17');
        } else if (change == 'invalid-number') {
          await tester.enterText(count, 'NaN');
        }
        await tester
            .tap(find.byKey(const ValueKey('plugin-configuration-save')));
        await tester.pumpAndSettle();
        if (change == 'number') {
          expect(writes, hasLength(1));
          expect(writes.single['options'], {'count': 17},
              reason:
                  'Official LXt skips unchanged fields and blank sensitive inputs.');
          expect(writes.single['clearOptionKeys'] ?? [], isEmpty);
        } else {
          expect(writes, isEmpty,
              reason:
                  'Official ke skips empty deltas; LXt never sends non-finite numbers.');
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        catalog.dispose();
      }
    });
  }
}
