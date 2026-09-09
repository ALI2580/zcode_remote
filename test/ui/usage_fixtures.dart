Map<String, dynamic> statisticsFixture(String range,
    {bool application = false,
    String provider = 'builtin:bigmodel-coding-plan',
    String timeZone = 'Asia/Shanghai',
    double total = 4000000000,
    bool credits = false}) {
  final days = range == '7d'
      ? 7
      : range == '30d'
          ? 30
          : 365;
  final dates = List.generate(
      days,
      (i) => DateTime.utc(2026, 9, 9)
          .subtract(Duration(days: days - i - 1))
          .toIso8601String()
          .substring(0, 10));
  final models = List.generate(
      9,
      (i) => {
            'modelId': 'GLM-5.${i + 1}',
            'totalTokens': (9 - i) * 10000000,
          });
  final heatmap = {
    'weeks': [
      for (var i = 0; i < dates.length; i += 7)
        {
          'weekIndex': i ~/ 7,
          'days': [
            for (var j = 0; j < 7; j++)
              i + j >= dates.length
                  ? null
                  : {
                      'date': dates[i + j],
                      'totalTokens': (i + j) % 5 * 1000000,
                      'turnCount': 1 + (i + j) % 7,
                      'toolCallCount': 10 + (i + j) % 20,
                      'level': (i + j) % 5,
                    }
          ]
        }
    ]
  };
  final common = {
    'range': range,
    'generatedAt': DateTime.utc(2026, 9, 9).millisecondsSinceEpoch
  };
  if (application) {
    return {
      ...common,
      'timeZone': timeZone,
      'source': 'agent-db',
      'summary': {
        'totalTokens': total,
        'peakDayTokens': 380000000,
        'longestSessionMs': 12345678,
        'currentStreakDays': 12,
        'longestStreakDays': 51
      },
      'heatmap': heatmap,
      'models': models,
      'dailyModelUsage': [
        for (var i = 0; i < dates.length; i++)
          {
            'date': dates[i],
            'models': [
              for (var j = 0; j < 9; j++)
                {
                  'modelId': 'GLM-5.${j + 1}',
                  'totalTokens': (i + j + 1) % 8 * 1000000,
                }
            ]
          }
      ],
      'tools': [],
    };
  }
  return {
    ...common,
    'sourceProvider': {'id': provider, 'name': 'GLM Coding Plan'},
    'quota': {
      'level': 'MAX',
      'limits': [
        {'type': 'TOKENS_LIMIT', 'unit': 3, 'number': 5, 'percentage': 0},
        {
          'type': 'TOKENS_LIMIT',
          'unit': 6,
          'percentage': 6,
          'nextResetTime': 1790082000000
        },
        {
          'type': 'TIME_LIMIT',
          'unit': 5,
          'number': 1,
          'percentage': 5,
          'nextResetTime': 1790002000000
        },
      ]
    },
    'activity': {
      'summary': {
        'totalTokens': total,
        'peakDailyTokens': 380000000,
        'peakDailyTokensDate': '2026-09-05',
        'totalUsageDurationMs': 297322951,
        'currentStreakDays': 12,
        'longestStreakDays': 51
      },
      'heatmap': heatmap
    },
    'detail': {
      for (final kind in ['model', 'tool'])
        kind: {
          'cacheHitRate': .94,
          'cacheHitRateTrend': -.025,
          'totalCredits': credits ? 10000 : 0,
          'totalCreditsTrend': .24,
          'averageDailyCredits': credits ? 1500 : 0,
          'averageDailyCreditsTrend': .03
        }
    },
    'modelUsage': {
      'xTime': dates,
      'granularity': 'day',
      'modelDataList': [
        for (var j = 0; j < 9; j++)
          {
            'modelName': 'GLM-5.${j + 1}',
            'totalCredits': credits ? 1000 : 0,
            'tokensUsage': [
              for (var i = 0; i < days; i++) (i + j + 1) % 8 * 1000000
            ],
            'creditsUsage': [
              for (var i = 0; i < days; i++) credits ? (i + j + 1) % 8 * 100 : 0
            ],
            for (final part in ['cachedInput', 'uncachedInput', 'output'])
              '${part}TokensUsage': [
                for (var i = 0; i < days; i++)
                  (i + j + 1) % 8 * (part == 'cachedInput' ? 800000 : 100000)
              ],
          }
      ]
    },
    'toolUsage': {
      'xTime': dates,
      'granularity': 'day',
      'toolDataList': [
        {
          'toolName': 'Web search',
          'usageCount': [for (var i = 0; i < days; i++) i * 3],
          'creditsUsage': [for (var i = 0; i < days; i++) credits ? i * 2 : 0]
        }
      ]
    },
    'health': {
      'xTime': dates.take(7).toList(),
      'proMaxDecodeSpeed': [for (var i = 0; i < 7; i++) 55.0 + i * 2],
      'liteDecodeSpeed': [for (var i = 0; i < 7; i++) 135.0 - i * 3]
    },
  };
}
