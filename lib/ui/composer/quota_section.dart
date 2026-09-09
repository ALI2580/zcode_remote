import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../protocol/entitlement.dart';
import '../../protocol/plan_reset.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_usage.dart';
import '../official_icons.dart';
import '../theme.dart';
import 'plan_reset_dialog.dart';
import 'quota_reset_status.dart';

String quotaResetDate(BuildContext context, int? millis) => millis == null
    ? ''
    : DateFormat.MMMd(Localizations.localeOf(context).toString())
        .format(DateTime.fromMillisecondsSinceEpoch(millis).toLocal());

class QuotaSection extends StatefulWidget {
  const QuotaSection(
      {super.key,
      required this.usage,
      this.onMore,
      this.separated = false,
      this.padding = const EdgeInsets.all(12)});
  final ComposerUsage usage;
  final VoidCallback? onMore;
  final bool separated;
  final EdgeInsetsGeometry padding;

  @override
  State<QuotaSection> createState() => _QuotaSectionState();
}

class _QuotaSectionState extends State<QuotaSection> {
  Timer? _timer;
  VoidCallback? _stopObserving;
  ComposerUsage get usage => widget.usage;
  bool get separated => widget.separated;
  EdgeInsetsGeometry get padding => widget.padding;
  @override
  void initState() {
    super.initState();
    usage.addListener(_changed);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _stopObserving = usage.observeResets();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (usage.source != null &&
          usage.resets.state(usage.source!).status != null) {
        _changed();
      }
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant QuotaSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.usage != usage) {
      oldWidget.usage.removeListener(_changed);
      _stopObserving?.call();
      usage.addListener(_changed);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _stopObserving = usage.observeResets();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _stopObserving?.call();
    usage.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!usage.eligible) return const SizedBox.shrink();
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final snapshot = usage.snapshot;
    final start = usage.source?.isStartPlan == true;
    final busy = usage.refreshing || usage.loadingSelection;
    final cards = <({String key, String label, QuotaLimit limit, Color color})>[
      if (start && snapshot != null)
        for (final limit in snapshot.startPlanLimits)
          (
            key: 'start-${startPlanLimitLabel(limit)}',
            label: startPlanLimitLabel(limit),
            limit: limit,
            color: ink.diffAdded
          ),
      if (usage.resetLimit(PlanResetType.fiveHour) case final QuotaLimit limit
          when !start)
        (
          key: 'fiveHour',
          label: uiText(context, '5 小时', '5 hours'),
          limit: limit,
          color: ink.usageCharts[0]
        ),
      if (usage.resetLimit(PlanResetType.week) case final QuotaLimit limit
          when !start)
        (
          key: 'weekly',
          label: uiText(context, '每周', 'Weekly'),
          limit: limit,
          color: ink.usageCharts[1]
        ),
      if (snapshot?.monthlyTool case final QuotaLimit limit when !start)
        (
          key: 'toolCalls',
          label: uiText(context, '工具调用', 'Tool calls'),
          limit: limit,
          color: ink.usageCharts[2]
        ),
    ];
    final mcp = start ? null : snapshot?.mcpAggregate;
    final hasData = cards.isNotEmpty || mcp != null;
    final message = usage.sourceUnavailable
        ? uiText(context, '所选团队项目暂不可用，请检查套餐连接。',
            'The selected team project is unavailable. Check the plan connection.')
        : usage.failed
            ? uiText(context, '可能网络原因，更新失败',
                'Could not update quota. Check the connection.')
            : switch (snapshot?.unavailableReason) {
                'not_configured' => uiText(context, '未找到已连接的编程套餐账号。',
                    'No connected Coding Plan account found.'),
                'not_authenticated' => uiText(
                    context, '登录后查看剩余额度。', 'Sign in to see remaining quota.'),
                'no_plan' =>
                  uiText(context, '暂无有效编程套餐', 'No active Coding Plan'),
                _ => uiText(
                    context, '暂无可展示的权益数据。', 'No entitlement data available.'),
              };
    return Padding(
        padding: padding,
        child: DefaultTextStyle.merge(
            style: TextStyle(fontSize: 12, color: ink.subtlest),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (separated) Divider(height: 1, color: ink.border),
                  if (separated) const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                        child: Wrap(
                            spacing: 4,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                          Text(
                              start
                                  ? uiText(context, '今日余额', "Today's balance")
                                  : uiText(context, '剩余额度', 'Remaining quota'),
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: ink.text)),
                          if (usage.resetCount > 0)
                            Material(
                                color: ink.confirmationSurface,
                                borderRadius: BorderRadius.circular(99),
                                child: InkWell(
                                    key: const ValueKey('quota-reset-open'),
                                    borderRadius: BorderRadius.circular(99),
                                    onTap: () =>
                                        showPlanResetDialog(context, usage),
                                    child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 2),
                                        child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              LucideIcon('gift',
                                                  size: 12,
                                                  color: ink.confirmationText),
                                              const SizedBox(width: 4),
                                              Text(
                                                  uiText(
                                                      context,
                                                      '${usage.resetCount} 次重置额度',
                                                      '${usage.resetCount} quota resets'),
                                                  style: TextStyle(
                                                      fontSize: 12,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: ink
                                                          .confirmationText)),
                                            ])))),
                        ])),
                    if (widget.onMore != null &&
                        !start &&
                        hasData &&
                        !usage.failed)
                      TextButton(
                          key: const ValueKey('quota-more'),
                          onPressed: widget.onMore,
                          style: TextButton.styleFrom(
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 4, vertical: 6)),
                          child: Text(uiText(context, '更多', 'More'),
                              style:
                                  TextStyle(fontSize: 12, color: ink.subtlest)))
                    else if (busy)
                      const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 1.5))
                    else
                      Tooltip(
                          message: uiText(context, '刷新额度', 'Refresh quota'),
                          child: InkWell(
                              key: const ValueKey('quota-refresh'),
                              onTap: () => usage.refresh(force: true).then(
                                  (_) => usage.refreshResetStatus(force: true)),
                              borderRadius: BorderRadius.circular(6),
                              child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: Center(
                                      child: LucideIcon('refresh-cw',
                                          size: 14, color: ink.subtlest))))),
                  ]),
                  if (usage.source?.isTeam == true)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(uiText(context, '团队', 'Team'))),
                  const SizedBox(height: 8),
                  if (!hasData)
                    Text(
                        busy
                            ? uiText(context, '同步中...', 'Syncing...')
                            : message,
                        key: const ValueKey('quota-empty'),
                        style: TextStyle(
                            color:
                                usage.failed ? ink.diffRemoved : ink.subtlest)),
                  if (hasData)
                    LayoutBuilder(builder: (context, constraints) {
                      final standaloneMcp = cards.length >= 3 && mcp != null;
                      final count = cards.length +
                          (mcp != null && !standaloneMcp ? 1 : 0);
                      final scale =
                          MediaQuery.textScalerOf(context).scale(12) / 12;
                      final columns = math.max(
                          1,
                          math.min(math.min(count, 3),
                              (constraints.maxWidth / (84 * scale)).floor()));
                      final width =
                          (constraints.maxWidth - (columns - 1) * 8) / columns;
                      return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Wrap(spacing: 8, runSpacing: 12, children: [
                              for (final card in cards)
                                SizedBox(
                                    width: width,
                                    child: _QuotaCard(
                                        key: ValueKey('quota-${card.key}'),
                                        label: card.label,
                                        color: card.color,
                                        limit: card.limit,
                                        start: start,
                                        resetStatus: card.key == 'weekly' ||
                                                card.key == 'fiveHour'
                                            ? QuotaResetStatus(
                                                usage: usage,
                                                type: card.key == 'weekly'
                                                    ? PlanResetType.week
                                                    : PlanResetType.fiveHour)
                                            : null,
                                        clock: card.key == 'fiveHour')),
                              if (mcp != null && !standaloneMcp)
                                SizedBox(
                                    width: width,
                                    child: _QuotaCard(
                                        key: const ValueKey('quota-mcp'),
                                        label: 'ZCode MCP',
                                        color: ink.usageCharts[4],
                                        limit: mcp,
                                        description: uiText(
                                            context,
                                            'ZCode 预置插件 MCP 每日合计额度',
                                            'Daily combined MCP quota for ZCode built-in plugins'))),
                            ]),
                            if (standaloneMcp) ...[
                              Divider(color: ink.border, height: 20),
                              Tooltip(
                                  message: uiText(
                                      context,
                                      'ZCode 预置插件 MCP 每日合计额度',
                                      'Daily combined MCP quota for ZCode built-in plugins'),
                                  child: _McpQuotaRow(
                                      key: const ValueKey('quota-mcp'),
                                      limit: mcp)),
                            ],
                          ]);
                    }),
                  if (hasData && usage.failed)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(message,
                            style: TextStyle(color: ink.diffRemoved))),
                  if (usage.source != null &&
                      usage.resets.state(usage.source!).failed)
                    Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                            uiText(context, '重置额度状态更新失败，请刷新重试。',
                                'Could not update quota resets. Refresh to retry.'),
                            style: TextStyle(color: ink.diffRemoved))),
                ])));
  }
}

class _McpQuotaRow extends StatelessWidget {
  const _McpQuotaRow({super.key, required this.limit});
  final QuotaLimit limit;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, size) {
        final ink = ZInk.of(Theme.of(context).colorScheme);
        final value = formatQuotaPercent(limit.remainingPercent);
        final reset = quotaResetDate(context, limit.nextResetTime);
        final style = DefaultTextStyle.of(context).style;
        final valueStyle =
            style.copyWith(fontFamily: 'monospace', color: ink.text);
        final valueText = TextSpan(children: [
          TextSpan(text: value, style: valueStyle),
          if (reset.isNotEmpty)
            TextSpan(
                text: ' · $reset',
                style: style.copyWith(fontSize: 10, color: ink.subtlest)),
        ]);
        final measure = TextPainter(
            text: TextSpan(
                style: style,
                children: [const TextSpan(text: 'ZCode MCP'), valueText]),
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context))
          ..layout();
        final barWidth = (size.maxWidth - 16) / 3;
        final fits = measure.width + 4 + 16 + 16 + barWidth <= size.maxWidth;
        measure.dispose();
        final label = Row(mainAxisSize: MainAxisSize.min, children: [
          const Text('ZCode MCP'),
          const SizedBox(width: 4),
          LucideIcon('info', size: 14, color: ink.subtlest),
        ]);
        final summary = Text.rich(valueText);
        final bar = QuotaBar(
            percent: limit.remainingPercent, color: ink.usageCharts[4]);
        return fits
            ? Row(children: [
                label,
                const SizedBox(width: 8),
                Expanded(
                    child: Align(
                        alignment: Alignment.centerRight, child: summary)),
                const SizedBox(width: 8),
                SizedBox(width: barWidth, child: bar),
              ])
            : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    spacing: 8,
                    runSpacing: 4,
                    children: [label, summary]),
                const SizedBox(height: 6),
                bar,
              ]);
      });
}

class _QuotaCard extends StatelessWidget {
  const _QuotaCard(
      {super.key,
      required this.label,
      required this.color,
      required this.limit,
      this.start = false,
      this.clock = false,
      this.resetStatus,
      this.description});
  final String label;
  final String? description;
  final Color color;
  final QuotaLimit limit;
  final bool start, clock;
  final Widget? resetStatus;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final denominator = limit.number ?? limit.unit;
    final percent = start
        ? startPlanRemainingPercent(limit.remaining, denominator)
        : limit.remainingPercent;
    final value = start
        ? formatStartPlanPercent(limit.remaining, denominator)
        : formatQuotaPercent(percent);
    final date = limit.nextResetTime == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(limit.nextResetTime!).toLocal();
    final now = DateTime.now();
    final showClock = clock ||
        start &&
            date != null &&
            date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
    final reset = date == null
        ? ''
        : showClock
            ? formatResetClock(limit.nextResetTime)
            : quotaResetDate(context, limit.nextResetTime);
    final summary = '$label $value${reset.isEmpty ? '' : ' · $reset'}';
    return Tooltip(
        message: description == null ? summary : '$summary\n$description',
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 20),
              child: Row(children: [
                Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: ink.subtlest))),
                if (resetStatus != null) ...[
                  const SizedBox(width: 4),
                  Flexible(child: resetStatus!),
                ],
              ])),
          const SizedBox(height: 2),
          LayoutBuilder(builder: (context, constraints) {
            final style = DefaultTextStyle.of(context)
                .style
                .copyWith(fontFamily: 'monospace', fontSize: 12);
            final resetStyle = DefaultTextStyle.of(context)
                .style
                .copyWith(fontSize: 10, color: ink.subtlest);
            final measure = TextPainter(
                text: TextSpan(children: [
                  TextSpan(text: value, style: style),
                  if (reset.isNotEmpty)
                    TextSpan(text: ' · $reset', style: resetStyle)
                ]),
                textDirection: Directionality.of(context),
                textScaler: MediaQuery.textScalerOf(context))
              ..layout();
            final fits = measure.width <= constraints.maxWidth;
            measure.dispose();
            return Text.rich(
                TextSpan(children: [
                  TextSpan(text: value, style: style.copyWith(color: ink.text)),
                  if (reset.isNotEmpty && fits)
                    TextSpan(text: ' · $reset', style: resetStyle)
                ]),
                maxLines: 1);
          }),
          const SizedBox(height: 6),
          QuotaBar(percent: percent, color: color),
        ]));
  }
}

class QuotaBar extends StatelessWidget {
  const QuotaBar({super.key, required this.percent, required this.color});
  final double? percent;
  final Color color;
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final fraction = ((percent ?? 0) / 100).clamp(0.0, 1.0);
        return ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Container(
                height: 6,
                color: ZInk.of(Theme.of(context).colorScheme).hover,
                alignment: Alignment.centerLeft,
                child: AnimatedContainer(
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeOut,
                    height: 6,
                    width: fraction == 0
                        ? 0
                        : math.max(6, constraints.maxWidth * fraction),
                    color: color)));
      });
}
