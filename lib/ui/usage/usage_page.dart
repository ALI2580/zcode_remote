import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../protocol/entitlement.dart';
import '../../protocol/plan_reset.dart';
import '../../protocol/usage_statistics.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_usage.dart';
import '../../state/usage_statistics.dart';
import '../official_icons.dart';
import '../theme.dart';
import '../composer/plan_reset_dialog.dart';
import '../composer/quota_reset_status.dart';
import 'usage_charts.dart';
import 'usage_heatmap.dart';

class UsagePage extends StatefulWidget {
  const UsagePage(
      {super.key,
      required this.usage,
      this.application = false,
      this.statistics});
  final ComposerUsage usage;
  final bool application;
  final UsageStatistics? statistics;
  @override
  State<UsagePage> createState() => _UsagePageState();
}

class _UsagePageState extends State<UsagePage> {
  late final UsageStatistics _stats;
  late bool _application;
  Timer? _timer;
  VoidCallback? _stopObserving;
  @override
  void initState() {
    super.initState();
    _application = widget.application;
    _stats = widget.statistics ?? UsageStatistics(widget.usage.transport);
    widget.usage.addListener(_usageChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _stopObserving = widget.usage.observeResets();
      _stats.select(application: _application, source: widget.usage.source);
      unawaited(widget.usage.refresh().then((_) {
        if (mounted) return widget.usage.refreshResetStatus();
      }));
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          widget.usage.source != null &&
          widget.usage.resets.state(widget.usage.source!).status != null) {
        setState(() {});
      }
    });
  }

  void _usageChanged() {
    if (_stats.source?.key != widget.usage.source?.key) {
      _stats.select(application: _application, source: widget.usage.source);
    }
    if (mounted) setState(() {});
  }

  Future<void> _refresh() async {
    await widget.usage.refresh(force: true);
    if (!mounted) return;
    await Future.wait([
      _stats.refresh(force: true),
      widget.usage.refreshResetStatus(force: true)
    ]);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopObserving?.call();
    widget.usage.removeListener(_usageChanged);
    if (widget.statistics == null) _stats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: _stats,
      builder: (context, _) {
        final ink = ZInk.of(Theme.of(context).colorScheme);
        return Scaffold(
            appBar: AppBar(
                title: Text(uiText(context, '使用统计', 'Usage statistics'))),
            body: SafeArea(
                top: false,
                child: Align(
                    alignment: Alignment.topCenter,
                    child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 896),
                        child: ListView(
                            key: const ValueKey('usage-page-scroll'),
                            padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
                            children: [
                              Wrap(
                                  spacing: 12,
                                  runSpacing: 12,
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    UsageSwitch(
                                        value: _application,
                                        options: {
                                          true: uiText(
                                              context, '应用统计', 'Application'),
                                          false: uiText(
                                              context, '个人套餐', 'Personal plan')
                                        },
                                        onChanged: (value) {
                                          setState(() => _application = value);
                                          _stats.select(
                                              application: value,
                                              source: widget.usage.source);
                                        }),
                                    if (!_application &&
                                        widget.usage.source != null)
                                      Text(
                                          widget.usage.source!.isTeam
                                              ? uiText(
                                                  context, '团队套餐', 'Team plan')
                                              : widget.usage.source!.family ==
                                                      'bigmodel'
                                                  ? 'GLM Coding Plan'
                                                  : 'Z.AI Coding Plan',
                                          style: TextStyle(
                                              fontSize: 12,
                                              color: ink.subtlest)),
                                  ]),
                              const SizedBox(height: 24),
                              if (_stats.timeZoneFailed)
                                _error(uiText(context, '无法读取本地时区，请刷新重试。',
                                    'Could not read the local time zone. Refresh to retry.')),
                              if (_application)
                                ..._appContent(context)
                              else
                                ..._codingContent(context),
                              const SizedBox(height: 20),
                              Align(
                                  alignment: Alignment.centerRight,
                                  child: OutlinedButton.icon(
                                      key: const ValueKey('usage-page-refresh'),
                                      onPressed: _stats.initializing ||
                                              _stats.app.loading ||
                                              _stats.coding.loading
                                          ? null
                                          : _refresh,
                                      icon: const LucideIcon('refresh-cw',
                                          size: 14),
                                      label: Text(
                                          uiText(context, '刷新', 'Refresh')))),
                            ])))));
      });
  Widget _error(String text) => Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(text,
          style: TextStyle(
              fontSize: 14,
              color: ZInk.of(Theme.of(context).colorScheme).diffRemoved)));
  Widget _heading(String text, {Widget? trailing}) => Wrap(
          spacing: 12,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(text,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            if (trailing != null) trailing
          ]);
  Widget _range(BuildContext context) => UsageSwitch(
      value: _stats.range,
      options: {
        UsageRange.week: uiText(context, '近 7 天', 'Last 7 days'),
        UsageRange.month: uiText(context, '近 30 天', 'Last 30 days')
      },
      onChanged: _stats.selectRange);
  List<Widget> _appContent(BuildContext context) {
    final range = _stats.app,
        lifetime = _stats.lifetime,
        snapshot = range.snapshot;
    return [
      if (lifetime.failed)
        _error(uiText(context, '累计统计更新失败，请刷新重试。',
            'Could not update lifetime statistics. Refresh to retry.')),
      _ActivitySummary(
          summary: lifetime.snapshot?.summary ?? const {}, coding: false),
      if (lifetime.snapshot case final AppUsageSnapshot all) ...[
        const SizedBox(height: 20),
        UsageHeatmapView(heatmap: all.heatmap),
      ],
      const SizedBox(height: 20),
      _heading(uiText(context, '应用用量', 'Application usage'),
          trailing: _range(context)),
      const SizedBox(height: 20),
      if (range.failed)
        _error(uiText(context, '应用统计更新失败，请刷新重试。',
            'Could not update application statistics. Refresh to retry.')),
      if (snapshot == null)
        UsageEmpty(loading: range.loading || _stats.initializing)
      else ...[
        _ChartCard(
            title: uiText(context, '每日 Token 用量', 'Daily token usage'),
            child: UsageChart(plot: snapshot.daily, height: 240)),
        const SizedBox(height: 20),
        _ChartCard(
            title: uiText(context, '模型用量分布', 'Model usage distribution'),
            child: UsagePie(snapshot: snapshot)),
      ],
    ];
  }

  List<Widget> _codingContent(BuildContext context) {
    final read = _stats.coding, snapshot = read.snapshot;
    if (widget.usage.source == null || widget.usage.source!.isStartPlan) {
      return [
        UsageEmpty(
            loading: widget.usage.loadingSelection || _stats.initializing,
            message: widget.usage.loadingSelection
                ? null
                : uiText(context, '当前连接暂无可用的编程套餐统计。',
                    'No Coding Plan statistics available for this connection.')),
      ];
    }
    return [
      if (read.failed)
        _error(uiText(context, '套餐统计更新失败，请刷新重试。',
            'Could not update plan statistics. Refresh to retry.')),
      if (snapshot == null)
        UsageEmpty(loading: read.loading || _stats.initializing)
      else ...[
        _UsageQuotas(
            usage: widget.usage, snapshot: snapshot, onRefresh: _refresh),
        const SizedBox(height: 20),
        _heading(uiText(context, '活跃度', 'Activity')),
        const SizedBox(height: 16),
        _ActivitySummary(summary: snapshot.summary, coding: true),
        const SizedBox(height: 16),
        UsageHeatmapView(heatmap: snapshot.heatmap, tools: true),
        const SizedBox(height: 20),
        _heading(uiText(context, '趋势', 'Trends'), trailing: _range(context)),
        const SizedBox(height: 20),
        _CodingDetail(
            key: ValueKey('${snapshot.providerId}:${_stats.source?.key}'),
            snapshot: snapshot),
        const SizedBox(height: 20),
        _heading(uiText(context, '健康度', 'Health'),
            trailing: Text(uiText(context, '近 7 天', 'Last 7 days'),
                style: const TextStyle(fontSize: 12))),
        const SizedBox(height: 16),
        _ChartCard(child: UsageChart(plot: snapshot.health, unit: 'tokens/s')),
      ],
    ];
  }
}

class _ActivitySummary extends StatelessWidget {
  const _ActivitySummary({required this.summary, required this.coding});
  final Map<String, dynamic> summary;
  final bool coding;
  String _duration(BuildContext context, double? millis) {
    if (millis == null) return '--';
    final minutes = millis ~/ 60000,
        hours = millis ~/ 3600000,
        days = millis ~/ 86400000;
    if (minutes == 0) return uiText(context, '0 分钟', '0 min');
    return [
      if (days > 0) '$days${uiText(context, ' 天', 'd')}',
      if (hours % 24 > 0) '${hours % 24}${uiText(context, ' 小时', 'h')}',
      if (minutes % 60 > 0) '${minutes % 60}${uiText(context, ' 分钟', 'm')}'
    ].join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    String number(String key) =>
        usageFormat(context, usageNumber(summary[key]));
    final items = [
      (uiText(context, '累计 Token', 'Lifetime tokens'), number('totalTokens')),
      (
        uiText(context, '单日峰值', 'Peak daily tokens'),
        number(coding ? 'peakDailyTokens' : 'peakDayTokens')
      ),
      (
        coding
            ? uiText(context, '累计使用时长', 'Total usage time')
            : uiText(context, '最长对话', 'Longest session'),
        _duration(
            context,
            usageNumber(
                summary[coding ? 'totalUsageDurationMs' : 'longestSessionMs']))
      ),
      (
        uiText(context, '当前连续', 'Current streak'),
        '${number('currentStreakDays')} ${uiText(context, '天', 'days')}'
      ),
      (
        uiText(context, '最长连续', 'Longest streak'),
        '${number('longestStreakDays')} ${uiText(context, '天', 'days')}'
      ),
    ];
    return Container(
        decoration: BoxDecoration(
            color: ink.surfaceFill, borderRadius: BorderRadius.circular(12)),
        child: LayoutBuilder(builder: (context, size) {
          Widget item(int i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(children: [
                Tooltip(
                    message: items[i].$2,
                    child: Text(items[i].$2,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.w500))),
                const SizedBox(height: 4),
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Flexible(
                      child: Text(items[i].$1,
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: ink.subtlest))),
                  if (i == 1 &&
                      coding &&
                      usageDate(summary['peakDailyTokensDate']) != null)
                    Tooltip(
                        message: summary['peakDailyTokensDate'] as String,
                        child:
                            LucideIcon('info', size: 14, color: ink.subtlest)),
                ]),
              ]));
          return size.maxWidth >=
                  640 * (MediaQuery.textScalerOf(context).scale(14) / 14)
              ? Row(children: [
                  for (var i = 0; i < items.length; i++) ...[
                    if (i > 0)
                      SizedBox(
                          height: 28,
                          child: VerticalDivider(width: 1, color: ink.border)),
                    Expanded(child: item(i))
                  ]
                ])
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (var i = 0; i < items.length; i++) item(i)]);
        }));
  }
}

class _ChartCard extends StatelessWidget {
  const _ChartCard({this.title, required this.child});
  final String? title;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
      padding: EdgeInsets.all(title == null ? 0 : 16),
      decoration: BoxDecoration(
          color: ZInk.of(Theme.of(context).colorScheme).surfaceFill,
          borderRadius: BorderRadius.circular(12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title != null) ...[
          Text(title!,
              style:
                  const TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
          const SizedBox(height: 12)
        ],
        child
      ]));
}

class _CodingDetail extends StatefulWidget {
  const _CodingDetail({super.key, required this.snapshot});
  final CodingUsageSnapshot snapshot;
  @override
  State<_CodingDetail> createState() => _CodingDetailState();
}

class _CodingDetailState extends State<_CodingDetail> {
  bool _tools = false, _credits = true;
  List<String> _selected = [];
  UsagePlot get plot => widget.snapshot.plot(
      tools: _tools,
      credits: widget.snapshot.hasCreditsFor(_tools) && _credits);
  void _reset() => _selected = plot.series.take(3).map((s) => s.name).toList();
  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(covariant _CodingDetail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.snapshot != widget.snapshot) _reset();
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme), data = plot;
    final selected =
        data.series.where((s) => _selected.contains(s.name)).toList();
    final sum = selected.any((s) => s.sum == null)
        ? null
        : selected.fold<double>(0, (n, s) => n + s.sum!);
    final unit = widget.snapshot.hasCreditsFor(_tools) && _credits
        ? uiText(context, '积分', 'credits')
        : _tools
            ? uiText(context, '次', 'calls')
            : 'Tokens';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (widget.snapshot.detailHasCredits(_tools)) ...[
        _CreditSummary(summary: widget.snapshot.detail(_tools)),
        const SizedBox(height: 16),
      ],
      Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
              color: ink.surfaceFill, borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (widget.snapshot.hasCreditsFor(_tools))
                UsageSwitch(
                    value: _credits,
                    options: {
                      true: uiText(context, '积分', 'Credits'),
                      false: uiText(context, '用量', 'Usage')
                    },
                    onChanged: (v) => setState(() {
                          _credits = v;
                          _reset();
                        })),
              UsageSwitch(
                  value: _tools,
                  options: {
                    false: uiText(context, '模型', 'Models'),
                    true: uiText(context, '工具', 'Tools')
                  },
                  onChanged: (v) => setState(() {
                        _tools = v;
                        _reset();
                      })),
            ]),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              TextButton(
                  style: TextButton.styleFrom(
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4)),
                  onPressed: () => setState(_reset),
                  child: Text(
                      '${uiText(context, '合计', 'Total')}: ${usageFormat(context, sum)} $unit',
                      style: const TextStyle(fontSize: 12))),
              for (var i = 0; i < data.series.length && i < 8; i++)
                Semantics(
                    selected: _selected.contains(data.series[i].name),
                    child: TextButton(
                        style: TextButton.styleFrom(
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 4)),
                        onPressed: () => setState(() {
                              final name = data.series[i].name;
                              if (_selected.contains(name)) {
                                if (_selected.length > 1) {
                                  _selected.remove(name);
                                }
                              } else {
                                if (_selected.length >= 3) {
                                  _selected.removeAt(0);
                                }
                                _selected.add(name);
                              }
                            }),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Container(
                              width: 16,
                              height: 16,
                              decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(3),
                                  border:
                                      Border.all(color: ink.usageCharts[i % 6]),
                                  color: _selected.contains(data.series[i].name)
                                      ? ink.usageCharts[i % 6]
                                      : Colors.transparent),
                              child: _selected.contains(data.series[i].name)
                                  ? const LucideIcon('check',
                                      size: 12, color: Colors.white)
                                  : null),
                          const SizedBox(width: 8),
                          Flexible(
                              child: Text(
                                  '${usageLabel(context, data.series[i].name)}: ${usageFormat(context, data.series[i].sum)} $unit',
                                  style: TextStyle(
                                      fontSize: 12, color: ink.subtlest))),
                        ]))),
            ]),
            const SizedBox(height: 12),
            UsageChart(
                plot: UsagePlot(data.times, selected,
                    granularity: data.granularity),
                bars: true,
                legend: false,
                unit: unit,
                colors: [
                  for (var i = 0; i < data.series.length; i++)
                    if (_selected.contains(data.series[i].name))
                      ink.usageCharts[i % 6]
                ]),
          ])),
    ]);
  }
}

class _CreditSummary extends StatelessWidget {
  const _CreditSummary({required this.summary});
  final Map<String, dynamic> summary;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final locale = Localizations.localeOf(context).toString();
    final number = NumberFormat.decimalPattern(locale)
      ..maximumFractionDigits = 0;
    final percent = NumberFormat.percentPattern(locale)
      ..maximumFractionDigits = 1;
    final items = [
      ('cacheHitRate', uiText(context, '缓存命中率', 'Cache hit rate')),
      ('totalCredits', uiText(context, '总积分', 'Total credits')),
      ('averageDailyCredits', uiText(context, '日均积分', 'Average daily credits')),
    ];
    Widget card((String, String) item) {
      final value = usageNumber(summary[item.$1]);
      final formatted = value == null
          ? '--'
          : item.$1 == 'cacheHitRate'
              ? percent.format(value > 1 ? value / 100 : value)
              : number.format(value);
      return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: ink.surfaceFill.withValues(alpha: ink.surfaceFill.a * .7),
              borderRadius: BorderRadius.circular(12)),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(formatted,
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
            const SizedBox(height: 4),
            Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(item.$2,
                      style: TextStyle(fontSize: 14, color: ink.subtlest)),
                  if (summary['${item.$1}Trend'] case final num trend
                      when trend.isFinite)
                    Text(
                        '${trend > 0 ? '+' : trend < 0 ? '-' : ''}${(NumberFormat.percentPattern(locale)..maximumFractionDigits = 0).format(trend.abs())}',
                        style: TextStyle(
                            fontSize: 14,
                            color:
                                trend < 0 ? ink.diffRemoved : ink.diffAdded)),
                ]),
          ]));
    }

    return LayoutBuilder(
        builder: (context, size) => size.maxWidth >=
                640 * (MediaQuery.textScalerOf(context).scale(14) / 14)
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: card(items[i])),
                ]
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  card(items[i]),
                ]
              ]));
  }
}

class _UsageQuotas extends StatelessWidget {
  const _UsageQuotas(
      {required this.usage, required this.snapshot, required this.onRefresh});
  final ComposerUsage usage;
  final CodingUsageSnapshot snapshot;
  final VoidCallback onRefresh;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final fallback =
        EntitlementSnapshot.parse({'quota': snapshot.raw['quota']});
    final quota = usage.snapshot?.hasQuota == true ? usage.snapshot : fallback;
    final rows = <(String, QuotaLimit, int, PlanResetType?)>[
      if (quota?.fiveHour case final QuotaLimit q)
        (
          uiText(context, '5 小时', '5 hours'),
          usage.source == null
              ? q
              : usage.resets
                      .displayLimit(usage.source!, PlanResetType.fiveHour, q) ??
                  q,
          0,
          PlanResetType.fiveHour
        ),
      if (quota?.weekly case final QuotaLimit q)
        (
          uiText(context, '每周', 'Weekly'),
          usage.source == null
              ? q
              : usage.resets
                      .displayLimit(usage.source!, PlanResetType.week, q) ??
                  q,
          1,
          PlanResetType.week
        ),
      if (quota?.monthlyTool case final QuotaLimit q)
        (uiText(context, '工具调用', 'Tool calls'), q, 2, null),
      if (usage.snapshot?.mcpAggregate case final QuotaLimit q)
        ('ZCode MCP', q, 4, null),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Wrap(
                spacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Text(uiText(context, '剩余额度', 'Remaining quota'),
                      style: const TextStyle(
                          fontSize: 16, fontWeight: FontWeight.w500)),
                  if (usage.resetCount > 0)
                    TextButton.icon(
                        onPressed: () => showPlanResetDialog(context, usage),
                        icon: LucideIcon('gift',
                            size: 12, color: ink.confirmationText),
                        label: Text(
                            uiText(context, '${usage.resetCount} 次重置额度',
                                '${usage.resetCount} quota resets'),
                            style: TextStyle(
                                fontSize: 12, color: ink.confirmationText))),
                ]),
            Row(mainAxisSize: MainAxisSize.min, children: [
              if (snapshot.generatedAt case final double at
                  when at > 0 && at < 8640000000000000)
                Flexible(
                    child: Text(
                        '${uiText(context, '更新于', 'Updated')} ${DateFormat.yMd(Localizations.localeOf(context).toString()).add_Hm().format(DateTime.fromMillisecondsSinceEpoch(at.toInt()).toLocal())}',
                        style: TextStyle(fontSize: 14, color: ink.subtlest))),
              IconButton(
                  onPressed: onRefresh,
                  tooltip: uiText(context, '刷新', 'Refresh'),
                  icon: const LucideIcon('refresh-cw', size: 14)),
            ]),
          ]),
      const SizedBox(height: 16),
      LayoutBuilder(builder: (context, size) {
        final wide = MediaQuery.sizeOf(context).width >= 1024 &&
            size.maxWidth >=
                700 * (MediaQuery.textScalerOf(context).scale(14) / 14);
        Widget card((String, QuotaLimit, int, PlanResetType?) row) {
          final q = row.$2;
          final date = q.nextResetTime == null
              ? ''
              : DateFormat.MMMd(Localizations.localeOf(context).toString())
                  .add_Hm()
                  .format(DateTime.fromMillisecondsSinceEpoch(q.nextResetTime!)
                      .toLocal());
          return Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color:
                      ink.surfaceFill.withValues(alpha: ink.surfaceFill.a * .7),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Wrap(
                        spacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(row.$1, style: const TextStyle(fontSize: 14)),
                          if (row.$4 != null)
                            QuotaResetStatus(usage: usage, type: row.$4!),
                          if (row.$3 == 4)
                            Tooltip(
                                message: uiText(
                                    context,
                                    'ZCode 预置插件 MCP 每日合计额度',
                                    'Daily combined MCP quota for ZCode built-in plugins'),
                                child: LucideIcon('info',
                                    size: 14, color: ink.subtlest)),
                        ]),
                    const SizedBox(height: 4),
                    Wrap(
                        spacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(formatQuotaPercent(q.remainingPercent),
                              style: const TextStyle(
                                  fontSize: 18, fontWeight: FontWeight.w600)),
                          if (date.isNotEmpty)
                            Text(date,
                                style: TextStyle(
                                    fontSize: 14, color: ink.subtlest))
                        ]),
                    const SizedBox(height: 12),
                    ClipRRect(
                        borderRadius: BorderRadius.circular(99),
                        child: SizedBox(
                            height: 8,
                            child: LinearProgressIndicator(
                                value: q.remainingPercent == null
                                    ? 0
                                    : q.remainingPercent! / 100,
                                backgroundColor: ink.background,
                                color: ink.usageCharts[row.$3],
                                minHeight: 8))),
                  ]));
        }

        return wide
            ? Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(width: 12),
                  Expanded(child: card(rows[i]))
                ]
              ])
            : Column(children: [
                for (var i = 0; i < rows.length; i++) ...[
                  if (i > 0) const SizedBox(height: 12),
                  card(rows[i])
                ]
              ]);
      }),
    ]);
  }
}
