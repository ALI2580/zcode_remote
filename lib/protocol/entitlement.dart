/// Coding-plan / start-plan entitlement snapshot parsing.
///
/// Mirrors the official web client's usage-popover quota logic (bundle
/// functions `fZe`/`gZe` renderers + `MF`/`NF`/`PF`/`IF`/`CI`/`SI`/`yI`
/// helpers, 2026-09-08 decryption). Data comes from the `usage-stats`
/// channel, method `getEntitlementSnapshot` — the same call `UsagePage`
/// already makes; this file only decodes and formats the response.
///
/// Pure Dart, zero Flutter dependency (protocol-layer convention).
library;

String? _string(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
num? _finite(Object? value) => value is num && value.isFinite ? value : null;
int? _resetMillis(Object? value) {
  final n = _finite(value);
  if (n == null || n == 0 || n.abs() > 8640000000000000) return null;
  return n.toInt();
}

/// O2e / Tv / fT: selected OAuth connection, including team scope.
class EntitlementSource {
  const EntitlementSource(
      {required this.providerId,
      required this.key,
      required this.isStartPlan,
      this.productId,
      this.organizationId,
      this.projectId});
  final String providerId, key;
  final bool isStartPlan;
  final String? productId, organizationId, projectId;
  bool get isTeam => key.startsWith('team-plan:');
  String get family =>
      providerId.startsWith('builtin:zai-') ? 'zai' : 'bigmodel';
  bool get needsTeamResolution =>
      isTeam &&
      (organizationId == null || projectId == null || projectId == '0');
  static bool supports(String? provider) => const {
        'builtin:zai-coding-plan',
        'builtin:bigmodel-coding-plan',
        'builtin:zai-start-plan',
        'builtin:bigmodel-start-plan',
      }.contains(provider);
  static EntitlementSource? resolve(
      String? provider, Map<String, dynamic> settings) {
    if (!supports(provider)) return null;
    final family = provider!.startsWith('builtin:zai-') ? 'zai' : 'bigmodel';
    final modes = settings['modelProviderFamilyModes'];
    if (modes is Map && modes[family] != null && modes[family] != 'oauth') {
      return null;
    }
    final keys = settings['modelProviderFamilySelectedKeys'];
    final key = keys is Map ? _string(keys[family]) : null;
    if (key == null) return null;
    final start = provider.endsWith('-start-plan');
    if (key == 'coding-plan:$provider') {
      return EntitlementSource(
          providerId: provider, key: key, isStartPlan: start);
    }
    final prefix = 'team-plan:$provider:';
    if (start || !key.startsWith(prefix)) return null;
    String decode(String value) {
      try {
        return Uri.decodeComponent(value).trim();
      } on FormatException {
        return value.trim();
      }
    }

    final parts = key.substring(prefix.length).split(':').map(decode).toList();
    if (parts.first.isEmpty) return null;
    final second = parts.length >= 2 ? _string(parts[1]) : null;
    final third = parts.length >= 3 ? _string(parts[2]) : null;
    final organization = second != null && third != null ? second : null;
    final project = organization != null ? third : second;
    return EntitlementSource(
        providerId: provider,
        key: key,
        isStartPlan: false,
        productId: parts.first,
        organizationId: organization,
        projectId: project);
  }

  EntitlementSource _team(
          String product, String organization, String project) =>
      EntitlementSource(
          providerId: providerId,
          key: 'team-plan:$providerId:${[
            product,
            organization,
            project
          ].map(Uri.encodeComponent).join(':')}',
          isStartPlan: false,
          productId: product,
          organizationId: organization,
          projectId: project);

  /// Official xB / pT: legacy product keys and :0 match a current product;
  /// project-only keys also match after the product id has changed.
  bool matchesTeam(EntitlementSource candidate) {
    if (!isTeam || !candidate.isTeam || providerId != candidate.providerId) {
      return false;
    }
    if (key == candidate.key ||
        key.startsWith('${candidate.key}:') ||
        candidate.key.startsWith('$key:')) {
      return true;
    }
    if (projectId == '0' && candidate.productId == productId) return true;
    if (projectId == null || projectId != candidate.projectId) return false;
    return organizationId == null ||
        candidate.organizationId == null ||
        organizationId == candidate.organizationId;
  }

  /// A2e/r2e: subscribed products supply authoritative organization/project
  /// identities for legacy source keys. Do not use an unrelated product.
  EntitlementSource? resolveTeamProducts(Object? response) {
    if (response is! Map || response['productList'] is! List) {
      throw const FormatException('missing team products');
    }
    for (final product in (response['productList'] as List).whereType<Map>()) {
      if (product['subscribed'] != true ||
          (product['family'] != null && product['family'] != family)) {
        continue;
      }
      final productId = _string(product['productId']);
      if (productId == null) continue;
      final projects = product['teamProjects'];
      final entries =
          projects is List && projects.isNotEmpty ? projects : [product];
      for (final project in entries.whereType<Map>()) {
        final organization = _string(project['organizationId']);
        final id = _string(project['projectId']);
        if (organization == null || id == null) continue;
        final candidate = _team(productId, organization, id);
        if (matchesTeam(candidate)) return candidate;
      }
    }
    return null;
  }

  /// Official k2e fallback uses the current entitlement's team identity, not
  /// its quota, to resolve a legacy selection before the scoped query.
  EntitlementSource? resolveTeamSnapshot(EntitlementSnapshot? snapshot) {
    if (snapshot?.providerId != providerId || snapshot?.scope != 'team') {
      return null;
    }
    final organization = snapshot!.organizationId, project = snapshot.projectId;
    if (organization == null || project == null) return null;
    final candidate =
        _team(snapshot.productId ?? 'current', organization, project);
    return matchesTeam(candidate) ? candidate : null;
  }

  bool accepts(EntitlementSnapshot snapshot) {
    if (snapshot.providerId != providerId) return false;
    if (!isTeam) return snapshot.scope != 'team';
    if (needsTeamResolution) return resolveTeamSnapshot(snapshot) != null;
    if (snapshot.scope != 'team') return false;
    if (organizationId != null && snapshot.organizationId != organizationId) {
      return false;
    }
    if (projectId != null && snapshot.projectId != projectId) return false;
    return projectId != null || snapshot.productId == productId;
  }
}

/// The seven `builtin:*` preset provider ids (official `G` enum) and their
/// fixed menu priority (official `YZe` map + `KI` stable sort). Providers
/// outside this map sort after all builtin ones, keeping their relative
/// wire order.
const Map<String, int> kBuiltinProviderPriority = {
  'builtin:zai-start-plan': 0,
  'builtin:zai-coding-plan': 1,
  'builtin:zai': 2,
  'builtin:bigmodel-start-plan': 3,
  'builtin:bigmodel-coding-plan': 4,
  'builtin:bigmodel': 5,
  'builtin:zapi': 6,
};

/// Models the official start-plan menu pins to the top (`Ed` constant —
/// the recommended set used by the `YI` filter).
const List<String> kRecommendedModels = ['GLM-5.2', 'GLM-5-Turbo'];

/// Official `po`/`Sd` predicate: one of the seven builtin preset ids.
bool isBuiltinProviderId(String? id) =>
    id != null && kBuiltinProviderPriority.containsKey(id);

/// The six Z.ai / BigModel **family** ids (official `wv` map — every
/// family member except `builtin:zapi`). `ja()` in the bundle: these are
/// the provider ids whose models render **without** the `{provider}/`
/// label prefix in the composer chip (official `PAe`).
const Set<String> kFamilyProviderIds = {
  'builtin:zai',
  'builtin:zai-start-plan',
  'builtin:zai-coding-plan',
  'builtin:bigmodel',
  'builtin:bigmodel-start-plan',
  'builtin:bigmodel-coding-plan',
};

/// Mirror of the official `ja(providerId)` first-party family check.
bool isFamilyProviderId(String? id) =>
    id != null && kFamilyProviderIds.contains(id);

/// Priority used to pin official provider groups to the top of the model
/// menu (official `GI`: map hit wins, everything else is 200 and keeps
/// the original wire order via the stable sort).
int officialProviderPriority(String? providerId) =>
    kBuiltinProviderPriority[providerId] ?? 200;

/// One entry of `quota.limits` (or `mcpQuota.aggregate`). Field semantics
/// per the official helpers:
/// - `type`: TOKENS_LIMIT / CREDIT_LIMIT (interchangeable family) or
///   TIME_LIMIT.
/// - `unit`/`number`: the quota period encoding — 5-hour pool is
///   unit 3 number 5, weekly is unit 6, monthly tool time is TIME_LIMIT
///   unit 5 number 1 (official `MF` selectors).
/// - `percentage`: **used** percent; the UI shows the remaining percent
///   (`PF`: `clamp(100 - percentage, 0, 100)`).
class QuotaLimit {
  final String type;
  final int? unit;
  final int? number;
  final num? remaining;

  /// Used percent (0..100), per the official field semantics.
  final double? percentage;

  /// Epoch milliseconds of the next reset.
  final int? nextResetTime;

  /// Per-model detail rows (`{modelCode, displayName, ...}`).
  final List<Map<String, dynamic>> usageDetails;

  QuotaLimit._(Map raw)
      : type = '${raw['type'] ?? ''}',
        unit = _finite(raw['unit'])?.toInt(),
        number = _finite(raw['number'])?.toInt(),
        remaining = _finite(raw['remaining']),
        percentage = _finite(raw['percentage'])?.toDouble(),
        nextResetTime = _resetMillis(raw['nextResetTime']),
        usageDetails = [
          for (final d in (raw['usageDetails'] is List
              ? raw['usageDetails'] as List
              : const []))
            if (d is Map) d.cast<String, dynamic>(),
        ];

  /// Test/dev seam mirroring the wire shape.
  factory QuotaLimit.fromRaw(Map raw) => QuotaLimit._(raw);

  QuotaLimit afterReset(int nextResetAt, {bool refill = false}) =>
      QuotaLimit._({
        'type': type,
        'unit': unit,
        'number': number,
        'remaining': remaining,
        'percentage': refill ? 0 : percentage,
        'nextResetTime': nextResetAt,
        'usageDetails': usageDetails,
      });

  /// Official `YYe`: TOKENS_LIMIT and CREDIT_LIMIT are the same family.
  bool matchesType(String family) {
    if (type == family) return true;
    const tokens = {'TOKENS_LIMIT', 'CREDIT_LIMIT'};
    const time = {'TIME_LIMIT'};
    if (tokens.contains(family)) return tokens.contains(type);
    if (time.contains(family)) return time.contains(type);
    return false;
  }

  /// Official `PF`: displayed value is the **remaining** percent.
  double? get remainingPercent {
    final p = percentage;
    if (p == null || p.isNaN || p.isInfinite) return null;
    return (100.0 - p).clamp(0.0, 100.0);
  }

  /// Official `FF`: quota completely full (nothing used).
  bool get isFull => remainingPercent == 100;
}

/// Parsed `getEntitlementSnapshot` response. Lenient throughout: missing
/// or malformed fields degrade to "section hidden", never to an error
/// (lesson #4 spirit — late/empty responses must not break the popover).
class EntitlementSnapshot {
  final String? providerId;
  final String? unavailableReason;
  final String? level;
  final List<QuotaLimit> limits;
  final QuotaLimit? mcpAggregate;
  final bool hasRemaining;
  final bool hasSubscription;
  final bool hasQuota;
  final String? scope, organizationId, projectId, productId;

  EntitlementSnapshot._({
    required this.providerId,
    required this.unavailableReason,
    required this.level,
    required this.limits,
    required this.mcpAggregate,
    required this.hasRemaining,
    required this.hasSubscription,
    required this.hasQuota,
    this.scope,
    this.organizationId,
    this.projectId,
    this.productId,
  });

  /// Official `BF`/`AS` visibility: not `no_plan`, and at least one of
  /// quota / subscription / remaining is present.
  bool get visible =>
      unavailableReason != 'no_plan' &&
      (hasQuota || hasSubscription || hasRemaining);

  /// A required provider can be absent on a negative response. It carries no
  /// account data, so show its empty-state reason without treating it as a
  /// successful match or falling back to another provider's balance.
  bool get isUnconfiguredSource =>
      (providerId == null || providerId!.isEmpty) &&
      const {'not_configured', 'not_authenticated', 'no_plan'}
          .contains(unavailableReason) &&
      !hasQuota &&
      !hasSubscription &&
      !hasRemaining &&
      mcpAggregate == null;

  /// `true` when this snapshot belongs to a start-plan (free tier)
  /// provider — the popover then renders the per-model "today's balance"
  /// section (`gZe`) instead of the coding-plan quota grid (`fZe`).
  bool get isStartPlan => providerId?.endsWith('-start-plan') ?? false;

  /// Official `MF(y, 'TOKENS_LIMIT', 3, 5)` — the rolling 5-hour pool.
  QuotaLimit? get fiveHour => _find('TOKENS_LIMIT', 3, 5);

  /// Official `MF(y, 'TOKENS_LIMIT', 6)` — the weekly quota.
  QuotaLimit? get weekly => _find('TOKENS_LIMIT', 6, null);

  /// Official `MF(y, 'TIME_LIMIT', 5, 1)` — monthly tool-call time.
  QuotaLimit? get monthlyTool => _find('TIME_LIMIT', 5, 1);

  QuotaLimit? _find(String family, int unit, int? number) {
    for (final l in limits) {
      if (l.matchesType(family) &&
          l.unit == unit &&
          (number == null || l.number == number)) {
        return l;
      }
    }
    return null;
  }

  /// Official `CI`: start-plan limits worth showing (`bI` reads
  /// `number ?? unit ?? 0`, `xI` reads `remaining ?? 0`).
  List<QuotaLimit> get startPlanLimits => [
        for (final l in limits)
          if ((l.number ?? l.unit ?? 0) > 0 || (l.remaining ?? 0) > 0) l,
      ];

  /// Lenient decoder. Returns `null` for a non-map response so callers
  /// hide the quota section entirely.
  static EntitlementSnapshot? parse(Object? res) {
    if (res is! Map) return null;
    final provider = res['provider'];
    final quota = res['quota'];
    final mcpQuota = res['mcpQuota'];
    final aggregate = mcpQuota is Map ? mcpQuota['aggregate'] : null;
    final context = res['context'];
    final subscription = res['subscription'];
    final details = subscription is Map ? subscription['details'] : null;
    final detail = details is List && details.isNotEmpty && details.first is Map
        ? details.first as Map
        : null;
    return EntitlementSnapshot._(
      providerId: provider is Map ? '${provider['id'] ?? ''}' : null,
      unavailableReason: _string(res['unavailableReason']),
      level: quota is Map ? _string(quota['level']) : null,
      scope: context is Map ? _string(context['scope']) : null,
      organizationId:
          context is Map ? _string(context['organizationId']) : null,
      projectId: context is Map ? _string(context['projectId']) : null,
      productId: (context is Map ? _string(context['productId']) : null) ??
          _string(detail?['productId']),
      hasQuota: quota is Map,
      limits: [
        if (quota is Map)
          for (final l
              in (quota['limits'] is List ? quota['limits'] as List : const []))
            if (l is Map) QuotaLimit._(l),
      ],
      mcpAggregate: aggregate is Map ? QuotaLimit._(aggregate) : null,
      hasRemaining: res['remaining'] is Map,
      hasSubscription: res['subscription'] is Map,
    );
  }
}

/// Official `IF`: remaining-percent text — `--` when unknown, otherwise
/// 0 decimals at >= 10%, 1 decimal below.
String formatQuotaPercent(double? remainingPercent) {
  if (remainingPercent == null || !remainingPercent.isFinite) return '--';
  final v = remainingPercent;
  if (v >= 10) return '${v.round()}%';
  // maximumFractionDigits: 1 — a whole value below 10 renders without
  // the decimal part (Intl drops trailing zeros).
  final oneDecimal = (v * 10).round() / 10;
  return '${oneDecimal.truncateToDouble() == oneDecimal ? oneDecimal.toInt() : oneDecimal}%';
}

/// Official `pZe`: start-plan card percent — remaining/number as a whole
/// percent, clamped 0..1.
String formatStartPlanPercent(num? remaining, num? number) {
  final percent = startPlanRemainingPercent(remaining, number);
  return percent == null ? '--' : '${percent.round()}%';
}

/// Missing balances must remain unknown, including on Start Plan cards.
double? startPlanRemainingPercent(num? remaining, num? number) {
  if (remaining == null ||
      !remaining.isFinite ||
      number == null ||
      !number.isFinite ||
      number <= 0) {
    return null;
  }
  return (remaining / number * 100).clamp(0.0, 100.0);
}

/// Official `mZe`: model code → display fallback. Strips the `model:`
/// prefix, special-cases `glm-5-turbo` → `GLM-5Turbo`, else uppercases.
String modelCodeDisplay(String code) {
  var c = code.replaceFirst(RegExp(r'^model:', caseSensitive: false), '');
  if (c.toLowerCase() == 'glm-5-turbo') return 'GLM-5Turbo';
  return c.toUpperCase();
}

/// Official `yI`: humanize a model display name. `GLM-*` keeps its dash
/// structure (first segment uppercased, `turbo` → `Turbo`); anything else
/// splits on `_`/`-`, uppercases the GLM/API/MCP/AI tokens and plain
/// version numbers stay untouched.
String prettyModelName(String name) {
  final t = name.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (RegExp(r'^GLM-\S+$', caseSensitive: false).hasMatch(t)) {
    final parts = t.split('-');
    for (var i = 0; i < parts.length; i++) {
      if (i == 0) {
        parts[i] = 'GLM';
      } else if (RegExp(r'^turbo$', caseSensitive: false).hasMatch(parts[i])) {
        parts[i] = 'Turbo';
      }
    }
    return parts.join('-');
  }
  final spaced = t.replaceAll(RegExp(r'[_-]+'), ' ');
  if (spaced.isEmpty) return '';
  final words = spaced.split(' ');
  for (var i = 0; i < words.length; i++) {
    final w = words[i];
    if (RegExp(r'^(GLM|API|MCP|AI)$', caseSensitive: false).hasMatch(w)) {
      words[i] = w.toUpperCase();
    } else if (RegExp(r'^\d+(\.\d+)?$').hasMatch(w)) {
      words[i] = w;
    } else if (w.isNotEmpty) {
      words[i] = w[0].toUpperCase() + w.substring(1).toLowerCase();
    }
  }
  return words.join(' ');
}

/// Official `SI`: start-plan card title — prettified display names (or
/// model codes) joined with ' / ', falling back to the raw limit type.
String startPlanLimitLabel(QuotaLimit limit) {
  final names = <String>[];
  for (final d in limit.usageDetails) {
    final display = '${d['displayName'] ?? ''}'.trim();
    final code = '${d['modelCode'] ?? ''}'.trim();
    final label = prettyModelName(display.isNotEmpty
        ? display
        : (code.isNotEmpty ? modelCodeDisplay(code) : ''));
    if (label.isNotEmpty) names.add(label);
  }
  return names.isEmpty ? limit.type : names.join(' / ');
}

/// Official `uZe`: 5-hour pool reset time — HH:mm, 24h.
String formatResetClock(int? epochMillis) {
  final millis = _resetMillis(epochMillis);
  if (millis == null) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  return '${t.hour.toString().padLeft(2, '0')}:'
      '${t.minute.toString().padLeft(2, '0')}';
}

/// Official `LF` with `format: 'date'`: month + day ("9月8日" in zh).
String formatResetDate(int? epochMillis) {
  final millis = _resetMillis(epochMillis);
  if (millis == null) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  return '${t.month}月${t.day}日';
}

/// Official `LF` with `format: 'adaptive'`: same-day resets show HH:mm,
/// later ones show the date.
String formatResetAdaptive(int? epochMillis) {
  final millis = _resetMillis(epochMillis);
  if (millis == null) return '';
  final t = DateTime.fromMillisecondsSinceEpoch(millis).toLocal();
  final now = DateTime.now();
  if (t.year == now.year && t.month == now.month && t.day == now.day) {
    return formatResetClock(epochMillis);
  }
  return formatResetDate(epochMillis);
}
