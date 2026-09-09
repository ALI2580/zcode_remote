/// Official rI / EXe: Coding Plan reset status, independent of token usage.
enum PlanResetType {
  fiveHour('FIVE_HOUR', Duration(hours: 5)),
  week('WEEK', Duration(days: 7));

  const PlanResetType(this.wire, this.period);
  final String wire;
  final Duration period;
}

int? _millis(Object? raw) =>
    raw is num && raw.isFinite && raw > 0 && raw <= 8640000000000000
        ? raw.toInt()
        : null;

class PlanResetStatus {
  const PlanResetStatus(this.expirations, this.usedAt, this.hasUnreadHistory);
  final Map<PlanResetType, List<int>> expirations;
  final Map<PlanResetType, int?> usedAt;
  final bool hasUnreadHistory;

  factory PlanResetStatus.parse(Object? raw) {
    if (raw is! Map ||
        raw['availableFiveHourResets'] is! List ||
        raw['availableWeekResets'] is! List) {
      throw const FormatException('missing coding plan reset status');
    }
    List<int> dates(String key) => [
          for (final entry in (raw[key] as List).whereType<Map>())
            if (_millis(entry['expireAt']) case final int value) value,
        ]..sort();
    int? history(String key) {
      final value = raw[key];
      return value is Map ? _millis(value['usedAt']) : null;
    }

    return PlanResetStatus({
      PlanResetType.fiveHour: dates('availableFiveHourResets'),
      PlanResetType.week: dates('availableWeekResets'),
    }, {
      PlanResetType.fiveHour: history('latestFiveHourResetHistory'),
      PlanResetType.week: history('latestWeekResetHistory'),
    }, raw['hasUnreadHistory'] == true);
  }

  List<int> available(PlanResetType type, int now) =>
      (expirations[type] ?? const []).where((date) => date > now).toList();
}

class PlanResetOpportunity {
  const PlanResetOpportunity(this.granted, this.nextTryAt);
  final bool granted;
  final int? nextTryAt;
  factory PlanResetOpportunity.parse(Object? raw) {
    if (raw is! Map || raw['granted'] is! bool) {
      throw const FormatException('missing coding plan reset opportunity');
    }
    return PlanResetOpportunity(
        raw['granted'] == true, _millis(raw['nextTryAt']));
  }

  /// Official mXe: grant/default cooldown 10m, server retry no earlier than 5m.
  int nextCheckAt(int now) => !granted && nextTryAt != null
      ? (nextTryAt! > now + 300000 ? nextTryAt! : now + 300000)
      : now + 600000;
}
