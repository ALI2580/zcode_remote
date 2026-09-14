import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/coding_plan_upgrade.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/upgrade_page.dart';
import 'fake_features.dart';

import 'dart:async';

Map<String, dynamic> get _pricing => {
      'authenticated': true,
      'productList': [
        {
          'productId': 'lite-month',
          'productName': 'GLM Coding Plan Lite',
          'productSmallTitle': 'Monthly',
          'priceUnit': 'month',
          'priceCurrency': 'USD',
          'payAmount': 8,
          'subscribed': true,
          'productEquityList': [
            {
              'productEquityTitle': 'Tokens',
              'productEquityDetails': ['120 million / month'],
            }
          ],
        }
      ],
    };

void main() {
  testWidgets('upgrade page renders official pricing products read-only',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'setting') return {'providerFamilyDomain': 'zai'};
      return {};
    };
    bridge.conversationTransport.teamProductsHandler = (_) async => _pricing;
    final controller = CodingPlanUpgradeCatalog(
        session: bridge,
        transport: bridge.conversationTransport,
        scopeKey: 'device|workspace');
    addTearDown(controller.dispose);

    await tester
        .pumpWidget(ZcodeRemoteApp(home: UpgradePage(catalog: controller)));
    await tester.pumpAndSettle();
    expect(find.text('Upgrade'), findsOneWidget);
    expect(find.text('builtin:zai-coding-plan'), findsOneWidget);
    expect(find.text('GLM Coding Plan Lite'), findsOneWidget);
    expect(find.text('\$8.00/month'), findsOneWidget);
    expect(find.text('Current'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
  });

  testWidgets('upgrade page exposes retry when pricing read fails',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler =
        (channel, method, args) => {'providerFamilyDomain': 'zai'};
    bridge.conversationTransport.teamProductsHandler =
        (_) async => Future<Object?>.error(StateError('offline'));
    final controller = CodingPlanUpgradeCatalog(
        session: bridge,
        transport: bridge.conversationTransport,
        scopeKey: 'device|workspace');
    addTearDown(controller.dispose);

    await tester
        .pumpWidget(ZcodeRemoteApp(home: UpgradePage(catalog: controller)));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not read plan pricing'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  testWidgets('upgrade page shows loading and empty states without purchases',
      (tester) async {
    final bridge = FeatureBridge();
    final gate = Completer<Map<String, dynamic>>();
    bridge.channels.handler =
        (channel, method, args) => {'providerFamilyDomain': 'zai'};
    bridge.conversationTransport.teamProductsHandler = (_) async => gate.future;
    final controller = CodingPlanUpgradeCatalog(
        session: bridge,
        transport: bridge.conversationTransport,
        scopeKey: 'device|workspace');
    addTearDown(controller.dispose);

    await tester
        .pumpWidget(ZcodeRemoteApp(home: UpgradePage(catalog: controller)));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    gate.complete({
      'authenticated': true,
      'productList': [],
    });
    await tester.pumpAndSettle();
    expect(find.text('No plans are available.'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
  });
}
