import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../../protocol/usage_statistics.dart';
import '../../state/client_preferences.dart';
import '../theme.dart';

String usageFormat(BuildContext context, num? value) {
  if (value == null || !value.isFinite) return '--';
  final locale = Localizations.localeOf(context).toString();
  return ((value.abs() >= 1000
          ? NumberFormat.compact(locale: locale)
          : NumberFormat.decimalPattern(locale))
        ..maximumFractionDigits = 1
        ..minimumFractionDigits = 0)
      .format(value);
}

String usageLabel(BuildContext context, String name) => name == '__other__'
    ? uiText(context, '其他', 'Other')
    : name.isEmpty
        ? uiText(context, '未知模型', 'Unknown model')
        : name;
String usageDayLabel(BuildContext context, String date) {
  final parsed = usageDate(date);
  return parsed == null
      ? date
      : DateFormat.MMMd(Localizations.localeOf(context).toString())
          .format(parsed);
}

class UsageEmpty extends StatelessWidget {
  const UsageEmpty({super.key, this.loading = false, this.message});
  final bool loading;
  final String? message;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      decoration: BoxDecoration(
          border:
              Border.all(color: ZInk.of(Theme.of(context).colorScheme).border),
          borderRadius: BorderRadius.circular(12)),
      child: Column(children: [
        if (loading)
          const SizedBox.square(
              dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
        const SizedBox(height: 8),
        Text(
            message ??
                (loading
                    ? uiText(context, '正在加载使用统计…', 'Loading usage statistics…')
                    : uiText(context, '暂无使用数据', 'No usage data')),
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14)),
      ]));
}

class UsageSwitch<T> extends StatelessWidget {
  const UsageSwitch(
      {super.key,
      required this.value,
      required this.options,
      required this.onChanged});
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onChanged;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Material(
        color: ink.surface,
        borderRadius: BorderRadius.circular(99),
        child: Padding(
            padding: const EdgeInsets.all(2),
            child: Wrap(children: [
              for (final entry in options.entries)
                Semantics(
                    selected: value == entry.key,
                    child: Material(
                        color: value == entry.key
                            ? ink.background
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(99),
                        child: InkWell(
                            borderRadius: BorderRadius.circular(99),
                            onTap: () => onChanged(entry.key),
                            child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 5),
                                child: Text(entry.value,
                                    style: TextStyle(
                                        fontSize: 12,
                                        height: 1.2,
                                        fontWeight: FontWeight.w500,
                                        color: value == entry.key
                                            ? ink.text
                                            : ink.subtlest))))))
            ])));
  }
}

class UsageChart extends StatefulWidget {
  const UsageChart(
      {super.key,
      required this.plot,
      this.bars = false,
      this.legend = true,
      this.unit = 'Tokens',
      this.colors,
      this.height = 256});
  final UsagePlot plot;
  final bool bars, legend;
  final String unit;
  final List<Color>? colors;
  final double height;
  @override
  State<UsageChart> createState() => _UsageChartState();
}

class _UsageChartState extends State<UsageChart> {
  int? _selected;
  @override
  void didUpdateWidget(covariant UsageChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.plot.times.length != widget.plot.times.length ||
        oldWidget.plot.series.length != widget.plot.series.length ||
        oldWidget.plot.times.indexed
            .any((e) => e.$2 != widget.plot.times[e.$1]) ||
        oldWidget.plot.series.indexed
            .any((e) => e.$2.name != widget.plot.series[e.$1].name)) {
      _selected = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final plot = widget.plot, ink = ZInk.of(Theme.of(context).colorScheme);
    if (!plot.hasData || plot.times.isEmpty) return const UsageEmpty();
    final colors = widget.colors ?? ink.usageCharts;
    final labels = plot.times
        .map((d) => plot.granularity == 'hour'
            ? d.substring(0, math.min(5, d.length))
            : usageDayLabel(context, d))
        .toList();
    return Padding(
        padding: const EdgeInsets.all(12),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (widget.legend) ...[
            Wrap(spacing: 12, runSpacing: 8, children: [
              for (var i = 0; i < plot.series.length; i++)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          color: colors[i % colors.length],
                          borderRadius: BorderRadius.circular(2))),
                  const SizedBox(width: 8),
                  Flexible(
                      child: Text(usageLabel(context, plot.series[i].name),
                          style: TextStyle(fontSize: 12, color: ink.subtlest)))
                ])
            ]),
            const SizedBox(height: 12),
          ],
          Semantics(
              label: uiText(
                  context, '用量图表，点击日期查看详情', 'Usage chart. Select a date for details'),
              child: LayoutBuilder(
                  builder: (context, size) => GestureDetector(
                      onTapDown: (d) => setState(() => _selected =
                          (((d.localPosition.dx - 24) / math.max(1, size.maxWidth - 48)) * (plot.times.length - 1))
                              .round()
                              .clamp(0, plot.times.length - 1)),
                      child: CustomPaint(
                          size: Size(size.maxWidth, widget.height),
                          painter: _PlotPainter(
                              plot,
                              colors,
                              ink.border,
                              ink.subtlest,
                              labels,
                              widget.bars,
                              MediaQuery.textScalerOf(context),
                              _selected,
                              DefaultTextStyle.of(context).style.fontFamily))))),
          if (_selected case final int selected) ...[
            const SizedBox(height: 8),
            Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                    color: ink.background,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: ink.border)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(labels[selected],
                          style: const TextStyle(
                              fontSize: 12, fontWeight: FontWeight.w500)),
                      for (final series in plot.series) ...[
                        const SizedBox(height: 6),
                        Text(
                            '${usageLabel(context, series.name)}: ${usageFormat(context, series.values[selected])} ${widget.unit}',
                            style: const TextStyle(fontSize: 12)),
                        if (widget.bars &&
                            series.breakdown.values
                                .any((v) => v.any((n) => (n ?? 0) > 0)))
                          for (final part in series.breakdown.entries)
                            Text(
                                '${switch (part.key) {
                                  'cachedInput' =>
                                    uiText(context, '缓存输入', 'Cached input'),
                                  'uncachedInput' =>
                                    uiText(context, '非缓存输入', 'Uncached input'),
                                  _ => uiText(context, '输出', 'Output')
                                }}: ${usageFormat(context, part.value[selected])}',
                                style: TextStyle(
                                    fontSize: 12, color: ink.subtlest)),
                      ],
                    ])),
          ],
        ]));
  }
}

class _PlotPainter extends CustomPainter {
  _PlotPainter(this.plot, this.colors, this.grid, this.text, this.labels,
      this.bars, this.scaler, this.selected, this.fontFamily);
  final UsagePlot plot;
  final List<Color> colors;
  final Color grid, text;
  final List<String> labels;
  final bool bars;
  final TextScaler scaler;
  final int? selected;
  final String? fontFamily;
  @override
  void paint(Canvas canvas, Size size) {
    final area = Rect.fromLTRB(24, 8, math.max(25, size.width - 24),
        size.height - scaler.scale(12) - 16);
    bool stacked(UsageSeries s) =>
        s.breakdown.values.any((v) => v.any((n) => (n ?? 0) > 0));
    double? valueAt(UsageSeries s, int i) =>
        bars && stacked(s) && s.breakdown.values.every((v) => v[i] != null)
            ? s.breakdown.values.fold<double>(0, (sum, v) => sum + v[i]!)
            : s.values[i];
    final maxValue = plot.series
        .expand((s) => List.generate(s.values.length, (i) => valueAt(s, i)))
        .whereType<double>()
        .fold<double>(0, math.max);
    if (maxValue <= 0) return;
    final paint = Paint()
      ..strokeWidth = 1
      ..color = grid;
    for (var i = 0; i < 5; i++) {
      final y = area.top + area.height * i / 4;
      for (var x = area.left; x < area.right; x += 6) {
        canvas.drawLine(
            Offset(x, y), Offset(math.min(x + 3, area.right), y), paint);
      }
    }
    final length = plot.times.length;
    double xAt(int i) => bars
        ? area.left + area.width * (i + .5) / length
        : area.left + area.width * i / math.max(1, length - 1);
    for (var s = 0; s < plot.series.length; s++) {
      final series = plot.series[s], color = colors[s % colors.length];
      final path = Path(), points = <Offset>[];
      void flush() {
        if (points.isNotEmpty) _monotone(path, points);
        points.clear();
      }

      for (var i = 0; i < length; i++) {
        final value = valueAt(series, i);
        if (value == null) {
          flush();
          continue;
        }
        final x = xAt(i), y = area.bottom - value / maxValue * area.height;
        if (!bars) {
          points.add(Offset(x, y));
        } else {
          final group = area.width / length * .8;
          final width = math
              .min(24.0,
                  (group - 4 * (plot.series.length - 1)) / plot.series.length)
              .clamp(1.0, 24.0);
          final left = x -
              (width * plot.series.length + 4 * (plot.series.length - 1)) / 2 +
              s * (width + 4);
          var bottom = area.bottom;
          final stacked = series.breakdown.isNotEmpty &&
              series.breakdown.values.any((v) => v.any((n) => (n ?? 0) > 0));
          if (stacked && series.breakdown.values.every((v) => v[i] != null)) {
            var partIndex = 0;
            for (final part in series.breakdown.values) {
              final height = part[i]! / maxValue * area.height;
              final partColor = partIndex == 0
                  ? Color.lerp(color, Colors.black, .12)!
                  : partIndex == 2
                      ? Color.lerp(color, Colors.white, .42)!
                      : color;
              canvas.drawRect(
                  Rect.fromLTWH(left, bottom - height, width, height),
                  Paint()..color = partColor);
              bottom -= height;
              partIndex++;
            }
          } else {
            canvas.drawRRect(
                RRect.fromRectAndRadius(
                    Rect.fromLTRB(left, y, left + width, area.bottom),
                    const Radius.circular(4)),
                Paint()..color = color);
          }
        }
      }
      if (!bars) {
        flush();
        canvas.drawPath(
            path,
            Paint()
              ..color = color
              ..strokeWidth = 2
              ..style = PaintingStyle.stroke);
      }
      if (selected case final int i when series.values[i] != null) {
        canvas.drawCircle(
            Offset(xAt(i),
                area.bottom - series.values[i]! / maxValue * area.height),
            4,
            Paint()..color = color);
      }
    }
    final maxLabels = math.max(2, (area.width / scaler.scale(55)).floor());
    final step = math.max(
        length <= 14
            ? 1
            : length > 45
                ? 7
                : 5,
        (length / maxLabels).ceil());
    for (var i = 0; i < length; i++) {
      if (i != 0 && i != length - 1 && i % step != 0) continue;
      if (i != length - 1 && i > length - 1 - step && i != 0) continue;
      final tp = TextPainter(
          text: TextSpan(
              text: labels[i],
              style:
                  TextStyle(fontSize: 12, color: text, fontFamily: fontFamily)),
          textDirection: TextDirection.ltr,
          textScaler: scaler)
        ..layout();
      tp.paint(
          canvas,
          Offset(
              (xAt(i) - tp.width / 2)
                  .clamp(0, math.max(0, size.width - tp.width)),
              area.bottom + 8));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(covariant _PlotPainter oldDelegate) => true;
}

// Monotone cubic interpolation preserves peaks instead of overshooting the
// reported usage. Missing samples are split into separate paths by the caller.
void _monotone(Path path, List<Offset> points) {
  path.moveTo(points.first.dx, points.first.dy);
  if (points.length < 2) return;
  final secants = [
    for (var i = 0; i < points.length - 1; i++)
      (points[i + 1].dy - points[i].dy) / (points[i + 1].dx - points[i].dx)
  ];
  final tangents = List<double>.filled(points.length, 0);
  for (var i = 1; i < points.length - 1; i++) {
    final h0 = points[i].dx - points[i - 1].dx,
        h1 = points[i + 1].dx - points[i].dx;
    final a = secants[i - 1], b = secants[i];
    final slope = (a * h1 + b * h0) / (h0 + h1);
    tangents[i] = (a.sign + b.sign) *
        math.min(math.min(a.abs(), b.abs()), .5 * slope.abs());
  }
  tangents[0] =
      points.length == 2 ? secants[0] : (3 * secants[0] - tangents[1]) / 2;
  tangents.last = points.length == 2
      ? secants.last
      : (3 * secants.last - tangents[points.length - 2]) / 2;
  for (var i = 1; i < points.length; i++) {
    final a = points[i - 1], b = points[i], dx = (b.dx - a.dx) / 3;
    path.cubicTo(a.dx + dx, a.dy + dx * tangents[i - 1], b.dx - dx,
        b.dy - dx * tangents[i], b.dx, b.dy);
  }
}

class UsagePie extends StatelessWidget {
  const UsagePie({super.key, required this.snapshot});
  final AppUsageSnapshot snapshot;
  @override
  Widget build(BuildContext context) {
    final models = snapshot.pie;
    final total = models.fold<double>(0, (n, m) => n + m.tokens!);
    if (total <= 0) return const UsageEmpty();
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final percent =
        NumberFormat.percentPattern(Localizations.localeOf(context).toString())
          ..maximumFractionDigits = 1;
    final chart = SizedBox(
        width: 272,
        height: 256,
        child: Stack(alignment: Alignment.center, children: [
          CustomPaint(
              size: const Size.square(256),
              painter: _PiePainter(
                  models.map((m) => m.tokens! / total).toList(),
                  ink.usageCharts,
                  ink.surface)),
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 70),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(usageFormat(context, total),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                    maxLines: 1),
                const Text('Tokens', style: TextStyle(fontSize: 12))
              ])),
        ]));
    final legend = Column(children: [
      for (var i = 0; i < models.length; i++)
        Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
                border: i == models.length - 1
                    ? null
                    : Border(bottom: BorderSide(color: ink.border))),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.only(top: 3),
                  color: ink.usageCharts[i % ink.usageCharts.length]),
              const SizedBox(width: 8),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(usageLabel(context, models[i].name),
                        style: const TextStyle(
                            fontFamily: 'monospace', fontSize: 12)),
                    Text('${usageFormat(context, models[i].tokens)} Tokens',
                        style: TextStyle(fontSize: 12, color: ink.subtlest))
                  ])),
              const SizedBox(width: 8),
              Text(percent.format(models[i].tokens! / total),
                  style: TextStyle(fontSize: 12, color: ink.subtlest)),
            ]))
    ]);
    return LayoutBuilder(
        builder: (context, size) => size.maxWidth >= 640
            ? Row(children: [
                Expanded(child: chart),
                const SizedBox(width: 16),
                Expanded(child: legend)
              ])
            : Column(children: [chart, legend]));
  }
}

class _PiePainter extends CustomPainter {
  _PiePainter(this.shares, this.colors, this.background);
  final List<double> shares;
  final List<Color> colors;
  final Color background;
  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width, size.height) * .355;
    final rect =
        Rect.fromCircle(center: size.center(Offset.zero), radius: radius);
    var start = 0.0;
    for (var i = 0; i < shares.length; i++) {
      final sweep = shares[i] * math.pi * 2;
      canvas.drawArc(
          rect,
          -start - sweep,
          math.max(0, sweep - (shares.length > 1 ? .035 : 0)),
          false,
          Paint()
            ..color = colors[i % colors.length]
            ..style = PaintingStyle.stroke
            ..strokeWidth = math.min(size.width, size.height) * .15);
      start += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _PiePainter oldDelegate) => true;
}
