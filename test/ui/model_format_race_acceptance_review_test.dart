import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/model_provider_catalog.dart';
import 'package:zcode_remote/state/model_connectivity.dart';
import 'package:zcode_remote/ui/model_provider_editor.dart';
import 'fake_features.dart';

void main() {
  testWidgets(
      'review: a queued API format selection survives an earlier provider readback',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1000);
    addTearDown(tester.view.reset);
    final bridge = FeatureBridge();
    final gate = Completer<void>();
    var confirmed = <String, dynamic>{
      'id': 'format-race',
      'name': 'Initial name',
      'source': 'custom',
      'apiFormat': 'anthropic-messages',
      'defaultKind': 'anthropic',
      'endpoints': {
        'baseURL': 'https://synthetic.invalid',
        'paths': {'anthropic-messages': '/v1/messages'}
      },
      'apiKey': 'synthetic-key',
      'models': <Map<String, dynamic>>[],
    };
    final saves = <Map<String, dynamic>>[];
    bridge.channels.handler = (_, method, args) async {
      if (method == 'save') {
        final payload = Map<String, dynamic>.from(args.single as Map);
        saves.add(payload);
        if (saves.length == 1) await gate.future;
        confirmed = payload;
        return null;
      }
      if (method == 'getDisplayOrder') return <String>[];
      return [confirmed];
    };
    final catalog = ModelProvidersCatalog(session: bridge, scopeKey: 'race');
    final connectivity =
        ModelConnectivityController(session: bridge, scopeKey: 'race');
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ModelProviderEditor(
                  provider: ModelProviderEntry.fromRaw(confirmed),
                  catalog: catalog,
                  connectivity: connectivity))));
      await tester.pump();
      Finder field(String name) => find.byWidgetPredicate((widget) =>
          widget is TextField && widget.decoration?.labelText == name);
      await tester.enterText(field('Name'), 'Queued name');
      await tester.tap(field('Base URL'));
      await tester.pump();
      expect(saves, hasLength(1));
      final format = find.byType(DropdownButtonFormField<String>);
      await tester.ensureVisible(format);
      await tester.tap(format);
      await tester.pumpAndSettle();
      await tester.tap(find.text('openai-responses').last);
      await tester.pumpAndSettle();
      gate.complete();
      await tester.pumpAndSettle();
      expect(confirmed['name'], 'Queued name');
      expect(confirmed['apiFormat'], 'openai-responses',
          reason:
              'The later dropdown edit is unsaved until its queued commit completes.');
      expect((confirmed['endpoints'] as Map)['paths'],
          {'openai-responses': '/responses'});
      expect(tester.takeException(), isNull);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
      connectivity.dispose();
    }
  });
}
