import 'package:flutter/foundation.dart';

import 'composer_usage.dart';
import 'composer_references.dart';
import 'usage_statistics.dart';

/// Coordinates cache invalidation when the account changes (login/logout).
/// E2.2: after account change, quotas, sources and settings caches must be
/// cleared so late responses from the old account don't pollute new state.
class AccountChangeManager {
  AccountChangeManager._();

  /// Invalidates all caches that can contain account-scoped data.
  /// Call after a confirmed login or logout, never on speculative changes.
  static void invalidateAll({
    ComposerUsage? usage,
    ComposerReferences? references,
    UsageStatistics? statistics,
  }) {
    if (usage != null) usage.invalidate(clearCache: true);
    if (references != null) references.invalidate();
    if (statistics != null) statistics.invalidate();
    debugPrint('[AccountChange] invalidated all account-scoped caches');
  }
}
