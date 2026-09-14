import 'dart:async';

import 'package:flutter/material.dart';

import '../state/coding_plan_upgrade.dart';
import '../state/client_preferences.dart';
import 'official_icons.dart';
import 'theme.dart';

class UpgradePage extends StatefulWidget {
  const UpgradePage({super.key, required this.catalog});

  final CodingPlanUpgradeCatalog catalog;

  @override
  State<UpgradePage> createState() => _UpgradePageState();
}

class _UpgradePageState extends State<UpgradePage> {
  @override
  void initState() {
    super.initState();
    unawaited(widget.catalog.refresh());
  }

  String _price(CodingPlanProduct product) {
    final amount = product.payAmount ?? product.originalAmount;
    if (amount == null) return '--';
    final value = amount.toStringAsFixed(2);
    return switch (product.priceCurrency?.toUpperCase()) {
      'USD' => '\$$value',
      'CNY' => '¥$value',
      _ => '${product.priceCurrency ?? '--'} $value',
    };
  }

  String _period(BuildContext context, CodingPlanProduct product) {
    return switch (product.priceUnit) {
      'year' => uiText(context, '/年', '/year'),
      'quarter' => uiText(context, '/季', '/quarter'),
      'month' => uiText(context, '/月', '/month'),
      _ => '',
    };
  }

  Widget _productCard(BuildContext context, CodingPlanProduct product) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
            color: ink.surfaceFill, borderRadius: BorderRadius.circular(12)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              spacing: 8,
              runSpacing: 4,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(product.title,
                    style: const TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w500)),
                if (product.subscribed == true)
                  Text(uiText(context, '当前套餐', 'Current'),
                      style: TextStyle(fontSize: 12, color: ink.subtlest)),
              ]),
          if (product.subtitle?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            Text(product.subtitle!,
                style: TextStyle(fontSize: 12, color: ink.subtlest)),
          ],
          const SizedBox(height: 8),
          Text('${_price(product)}${_period(context, product)}',
              style:
                  const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          if (product.description?.isNotEmpty == true) ...[
            const SizedBox(height: 8),
            Text(product.description!),
          ],
          if (product.benefits.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final benefit in product.benefits)
              Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(children: [
                    const LucideIcon('check', size: 14),
                    const SizedBox(width: 6),
                    Expanded(child: Text(benefit)),
                  ])),
          ],
        ]));
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Scaffold(
      appBar: AppBar(title: Text(uiText(context, '升级', 'Upgrade'))),
      body: SafeArea(
        top: false,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 880),
            child: ListenableBuilder(
              listenable: widget.catalog,
              builder: (context, _) {
                final catalog = widget.catalog;
                return ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      uiText(context, '当前 Coding Plan 来源',
                          'Current Coding Plan source'),
                      style: TextStyle(fontSize: 12, color: ink.subtlest),
                    ),
                    const SizedBox(height: 4),
                    Text(catalog.providerId ?? '--',
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(height: 20),
                    if (catalog.status == CodingPlanUpgradeStatus.error) ...[
                      Text(
                        uiText(context, '套餐价格读取失败，请重试。',
                            'Could not read plan pricing. Retry.'),
                        style: TextStyle(color: ink.diffRemoved),
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton(
                          onPressed: () =>
                              unawaited(catalog.refresh(force: true)),
                          child: Text(uiText(context, '重试', 'Retry')),
                        ),
                      ),
                    ],
                    if (catalog.status == CodingPlanUpgradeStatus.loading)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      ),
                    if (catalog.status == CodingPlanUpgradeStatus.loaded &&
                        catalog.products.isEmpty)
                      Text(
                        uiText(context, '没有可显示的套餐。', 'No plans are available.'),
                        style: TextStyle(color: ink.subtlest),
                      ),
                    if (catalog.status == CodingPlanUpgradeStatus.loaded)
                      for (final product in catalog.products) ...[
                        _productCard(context, product),
                        const SizedBox(height: 16),
                      ],
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
