import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/channel_client.dart';
import '../protocol/conversation.dart';
import '../protocol/zemote_client.dart';

enum CodingPlanUpgradeStatus { idle, loading, loaded, error }

class CodingPlanProduct {
  const CodingPlanProduct({
    required this.id,
    required this.title,
    required this.raw,
    this.subtitle,
    this.description,
    this.priceUnit,
    this.priceCurrency,
    this.originalAmount,
    this.payAmount,
    this.monthlyPayAmount,
    this.subscribed,
    this.benefits = const [],
  });

  factory CodingPlanProduct.fromRaw(Map raw) {
    final map = raw.cast<String, dynamic>();
    String? text(String key) =>
        map[key] is String && (map[key] as String).trim().isNotEmpty
            ? map[key] as String
            : null;
    num? amount(String key) => map[key] is num ? map[key] as num : null;
    final benefits = <String>[];
    final equity = map['productEquityList'];
    if (equity is List) {
      for (final item in equity.whereType<Map>()) {
        final title = item['productEquityTitle'] is String
            ? (item['productEquityTitle'] as String).trim()
            : '';
        final details = item['productEquityDetails'];
        final detail = details is List
            ? details
                .whereType<String>()
                .where((e) => e.trim().isNotEmpty)
                .join(' · ')
            : details is String
                ? details.trim()
                : '';
        benefits.add([title, detail].where((e) => e.isNotEmpty).join(': '));
      }
    }
    return CodingPlanProduct(
      id: text('productId') ?? '--',
      title: text('productName') ?? text('productBigTitle') ?? '--',
      subtitle: text('productSmallTitle'),
      description: text('productDescription') ?? text('productIntroduction'),
      priceUnit: text('priceUnit'),
      priceCurrency: text('priceCurrency'),
      originalAmount: amount('originalAmount'),
      payAmount: amount('payAmount'),
      monthlyPayAmount: amount('monthlyPayAmount'),
      subscribed: map['subscribed'] is bool ? map['subscribed'] as bool : null,
      benefits: benefits,
      raw: map,
    );
  }

  final String id;
  final String title;
  final String? subtitle;
  final String? description;
  final String? priceUnit;
  final String? priceCurrency;
  final num? originalAmount;
  final num? payAmount;
  final num? monthlyPayAmount;
  final bool? subscribed;
  final List<String> benefits;
  final Map<String, dynamic> raw;
}

/// Read-only source for the official account-menu Upgrade entry. The official
/// menu resolves the current `providerFamilyDomain`, then reads authenticated
/// `codingPlanSubscriptionService.getEnterprisePricing({authenticated:true,
/// family})`. Payment submission is a separate flow and is not wired here.
class CodingPlanUpgradeCatalog extends ChangeNotifier {
  CodingPlanUpgradeCatalog({
    required this.session,
    required this.transport,
    required this.scopeKey,
  });

  final BridgeSession session;
  final ConversationTransport transport;
  final String scopeKey;

  int _generation = 0;
  Future<void>? _pending;
  bool _disposed = false;

  CodingPlanUpgradeStatus status = CodingPlanUpgradeStatus.idle;
  List<CodingPlanProduct> products = const [];
  String? family;
  String? providerId;
  bool? authenticatedPricing;
  Object? error;

  Future<void> refresh({bool force = false}) {
    if (_disposed) return Future.value();
    final pending = _pending;
    if (!force && pending != null) return pending;
    final generation = ++_generation;
    status = CodingPlanUpgradeStatus.loading;
    error = null;
    notifyListeners();
    Future<void>? operationFuture;
    Future<void> operation() async {
      try {
        final settings = await session.channels.call(
          Channels.setting,
          'get',
          const [],
          timeout: const Duration(seconds: 20),
        );
        if (_disposed || generation != _generation) return;
        final settingsMap = settings is Map
            ? settings.cast<String, dynamic>()
            : const <String, dynamic>{};
        final domain = settingsMap['providerFamilyDomain'] is String
            ? settingsMap['providerFamilyDomain'] as String
            : 'zai';
        final nextFamily = domain == 'bigmodel' ? 'bigmodel' : 'zai';
        final nextProviderId = 'builtin:$nextFamily-coding-plan';
        final raw = await transport.teamPlanProducts(nextFamily);
        if (_disposed || generation != _generation) return;
        final map = raw is Map
            ? raw.cast<String, dynamic>()
            : const <String, dynamic>{};
        final nextAuthenticated =
            map['authenticated'] is bool ? map['authenticated'] as bool : null;
        final list = map['productList'] is List
            ? (map['productList'] as List).whereType<Map>()
            : const Iterable<Map>.empty();
        final nextProducts = [
          for (final item in list) CodingPlanProduct.fromRaw(item)
        ];
        family = nextFamily;
        providerId = nextProviderId;
        authenticatedPricing = nextAuthenticated;
        products = nextProducts;
        status = CodingPlanUpgradeStatus.loaded;
        error = null;
      } catch (value) {
        if (_disposed || generation != _generation) return;
        status = CodingPlanUpgradeStatus.error;
        error = value;
      } finally {
        if (_pending == operationFuture) _pending = null;
        if (!_disposed && generation == _generation) notifyListeners();
      }
    }

    operationFuture = operation();
    _pending = operationFuture;
    return operationFuture;
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
