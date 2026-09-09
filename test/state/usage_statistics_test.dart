import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/entitlement.dart';
import 'package:zcode_remote/protocol/usage_statistics.dart';
import 'package:zcode_remote/state/usage_statistics.dart';
import '../ui/fake_features.dart';
import '../ui/usage_fixtures.dart';

const _personal = EntitlementSource(
    providerId: 'builtin:bigmodel-coding-plan',
    key: 'coding-plan:builtin:bigmodel-coding-plan',
    isStartPlan: false);
const _team = EntitlementSource(
    providerId: 'builtin:bigmodel-coding-plan',
    key: 'team-plan:builtin:bigmodel-coding-plan:p:org:project',
    isStartPlan: false,
    organizationId: 'org',
    projectId: 'project');
void main() {
  late FeatureBridge bridge;
  late UsageStatistics stats;
  late DateTime now;
  setUp(() {
    bridge = FeatureBridge();
    now = DateTime.utc(2026, 9, 9);
    stats = UsageStatistics(bridge.conversationTransport,
        timeZone: () async => 'Asia/Shanghai', now: () => now);
    bridge.channels.handler = (channel, method, args) {
      final query = args.single as Map;
      return statisticsFixture(query['range'],
          application: method == 'getAppUsageSnapshot',
          total: query['range'] == 'all' ? 4000000000 : 800000000);
    };
  });
  tearDown(() {
    stats.dispose();
    bridge.channels.dispose();
  });
  test('application lifetime and range use distinct requests and cache keys',
      () async {
    stats.select(application: true, source: _personal);
    await stats.refresh();
    expect(stats.app.snapshot!.summary['totalTokens'], 800000000);
    expect(stats.lifetime.snapshot!.summary['totalTokens'], 4000000000);
    expect(bridge.channels.calls.map((c) => c.method),
        everyElement('getAppUsageSnapshot'));
    expect(bridge.channels.calls.map((c) => (c.args.single as Map)['range']),
        unorderedEquals(['all', '7d']));
    await stats.refresh();
    expect(bridge.channels.calls.length, 2);
    stats.selectRange(UsageRange.month);
    expect(stats.app.snapshot, isNull);
    await stats.refresh();
    expect(stats.app.snapshot!.range, '30d');
    expect(bridge.channels.calls.length, 3);
    now = now.add(const Duration(seconds: 61));
    await stats.refresh();
    expect(bridge.channels.calls.length, 5);
  });
  test('team switch clears personal data immediately and ignores late display',
      () async {
    final pending = Completer<dynamic>();
    bridge.channels.handler = (_, __, args) =>
        (args.single as Map)['organizationId'] == null
            ? pending.future
            : statisticsFixture('7d', total: 42);
    stats.select(application: false, source: _personal);
    await Future<void>.delayed(Duration.zero);
    stats.select(application: false, source: _team);
    expect(stats.coding.snapshot, isNull);
    await stats.refresh();
    expect(stats.coding.snapshot!.summary['totalTokens'], 42);
    final query = bridge.channels.calls.last.args.single as Map;
    expect(query, {
      'preferredProviderId': _team.providerId,
      'organizationId': 'org',
      'projectId': 'project',
      'range': '7d',
      'customStartDate': null,
      'customEndDate': null,
      'timeZone': 'Asia/Shanghai'
    });
    pending.complete(statisticsFixture('7d', total: 99));
    await Future<void>.delayed(Duration.zero);
    expect(stats.coding.snapshot!.summary['totalTokens'], 42);
  });
  test('application and coding tabs keep independent selected time ranges',
      () async {
    stats.select(application: true, source: _personal);
    await stats.refresh();
    stats.selectRange(UsageRange.month);
    await stats.refresh();
    stats.select(application: false, source: _personal);
    await stats.refresh();
    expect(stats.range, UsageRange.week);
    expect(stats.coding.snapshot!.range, '7d');
    expect(stats.app.snapshot!.range, '30d');
    stats.select(application: true, source: _personal);
    await stats.refresh();
    expect(stats.range, UsageRange.month);
    expect(stats.app.snapshot!.range, '30d');
  });
  test(
      'failed coding clears its cache but failed application keeps only its range',
      () async {
    stats.select(application: false, source: _personal);
    await stats.refresh();
    bridge.channels.handler = (_, __, ___) => throw StateError('offline');
    await stats.refresh(force: true);
    expect(stats.coding.snapshot, isNull);
    expect(stats.coding.failed, isTrue);
    bridge.channels.handler = (_, __, args) =>
        statisticsFixture((args.single as Map)['range'], application: true);
    stats.select(application: true, source: _personal);
    await stats.refresh();
    final prior = stats.app.snapshot;
    bridge.channels.handler = (_, __, ___) => throw StateError('offline');
    await stats.refresh(force: true);
    expect(stats.app.snapshot, same(prior));
    expect(stats.app.failed, isTrue);
    stats.selectRange(UsageRange.month);
    await stats.refresh();
    expect(stats.app.snapshot, isNull);
  });
  test(
      'duplicate refreshes coalesce; reconnect invalidates late same-provider result',
      () async {
    final first = Completer<dynamic>(), second = Completer<dynamic>();
    var n = 0;
    bridge.channels.handler =
        (_, __, ___) => ++n == 1 ? first.future : second.future;
    stats.select(application: false, source: _personal);
    final request = stats.refresh();
    await Future<void>.delayed(Duration.zero);
    stats.refresh(force: true);
    expect(n, 1);
    bridge.recovered.value++;
    await Future<void>.delayed(Duration.zero);
    expect(n, 2);
    first.complete(statisticsFixture('7d', total: 111));
    await request;
    expect(stats.coding.snapshot, isNull);
    second.complete(statisticsFixture('7d', total: 222));
    await Future<void>.delayed(Duration.zero);
    expect(stats.coding.snapshot!.summary['totalTokens'], 222);
  });
  test('two transports with identical source IDs cannot share statistics',
      () async {
    final other = FeatureBridge();
    final otherStats = UsageStatistics(other.conversationTransport,
        timeZone: () async => 'Asia/Shanghai');
    other.channels.handler = (_, __, ___) => statisticsFixture('7d', total: 1);
    stats.select(application: false, source: _personal);
    otherStats.select(application: false, source: _personal);
    await Future.wait([stats.refresh(), otherStats.refresh()]);
    expect(stats.coding.snapshot!.summary['totalTokens'], 800000000);
    expect(otherStats.coding.snapshot!.summary['totalTokens'], 1);
    otherStats.dispose();
    other.channels.dispose();
  });
  test('invalid timezone is retryable; no request uses an invented timezone',
      () async {
    stats.dispose();
    var tries = 0;
    stats = UsageStatistics(bridge.conversationTransport, timeZone: () async {
      if (++tries == 1) throw StateError('no channel');
      return 'Asia/Shanghai';
    });
    stats.select(application: true, source: null);
    await stats.refresh();
    expect(stats.timeZoneFailed, isTrue);
    expect(bridge.channels.calls, isEmpty);
    await stats.refresh();
    expect(stats.app.snapshot, isNotNull);
  });
  test('snapshot identity and range validation rejects unexpected data', () {
    final raw = statisticsFixture('7d');
    expect(
        CodingUsageSnapshot.parse(raw,
            range: UsageRange.month, providerId: _personal.providerId),
        isNull);
    expect(
        CodingUsageSnapshot.parse(raw,
            range: UsageRange.week, providerId: 'other'),
        isNull);
    expect(
        AppUsageSnapshot.parse(statisticsFixture('7d', application: true),
            range: UsageRange.week, timeZone: 'America/New_York'),
        isNull);
  });
  test('missing numeric samples stay null and all-zero credits hide controls',
      () {
    final raw = statisticsFixture('7d');
    final model = raw['modelUsage']['modelDataList'][0] as Map;
    model['tokensUsage'] = [null, double.nan, double.infinity, -1, 12];
    final parsed = CodingUsageSnapshot.parse(raw,
        range: UsageRange.week, providerId: _personal.providerId)!;
    expect(parsed.plot().series.first.values,
        [null, null, null, null, 12, null, null]);
    expect(parsed.plot().series.first.sum, isNull);
    expect(parsed.hasCredits, isFalse);
    expect(parsed.plot().series.first.breakdown, isEmpty);
    model['cachedInputCreditsUsage'] = [1];
    expect(parsed.hasCredits, isTrue);
    expect(parsed.plot().series.first.breakdown, isNotEmpty);
  });
  test(
      'pie aggregates other models while daily line uses first six, heatmap exactly 52 weeks',
      () {
    final app = AppUsageSnapshot.parse(
        statisticsFixture('all', application: true),
        range: UsageRange.all,
        timeZone: 'Asia/Shanghai')!;
    expect(app.pie.length, 6);
    expect(app.pie.last.name, '__other__');
    expect(app.pie.last.tokens, 100000000);
    expect(app.daily.series.length, 6);
    expect(app.heatmap.weeks.length, 52);
    expect(app.heatmap.weeks.first.first.date.weekday, DateTime.sunday);
    expect(usageDate('2026-02-30'), isNull);
    expect(UsageHeatmap.parse({}).weeks, isEmpty);
  });
}
