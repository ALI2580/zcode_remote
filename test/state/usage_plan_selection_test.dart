import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_usage.dart';
import 'package:zcode_remote/state/usage_plan_selection.dart';
import '../ui/fake_features.dart';

const _zai = 'builtin:zai-coding-plan';
const _bigmodel = 'builtin:bigmodel-coding-plan';

Map<String, dynamic> _provider(String id,
        {bool hasKey = true,
        String? disabledReason,
        bool enabled = true}) =>
    {
      'id': id,
      'enabled': enabled,
      'hasApiKey': hasKey,
      if (disabledReason != null) 'systemDisabledReason': disabledReason,
    };

void _candidates(FeatureTransport transport, List<Map<String, dynamic>> list) {
  transport.families['modelProviders'] = list;
  // Both coding-plan families resolve to their personal key so the selected
  // provider yields a real EntitlementSource.
  transport.families['modelProviderFamilySelectedKeys'] = {
    'bigmodel': 'coding-plan:$_bigmodel',
    'zai': 'coding-plan:$_zai',
  };
}

void main() {
  late FeatureTransport transport;
  late ClientPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = ClientPreferences();
    await prefs.load();
    transport = FeatureBridge().conversationTransport;
  });

  test('candidates follow the official wB filter and CB order', () {
    final selection = UsagePlanSelection(
        usage: ComposerUsage(transport), preferences: prefs);
    addTearDown(selection.dispose);
    final options = selection.computeCandidates({
      'modelProviders': [
        _provider(_bigmodel),
        _provider(_zai, hasKey: false),
        _provider('builtin:zai', disabledReason: 'oauth_provider_inactive'),
        _provider('custom:x', hasKey: true),
      ]
    });
    expect([for (final o in options) o.providerId], [_bigmodel]);
    // A merely-not-entitled coding-plan provider stays selectable.
    final pending = selection.computeCandidates({
      'modelProviders': [
        _provider(_zai, disabledReason: 'coding_plan_not_entitled'),
      ]
    });
    expect(pending.single.providerId, _zai);
    expect(pending.single.entitled, isFalse);
  });

  test('statistics source is independent of the chat composer provider',
      () async {
    _candidates(transport, [_provider(_zai), _provider(_bigmodel)]);
    final chatUsage = ComposerUsage(transport)
      ..selectProvider('custom:my-provider');
    final selection = UsagePlanSelection(
        usage: ComposerUsage(transport), preferences: prefs);
    addTearDown(() {
      chatUsage.dispose();
      selection.dispose();
    });
    await selection.refreshSelection();
    await selection.usage.refresh();
    // The chat model is a custom provider while the statistics still read
    // the persisted Coding Plan source.
    expect(chatUsage.source, isNull);
    expect(selection.usage.source, isNotNull);
    expect(selection.usage.source!.providerId, _zai);
    expect(transport.quotaCalls.single['provider'], _zai);
    // Switching the statistics source never touches the chat usage.
    await selection.select(_bigmodel);
    await selection.usage.refresh();
    expect(chatUsage.source, isNull);
    expect(selection.usage.source!.providerId, _bigmodel);
  });

  test('candidate read failure surfaces an error, never "no plan"', () async {
    _candidates(transport, [_provider(_bigmodel)]);
    final selection = UsagePlanSelection(
        usage: ComposerUsage(transport), preferences: prefs);
    addTearDown(selection.dispose);
    transport.familyHandler = () async => throw StateError('setting get');
    await selection.refreshSelection();
    expect(selection.candidatesFailed, isTrue);
    expect(selection.usage.source, isNull);
    expect(selection.usage.failed, isFalse);
  });

  test('preference persists across rebuilds and invalid values fall back',
      () async {
    _candidates(transport, [_provider(_zai), _provider(_bigmodel)]);
    final selection = UsagePlanSelection(
        usage: ComposerUsage(transport), preferences: prefs);
    addTearDown(selection.dispose);
    await selection.refreshSelection();
    expect(selection.selectedProvider, _zai);
    await selection.select(_bigmodel);
    await prefs.settled;
    expect(prefs.usagePlanSource, _bigmodel);

    final reloaded = ClientPreferences();
    await reloaded.load();
    expect(reloaded.usagePlanSource, _bigmodel);
    final restored = UsagePlanSelection(
        usage: ComposerUsage(transport), preferences: reloaded);
    addTearDown(restored.dispose);
    await restored.refreshSelection();
    expect(restored.selectedProvider, _bigmodel);

    await reloaded.setUsagePlanSource('team-plan:builtin:zai-coding-plan:p:o:1');
    final teamSelection = UsagePlanSelection(
        usage: ComposerUsage(transport), preferences: reloaded);
    addTearDown(teamSelection.dispose);
    await teamSelection.refreshSelection();
    // A team-plan preference is legal but not a candidate provider id; the
    // official effect falls back to the first candidate.
    expect(teamSelection.selectedProvider, _zai);
  });
}
