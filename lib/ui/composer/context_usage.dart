import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:intl/intl.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_controller.dart';
import '../theme.dart';
import '../css_color.dart';
import '../usage/usage_page.dart';
import 'composer_popover.dart';
import 'quota_section.dart';

const _sources = [
  'messages',
  'system_prompt',
  'meta_user_context',
  'skills',
  'tool_prompt',
  'system_tool_schemas',
  'mcp_tool_schemas'
];

class ContextUsageInfo {
  const ContextUsageInfo(
      this.used, this.total, this.breakdown, this.cacheHitRate);
  final num used, total;
  final Map<String, double> breakdown;
  final double? cacheHitRate;
  double get ratio => (used / total).clamp(0.0, 1.0);

  static ContextUsageInfo? parse(Map<String, dynamic>? usage) {
    final raw = usage?['contextWindow'];
    if (raw is! Map) return null;
    final used = raw['usedTokens'], total = raw['maxTokens'];
    if (used is! num ||
        !used.isFinite ||
        used <= 0 ||
        total is! num ||
        !total.isFinite ||
        total <= 0) {
      return null;
    }
    final sources = <String, double>{};
    if (raw['breakdown'] case final List entries) {
      for (final entry in entries.whereType<Map>()) {
        final source = entry['source'], chars = entry['chars'];
        if (source is String &&
            source.isNotEmpty &&
            chars is num &&
            chars.isFinite &&
            chars > 0) {
          sources.update(source, (n) => n + chars,
              ifAbsent: () => chars.toDouble());
        }
      }
    }
    int rank(String source) =>
        _sources.contains(source) ? _sources.indexOf(source) : _sources.length;
    final entries = sources.entries.toList()
      ..sort((a, b) {
        final size = b.value.compareTo(a.value);
        if (size != 0) return size;
        final order = rank(a.key).compareTo(rank(b.key));
        return order != 0 ? order : a.key.compareTo(b.key);
      });
    final cache = raw['cache'];
    final rate = cache is Map ? cache['hitRate'] : null;
    return ContextUsageInfo(used, total, Map.fromEntries(entries),
        rate is num && rate.isFinite && rate >= .78 ? rate.toDouble() : null);
  }
}

class ContextUsageButton extends StatefulWidget {
  const ContextUsageButton(
      {super.key, required this.info, required this.controller});
  final ContextUsageInfo? info;
  final ComposerController controller;
  @override
  State<ContextUsageButton> createState() => _ContextUsageButtonState();
}

class _ContextUsageButtonState extends State<ContextUsageButton> {
  bool _open = false;
  Future<void> _show() async {
    if (_open) return;
    _open = true;
    try {
      widget.controller.usage
          .refresh()
          .then((_) => widget.controller.usage.refreshResetStatus());
      final more = await showComposerPopover<bool>(context,
          width: 320,
          maxHeight: 520,
          gap: 2,
          child: ListenableBuilder(
              listenable: widget.controller,
              builder: (context, _) {
                final info =
                    ContextUsageInfo.parse(widget.controller.state?.usage);
                return Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      if (info != null)
                        ContextUsageDetails(
                            info: info, padding: EdgeInsets.zero),
                      if (info != null && widget.controller.usage.eligible)
                        const SizedBox(height: 12),
                      QuotaSection(
                          usage: widget.controller.usage,
                          onMore: () => Navigator.of(context).pop(true),
                          separated: info != null,
                          padding: EdgeInsets.zero),
                    ]));
              }));
      if (more == true && mounted) {
        await Navigator.of(context).push(MaterialPageRoute<void>(
            builder: (_) => UsagePage(usage: widget.controller.usage)));
      }
    } finally {
      _open = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final label = widget.info == null
        ? uiText(context, '剩余额度', 'Remaining quota')
        : '${uiText(context, '上下文容量', 'Context window')} ${contextPercent(context, widget.info!.ratio)}';
    return Tooltip(
        message: label,
        child: Semantics(
            button: true,
            label: label,
            onTap: _show,
            child: Listener(
                onPointerDown: (event) {
                  if (event.kind == PointerDeviceKind.touch) _show();
                },
                child: InkWell(
                    key: const ValueKey('composer-context-usage'),
                    onTap: _show,
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(
                            child: CustomPaint(
                                size: const Size.square(14),
                                painter: _UsageRing(
                                    widget.info?.ratio ?? 0,
                                    ZInk.of(Theme.of(context).colorScheme)
                                        .subtlest))))))));
  }
}

class _UsageRing extends CustomPainter {
  const _UsageRing(this.ratio, this.color);
  final double ratio;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 4 / 24
      ..strokeCap = StrokeCap.round;
    final center = size.center(Offset.zero);
    final radius = size.width * 10 / 24;
    canvas.drawCircle(
        center, radius, paint..color = color.withValues(alpha: color.a * .25));
    if (ratio > 0) {
      canvas.drawArc(
          Rect.fromCircle(center: center, radius: radius),
          -math.pi / 2,
          math.pi * 2 * ratio,
          false,
          paint..color = color.withValues(alpha: color.a * .7));
    }
  }

  @override
  bool shouldRepaint(_UsageRing old) =>
      old.ratio != ratio || old.color != color;
}

String contextPercent(BuildContext context, num ratio) =>
    (NumberFormat.percentPattern(Localizations.localeOf(context).toString())
          ..maximumFractionDigits = 1
          ..minimumFractionDigits = 0)
        .format(ratio);

class ContextUsageDetails extends StatelessWidget {
  const ContextUsageDetails(
      {super.key, required this.info, this.padding = const EdgeInsets.all(12)});
  final ContextUsageInfo info;
  final EdgeInsetsGeometry padding;
  String _number(BuildContext context, num n, {int digits = 1}) {
    final locale = Localizations.localeOf(context).toString();
    final format = n.abs() >= 1000
        ? NumberFormat.compact(locale: locale)
        : NumberFormat.decimalPattern(locale);
    return (format
          ..maximumFractionDigits = digits
          ..minimumFractionDigits = 0)
        .format(n);
  }

  String _label(BuildContext context, String source) => switch (source) {
        'messages' => uiText(context, '消息', 'Messages'),
        'system_prompt' => uiText(context, '系统提示词', 'System prompt'),
        'tool_prompt' => uiText(context, '工具提示词', 'Tool prompt'),
        'system_tool_schemas' => uiText(context, '系统工具', 'System tools'),
        'mcp_tool_schemas' => uiText(context, 'MCP 工具', 'MCP tools'),
        'skills' => uiText(context, '技能', 'Skills'),
        'meta_user_context' => uiText(context, '其他', 'Other'),
        _ => source,
      };
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final entries = info.breakdown.entries.toList();
    final totalChars = entries.fold(0.0, (n, e) => n + e.value);
    Color color(int i) => mixOklab(ink.surfaceFill, ink.usageChart,
        const [1.0, .78, .58, .42, .28][math.min(i, 4)]);
    return Padding(
        padding: padding,
        child: DefaultTextStyle.merge(
            style: TextStyle(fontSize: 12, color: ink.subtlest),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                      alignment: WrapAlignment.spaceBetween,
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        Text(uiText(context, '上下文容量', 'Context window'),
                            style: TextStyle(
                                color: ink.text,
                                fontSize: 14,
                                fontWeight: FontWeight.w500)),
                        Text(
                            '${_number(context, info.used)}/${_number(context, info.total, digits: 0)} (${contextPercent(context, info.ratio)})',
                            style: const TextStyle(fontFamily: 'monospace')),
                      ]),
                  const SizedBox(height: 12),
                  Semantics(
                    label: uiText(context, '上下文容量', 'Context window'),
                    value: contextPercent(context, info.ratio),
                    child: LayoutBuilder(
                        builder: (context, size) => ClipRRect(
                              key: const ValueKey('context-total-progress'),
                              borderRadius: BorderRadius.circular(4),
                              child: Container(
                                height: 8,
                                alignment: Alignment.centerLeft,
                                color: ink.surfaceFill,
                                child: SizedBox(
                                  key: const ValueKey('context-used-progress'),
                                  width:
                                      math.max(8, size.maxWidth * info.ratio),
                                  height: 8,
                                  child: entries.isEmpty
                                      ? ColoredBox(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary)
                                      : Row(children: [
                                          for (var i = 0;
                                              i < entries.length;
                                              i++)
                                            Expanded(
                                                flex: math.max(
                                                    1,
                                                    (entries[i].value /
                                                            totalChars *
                                                            1000000)
                                                        .round()),
                                                child: ColoredBox(
                                                    color: color(i),
                                                    child: const SizedBox
                                                        .expand()))
                                        ]),
                                ),
                              ),
                            )),
                  ),
                  if (entries.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    for (var i = 0; i < entries.length; i++)
                      Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(children: [
                            Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                    color: color(i),
                                    borderRadius: BorderRadius.circular(2))),
                            const SizedBox(width: 8),
                            Expanded(
                                child: Text(_label(context, entries[i].key))),
                            Text(
                                contextPercent(
                                    context, entries[i].value / totalChars),
                                style:
                                    const TextStyle(fontFamily: 'monospace')),
                          ])),
                  ],
                  if (info.cacheHitRate case final double rate) ...[
                    const SizedBox(height: 12),
                    if (entries.isNotEmpty) ...[
                      Divider(color: ink.border, height: 1),
                      const SizedBox(height: 12),
                    ],
                    Row(children: [
                      Expanded(
                          child: Text(uiText(
                              context, '平均缓存命中率', 'Average cache hit rate'))),
                      Text(contextPercent(context, rate),
                          style: const TextStyle(fontFamily: 'monospace'))
                    ]),
                  ],
                ])));
  }
}
