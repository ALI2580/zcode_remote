import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/ui/plugins_settings.dart';

import 'fake_features.dart';

void main() {
  for (final action in ['undo', 'cancel', 'failure-retry']) {
    testWidgets('review: plugin configuration $action preserves intent',
        (tester) async {
      final fixture = _PluginFixture();
      final catalog = fixture.catalog();
      try {
        await _show(tester, catalog);
        await _menu(tester, 'Configure');
        await tester
            .tap(find.byKey(const ValueKey('plugin-config-clear-token')));
        await tester.pump();
        expect(fixture.writes, isEmpty);
        if (action == 'undo') {
          await tester.tap(find.byTooltip('Undo clear'));
          await tester.pump();
          await tester
              .tap(find.byKey(const ValueKey('plugin-configuration-save')));
          await tester.pumpAndSettle();
          expect(fixture.writes, isEmpty);
          expect(find.byKey(const ValueKey('plugin-configuration-dialog')),
              findsNothing);
        } else if (action == 'cancel') {
          await tester.tap(find.text('Cancel'));
          await tester.pumpAndSettle();
          expect(fixture.writes, isEmpty);
          await _menu(tester, 'Configure');
          expect(find.byTooltip('Undo clear'), findsNothing);
          expect(find.byTooltip('Clear'), findsOneWidget);
        } else {
          fixture.rejectMutation = true;
          await tester
              .tap(find.byKey(const ValueKey('plugin-configuration-save')));
          await tester.pumpAndSettle();
          expect(find.text('Save failed. The current configuration was kept.'),
              findsOneWidget);
          expect(find.byTooltip('Undo clear'), findsOneWidget);
          expect(catalog.configurationRevision, 0);
          fixture.rejectMutation = false;
          await tester
              .tap(find.byKey(const ValueKey('plugin-configuration-save')));
          await tester.pumpAndSettle();
          expect(fixture.writes, hasLength(2));
          for (final write in fixture.writes) {
            expect(write, {
              'pluginId': 'review@synthetic',
              'scope': 'user',
              'options': <String, dynamic>{},
              'clearOptionKeys': ['token'],
            });
          }
          expect(catalog.configurationRevision, 1);
          expect(find.byKey(const ValueKey('plugin-configuration-dialog')),
              findsNothing);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        catalog.dispose();
      }
    });
  }

  testWidgets('review: workspace restore retries without user-scope writes',
      (tester) async {
    final fixture = _PluginFixture()..workspace = true;
    final catalog = fixture.catalog();
    try {
      await _show(tester, catalog, scope: 'workspace');
      fixture.rejectMutation = true;
      await _menu(tester, 'Restore user default');
      expect(catalog.configurationRevision, 0);
      expect(catalog.items.single.enabledSource, 'workspace');
      fixture.rejectMutation = false;
      await _menu(tester, 'Restore user default');
      expect(fixture.writes, hasLength(2));
      for (final write in fixture.writes) {
        expect(write, {
          'pluginId': 'review@synthetic',
          'scope': 'workspace',
          'configScope': 'workspace',
          'workspacePath': 'C:/Synthetic/Review',
        });
      }
      expect(catalog.configurationRevision, 1);
      expect(catalog.items.single.enabledSource, 'user');
      await tester
          .tap(find.byKey(const ValueKey('plugin-actions-review@synthetic')));
      await tester.pumpAndSettle();
      expect(find.text('Restore user default'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    }
  });

  testWidgets('review: inline plugin detail read failure can retry and return',
      (tester) async {
    final fixture = _PluginFixture()..rejectDescribe = true;
    final catalog = fixture.catalog();
    try {
      await _show(tester, catalog);
      await tester.tap(find.text('Review Plugin').first);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plugin-details')), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(fixture.describeCount, 1);
      expect(
          find.byKey(const ValueKey('plugin-details-retry')), findsOneWidget);
      fixture.rejectDescribe = false;
      await tester.tap(find.byKey(const ValueKey('plugin-details-retry')));
      await tester.pumpAndSettle();
      expect(fixture.describeCount, 2);
      expect(find.text('C:/Synthetic/PluginRoot'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('plugin-details-back')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('plugin-details')), findsNothing);
      expect(fixture.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    }
  });
}

Future<void> _show(WidgetTester tester, PluginCatalog catalog,
    {String scope = 'user'}) async {
  await tester.pumpWidget(MaterialApp(
      home:
          Scaffold(body: PluginsSettingsPage(catalog: catalog, scope: scope))));
  await tester.pumpAndSettle();
}

Future<void> _menu(WidgetTester tester, String action) async {
  await tester
      .tap(find.byKey(const ValueKey('plugin-actions-review@synthetic')));
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

class _PluginFixture {
  final bridge = FeatureBridge();
  final writes = <Map<String, dynamic>>[];
  bool workspace = false;
  bool rejectMutation = false;
  bool rejectDescribe = false;
  bool restored = false;
  int describeCount = 0;

  PluginCatalog catalog() {
    bridge.channels.handler = (_, method, args) {
      if (method == 'listPlugins') {
        return {
          'plugins': [
            {
              'id': 'review@synthetic',
              'name': 'Review Plugin',
              'marketplace': 'synthetic',
              'enabled': true,
              'enabledSource': workspace && !restored ? 'workspace' : 'user',
              'packageStatus': 'ok',
              'userConfig': {
                'token': {
                  'type': 'string',
                  'title': 'Token',
                  'sensitive': true
                },
              },
              'configuredOptions': {'token': 'synthetic-secret'},
              'optionSources': {'token': 'user'},
            }
          ],
        };
      }
      if (method == 'getPluginsOverview') {
        return {
          'availablePlugins': [
            {
              'id': 'review@synthetic',
              'name': 'Review Plugin',
              'marketplace': 'synthetic',
              'installed': true,
            }
          ],
          'installedPlugins': [
            {'id': 'review@synthetic', 'scope': 'user'},
          ],
        };
      }
      if (method == 'configurePlugin' || method == 'resetPluginConfig') {
        writes.add(Map<String, dynamic>.from(args.single as Map));
        if (rejectMutation) return {'success': false};
        if (method == 'resetPluginConfig') restored = true;
        return {'success': true};
      }
      if (method == 'describePlugin') {
        describeCount++;
        if (rejectDescribe) throw StateError('synthetic detail unavailable');
        return {'rootPath': 'C:/Synthetic/PluginRoot'};
      }
      return <String, dynamic>{};
    };
    return PluginCatalog(
        bridge: bridge,
        selectedScope: workspace ? 'workspace' : null,
        scope: workspace
            ? const {
                'workspacePath': 'C:/Synthetic/Review',
              }
            : const {});
  }
}
