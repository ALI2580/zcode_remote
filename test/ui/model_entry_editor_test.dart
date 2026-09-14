import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/model_connectivity.dart';
import 'package:zcode_remote/state/model_provider_catalog.dart';
import 'package:zcode_remote/ui/model_provider_editor.dart';

import 'fake_features.dart';

Map<String, dynamic> _providerRaw() => {
      'id': 'entry-provider',
      'name': 'Entry provider',
      'source': 'custom',
      'apiFormat': 'anthropic-messages',
      'defaultKind': 'anthropic',
      'apiKey': 'entry-key',
      'endpoints': {
        'baseURL': 'https://entry.invalid',
        'paths': {'anthropic-messages': '/v1/messages'},
      },
      'models': [
        {
          'id': 'entry-model',
          'name': 'Entry model',
          'kinds': ['anthropic'],
          'defaultKind': 'anthropic',
          'contextWindow': 128000,
          'maxOutputTokens': 8192,
          'modalities': {
            'input': ['text'],
            'output': ['text'],
          },
          'reasoning': {'defaultLevel': 'high'},
        },
      ],
    };

void main() {
  testWidgets(
      'model entry editor tests visible draft before whole-provider save',
      (tester) async {
    final bridge = FeatureBridge();
    Map<String, dynamic>? committed;
    Map<String, dynamic>? tested;
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'testModelConnectivity') {
        tested = args.single as Map<String, dynamic>;
        return {
          'results': [
            {'success': true},
          ],
        };
      }
      return method == 'getDisplayOrder' ? <String>[] : [_providerRaw()];
    };
    final provider = ModelProviderEntry.fromRaw(_providerRaw());
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'entry-scope');
    final connectivity =
        ModelConnectivityController(session: bridge, scopeKey: 'entry-scope');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);

    await tester.pumpWidget(MaterialApp(
      home: ModelEntryEditor(
        provider: provider,
        model: provider.models.single,
        connectivity: connectivity,
        onCommit: (model) async {
          committed = model;
          return true;
        },
        onCancel: () {},
      ),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'Visible label');
    await tester.ensureVisible(find.widgetWithText(FilterChip, 'image'));
    await tester.tap(find.widgetWithText(FilterChip, 'image'));
    final testButton = find.byTooltip('Test model');
    await tester.ensureVisible(testButton);
    await tester.tap(testButton);
    await tester.pumpAndSettle();

    expect(tested, isNotNull);
    expect(tested!['model'], 'entry-model');
    expect(
        (tested!['provider'] as Map)['models'].single['name'], 'Visible label');
    expect((tested!['provider'] as Map)['models'].single['modalities']['input'],
        ['text', 'image']);
    expect(
        bridge.channels.calls.where((call) => call.method == 'save'), isEmpty);

    final save = find.text('Save');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(committed?['name'], 'Visible label');
    expect(committed?['maxOutputTokens'], 8192);
  });

  testWidgets('cancel discards model draft without invoking provider save',
      (tester) async {
    final bridge = FeatureBridge();
    final provider = ModelProviderEntry.fromRaw(_providerRaw());
    final catalog =
        ModelProvidersCatalog(session: bridge, scopeKey: 'entry-cancel');
    final connectivity =
        ModelConnectivityController(session: bridge, scopeKey: 'entry-cancel');
    addTearDown(catalog.dispose);
    addTearDown(connectivity.dispose);
    var commits = 0;
    var cancelled = false;
    await tester.pumpWidget(MaterialApp(
      home: ModelEntryEditor(
        provider: provider,
        model: provider.models.single,
        connectivity: connectivity,
        onCommit: (_) async {
          commits++;
          return true;
        },
        onCancel: () => cancelled = true,
      ),
    ));
    await tester.pump();

    await tester.enterText(find.byType(TextField).first, 'discarded label');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(cancelled, isTrue);
    expect(commits, 0);
    expect(bridge.channels.calls.where((call) => call.method == 'save'),
        isEmpty);
  });
}
