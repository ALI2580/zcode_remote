import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../protocol/usage_statistics.dart';
import '../../state/client_preferences.dart';
import '../css_color.dart';
import '../theme.dart';
import 'usage_charts.dart';

enum HeatmapMode { daily, weekly, cumulative }

class UsageHeatmapView extends StatefulWidget {
  const UsageHeatmapView(
      {super.key, required this.heatmap, this.tools = false});
  final UsageHeatmap heatmap;
  final bool tools;
  @override
  State<UsageHeatmapView> createState() => _UsageHeatmapViewState();
}

class _UsageHeatmapViewState extends State<UsageHeatmapView> {
  HeatmapMode _mode = HeatmapMode.daily;
  (int, int)? _selected;
  @override
  Widget build(BuildContext context) {
    final weeks = widget.heatmap.weeks,
        ink = ZInk.of(Theme.of(context).colorScheme);
    if (weeks.isEmpty) return const SizedBox.shrink();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final colors = [
      for (var i = 0; i < 5; i++)
        mixOklab(
            ink.surfaceFill,
            i == 4
                ? (dark ? const Color(0xFF80BEFF) : const Color(0xFF0066DD))
                : ink.usageChart,
            (dark ? [0.0, .24, .42, .62, .78] : [0.0, .18, .36, .58, .82])[i])
    ];
    double? sum(Iterable<double?> values) => values.any((v) => v == null)
        ? null
        : values.fold<double>(0, (n, v) => n + v!);
    final totals = weeks.map((w) => sum(w.map((d) => d.tokens))).toList();
    final counts = weeks
        .map((w) => sum(w.map((d) => widget.tools ? d.tools : d.turns)))
        .toList();
    if (_mode == HeatmapMode.cumulative) {
      for (var i = 1; i < totals.length; i++) {
        totals[i] = sum([totals[i - 1], totals[i]]);
        counts[i] = sum([counts[i - 1], counts[i]]);
      }
    }
    final maxValue = totals.whereType<double>().fold<double>(0, math.max);
    final levels = List.generate(
        weeks.length,
        (w) => List.generate(7, (d) {
              if (_mode == HeatmapMode.daily) return weeks[w][d].level;
              final value = totals[w];
              if (value == null) return null;
              if (value <= 0 || maxValue <= 0) return 0;
              final height = (value / maxValue * 7).ceil().clamp(1, 7);
              return d >= 7 - height
                  ? (value / maxValue * 4).ceil().clamp(1, 4)
                  : 0;
            }));
    final months = <(int, int, String)>[];
    var start = 0;
    for (var w = 1; w <= weeks.length; w++) {
      if (w == weeks.length ||
          weeks[w][0].date.month != weeks[start][0].date.month) {
        months.add((
          start,
          w - start,
          DateFormat.MMM(Localizations.localeOf(context).toString())
              .format(weeks[start][0].date)
        ));
        start = w;
      }
    }
    return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
            color: ink.surfaceFill, borderRadius: BorderRadius.circular(12)),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Wrap(
              alignment: WrapAlignment.spaceBetween,
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(uiText(context, 'Token 活跃度', 'Token activity'),
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w500)),
                UsageSwitch(
                    value: _mode,
                    options: {
                      HeatmapMode.daily: uiText(context, '每日', 'Daily'),
                      HeatmapMode.weekly: uiText(context, '每周', 'Weekly'),
                      HeatmapMode.cumulative:
                          uiText(context, '累计', 'Cumulative')
                    },
                    onChanged: (v) => setState(() {
                          _mode = v;
                          _selected = null;
                        })),
              ]),
          const SizedBox(height: 12),
          LayoutBuilder(builder: (context, size) {
            final cell = math.max(1.0, (size.maxWidth - 51 * 2) / 52),
                row = cell + 4;
            final chartHeight = 7 * cell + 24;
            return Column(children: [
              Semantics(
                  label: uiText(context, '过去 52 周 Token 活跃度，点击查看日期和用量',
                      'Token activity for the last 52 weeks. Select a date for usage'),
                  child: GestureDetector(
                      onTapDown: (d) => setState(() => _selected = (
                            (d.localPosition.dx / (cell + 2))
                                .floor()
                                .clamp(0, 51),
                            (d.localPosition.dy / row).floor().clamp(0, 6)
                          )),
                      child: CustomPaint(
                          size: Size(size.maxWidth, chartHeight),
                          painter: _HeatmapPainter(
                              levels, colors, ink.border, cell, _selected)))),
              const SizedBox(height: 12),
              Row(children: [
                for (final month in months)
                  Expanded(
                      flex: month.$2,
                      child: Text(month.$3,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(fontSize: 12, color: ink.subtlest)))
              ]),
            ]);
          }),
          if (_selected case (final int w, final int d)) ...[
            const SizedBox(height: 12),
            Text(
                '${DateFormat.yMMMMd(Localizations.localeOf(context).toString()).format(weeks[w][_mode == HeatmapMode.daily ? d : 6].date)} · ${usageFormat(context, _mode == HeatmapMode.daily ? weeks[w][d].tokens : totals[w])} Tokens · ${usageFormat(context, _mode == HeatmapMode.daily ? widget.tools ? weeks[w][d].tools : weeks[w][d].turns : counts[w])} ${widget.tools ? uiText(context, '次工具调用', 'tool calls') : uiText(context, '轮对话', 'turns')}',
                style: const TextStyle(fontSize: 12)),
          ],
        ]));
  }
}

class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter(
      this.levels, this.colors, this.border, this.cell, this.selected);
  final List<List<int?>> levels;
  final List<Color> colors;
  final Color border;
  final double cell;
  final (int, int)? selected;
  @override
  void paint(Canvas canvas, Size size) {
    for (var w = 0; w < levels.length; w++) {
      for (var d = 0; d < 7; d++) {
        final level = levels[w][d];
        final rect = RRect.fromRectAndRadius(
            Rect.fromLTWH(w * (cell + 2), d * (cell + 4), cell, cell),
            const Radius.circular(4));
        if (level != null) {
          canvas.drawRRect(rect, Paint()..color = colors[level]);
        }
        if (level == null || level > 0 || selected == (w, d)) {
          canvas.drawRRect(
              rect,
              Paint()
                ..color = border
                ..style = PaintingStyle.stroke
                ..strokeWidth = selected == (w, d) ? 2 : .7);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HeatmapPainter oldDelegate) => true;
}
