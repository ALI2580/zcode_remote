import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/coding_plan_upgrade.dart';

import '../ui/fake_features.dart';

Map<String, dynamic> _pricing() => {
      'authenticated': true,
      'productList': [
        {
          'productId': 'lite-month',
          'productName': 'GLM Coding Plan Lite',
          'productSmallTitle': 'Monthly',
          'productDescription': 'Synthetic starter plan',
          'priceUnit': 'month',
          'priceCurrency': 'USD',
          'originalAmount': 10,
          'payAmount': 8,
          'subscribed': true,
          'productEquityList': [
            {
              'productEquityTitle': 'Tokens',
              'productEquityDetails': ['120', 'million', 'month'],
            }
          ],
        }
      ],
    };

void main() {
  test('upgrade catalog resolves family and reads authenticated pricing',
      () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'setting') {
        expect(method, 'get');
        return {'providerFamilyDomain': 'zai'};
      }
      return {};
    };
    bridge.conversationTransport.teamProductsHandler = (family) async {
      expect(family, 'zai');
      return _pricing();
    };
    final controller = CodingPlanUpgradeCatalog(
        session: bridge,
        transport: bridge.conversationTransport,
        scopeKey: 'device|workspace');
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.status, CodingPlanUpgradeStatus.loaded);
    expect(controller.family, 'zai');
    expect(controller.providerId, 'builtin:zai-coding-plan');
    expect(controller.authenticatedPricing, isTrue);
    final product = controller.products.single;
    expect(product.id, 'lite-month');
    expect(product.title, 'GLM Coding Plan Lite');
    expect(product.payAmount, 8);
    expect(product.subscribed, isTrue);
    expect(product.benefits.single, 'Tokens: 120 · million · month');
  });

  test('a failed pricing read keeps prior products and retry succeeds',
      () async {
    final bridge = FeatureBridge();
    var fail = false;
    bridge.channels.handler =
        (channel, method, args) => {'providerFamilyDomain': 'bigmodel'};
    bridge.conversationTransport.teamProductsHandler = (_) async {
      if (fail) throw StateError('offline');
      return _pricing();
    };
    final controller = CodingPlanUpgradeCatalog(
        session: bridge,
        transport: bridge.conversationTransport,
        scopeKey: 'device|workspace');
    addTearDown(controller.dispose);
    await controller.refresh();

    fail = true;
    await controller.refresh(force: true);
    expect(controller.status, CodingPlanUpgradeStatus.error);
    expect(controller.products.single.id, 'lite-month');
    expect(controller.providerId, 'builtin:bigmodel-coding-plan');

    fail = false;
    bridge.channels.handler =
        (channel, method, args) => {'providerFamilyDomain': 'bigmodel'};
    bridge.conversationTransport.teamProductsHandler = (_) async => _pricing();
    await controller.refresh(force: true);
    expect(controller.status, CodingPlanUpgradeStatus.loaded);
    expect(controller.family, 'bigmodel');
    expect(controller.providerId, 'builtin:bigmodel-coding-plan');
  });

  test('a disposed catalog does not apply a late response', () async {
    final bridge = FeatureBridge();
    final gate = Completer<Object?>();
    bridge.channels.handler = (channel, method, args) {
      if (channel == 'setting') return {'providerFamilyDomain': 'zai'};
      return gate.future;
    };
    final controller = CodingPlanUpgradeCatalog(
        session: bridge,
        transport: bridge.conversationTransport,
        scopeKey: 'device|workspace');
    final pending = controller.refresh();
    await pumpEventQueue();
    controller.dispose();
    gate.complete(_pricing());
    await pending;
    expect(controller.products, isEmpty);
  });
}
