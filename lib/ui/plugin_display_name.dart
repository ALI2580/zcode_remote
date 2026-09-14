import 'package:flutter/material.dart';

import '../state/plugin_catalog.dart';

/// Resolves the plugin title used by the official settings projections.
///
/// Locale-specific listing names take precedence over the generic listing
/// name. Category metadata is intentionally never used as a display label.
String pluginDisplayName(CatalogPlugin plugin, Locale locale) {
  final listing = plugin.listing;
  final localized = _localizedListingName(listing['displayNameI18n'], locale);
  final displayName = listing['displayName'];
  if (localized != null) return localized;
  if (displayName is String && displayName.trim().isNotEmpty) {
    return displayName.trim();
  }
  return formatPluginName(plugin.name);
}

/// Applies the readable fallback used for IDs when a listing has no display
/// name (for example, `browser-use` becomes `Browser Use`).
String formatPluginName(String value) {
  final words = value
      .trim()
      .split(RegExp(r'[-_]+'))
      .where((word) => word.isNotEmpty)
      .map((word) {
    final lower = word.toLowerCase();
    if (lower == 'aws') return 'AWS';
    if (lower == 'mcp') return 'MCP';
    if (lower == 'zcode') return 'ZCode';
    return '${word[0].toUpperCase()}${word.substring(1)}';
  });
  final result = words.join(' ');
  return result.isEmpty ? value : result;
}

String? _localizedListingName(Object? raw, Locale locale) {
  if (raw is! Map) return null;
  final values = raw.map((key, value) => MapEntry('$key', value));
  final localeTag = locale.toLanguageTag().replaceAll('_', '-').toLowerCase();
  final language = locale.languageCode.toLowerCase();

  for (final entry in values.entries) {
    if (entry.key.replaceAll('_', '-').toLowerCase() == localeTag &&
        entry.value is String &&
        (entry.value as String).trim().isNotEmpty) {
      return (entry.value as String).trim();
    }
  }
  for (final entry in values.entries) {
    final key = entry.key.replaceAll('_', '-').toLowerCase();
    if ((key == language || key.startsWith('$language-')) &&
        entry.value is String &&
        (entry.value as String).trim().isNotEmpty) {
      return (entry.value as String).trim();
    }
  }
  return null;
}
