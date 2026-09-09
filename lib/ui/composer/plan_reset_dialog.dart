import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import '../../protocol/entitlement.dart';
import '../../protocol/plan_reset.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_usage.dart';
import '../../state/plan_resets.dart';
import '../official_icons.dart';
import '../theme.dart';
import 'quota_section.dart';

Future<void> showPlanResetDialog(
    BuildContext context, ComposerUsage usage) async {
  final sourceKey = usage.source?.key;
  if (sourceKey == null) return;
  await showDialog<void>(
      context: context,
      barrierColor: const Color(0x99000000),
      builder: (_) => BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 4, sigmaY: 4),
          child: PlanResetDialog(usage: usage, sourceKey: sourceKey)));
}

class PlanResetDialog extends StatefulWidget {
  const PlanResetDialog(
      {super.key, required this.usage, required this.sourceKey});
  final ComposerUsage usage;
  final String sourceKey;
  @override
  State<PlanResetDialog> createState() => _PlanResetDialogState();
}

class _PlanResetDialogState extends State<PlanResetDialog> {
  Timer? _timer;
  PlanResetType? _busy;
  PlanResetType? _completed;
  String? _failure;
  final _consumed = <PlanResetType, ({int authoritative, int local})>{};
  ComposerUsage get usage => widget.usage;

  @override
  void initState() {
    super.initState();
    usage.addListener(_changed);
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(usage.refreshResetStatus(force: true));
    });
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timer?.cancel();
    usage.removeListener(_changed);
    super.dispose();
  }

  int _count(PlanResetType type) {
    final source = usage.source!;
    final current = usage.resets.available(source, type).length;
    final saved = _consumed[type];
    if (saved == null) return current;
    final local = current < saved.authoritative
        ? math.max(0, saved.local - (saved.authoritative - current))
        : saved.local;
    _consumed[type] = (authoritative: current, local: local);
    return math.max(0, current - local);
  }

  Future<void> _reset(PlanResetType type) async {
    if (_busy != null || usage.source?.key != widget.sourceKey) return;
    final initialCount = usage.resets.available(usage.source!, type).length;
    setState(() {
      _busy = type;
      _failure = null;
    });
    final success = await usage.useReset(type, sourceKey: widget.sourceKey);
    if (!mounted) return;
    if (success) {
      setState(() => _completed = type);
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      if (!mounted) return;
      if (usage.source?.key == widget.sourceKey) {
        final current = usage.resets.available(usage.source!, type).length;
        final previousLocal = _consumed[type]?.local ?? 0;
        _consumed[type] = (
          authoritative: current,
          local: current >= initialCount ? previousLocal + 1 : previousLocal
        );
      }
    } else {
      _failure = usage.source?.key != widget.sourceKey
          ? 'source'
          : usage.resets.state(usage.source!).entries[type]?.error ?? 'failed';
    }
    setState(() {
      _busy = null;
      _completed = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final matches = usage.source?.key == widget.sourceKey;
    final source = matches ? usage.source : null;
    final state = source == null ? null : usage.resets.state(source);
    final snapshot = matches ? usage.snapshot : null;
    final cards = <({String label, QuotaLimit limit, Color color, bool clock})>[
      if ((matches ? usage.resetLimit(PlanResetType.fiveHour) : null)
          case final QuotaLimit limit)
        (
          label: uiText(context, '5 小时', '5 hours'),
          limit: limit,
          color: ink.usageCharts[0],
          clock: true
        ),
      if ((matches ? usage.resetLimit(PlanResetType.week) : null)
          case final QuotaLimit limit)
        (
          label: uiText(context, '每周', 'Weekly'),
          limit: limit,
          color: ink.usageCharts[1],
          clock: false
        ),
      if (snapshot?.monthlyTool case final QuotaLimit limit)
        (
          label: uiText(context, '工具调用', 'Tool calls'),
          limit: limit,
          color: ink.usageCharts[2],
          clock: false
        ),
      if (snapshot?.mcpAggregate case final QuotaLimit limit)
        (
          label: 'ZCode MCP',
          limit: limit,
          color: ink.usageCharts[4],
          clock: false
        ),
    ];
    final types = matches
        ? PlanResetType.values
            .where((type) =>
                _busy == type || (usage.resetVisible(type) && _count(type) > 0))
            .toList()
        : <PlanResetType>[];
    final failure = !matches || _failure == 'source'
        ? uiText(context, '套餐来源已变更，请重新打开额度窗口。',
            'The plan source changed. Reopen the quota window.')
        : _failure == 'unconfirmed'
            ? uiText(context, '尚未确认重置结果，请刷新状态。',
                'Reset is not confirmed yet. Refresh its status.')
            : uiText(
                context, '重置额度失败，请重试。', 'Failed to reset quota. Try again.');
    return Dialog(
        backgroundColor: ink.card,
        insetPadding: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: ink.border)),
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(children: [
                        Expanded(
                            child: Text(
                                uiText(context, '可重置额度', 'Quota resets'),
                                style: TextStyle(
                                    fontSize: 16,
                                    height: 1.5,
                                    fontWeight: FontWeight.w500,
                                    color: ink.text))),
                        IconButton(
                            tooltip: uiText(context, '关闭', 'Close'),
                            style: IconButton.styleFrom(
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                minimumSize: const Size(24, 24),
                                fixedSize: const Size(24, 24)),
                            padding: EdgeInsets.zero,
                            onPressed: () => Navigator.pop(context),
                            icon:
                                LucideIcon('x', size: 16, color: ink.subtlest)),
                      ]),
                      const SizedBox(height: 20),
                      if (cards.isNotEmpty)
                        LayoutBuilder(builder: (context, constraints) {
                          final scale =
                              MediaQuery.textScalerOf(context).scale(12) / 12;
                          final columns = MediaQuery.sizeOf(context).width < 640
                              ? 1
                              : math.max(
                                  1,
                                  math.min(
                                      3,
                                      (constraints.maxWidth / (115 * scale))
                                          .floor()));
                          final width =
                              (constraints.maxWidth - (columns - 1) * 8) /
                                  columns;
                          return Wrap(spacing: 8, runSpacing: 8, children: [
                            for (final card in cards)
                              Container(
                                  width: width,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                      color: ink.surfaceFill,
                                      borderRadius: BorderRadius.circular(8)),
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(card.label,
                                            style: TextStyle(
                                                fontSize: 12,
                                                height: 1.625,
                                                color: ink.subtlest)),
                                        const SizedBox(height: 8),
                                        Wrap(
                                            spacing: 6,
                                            runSpacing: 4,
                                            crossAxisAlignment:
                                                WrapCrossAlignment.center,
                                            children: [
                                              Text(
                                                  formatQuotaPercent(card
                                                      .limit.remainingPercent),
                                                  style: TextStyle(
                                                      fontSize: 16,
                                                      height: 1,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                      color: ink.text)),
                                              Text(
                                                  card.clock
                                                      ? formatResetClock(card
                                                          .limit.nextResetTime)
                                                      : quotaResetDate(
                                                          context,
                                                          card.limit
                                                              .nextResetTime),
                                                  style: TextStyle(
                                                      fontSize: 10,
                                                      height: 1.625,
                                                      color: ink.subtlest)),
                                            ]),
                                        const SizedBox(height: 8),
                                        QuotaBar(
                                            percent:
                                                card.limit.remainingPercent,
                                            color: card.color),
                                      ])),
                          ]);
                        }),
                      if (types.isNotEmpty) const SizedBox(height: 20),
                      for (final type in types)
                        Padding(
                            padding: EdgeInsets.only(
                                bottom: type == types.last ? 0 : 8),
                            child: _resetRow(context, type, state!, source!)),
                      if (!matches || _failure != null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(failure,
                                key: const ValueKey('quota-reset-error'),
                                style: TextStyle(
                                    fontSize: 12, color: ink.diffRemoved))),
                      if (matches && state?.failed == true)
                        TextButton(
                            onPressed: () =>
                                usage.refreshResetStatus(force: true),
                            child: Text(uiText(context, '更新失败，重试',
                                'Could not update. Retry'))),
                      if (matches && types.isEmpty && _failure == null)
                        Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                                state?.loading == true
                                    ? uiText(context, '同步中...', 'Syncing...')
                                    : uiText(context, '暂无可用的重置额度',
                                        'No quota resets available'),
                                style: TextStyle(
                                    fontSize: 12,
                                    height: 1.625,
                                    color: ink.subtlest))),
                    ]))));
  }

  Widget _resetRow(BuildContext context, PlanResetType type,
      PlanResetScope state, EntitlementSource source) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final dates = usage.resets.available(source, type);
    final count = _count(type);
    final seconds = dates.isEmpty
        ? 0
        : math.max(0, ((dates.first - usage.resets.nowMillis) / 1000).ceil());
    final countdown = resetCountdown(context, seconds);
    final busy = _busy == type ||
        state.entries[type]?.phase == PlanResetPhase.processing;
    final done = _completed == type;
    final unconfirmed = state.entries[type]?.awaitingConfirmation == true;
    final title = type == PlanResetType.week
        ? uiText(context, '周额度重置', 'Weekly quota reset')
        : uiText(context, '5 小时额度重置', '5-hour quota reset');
    final caption = count > 1
        ? uiText(context, '最早 $countdown 后过期', 'Earliest expires in $countdown')
        : uiText(context, '$countdown 后过期', 'Expires in $countdown');
    final buttonLabel = done
        ? uiText(context, '已完成', 'Completed')
        : unconfirmed
            ? uiText(context, '刷新', 'Refresh')
            : uiText(context, '重置', 'Reset');
    final button = FilledButton(
        key: ValueKey('quota-reset-use-${type.wire}'),
        style: FilledButton.styleFrom(
            backgroundColor: ink.diffAdded,
            foregroundColor: Colors.white,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            minimumSize: const Size(48, 32),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            textStyle: const TextStyle(fontSize: 12),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6))),
        onPressed:
            busy || done || _busy != null || state.busy || usage.resets.readOnly
                ? null
                : () => _reset(type),
        child: busy && !done
            ? const SizedBox.square(
                dimension: 14,
                child: CircularProgressIndicator(strokeWidth: 1.5))
            : Text(buttonLabel));
    final description =
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(count > 1 ? '$title · $count' : title,
          style: TextStyle(fontSize: 14, height: 1.625, color: ink.text)),
      const SizedBox(height: 2),
      Text(caption,
          style: TextStyle(fontSize: 12, height: 1.625, color: ink.subtlest)),
    ]);
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: ink.surfaceFill, borderRadius: BorderRadius.circular(8)),
        child: LayoutBuilder(builder: (context, constraints) {
          final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
          return constraints.maxWidth < 240 * scale
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [description, const SizedBox(height: 8), button])
              : Row(children: [
                  Expanded(child: description),
                  const SizedBox(width: 12),
                  button
                ]);
        }));
  }
}

String resetCountdown(BuildContext context, int seconds) {
  final days = seconds ~/ 86400, hours = seconds % 86400 ~/ 3600;
  final minutes = seconds % 3600 ~/ 60, remainder = seconds % 60;
  if (days > 0) {
    return hours > 0
        ? uiText(context, '$days天$hours小时', '${days}d ${hours}h')
        : uiText(context, '$days天', '${days}d');
  }
  if (hours > 0) {
    return minutes > 0
        ? uiText(context, '$hours小时$minutes分钟', '${hours}h ${minutes}m')
        : uiText(context, '$hours小时', '${hours}h');
  }
  return uiText(context, '$minutes分钟$remainder秒', '${minutes}m ${remainder}s');
}
