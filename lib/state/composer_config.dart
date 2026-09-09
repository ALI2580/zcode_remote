import '../protocol/conversation.dart';

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

bool firstPartyProvider(String value) => const {
      'glm',
      'builtin:zai-start-plan',
      'builtin:zai-coding-plan',
      'builtin:zai',
      'builtin:bigmodel-start-plan',
      'builtin:bigmodel-coding-plan',
      'builtin:bigmodel',
    }.contains(value);

int providerPriority(String value) {
  final index = const [
    'builtin:zai-start-plan',
    'builtin:zai-coding-plan',
    'builtin:zai',
    'builtin:bigmodel-start-plan',
    'builtin:bigmodel-coding-plan',
    'builtin:bigmodel',
    'builtin:zapi'
  ].indexOf(value);
  return index < 0 ? 200 : index;
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
      final result = providerPriority(provider(a))
          .compareTo(providerPriority(provider(b)));
      return result == 0 ? order[a]!.compareTo(order[b]!) : result;
    });
    return entries;
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
          .where(
              (o) => const ['build', 'edit', 'plan', 'yolo'].contains(o.value))
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
