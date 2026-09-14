import '../protocol/entitlement.dart';
import 'model_provider_catalog.dart';

/// Secret-free provider metadata used only to decorate the composer picker.
/// Model candidates still come exclusively from prepareWorkspace.
class ComposerProviderProjection {
  const ComposerProviderProjection({
    required this.id,
    required this.label,
    required this.source,
    required this.directItems,
    this.badgeLabel,
    this.visionModelIds = const <String>{},
  });

  final String id;
  final String label;
  final String source;
  final bool directItems;
  final String? badgeLabel;
  final Set<String> visionModelIds;

  bool supportsVision(String model) => visionModelIds.contains(model);
}

class ComposerModelCatalogProjection {
  const ComposerModelCatalogProjection({
    required this.scopeKey,
    required this.providers,
  });

  final String scopeKey;
  final Map<String, ComposerProviderProjection> providers;

  ComposerProviderProjection? provider(String id) => providers[id];

  /// Build a UI-safe projection. No raw provider map, API key, endpoint or
  /// headers are retained. Unknown metadata is left absent.
  factory ComposerModelCatalogProjection.fromCatalog(
      ModelProvidersCatalog catalog, Map<String, dynamic> familySelection) {
    final result = <String, ComposerProviderProjection>{};
    for (final provider in catalog.items) {
      final rawBadge = provider.raw['badgeLabel'];
      final entitlement =
          EntitlementSource.resolve(provider.id, familySelection);
      final badge = rawBadge is String && rawBadge.trim().isNotEmpty
          ? rawBadge.trim()
          : entitlement?.isTeam == true
              ? 'Team'
              : provider.id.endsWith('-start-plan')
                  ? 'Start'
                  : provider.id.endsWith('-coding-plan')
                      ? 'Individual'
                      : provider.id == 'zapi' ||
                              provider.id == 'builtin:zai' ||
                              provider.id == 'builtin:bigmodel' ||
                              provider.id == 'builtin:zapi'
                          ? 'API'
                          : null;
      final vision = <String>{};
      for (final model in provider.models) {
        if (model.inputModalities.any(_isVisionModality)) {
          vision.add(model.id);
          vision.add(model.name);
        }
      }
      final builtin = isFamilyProviderId(provider.id);
      result[provider.id] = ComposerProviderProjection(
        id: provider.id,
        label: provider.name,
        source: provider.source,
        directItems: builtin,
        badgeLabel: badge,
        visionModelIds: Set<String>.unmodifiable(vision),
      );
    }
    return ComposerModelCatalogProjection(
      scopeKey: catalog.scopeKey,
      providers: Map<String, ComposerProviderProjection>.unmodifiable(result),
    );
  }
}

bool _isVisionModality(String value) {
  final normalized = value.trim().toLowerCase();
  // Official WI marks a model when input modalities contain anything other
  // than text. Keep this broad so video/audio-capable rows are not hidden.
  return normalized != 'text';
}
