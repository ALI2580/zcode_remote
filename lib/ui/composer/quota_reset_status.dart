import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../protocol/plan_reset.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_usage.dart';
import '../../state/plan_resets.dart';
import '../theme.dart';
import 'plan_reset_dialog.dart';

/// Official AXe/jXe/sI: automatic reset progress 1s, completion until 2.6s.
class QuotaResetStatus extends StatefulWidget {
  const QuotaResetStatus({super.key, required this.usage, required this.type});
  final ComposerUsage usage;
  final PlanResetType type;
  @override
  State<QuotaResetStatus> createState() => _QuotaResetStatusState();
}

class _QuotaResetStatusState extends State<QuotaResetStatus> {
  Timer? _boundary, _removeBurst;
  OverlayEntry? _burst;
  ComposerUsage get usage => widget.usage;
  @override
  void initState() {
    super.initState();
    usage.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant QuotaResetStatus oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.usage != usage) {
      oldWidget.usage.removeListener(_changed);
      usage.addListener(_changed);
    }
  }

  @override
  void dispose() {
    usage.removeListener(_changed);
    _boundary?.cancel();
    _removeBurst?.cancel();
    _burst?.remove();
    super.dispose();
  }

  void _celebrate(int at) {
    final sourceKey = usage.source?.key;
    final generation = usage.resets.generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted ||
          usage.source == null ||
          usage.source?.key != sourceKey ||
          generation != usage.resets.generation ||
          MediaQuery.disableAnimationsOf(context)) {
        return;
      }
      final box = context.findRenderObject();
      final overlay = Overlay.maybeOf(context);
      if (box is! RenderBox || !box.attached || overlay == null) return;
      if (!usage.resets.claimCelebration(usage.source!, widget.type, at)) {
        return;
      }
      final origin = overlay.context.findRenderObject()! as RenderBox;
      final center =
          box.localToGlobal(box.size.center(Offset.zero), ancestor: origin);
      final ink = ZInk.of(Theme.of(context).colorScheme);
      _burst?.remove();
      _removeBurst?.cancel();
      _burst = OverlayEntry(
          builder: (_) => Positioned.fill(
              child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: 1),
                      duration: const Duration(milliseconds: 490),
                      builder: (_, progress, __) => CustomPaint(
                              painter: _ResetBurst(center, progress, [
                            ...ink.usageCharts.take(3),
                            Theme.of(context).colorScheme.primary,
                            ink.warning
                          ]))))));
      overlay.insert(_burst!);
      _removeBurst = Timer(const Duration(milliseconds: 500), () {
        _burst?.remove();
        _burst = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final source = usage.source;
    final entry =
        source == null ? null : usage.resets.state(source).entries[widget.type];
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final age = entry?.observedAt == null
        ? null
        : usage.resets.nowMillis - entry!.observedAt!;
    final automatic = entry?.automatic == true && age != null && age < 2600;
    final processing =
        entry?.phase == PlanResetPhase.processing || automatic && age < 1000;
    final completed = entry?.phase == PlanResetPhase.completed &&
        (entry?.automatic != true || automatic && !processing);
    _boundary?.cancel();
    if (automatic) {
      _boundary = Timer(
          Duration(milliseconds: (age < 1000 ? 1000 : 2600) - age), _changed);
    }
    if (completed) {
      if (automatic) _celebrate(entry!.completedAt!);
      final label = uiText(context, '已完成', 'Completed');
      final at = DateFormat.Hm(Localizations.localeOf(context).toString())
          .format(DateTime.fromMillisecondsSinceEpoch(entry!.completedAt!));
      return Tooltip(
          message: uiText(context, '$at 重置完成', 'Reset completed at $at'),
          child: Semantics(
              liveRegion: true,
              child: Text(label,
                  key: ValueKey('quota-reset-completed-${widget.type.wire}'),
                  style: TextStyle(fontSize: 12, color: ink.subtlest))));
    }
    if (processing) {
      return Semantics(
          label: uiText(context, '重置中', 'Resetting quota'),
          liveRegion: true,
          child: SizedBox.square(
              dimension: 12,
              child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  value: MediaQuery.disableAnimationsOf(context) ? 1 : null)));
    }
    if (!usage.resetVisible(widget.type)) return const SizedBox.shrink();
    return InkWell(
        onTap: usage.resets.readOnly
            ? null
            : () => showPlanResetDialog(context, usage),
        borderRadius: BorderRadius.circular(4),
        child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(uiText(context, '重置', 'Reset'),
                style: TextStyle(fontSize: 12, color: ink.confirmationText))));
  }
}

class _ResetBurst extends CustomPainter {
  const _ResetBurst(this.center, this.progress, this.colors);
  final Offset center;
  final double progress;
  final List<Color> colors;
  @override
  void paint(Canvas canvas, Size size) {
    for (var i = 0; i < 10; i++) {
      final t = (progress * 490 / (420 + i % 3 * 35)).clamp(0.0, 1.0);
      if (t >= 1) continue;
      final eased = const Cubic(.2, .8, .2, 1).transform(t);
      final angle = (-160 + 140 * i / 9) * math.pi / 180;
      final distance = 36 + (i * 19 % 29);
      final offset = Offset(
          math.cos(angle) * distance * eased,
          math.sin(angle) * distance * eased +
              32 * math.max(0, (eased - .65) / .35));
      canvas.save();
      canvas.translate(center.dx + offset.dx, center.dy + offset.dy);
      canvas.rotate((360 + i * 31) * eased * math.pi / 180);
      canvas.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromCenter(
                  center: Offset.zero, width: 2 + (i % 2), height: 3 + (i % 3)),
              const Radius.circular(1)),
          Paint()
            ..color = colors[i % colors.length].withValues(
                alpha: (1.0 - math.max(0.0, (eased - .65) / .35))
                    .clamp(0.0, 1.0)
                    .toDouble()));
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(_ResetBurst oldDelegate) =>
      progress != oldDelegate.progress;
}
