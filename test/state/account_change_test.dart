import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/account_change.dart';
import 'package:zcode_remote/state/composer_input.dart';
import 'package:zcode_remote/state/composer_references.dart';
import 'package:zcode_remote/state/composer_usage.dart';
import 'package:zcode_remote/state/usage_statistics.dart';
import 'package:zcode_remote/protocol/entitlement.dart';

import '../ui/fake_features.dart';
import '../ui/usage_fixtures.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('account change invalidates cached usage and references together',
      () async {
    final bridge = FeatureBridge();
    final transport = bridge.conversationTransport;
    final usage = ComposerUsage(transport);
    final input = ComposerInput();
    final references = ComposerReferences(
        input: input,
        transport: transport,
        preparation: () => null,
        session: () => 'session');
    addTearDown(usage.dispose);
    addTearDown(references.dispose);
    addTearDown(input.dispose);

    usage.selectProvider('builtin:zai-start-plan');
    await usage.refresh();
    input.value = const TextEditingValue(text: '');
    input.value = const TextEditingValue(
        text: '@', selection: TextSelection.collapsed(offset: 1));
    await Future<void>.delayed(Duration.zero);
    expect(references.entries, isNotEmpty);
    expect(usage.snapshot, isNotNull);

    final fileReadsBefore = transport.fileReads;
    AccountChangeManager.invalidateAll(usage: usage, references: references);
    input.value = const TextEditingValue(
        text: '@', selection: TextSelection.collapsed(offset: 1));
    await Future<void>.delayed(Duration.zero);
    expect(transport.fileReads, greaterThan(fileReadsBefore));
  });

  test('account change clears cached usage statistics', () async {
    final bridge = FeatureBridge();
    final transport = bridge.conversationTransport;
    bridge.channels.handler = (_, __, args) =>
        statisticsFixture((args.single as Map)['range'], application: true);
    final stats = UsageStatistics(transport,
        timeZone: () async => 'Asia/Shanghai',
        now: () => DateTime.utc(2026, 9, 11));
    addTearDown(stats.dispose);
    stats.select(
        application: true,
        source: const EntitlementSource(
            providerId: 'builtin:bigmodel-coding-plan',
            key: 'coding-plan:builtin:bigmodel-coding-plan',
            isStartPlan: false));
    await stats.refresh();
    expect(stats.app.snapshot, isNotNull);

    AccountChangeManager.invalidateAll(statistics: stats);
    expect(stats.app.snapshot, isNull);
    expect(stats.lifetime.snapshot, isNull);
  });
}
