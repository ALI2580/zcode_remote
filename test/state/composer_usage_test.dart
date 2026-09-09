import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/composer_usage.dart';
import '../ui/fake_features.dart';

const _coding = 'builtin:bigmodel-coding-plan';
const _start = 'builtin:zai-start-plan';
Future<void> _settle() => Future<void>.delayed(Duration.zero);
Map<String, dynamic> _products(String project) => {
      'productList': [
        {
          'productId': 'product',
          'subscribed': true,
          'family': 'bigmodel',
          'teamProjects': [
            {'organizationId': 'org', 'projectId': project}
          ]
        }
      ]
    };
Map<String, dynamic> _teamQuota(String provider, String? org, String? project,
        {double used = 23}) =>
    {
      ...quotaFixture(provider, used: used),
      'context': {
        'scope': 'team',
        'organizationId': org,
        'projectId': project,
        'productId': 'product'
      }
    };

void main() {
  test(
      'legacy zero resolves the live team before its scoped quota and caches identity',
      () async {
    var now = DateTime.utc(2026, 9, 9);
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport, now: () => now);
    addTearDown(usage.dispose);
    transport.families['modelProviderFamilySelectedKeys'] = {
      'bigmodel': 'team-plan:$_coding:product:0'
    };
    transport.teamProductsHandler = (_) async => _products('project-A');
    transport.quotaHandler =
        (provider, org, project) async => _teamQuota(provider, org, project);
    usage.selectProvider(_coding);
    await usage.refresh();
    expect(transport.teamProductCalls, ['bigmodel']);
    expect(transport.quotaCalls.single['projectId'], 'project-A');
    expect(transport.quotaCalls.single['organizationId'], 'org');
    expect(usage.snapshot!.fiveHour!.remainingPercent, 77);
    await usage.refresh();
    expect(transport.quotaCalls.length, 1);
    expect(transport.teamProductCalls.length, 1);
    now = now.add(const Duration(seconds: 60));
    transport.teamProductsHandler = (_) async => _products('project-B');
    await usage.refresh();
    expect(transport.teamProductCalls.length, 2);
    expect(transport.quotaCalls.last['projectId'], 'project-B');
    expect(usage.source!.projectId, 'project-B');
  });

  test(
      'fallback snapshot contributes team identity but its unscoped quota is not displayed',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    transport.families['modelProviderFamilySelectedKeys'] = {
      'bigmodel': 'team-plan:$_coding:product:0'
    };
    transport.quotaHandler = (provider, org, project) async => _teamQuota(
        provider, org ?? 'org', project ?? 'project',
        used: project == null ? 99 : 20);
    usage.selectProvider(_coding);
    await usage.refresh();
    expect(transport.quotaCalls.map((call) => call['projectId']),
        [null, 'project']);
    expect(usage.snapshot!.fiveHour!.remainingPercent, 80);
    expect(usage.source!.organizationId, 'org');
    expect(usage.failed, isFalse);
  });

  test('an unresolved team never displays a previous personal balance',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    usage.selectProvider(_coding);
    await usage.refresh();
    expect(usage.snapshot, isNotNull);
    final gate = Completer<dynamic>();
    transport.teamProductsHandler = (_) => gate.future;
    transport.families['modelProviderFamilySelectedKeys'] = {
      'bigmodel': 'team-plan:$_coding:missing:0'
    };
    final refresh = usage.refresh(force: true);
    await _settle();
    expect(usage.snapshot, isNull);
    gate.complete(_products('unrelated-project'));
    await refresh;
    expect(usage.sourceUnavailable, isTrue);
    expect(usage.snapshot, isNull);
    expect(usage.source, isNull);
    expect(transport.quotaCalls.length,
        2); // initial personal + identity probe only
    expect(transport.quotaCalls.last['projectId'], isNull);
  });

  test('late team resolution cannot replace a newly selected provider',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    final gate = Completer<dynamic>();
    transport.teamProductsHandler = (_) => gate.future;
    transport.families['modelProviderFamilySelectedKeys'] = {
      'bigmodel': 'team-plan:$_coding:product:0',
      'zai': 'coding-plan:$_start'
    };
    usage.selectProvider(_coding);
    final old = usage.refresh();
    await _settle();
    usage.selectProvider(_start);
    await usage.refresh();
    gate.complete(_products('old-project'));
    await old;
    expect(usage.source!.providerId, _start);
    expect(transport.quotaCalls.every((call) => call['provider'] == _start),
        isTrue);
    expect(usage.sourceUnavailable, isFalse);
  });

  test(
      'reconnect discards legacy bindings even when the selected key is unchanged',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    transport.families['modelProviderFamilySelectedKeys'] = {
      'bigmodel': 'team-plan:$_coding:product:0'
    };
    transport.teamProductsHandler = (_) async => _products('old');
    transport.quotaHandler =
        (provider, org, project) async => _teamQuota(provider, org, project);
    usage.selectProvider(_coding);
    await usage.refresh();
    transport.teamProductsHandler = (_) async => _products('new');
    usage.invalidate();
    await usage.refresh();
    expect(transport.teamProductCalls.length, 2);
    expect(
        transport.quotaCalls.map((call) => call['projectId']), ['old', 'new']);
    expect(usage.snapshot!.projectId, 'new');
  });

  test(
      'only selected OAuth source can request a plan; API keys never fall back',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    for (final provider in ['builtin:bigmodel', 'builtin:zapi', 'custom:glm']) {
      usage.selectProvider(provider);
      await usage.refresh();
      expect(usage.eligible, isFalse);
    }
    transport.families['modelProviderFamilyModes'] = {'bigmodel': 'apiKey'};
    usage.selectProvider(_coding);
    await usage.refresh();
    expect(usage.eligible, isFalse);
    transport.families['modelProviderFamilyModes'] = {'bigmodel': 'oauth'};
    transport.families['modelProviderFamilySelectedKeys'] = {
      'bigmodel': 'coding-plan:another-provider'
    };
    await usage.refresh();
    expect(usage.eligible, isFalse);
    expect(transport.quotaCalls, isEmpty);
  });

  test('opening deduplicates requests; 60 second cache and forced refresh work',
      () async {
    var now = DateTime.utc(2026, 9, 9);
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport, now: () => now);
    addTearDown(usage.dispose);
    final gate = Completer<dynamic>();
    transport.quotaHandler = (provider, organization, project) => gate.future;
    usage.selectProvider(_coding);
    final first = usage.refresh();
    await _settle();
    final duplicate = usage.refresh();
    expect(transport.quotaCalls, hasLength(1));
    gate.complete(quotaFixture(_coding));
    await Future.wait([first, duplicate]);
    expect(usage.snapshot!.fiveHour!.remainingPercent, 77);
    transport.quotaHandler = null;
    now = now.add(const Duration(seconds: 59));
    await usage.refresh();
    expect(transport.quotaCalls, hasLength(1));
    now = now.add(const Duration(seconds: 1));
    await usage.refresh();
    expect(transport.quotaCalls, hasLength(2));
    await usage.refresh(force: true);
    expect(transport.quotaCalls, hasLength(3));
  });

  test('same IDs on independent devices cannot share quota or pending results',
      () async {
    final a = FeatureBridge().conversationTransport;
    final b = FeatureBridge().conversationTransport;
    final usageA = ComposerUsage(a), usageB = ComposerUsage(b);
    addTearDown(usageA.dispose);
    addTearDown(usageB.dispose);
    a.quotaHandler = (provider, organization, project) async =>
        quotaFixture(_coding, used: 10);
    b.quotaHandler = (provider, organization, project) async =>
        quotaFixture(_coding, used: 80);
    usageA.selectProvider(_coding);
    usageB.selectProvider(_coding);
    await Future.wait([usageA.refresh(), usageB.refresh()]);
    expect(usageA.snapshot!.fiveHour!.remainingPercent, 90);
    expect(usageB.snapshot!.fiveHour!.remainingPercent, 20);
  });

  test('late provider response cannot overwrite current Start Plan source',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    final gate = Completer<dynamic>();
    transport.quotaHandler = (provider, organization, project) =>
        provider == _coding
            ? gate.future
            : Future.value(quotaFixture(provider));
    usage.selectProvider(_coding);
    final old = usage.refresh();
    await _settle();
    usage.selectProvider(_start);
    await usage.refresh();
    gate.complete(quotaFixture(_coding, used: 99));
    await old;
    expect(usage.source!.isStartPlan, isTrue);
    expect(usage.snapshot!.providerId, _start);
    expect(usage.failed, isFalse);
    expect(usage.refreshing, isFalse);
  });

  test('late settings selection cannot restore an ineligible provider',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    final gate = Completer<Map<String, dynamic>>();
    transport.familyHandler = () => gate.future;
    usage.selectProvider(_coding);
    final old = usage.refresh();
    usage.selectProvider('custom:model');
    gate.complete(transport.families);
    await old;
    expect(usage.eligible, isFalse);
    expect(usage.snapshot, isNull);
    expect(transport.quotaCalls, isEmpty);
  });

  test('team selection passes decoded scope and rejects another project',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    transport.families['modelProviderFamilySelectedKeys'] = {
      'bigmodel': 'team-plan:$_coding:product:org%3Aone:project%3Atwo'
    };
    transport.quotaHandler = (provider, org, project) async => {
          ...quotaFixture(provider),
          'context': {
            'scope': 'team',
            'organizationId': org,
            'projectId': project,
            'productId': 'product'
          }
        };
    usage.selectProvider(_coding);
    await usage.refresh();
    expect(usage.failed, isFalse);
    expect(transport.quotaCalls.single, {
      'provider': _coding,
      'organizationId': 'org:one',
      'projectId': 'project:two'
    });
    transport.families['modelProviderFamilySelectedKeys'] = {
      'bigmodel': 'team-plan:$_coding:product:org%3Aone:new-project'
    };
    transport.quotaHandler = (provider, org, _) async => {
          ...quotaFixture(provider),
          'context': {
            'scope': 'team',
            'organizationId': org,
            'projectId': 'project:two'
          }
        };
    await usage.refresh();
    expect(usage.snapshot, isNull);
    expect(usage.failed, isTrue);
  });

  test('timeout retains same-source cache with failure, recovery replaces it',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    usage.selectProvider(_coding);
    await usage.refresh();
    final previous = usage.snapshot;
    transport.quotaHandler = (provider, organization, project) =>
        Future.error(TimeoutException('quota'));
    await usage.refresh(force: true);
    expect(usage.failed, isTrue);
    expect(usage.refreshing, isFalse);
    expect(usage.snapshot, same(previous));
    transport.quotaHandler = (provider, organization, project) async =>
        quotaFixture(_coding, used: 32);
    await usage.refresh(force: true);
    expect(usage.failed, isFalse);
    expect(usage.snapshot!.fiveHour!.remainingPercent, 68);
  });

  test('reconnect invalidation cannot reuse a previous account quota cache',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    usage.selectProvider(_coding);
    await usage.refresh();
    transport.quotaHandler = (provider, organization, project) async =>
        quotaFixture(_coding, used: 90);
    usage.invalidate();
    await usage.refresh();
    expect(transport.quotaCalls, hasLength(2));
    expect(usage.snapshot!.fiveHour!.remainingPercent, 10);
  });

  test('late pre-reconnect quota is discarded after a fresh response',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    final gate = Completer<dynamic>();
    transport.quotaHandler = (provider, organization, project) => gate.future;
    usage.selectProvider(_coding);
    final previous = usage.refresh();
    await _settle();
    usage.invalidate();
    transport.quotaHandler = (provider, organization, project) async =>
        quotaFixture(_coding, used: 80);
    await usage.refresh();
    gate.complete(quotaFixture(_coding, used: 1));
    await previous;
    expect(usage.snapshot!.fiveHour!.remainingPercent, 20);
  });

  test(
      'failed source verification cannot refresh a previously selected account',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    usage.selectProvider(_coding);
    await usage.refresh();
    final cached = usage.snapshot;
    transport.familyHandler = () => Future.error(TimeoutException('settings'));
    await usage.refresh(force: true);
    expect(transport.quotaCalls, hasLength(1));
    expect(usage.snapshot, same(cached));
    expect(usage.failed, isTrue);
  });

  test('unconfigured response is an empty account state, not a network failure',
      () async {
    final transport = FeatureBridge().conversationTransport;
    final usage = ComposerUsage(transport);
    addTearDown(usage.dispose);
    transport.quotaHandler = (provider, org, project) async => {
          'unavailableReason': 'not_configured',
          'provider': null,
          'quota': null,
          'subscription': null,
          'remaining': null,
        };
    usage.selectProvider(_coding);
    await usage.refresh();
    expect(usage.failed, isFalse);
    expect(usage.snapshot!.unavailableReason, 'not_configured');
    expect(usage.snapshot!.limits, isEmpty);
  });
}
