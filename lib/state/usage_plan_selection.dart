import 'dart:async';

import 'package:flutter/foundation.dart';

import 'client_preferences.dart';
import 'composer_usage.dart';

/// One selectable usage-statistics source option.
class UsageSourceOption {
  const UsageSourceOption(
      {required this.providerId, required this.label, this.entitled = true});
  final String providerId;
  final String label;
  final bool entitled;
}

/// Official `sidebarUsageCodingPlanProviderPreference`: the usage-statistics
/// page picks its Coding Plan source independently of the chat model
/// provider. The preference (official localStorage key
/// `zcode:sidebar-usage-coding-plan-provider`) is persisted client-side and
/// only accepts the two coding-plan provider ids or a `team-plan:` key
/// (official `o2e`/`s2e`). Candidates mirror the official `wB` filter —
/// coding-plan providers that are enabled (or merely
/// `coding_plan_not_entitled`) with a non-empty key, in official `CB` order.
class UsagePlanSelection extends ChangeNotifier {
  UsagePlanSelection({
    required this.usage,
    ClientPreferences? preferences,
  }) : _preferences = preferences {
    usage.addListener(notifyListeners);
    _selectedProvider = _validPreference(preferences?.usagePlanSource);
  }

  /// Statistics-owned entitlement reader. Never driven by the chat composer's
  /// model provider.
  final ComposerUsage usage;
  final ClientPreferences? _preferences;

  List<UsageSourceOption> options = const [];
  String? _selectedProvider;
  bool loadingCandidates = false;
  bool candidatesFailed = false;
  Object? error;
  int _generation = 0;
  Future<void>? _pending;

  String? get selectedProvider => _selectedProvider;

  /// The statistics usage keeps its own provider; the chat composer's
  /// `config['provider']` never gates this page (official `O2e` resolves the
  /// sidebar source from the persisted preference instead).
  bool get hasChoice => options.length > 1;

  static const candidateProviderIds = <String>[
    'builtin:zai-coding-plan',
    'builtin:bigmodel-coding-plan',
  ];

  /// Official `o2e`/`s2e`: a coding-plan provider id or a `team-plan:` key.
  static bool isValidPreference(String? value) =>
      value != null &&
      (candidateProviderIds.contains(value) || value.startsWith('team-plan:'));

  String? _validPreference(String? value) =>
      isValidPreference(value) ? value : null;

  /// Official `wB`: keep coding-plan providers that are enabled (or merely
  /// `coding_plan_not_entitled`) and carry a non-empty key.
  List<UsageSourceOption> computeCandidates(Map<String, dynamic> settings) {
    final providers = settings['modelProviders'];
    if (providers is! List) return const [];
    final result = <UsageSourceOption>[];
    for (final id in candidateProviderIds) {
      Map? entry;
      for (final item in providers.whereType<Map>()) {
        if ('${item['id'] ?? ''}' == id) {
          entry = item;
          break;
        }
      }
      if (entry == null) continue;
      final disabledReason = entry['systemDisabledReason'];
      final notEntitled = disabledReason == 'coding_plan_not_entitled';
      final enabled = entry['enabled'] != false && disabledReason == null;
      final hasKey = entry['hasApiKey'] == true;
      if (!(enabled || notEntitled) || !hasKey) continue;
      result.add(UsageSourceOption(
          providerId: id,
          label: id == candidateProviderIds.first ? 'Z.ai' : 'BigModel',
          entitled: !notEntitled));
    }
    return result;
  }

  Future<void> refreshSelection() {
    final pending = _pending;
    if (pending != null) return pending;
    final generation = ++_generation;
    final operation = () async {
      loadingCandidates = true;
      candidatesFailed = false;
      error = null;
      notifyListeners();
      try {
        final settings = await usage.transport.providerFamilySelection();
        if (generation != _generation) return;
        options = computeCandidates(settings);
        var selected = _selectedProvider;
        if (!options.any((option) => option.providerId == selected)) {
          // Official effect: an invalid or missing preference falls back to
          // the first candidate.
          selected = options.isEmpty ? null : options.first.providerId;
          _selectedProvider = selected;
          if (selected != null) _persist(selected);
        }
        usage.selectProvider(selected);
      } catch (value) {
        if (generation != _generation) return;
        candidatesFailed = true;
        error = value;
      } finally {
        if (generation == _generation) {
          loadingCandidates = false;
          notifyListeners();
        }
      }
    }();
    _pending = operation;
    return operation.whenComplete(() {
      if (identical(_pending, operation)) _pending = null;
    });
  }
  /// Official `ae`: persist the choice, then re-resolve the source.
  Future<void> select(String providerId) async {
    if (!candidateProviderIds.contains(providerId)) return;
    if (_selectedProvider == providerId) return;
    _selectedProvider = providerId;
    await _persist(providerId);
    usage.selectProvider(providerId);
    notifyListeners();
  }

  Future<void> _persist(String value) =>
      _preferences?.setUsagePlanSource(value) ?? Future.value();

  @override
  void dispose() {
    _generation++;
    usage.removeListener(notifyListeners);
    usage.dispose();
    super.dispose();
  }
}
