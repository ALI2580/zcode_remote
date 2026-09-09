import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:zcode_remote/protocol/entitlement.dart';
import 'package:zcode_remote/protocol/plan_reset.dart';
import 'package:zcode_remote/state/composer_usage.dart';
import 'package:zcode_remote/state/plan_resets.dart';
import '../ui/fake_features.dart';

const _provider = 'builtin:bigmodel-coding-plan';
const _source = EntitlementSource(
    providerId: _provider, key: 'coding-plan:$_provider', isStartPlan: false);
const _team = EntitlementSource(
    providerId: _provider,
    key: 'team-plan:$_provider:p:org:project',
    isStartPlan: false,
    organizationId: 'org',
    projectId: 'project');

Map<String, dynamic> _status(int now,
        {int? usedAt, int count = 1, int? fiveUsedAt, bool unread = false}) =>
    {
      'availableFiveHourResets': [
        {'expireAt': now + 600000}
      ],
      'availableWeekResets':
          List.generate(count, (_) => {'expireAt': now + 1200000}),
      if (usedAt != null) 'latestWeekResetHistory': {'usedAt': usedAt},
      if (fiveUsedAt != null)
        'latestFiveHourResetHistory': {'usedAt': fiveUsedAt},
      'hasUnreadHistory': unread,
    };

void main() {
  late FeatureBridge bridge;
  late PlanResets resets;
  late int now;
  late Map<String, dynamic> status;
  var id = 0;
  setUp(() {
    now = DateTime.utc(2026, 9, 9).millisecondsSinceEpoch;
    status = _status(now);
    bridge = FeatureBridge();
    id = 0;
    resets = PlanResets(bridge.conversationTransport,
        now: () => DateTime.fromMillisecondsSinceEpoch(now),
        delay: (_) async {},
        newId: () => 'id-${++id}');
    bridge.channels.handler =
        (channel, method, args) => method == 'getCodingPlanResetStatus'
            ? status
            : method == 'requestCodingPlanResetOpportunity'
                ? {'granted': false}
                : {};
  });
  tearDown(() {
    resets.dispose();
    bridge.channels.dispose();
  });

  test('reset status rejects missing lists and excludes invalid/expired dates',
      () {
    expect(() => PlanResetStatus.parse({}), throwsFormatException);
    status['availableWeekResets'] = [
      {'expireAt': now},
      {'expireAt': now - 1},
      {'expireAt': 'bad'},
      {'expireAt': double.infinity},
      {'expireAt': 9e20},
      {'expireAt': now + 20},
      {'expireAt': now + 10},
    ];
    final parsed = PlanResetStatus.parse(status);
    expect(parsed.available(PlanResetType.week, now), [now + 10, now + 20]);
    expect(parsed.usedAt[PlanResetType.week], isNull);
  });

  test('status access is read-only, deduplicated and cached for 1500ms',
      () async {
    final gate = Completer<Object>();
    bridge.channels.handler = (channel, method, args) => gate.future;
    final first = resets.refresh(_source);
    final second = resets.refresh(_source, force: true);
    expect(bridge.channels.calls.length, 1);
    gate.complete(status);
    expect(await first, isTrue);
    expect(await second, isTrue);
    await resets.refresh(_source);
    expect(bridge.channels.calls.length, 1);
    now += 1500;
    await resets.refresh(_source);
    expect(bridge.channels.calls.length, 2);
    expect(
        bridge.channels.calls
            .every((c) => c.method == 'getCodingPlanResetStatus'),
        isTrue);
    expect(PlanResets.forTransport(bridge.conversationTransport),
        same(PlanResets.forTransport(bridge.conversationTransport)));
  });

  test(
      'scope and independent-device caches never share even with identical IDs',
      () async {
    final old = Completer<Object>();
    bridge.channels.handler = (channel, method, args) =>
        (args.single as Map)['projectId'] == null
            ? old.future
            : _status(now, count: 3);
    final pending = resets.refresh(_source);
    await resets.refresh(_team);
    expect(resets.available(_team, PlanResetType.week).length, 3);
    expect(resets.available(_source, PlanResetType.week), isEmpty);
    old.complete(_status(now, count: 2));
    await pending;
    expect(resets.available(_source, PlanResetType.week).length, 2);
    expect(resets.available(_team, PlanResetType.week).length, 3);
    final other = FeatureBridge();
    expect(
        PlanResets.forTransport(other.conversationTransport)
            .available(_team, PlanResetType.week),
        isEmpty);
    other.channels.dispose();
  });

  test('status timeout retains its own data, exposes failure, and recovers',
      () async {
    await resets.refresh(_source);
    bridge.channels.handler =
        (channel, method, args) => throw TimeoutException('timeout');
    expect(await resets.refresh(_source, force: true), isFalse);
    expect(resets.state(_source).failed, isTrue);
    expect(resets.available(_source, PlanResetType.week).length, 1);
    bridge.channels.handler = (channel, method, args) => _status(now, count: 0);
    expect(await resets.refresh(_source, force: true), isTrue);
    expect(resets.state(_source).failed, isFalse);
    expect(resets.available(_source, PlanResetType.week), isEmpty);
  });

  test('simultaneous main/side reset and other type can submit only once',
      () async {
    final gate = Completer<Object>();
    bridge.channels.handler = (channel, method, args) =>
        method == 'getCodingPlanResetStatus' ? status : gate.future;
    final first = resets.use(_team, PlanResetType.week);
    expect(await resets.use(_team, PlanResetType.week), isFalse);
    expect(await resets.use(_team, PlanResetType.fiveHour), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(resets.state(_team).busy, isTrue);
    status = _status(now, usedAt: now, count: 0);
    gate.complete({});
    expect(await first, isTrue);
    final writes = bridge.channels.calls
        .where((c) => c.method == 'useCodingPlanReset')
        .toList();
    expect(writes.length, 1);
    expect(writes.single.args, [
      {
        'preferredProviderId': _provider,
        'organizationId': 'org',
        'projectId': 'project',
        'idempotencyKey': 'id-1',
        'resetType': 'WEEK',
      }
    ]);
  });

  test('old history cannot confirm a reset and failed retry reuses the key',
      () async {
    status = _status(now, usedAt: now - 10000);
    var attempt = 0;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'getCodingPlanResetStatus') return status;
      if (++attempt == 1) throw TimeoutException('response lost');
      status = _status(now, usedAt: now, count: 0);
      return {};
    };
    expect(await resets.use(_source, PlanResetType.week), isFalse);
    final failed = resets.state(_source).entries[PlanResetType.week]!;
    expect(failed.phase, PlanResetPhase.available);
    expect(failed.completedAt, isNull);
    expect(failed.idempotencyKey, 'id-1');
    expect(await resets.use(_source, PlanResetType.week), isTrue);
    final keys = bridge.channels.calls
        .where((c) => c.method == 'useCodingPlanReset')
        .map((c) => (c.args.single as Map)['idempotencyKey']);
    expect(keys, ['id-1', 'id-1']);
  });

  test(
      'accepted-but-unconfirmed reset only polls; explicit retry does not resend',
      () async {
    status = _status(now, usedAt: now - 1000);
    expect(await resets.use(_source, PlanResetType.week), isFalse);
    final entry = resets.state(_source).entries[PlanResetType.week]!;
    expect(entry.awaitingConfirmation, isTrue);
    expect(entry.error, 'unconfirmed');
    expect(await resets.use(_source, PlanResetType.week), isFalse);
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'useCodingPlanReset')
            .length,
        1);
    status = _status(now, usedAt: now, count: 2, unread: true);
    expect(await resets.use(_source, PlanResetType.week), isTrue);
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'useCodingPlanReset')
            .length,
        1);
    expect(entry.phase, PlanResetPhase.completed);
    expect(resets.available(_source, PlanResetType.week), isEmpty);
  });

  test(
      'changed history after an RPC timeout confirms without consuming another credit',
      () async {
    bridge.channels.handler = (channel, method, args) {
      if (method == 'getCodingPlanResetStatus') return status;
      status = _status(now, usedAt: now, count: 2, unread: true);
      throw TimeoutException('reply lost');
    };
    expect(await resets.use(_source, PlanResetType.week), isFalse);
    expect(await resets.use(_source, PlanResetType.week), isTrue);
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'useCodingPlanReset')
            .length,
        1);
  });

  test('reconnect ignores late status and cannot continue an old reset',
      () async {
    final gate = Completer<Object>();
    bridge.channels.handler = (channel, method, args) => gate.future;
    final action = resets.use(_source, PlanResetType.week);
    resets.invalidate();
    gate.complete(status);
    expect(await action, isFalse);
    expect(resets.state(_source).status, isNull);
    expect(bridge.channels.calls.where((c) => c.method == 'useCodingPlanReset'),
        isEmpty);
  });

  test(
      'refill projection starts only after confirmation and old quota cannot clear it',
      () async {
    final limit = QuotaLimit.fromRaw(
        {'type': 'TOKENS_LIMIT', 'unit': 6, 'percentage': 30});
    final oldObservation = resets.completed(_source);
    bridge.channels.handler = (channel, method, args) {
      if (method == 'getCodingPlanResetStatus') return status;
      status = _status(now, usedAt: now, count: 0);
      return {};
    };
    expect(
        resets
            .displayLimit(_source, PlanResetType.week, limit)!
            .remainingPercent,
        70);
    expect(await resets.use(_source, PlanResetType.week), isTrue);
    expect(
        resets
            .displayLimit(_source, PlanResetType.week, limit)!
            .remainingPercent,
        100);
    expect(
        resets
            .displayLimit(_source, PlanResetType.fiveHour, limit)!
            .remainingPercent,
        70);
    resets.acknowledgeEntitlement(_source, oldObservation);
    expect(
        resets
            .displayLimit(_source, PlanResetType.week, limit)!
            .remainingPercent,
        100);
    resets.acknowledgeEntitlement(_source, resets.completed(_source));
    expect(
        resets
            .displayLimit(_source, PlanResetType.week, limit)!
            .remainingPercent,
        70);
    expect(
        resets.displayLimit(_source, PlanResetType.week, limit)!.nextResetTime,
        now + const Duration(days: 7).inMilliseconds);
  });

  test(
      'opportunity transient retries reuse ID after five minutes; throttled starts fresh after ten',
      () async {
    var error = 'network error';
    bridge.channels.handler =
        (channel, method, args) => throw StateError(error);
    await resets.requestOpportunity(_source);
    await resets.requestOpportunity(_source);
    expect(bridge.channels.calls.length, 1);
    now += 300000;
    error = 'coding_plan_reset_api_error:429';
    await resets.requestOpportunity(_source);
    expect((bridge.channels.calls.last.args.single as Map)['idempotencyKey'],
        'id-1');
    now += 599999;
    await resets.requestOpportunity(_source);
    expect(bridge.channels.calls.length, 2);
    now++;
    bridge.channels.handler = (channel, method, args) =>
        method == 'getCodingPlanResetStatus' ? status : {'granted': true};
    await resets.requestOpportunity(_source);
    expect((bridge.channels.calls[2].args.single as Map)['idempotencyKey'],
        'id-2');
    expect(bridge.channels.calls.last.method, 'getCodingPlanResetStatus');
  });

  test('server opportunity nextTryAt has the official minimum and cannot spin',
      () {
    expect(
        PlanResetOpportunity.parse({'granted': false, 'nextTryAt': now + 1})
            .nextCheckAt(now),
        now + 300000);
    expect(
        PlanResetOpportunity.parse(
            {'granted': false, 'nextTryAt': now + 900000}).nextCheckAt(now),
        now + 900000);
    expect(
        PlanResetOpportunity.parse({'granted': true, 'nextTryAt': now + 1})
            .nextCheckAt(now),
        now + 600000);
  });

  test(
      'history acknowledgment is scoped, deduplicated and retries a failed acknowledgment',
      () async {
    status = _status(now, usedAt: now, unread: true);
    await resets.refresh(_team);
    final gate = Completer<Object>();
    bridge.channels.handler = (channel, method, args) => gate.future;
    final read = resets.markHistoryRead(_team);
    await resets.markHistoryRead(_team);
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'markCodingPlanResetHistoryRead')
            .length,
        1);
    gate.completeError(StateError('temporary'));
    await read;
    bridge.channels.handler = (channel, method, args) => {};
    await resets.markHistoryRead(_team);
    await resets.markHistoryRead(_team);
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'markCodingPlanResetHistoryRead')
            .length,
        2);
    expect((bridge.channels.calls.last.args.single as Map)['projectId'],
        'project');
  });

  test('composer revalidates selected source and full pools before consumption',
      () async {
    final usage = ComposerUsage(bridge.conversationTransport, resets: resets);
    addTearDown(usage.dispose);
    usage.selectProvider(_provider);
    await usage.refresh();
    await usage.refreshResetStatus();
    final key = usage.source!.key;
    bridge.conversationTransport.quotaHandler =
        (provider, org, project) async => quotaFixture(provider, used: 0);
    expect(
        await usage.useReset(PlanResetType.fiveHour, sourceKey: key), isFalse);
    bridge.conversationTransport.families['modelProviderFamilySelectedKeys'] = {
      'bigmodel': 'team-plan:$_provider:p:org:project'
    };
    expect(await usage.useReset(PlanResetType.week, sourceKey: key), isFalse);
    expect(bridge.channels.calls.where((c) => c.method == 'useCodingPlanReset'),
        isEmpty);
  });

  testWidgets('visible subscribers share polling and stop after the last close',
      (tester) async {
    final closeMain = resets.observe(_source, refreshEntitlement: () async {});
    final closeSide = resets.observe(_source, refreshEntitlement: () async {});
    await tester.pump();
    expect(bridge.channels.calls.map((c) => c.method),
        ['getCodingPlanResetStatus', 'requestCodingPlanResetOpportunity']);
    closeMain();
    now += 300000;
    await tester.pump(const Duration(minutes: 5));
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'getCodingPlanResetStatus')
            .length,
        2);
    closeSide();
    now += 600000;
    await tester.pump(const Duration(minutes: 10));
    expect(bridge.channels.calls.length, 3);
  });

  testWidgets(
      'external latest history refreshes each view once and never consumes',
      (tester) async {
    status = _status(now,
        usedAt: now, fiveUsedAt: now - 1000, unread: true, count: 0);
    var mainRefreshes = 0, sideRefreshes = 0;
    final closeMain = resets.observe(_source, refreshEntitlement: () async {
      mainRefreshes++;
    });
    final closeSide = resets.observe(_source, refreshEntitlement: () async {
      sideRefreshes++;
    });
    await tester.pump();
    expect(mainRefreshes, 1);
    expect(sideRefreshes, 1);
    final entry = resets.state(_source).entries[PlanResetType.week]!;
    expect(entry.automatic, isTrue);
    expect(entry.observedAt, now);
    expect(resets.state(_source).entries[PlanResetType.fiveHour], isNull);
    expect(bridge.channels.calls.map((c) => c.method),
        ['getCodingPlanResetStatus', 'markCodingPlanResetHistoryRead']);
    now += 300000;
    await tester.pump(const Duration(minutes: 5));
    expect(mainRefreshes, 1);
    expect(sideRefreshes, 1);
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'markCodingPlanResetHistoryRead')
            .length,
        1);
    expect(bridge.channels.calls.where((c) => c.method == 'useCodingPlanReset'),
        isEmpty);
    expect(
        resets.claimCelebration(
            _source, PlanResetType.week, entry.completedAt!),
        isTrue);
    expect(
        resets.claimCelebration(
            _source, PlanResetType.week, entry.completedAt!),
        isFalse);
    closeMain();
    closeSide();
    resets.invalidate();
    await resets.refresh(_source);
    expect(
        resets.state(_source).entries[PlanResetType.week]!.observedAt, isNull);
  });

  testWidgets(
      'late status after last surface closes cannot grant or mark history',
      (tester) async {
    final gate = Completer<Object>();
    bridge.channels.handler = (channel, method, args) => gate.future;
    final close = resets.observe(_source, refreshEntitlement: () async {
      fail('closed subscriber refreshed');
    });
    await tester.pump();
    close();
    gate.complete(_status(now, usedAt: now, unread: true));
    await tester.pump();
    expect(bridge.channels.calls.map((c) => c.method),
        ['getCodingPlanResetStatus']);
  });

  testWidgets(
      'audit policy allows status and quota reads but blocks all quota writes',
      (tester) async {
    final audit =
        PlanResets(bridge.conversationTransport, readOnly: () => true);
    addTearDown(audit.dispose);
    status = _status(now, usedAt: now, unread: true);
    var refreshed = 0;
    final close = audit.observe(_source, refreshEntitlement: () async {
      refreshed++;
    });
    await tester.pump();
    expect(refreshed, 1);
    expect(await audit.use(_source, PlanResetType.week), isFalse);
    await audit.requestOpportunity(_source);
    await audit.markHistoryRead(_source);
    expect(
        bridge.channels.calls
            .every((c) => c.method == 'getCodingPlanResetStatus'),
        isTrue);
    close();
  });

  testWidgets(
      'foreground resume checks immediately and provider switch releases old scope',
      (tester) async {
    final usage = ComposerUsage(bridge.conversationTransport, resets: resets);
    addTearDown(usage.dispose);
    usage.selectProvider(_provider);
    await usage.refresh();
    final close = usage.observeResets();
    await tester.pump();
    usage.didChangeAppLifecycleState(AppLifecycleState.paused);
    final before = bridge.channels.calls.length;
    now += 600000;
    await tester.pump(const Duration(minutes: 10));
    expect(bridge.channels.calls.length, before);
    usage.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(bridge.channels.calls.length, greaterThan(before));
    usage.selectProvider('other-provider');
    final after = bridge.channels.calls.length;
    now += 600000;
    await tester.pump(const Duration(minutes: 10));
    expect(bridge.channels.calls.length, after);
    close();
  });

  testWidgets(
      'failed completion refresh retries; late reconnect result cannot write',
      (tester) async {
    status = _status(now, usedAt: now, unread: true);
    var attempts = 0;
    final close = resets.observe(_source, refreshEntitlement: () async {
      if (++attempts == 1) throw StateError('quota timeout');
    });
    await tester.pump();
    now += 300000;
    await tester.pump(const Duration(minutes: 5));
    expect(attempts, 2);
    close();
    final gate = Completer<Object>();
    bridge.channels.handler = (channel, method, args) => gate.future;
    resets.invalidate();
    final release = resets.observe(_team, refreshEntitlement: () async {
      fail('old generation callback');
    });
    await tester.pump();
    final before = bridge.channels.calls.length;
    resets.invalidate();
    gate.complete(status);
    await tester.pump();
    expect(bridge.channels.calls.length, before);
    expect(resets.state(_team).status, isNull);
    release();
  });

  testWidgets(
      'completion waits for an old quota request then obtains fresh quota',
      (tester) async {
    final usage = ComposerUsage(bridge.conversationTransport, resets: resets);
    addTearDown(usage.dispose);
    usage.selectProvider(_provider);
    await usage.refresh();
    final oldQuota = Completer<Map<String, dynamic>>();
    var reads = 0;
    bridge.conversationTransport.quotaHandler = (provider, org, project) async {
      if (++reads == 1) return oldQuota.future;
      return quotaFixture(provider, used: 1);
    };
    final oldRequest = usage.refresh(force: true);
    await tester.pump();
    status = _status(now, usedAt: now, unread: true, count: 0);
    final close = usage.observeResets();
    await tester.pump();
    expect(
        resets.state(_source).entries[PlanResetType.week]!.quotaOverridePending,
        isTrue);
    oldQuota.complete(quotaFixture(_provider, used: 50));
    await oldRequest;
    await tester.pump();
    expect(reads, 2);
    expect(usage.resetLimit(PlanResetType.week)!.remainingPercent, 95);
    expect(usage.snapshot!.fiveHour!.remainingPercent, 99);
    expect(
        resets.state(_source).entries[PlanResetType.week]!.quotaOverridePending,
        isFalse);
    close();
  });
}
