import '../protocol/conversation.dart';
import '../protocol/entitlement.dart';
import 'composer_model_projection.dart';

// Official zI / HZe ordering; unknown server values retain their relative order.
int? thoughtRank(String value) => switch (value.trim().toLowerCase()) {
      'disabled' ||
      'false' ||
      'no' ||
      'none' ||
      'nothink' ||
      'no-think' ||
      'no_think' ||
      'off' =>
        0,
      'low' || 'light' || 'minimal' || 'shallow' => 1,
      'balanced' || 'default' || 'medium' || 'normal' || 'standard' => 2,
      'deep' || 'high' => 3,
      'enable' || 'enabled' || 'on' || 'true' => 4,
      'extra-high' ||
      'extra_high' ||
      'very-high' ||
      'very_high' ||
      'xhigh' =>
        5,
      'max' || 'maximum' => 6,
      _ => null,
    };

List<String> sortedThoughtLevels(List<String> levels) {
  final entries = levels.indexed.toList();
  entries.sort((a, b) {
    final rank = (thoughtRank(a.$2) ?? 200).compareTo(thoughtRank(b.$2) ?? 200);
    return rank == 0 ? a.$1.compareTo(b.$1) : rank;
  });
  return entries.map((e) => e.$2).toList();
}

/// Model references mirror official pf / custom-reference decoding.
({String provider, String model}) modelReference(String value) {
  String decode(String value) {
    try {
      return Uri.decodeComponent(value);
    } on FormatException {
      return value;
    }
  }

  if (value.startsWith('custom:')) {
    final parts = value.substring(7).split(':');
    if (parts.length >= 3 && parts.first == 'builtin') {
      return (
        provider: 'builtin:${parts[1]}',
        model: decode(parts.skip(2).join(':'))
      );
    }
    return (
      provider: decode(parts.first),
      model: decode(parts.skip(1).join(':'))
    );
  }
  final slash = value.indexOf('/');
  return slash <= 0
      ? (provider: 'glm', model: value.trim())
      : (
          provider: value.substring(0, slash),
          model: value.substring(slash + 1).split(r'$').first
        );
}

bool firstPartyProvider(String value) =>
    value == 'glm' || isFamilyProviderId(value);

int providerPriority(String value) => officialProviderPriority(value);

String? _familyLabel(String providerId) {
  if (providerId == 'builtin:zai' || providerId.startsWith('builtin:zai-')) {
    return 'Z.ai';
  }
  if (providerId == 'builtin:bigmodel' ||
      providerId.startsWith('builtin:bigmodel-')) {
    return 'BigModel';
  }
  return null;
}

int _recommendedModelPriority(ConfigOptionValue option, String providerId) {
  if (!providerId.endsWith('-start-plan')) return kRecommendedModels.length;
  final model = modelReference(option.value).model.toLowerCase();
  final index = kRecommendedModels
      .indexWhere((candidate) => candidate.toLowerCase() == model);
  return index < 0 ? kRecommendedModels.length : index;
}

class ComposerOptions {
  ComposerOptions(this.prep);
  final WorkspacePrep? prep;

  ConfigOption? option(String category) => prep?.configOptions
      .where((o) =>
          o.type == 'select' && (o.category == category || o.id == category))
      .firstOrNull;

  List<ConfigOptionValue> get models {
    final entries = (option('model')?.options ?? [])
        .where((o) =>
            o.origin != 'injected' &&
            (o.origin == 'native' ||
                !(o.description
                        ?.trim()
                        .toLowerCase()
                        .startsWith('custom model') ??
                    false)))
        .toList();
    final order = {for (var i = 0; i < entries.length; i++) entries[i]: i};
    entries.sort((a, b) {
      final leftProvider = provider(a), rightProvider = provider(b);
      final providerResult = providerPriority(leftProvider)
          .compareTo(providerPriority(rightProvider));
      if (providerResult != 0) return providerResult;
      final leftRecommended = _recommendedModelPriority(a, leftProvider);
      final rightRecommended = _recommendedModelPriority(b, rightProvider);
      if (leftRecommended != rightRecommended) {
        return leftRecommended.compareTo(rightRecommended);
      }
      return order[a]!.compareTo(order[b]!);
    });
    return entries;
  }

  /// Models grouped by the stable provider identity advertised on each
  /// option. Display names are labels only; two providers with the same label
  /// must remain separate groups.
  List<ComposerModelGroup> get modelGroups {
    return modelGroupsFor(null);
  }

  List<ComposerModelGroup> modelGroupsFor(
      ComposerModelCatalogProjection? projection) {
    final groups = <String, List<ConfigOptionValue>>{};
    final order = <String>[];
    for (final value in models) {
      final id = provider(value);
      if (!groups.containsKey(id)) {
        groups[id] = <ConfigOptionValue>[];
        order.add(id);
      }
      groups[id]!.add(value);
    }
    return [
      for (final id in order)
        () {
          final metadata = projection?.provider(id);
          final label = _familyLabel(id) ??
              groups[id]!
                  .map((value) => value.modelProviderName?.trim())
                  .whereType<String>()
                  .firstWhere((value) => value.isNotEmpty,
                      orElse: () => metadata?.label ?? id);
          final vision = <String>{};
          for (final value in groups[id]!) {
            final model = modelReference(value.value).model;
            if (metadata?.supportsVision(model) == true ||
                metadata?.supportsVision(value.name) == true) {
              vision.add(value.value);
            }
          }
          return ComposerModelGroup(
            id: id,
            label: label,
            items: List<ConfigOptionValue>.unmodifiable(groups[id]!),
            directItems: metadata?.directItems ?? _defaultDirectItems(id),
            badgeLabel: metadata?.badgeLabel,
            visionModelValues: Set<String>.unmodifiable(vision),
          );
        }(),
    ];
  }

  String provider(ConfigOptionValue option) =>
      option.modelProviderId ?? modelReference(option.value).provider;

  ConfigOptionValue? model(Map<String, dynamic> config) => models
      .where((o) =>
          provider(o) == config['provider'] &&
          modelReference(o.value).model == config['model'])
      .firstOrNull;

  List<ConfigOptionValue> get modes =>
      option('mode')
          ?.options
          .where((o) => const {
                'default',
                'build',
                'plan',
                'edit',
                'yolo',
                'auto',
                'acceptEdits',
                'agent',
                'autoEdit',
                'dontAsk',
                'read-only',
                'fullAccess',
                'full-access',
                'agent-full-access',
                'bypassPermissions',
              }.contains(o.value))
          .toList() ??
      [];

  List<String> levels(Map<String, dynamic> config) {
    final advertised = model(config)?.modelThoughtLevels;
    if (advertised != null) return advertised;
    if (config['thoughtLevels'] is List) {
      return (config['thoughtLevels'] as List).map((e) => '$e').toList();
    }
    // prepareWorkspace's generic reasoning options belong only to its model.
    final selected = option('model')?.currentValue;
    if (selected is String) {
      final ref = modelReference(selected);
      if (ref.provider == config['provider'] && ref.model == config['model']) {
        return option('thought_level')?.options.map((o) => o.value).toList() ??
            [];
      }
    }
    return [];
  }

  Map<String, dynamic> defaults() {
    final value = option('model')?.currentValue;
    final mode = option('mode')?.currentValue;
    final thought = option('thought_level')?.currentValue;
    final result = <String, dynamic>{
      if (mode is String) 'mode': mode,
      if (thought is String) 'thought': thought,
    };
    if (value is String && value.isNotEmpty) {
      final ref = modelReference(value);
      result.addAll({'provider': ref.provider, 'model': ref.model});
    }
    final selected = model(result);
    return selected == null ? result : selectModel(selected, result);
  }

  Map<String, dynamic> selectModel(
      ConfigOptionValue value, Map<String, dynamic> current) {
    final ref = modelReference(value.value);
    final next = <String, dynamic>{
      ...current,
      'provider': provider(value),
      'model': ref.model
    };
    next.remove('thoughtLevels');
    final available = levels(next);
    final preferred = value.modelDefaultThoughtLevel;
    next['thought'] = available.contains(current['thought'])
        ? current['thought']
        : available.contains(preferred)
            ? preferred
            : available.firstOrNull ?? '';
    return next;
  }
}

/// One provider section in the official model picker.
class ComposerModelGroup {
  const ComposerModelGroup({
    required this.id,
    required this.label,
    required this.items,
    this.directItems = false,
    this.badgeLabel,
    this.visionModelValues = const <String>{},
  });

  final String id;
  final String label;
  final List<ConfigOptionValue> items;
  final bool directItems;
  final String? badgeLabel;
  final Set<String> visionModelValues;
}

bool _defaultDirectItems(String providerId) => isFamilyProviderId(providerId);
