import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/model_connectivity.dart';
import 'package:zcode_remote/state/model_provider_catalog.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/model_provider_editor.dart';

import 'fake_features.dart';
import 'review_capture.dart';

void main() {
  testWidgets(
      'review: provider editor remains usable after a narrow connection failure',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(344, 760);
    addTearDown(tester.view.reset);
    final preferences = ClientPreferences();
    await preferences.setLanguage('en');
    await preferences.setTextScale(1.4);
    await preferences.setTheme(ThemeMode.dark);
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) => {
          'results': [
            {
              'success': false,
              'error': {
                'message':
                    'Synthetic endpoint unavailable. Retry the connection.'
              }
            }
          ],
        };
    final provider = ModelProviderEntry.fromRaw({
      'id': 'visual-review',
      'name': 'Review provider',
      'source': 'custom',
      'apiFormat': 'anthropic-messages',
      'defaultKind': 'anthropic',
      'apiKey': 'synthetic-visual-key',
      'endpoints': {'baseURL': 'https://synthetic.invalid'},
      'models': [
        {
          'id': 'review-model',
          'name': 'Review model',
          'contextWindow': 128000,
          'kinds': ['anthropic'],
          'defaultKind': 'anthropic'
        }
      ],
    });
    final catalog = ModelProvidersCatalog(session: bridge, scopeKey: 'visual');
    final connectivity =
        ModelConnectivityController(session: bridge, scopeKey: 'visual');
    final boundary = GlobalKey();
    try {
      await tester.runAsync(loadReviewCaptureFonts);
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: RepaintBoundary(
            key: boundary,
            child: Scaffold(
                body: SafeArea(
              child: ModelProviderEditor(
                  provider: provider,
                  catalog: catalog,
                  connectivity: connectivity,
                  onCancel: () {}),
            ))),
      ));
      await tester.pumpAndSettle();
      final testButton = find.byTooltip('Test model');
      await tester.ensureVisible(testButton);
      await tester.pump();
      await tester.tap(testButton);
      await tester.pumpAndSettle();
      await captureReviewBoundary(
          tester, boundary, 'u14-provider-error-344-en-140');
      expect(connectivity.resultFor(provider.id, 'review-model')?.success,
          isFalse);
      expect(tester.takeException(), isNull,
          reason:
              'The result and editable context window must remain inside the narrow pane.');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      connectivity.dispose();
      catalog.dispose();
      preferences.dispose();
    }
  });
}
