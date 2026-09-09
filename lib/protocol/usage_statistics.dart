/// Usage snapshots from the official usage-stats channel. Missing numeric
/// values stay missing; charts never substitute another provider's data.
library;

Map<String, dynamic> usageMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : const {};
List<dynamic> usageList(Object? value) => value is List ? value : const [];
double? usageNumber(Object? value) =>
    value is num && value.isFinite && value >= 0 ? value.toDouble() : null;
String? usageString(Object? value) =>
    value is String && value.trim().isNotEmpty ? value.trim() : null;
DateTime? usageDate(Object? value) {
  final text = usageString(value);
  if (text == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(text)) {
    return null;
  }
  final date = DateTime.tryParse('${text}T00:00:00Z');
  return date != null && date.toIso8601String().startsWith(text) ? date : null;
}

enum UsageRange {
  week('7d'),
  month('30d'),
  all('all');

  const UsageRange(this.wire);
  final String wire;
}

class UsageDay {
  UsageDay(this.date, this.tokens, this.turns, this.tools, this.level);
  final DateTime date;
  final double? tokens, turns, tools;
  final int? level;
  static UsageDay? parse(Object? raw) {
    final map = usageMap(raw), date = usageDate(usageMap(raw)['date']);
    if (date == null) return null;
    final level = usageNumber(map['level']);
    return UsageDay(
        date,
        usageNumber(map['totalTokens']),
        usageNumber(map['turnCount']),
        usageNumber(map['toolCallCount']),
        level != null && level <= 4 && level == level.round()
            ? level.toInt()
            : null);
  }
}

class UsageHeatmap {
  UsageHeatmap(this.days);
  final List<UsageDay> days;
  static UsageHeatmap parse(Object? raw) => UsageHeatmap([
        for (final week in usageList(usageMap(raw)['weeks']))
          for (final day in usageList(usageMap(week)['days']))
            if (UsageDay.parse(day) case final UsageDay parsed) parsed,
      ]);

  /// Official Xqt normalizes to the last 52 Sunday-based weeks, including
  /// implicit zero cells only when a valid dated heatmap was returned.
  List<List<UsageDay>> get weeks {
    if (days.isEmpty) return const [];
    final byDate = {for (final day in days) day.date: day};
    final last = days.map((d) => d.date).reduce((a, b) => a.isAfter(b) ? a : b);
    final first = last.subtract(Duration(days: last.weekday % 7 + 51 * 7));
    return List.generate(
        52,
        (week) => List.generate(7, (day) {
              final date = first.add(Duration(days: week * 7 + day));
              return byDate[date] ?? UsageDay(date, 0, 0, 0, 0);
            }));
  }
}

class UsageSeries {
  UsageSeries(
      {required this.name,
      required this.values,
      this.breakdown = const {},
      this.total});
  final String name;
  final List<double?> values;
  final Map<String, List<double?>> breakdown;
  final double? total;
  double? get sum => values.isEmpty || values.any((v) => v == null)
      ? null
      : values.fold<double>(0, (n, v) => n + v!);
  bool get hasData => values.any((v) => v != null && v > 0);
}

List<double?> _numbers(Object? value, int length) {
  final list = usageList(value);
  return List.generate(
      length, (i) => i < list.length ? usageNumber(list[i]) : null);
}

class UsagePlot {
  UsagePlot(this.times, this.series, {this.granularity = 'day'});
  final List<String> times;
  final List<UsageSeries> series;
  final String granularity;
  bool get hasData => series.any((s) => s.hasData);
}

class CodingUsageSnapshot {
  CodingUsageSnapshot._(this.raw, this.range, this.providerId);
  final Map<String, dynamic> raw;
  final String range, providerId;
  static CodingUsageSnapshot? parse(Object? raw,
      {required UsageRange range, required String providerId}) {
    final map = usageMap(raw);
    if (map['range'] != range.wire ||
        usageMap(map['sourceProvider'])['id'] != providerId ||
        map['activity'] is! Map ||
        map['modelUsage'] is! Map ||
        map['toolUsage'] is! Map) {
      return null;
    }
    return CodingUsageSnapshot._(map, range.wire, providerId);
  }

  Map<String, dynamic> get summary =>
      usageMap(usageMap(raw['activity'])['summary']);
  UsageHeatmap get heatmap =>
      UsageHeatmap.parse(usageMap(raw['activity'])['heatmap']);
  double? get generatedAt => usageNumber(raw['generatedAt']);
  Map<String, dynamic> detail(bool tools) =>
      usageMap(usageMap(raw['detail'])[tools ? 'tool' : 'model']);
  List<Map<String, dynamic>> _rows(bool tools) =>
      usageList(usageMap(raw[tools ? 'toolUsage' : 'modelUsage'])[
              tools ? 'toolDataList' : 'modelDataList'])
          .map(usageMap)
          .toList();
  bool _positive(Object? value) => (usageNumber(value) ?? 0) > 0;
  bool _rowHasCredits(Map<String, dynamic> row) =>
      _positive(row['totalCredits']) ||
      [
        'creditsUsage',
        'cachedInputCreditsUsage',
        'uncachedInputCreditsUsage',
        'outputCreditsUsage'
      ].any((key) => usageList(row[key]).any(_positive));
  bool get hasCredits => hasCreditsFor(false);
  bool hasCreditsFor(bool tools) =>
      _positive(detail(tools)['totalCredits']) ||
      _positive(detail(tools)['averageDailyCredits']) ||
      [false, true].any((kind) => _rows(kind).any(_rowHasCredits));
  bool detailHasCredits(bool tools) =>
      _positive(detail(tools)['totalCredits']) ||
      _positive(detail(tools)['averageDailyCredits']) ||
      _rows(tools).any(_rowHasCredits);
  UsagePlot plot({bool tools = false, bool credits = false}) {
    final map = usageMap(raw[tools ? 'toolUsage' : 'modelUsage']);
    final times =
        usageList(map['xTime']).map((v) => usageString(v) ?? '').toList();
    return UsagePlot(
        times,
        [
          for (final row in _rows(tools))
            UsageSeries(
                name: usageString(row[tools ? 'toolName' : 'modelName']) ?? '',
                values: _numbers(
                    row[credits
                        ? 'creditsUsage'
                        : tools
                            ? 'usageCount'
                            : 'tokensUsage'],
                    times.length),
                breakdown: tools || !hasCreditsFor(tools)
                    ? const {}
                    : {
                        for (final key in [
                          'cachedInput',
                          'uncachedInput',
                          'output'
                        ])
                          key: _numbers(
                              row['$key${credits ? 'Credits' : 'Tokens'}Usage'],
                              times.length),
                      },
                total: usageNumber(row[credits
                    ? 'totalCredits'
                    : tools
                        ? 'totalUsageCount'
                        : 'totalTokens']))
        ],
        granularity: usageString(map['granularity']) ?? 'day');
  }

  UsagePlot get health {
    final map = usageMap(raw['health']);
    final times =
        usageList(map['xTime']).map((v) => usageString(v) ?? '').toList();
    return UsagePlot(times, [
      UsageSeries(
          name: 'Max & Pro Decode',
          values: _numbers(map['proMaxDecodeSpeed'], times.length)),
      UsageSeries(
          name: 'Lite Decode',
          values: _numbers(map['liteDecodeSpeed'], times.length)),
    ]);
  }
}

class AppUsageModel {
  AppUsageModel(this.name, this.tokens);
  final String name;
  final double? tokens;
}

class AppUsageSnapshot {
  AppUsageSnapshot._(this.raw, this.range, this.timeZone);
  final Map<String, dynamic> raw;
  final String range, timeZone;
  static AppUsageSnapshot? parse(Object? raw,
      {required UsageRange range, required String timeZone}) {
    final map = usageMap(raw);
    if (map['range'] != range.wire ||
        map['timeZone'] != timeZone ||
        map['source'] != 'agent-db' ||
        map['summary'] is! Map ||
        map['dailyModelUsage'] is! List ||
        map['models'] is! List) {
      return null;
    }
    return AppUsageSnapshot._(map, range.wire, timeZone);
  }

  Map<String, dynamic> get summary => usageMap(raw['summary']);
  UsageHeatmap get heatmap => UsageHeatmap.parse(raw['heatmap']);
  List<AppUsageModel> get models => [
        for (final row in usageList(raw['models']).map(usageMap))
          AppUsageModel(usageString(row['modelId']) ?? '',
              usageNumber(row['totalTokens']))
      ];
  List<AppUsageModel> get pie {
    final positive = models.where((m) => (m.tokens ?? 0) > 0).toList();
    if (positive.length <= 6) return positive;
    return [
      ...positive.take(5),
      AppUsageModel('__other__',
          positive.skip(5).fold<double>(0, (sum, m) => sum + m.tokens!))
    ];
  }

  UsagePlot get daily {
    final top = models.take(6).toList();
    final days = usageList(raw['dailyModelUsage'])
        .map(usageMap)
        .where((d) => usageDate(d['date']) != null)
        .toList()
      ..sort((a, b) => (a['date'] as String).compareTo(b['date'] as String));
    return UsagePlot(days.map((d) => d['date'] as String).toList(), [
      for (final model in top)
        UsageSeries(name: model.name, values: [
          for (final day in days) _dayValue(day, model.name),
        ]),
    ]);
  }

  double? _dayValue(Map<String, dynamic> day, String name) {
    if (day['models'] is! List) return null;
    final rows = usageList(day['models'])
        .map(usageMap)
        .where((r) => (usageString(r['modelId']) ?? '') == name);
    var total = 0.0;
    for (final row in rows) {
      final value = usageNumber(row['totalTokens']);
      if (value == null) return null;
      total += value;
    }
    return total;
  }
}
