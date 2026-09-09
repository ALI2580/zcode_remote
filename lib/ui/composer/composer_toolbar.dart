import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../protocol/conversation.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_config.dart';
import '../../state/composer_controller.dart';
import '../official_icons.dart';
import '../theme.dart';
import 'composer_popover.dart';
import 'context_usage.dart';
import 'composer_actions.dart';

class ComposerToolbar extends StatelessWidget {
  const ComposerToolbar(
      {super.key,
      required this.controller,
      required this.onSend,
      this.containerWidth,
      this.onTrigger,
      this.onAddAttachment});
  final ComposerController controller;
  final VoidCallback onSend;

  /// Official @container/composer is outside the padded input surface.
  final double? containerWidth;
  final ValueChanged<String>? onTrigger;
  final VoidCallback? onAddAttachment;

  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, constraints) {
        final config = controller.config;
        final options = controller.options;
        final model = options.model(config);
        final provider =
            model?.modelProviderName ?? config['provider'] as String? ?? '';
        final modelName = model?.name ??
            config['model'] as String? ??
            uiText(context, '模型', 'Model');
        final mode =
            options.modes.where((o) => o.value == config['mode']).firstOrNull;
        final thought = config['thought'] as String? ?? '';
        final levels = sortedThoughtLevels(options.levels(config));
        final width = constraints.maxWidth;
        final queryWidth = containerWidth ?? width;
        final usage = ContextUsageInfo.parse(controller.state?.usage);
        final labelModel = queryWidth >= 384;
        final labelMode = queryWidth >= 576;
        final labelThought = queryWidth >= 576;
        final prefix = queryWidth >= 672 &&
                provider.isNotEmpty &&
                !firstPartyProvider(config['provider'] as String? ?? '')
            ? '$provider/'
            : '';
        final modeIcon = switch (config['mode']) {
          'yolo' || 'fullAccess' || 'bypassPermissions' => 'shield-alert',
          'plan' => 'notepad-text',
          'edit' => 'shield-check',
          _ => 'hand',
        };
        return Row(
            key: ValueKey(
                'composer-width-${queryWidth < 384 ? 'compact' : queryWidth < 576 ? 'medium' : queryWidth < 672 ? 'wide' : 'full'}'),
            children: [
              ComposerActions(
                  controller: controller,
                  onTrigger: onTrigger ?? controller.references.insertTrigger,
                  onAddAttachment: onAddAttachment),
              const SizedBox(width: 4),
              if (options.modes.isNotEmpty || config['mode'] != null)
                ConstrainedBox(
                    constraints:
                        BoxConstraints(maxWidth: math.min(136, width * .3)),
                    child: Builder(
                        builder: (anchor) => _Chip(
                              id: 'mode',
                              icon: modeIcon,
                              label: labelMode
                                  ? modeLabel(context,
                                      '${config['mode'] ?? ''}', mode?.name)
                                  : null,
                              color: modeIcon == 'shield-alert'
                                  ? ZInk.of(Theme.of(context).colorScheme)
                                      .warning
                                  : null,
                              tooltip:
                                  uiText(context, '协作模式', 'Collaboration mode'),
                              onTap: controller.canConfigureMode
                                  ? () => _choose(
                                      anchor,
                                      options.modes,
                                      config['mode'] as String?,
                                      controller.selectMode,
                                      modes: true)
                                  : null,
                            ))),
              const SizedBox(width: 8),
              Expanded(
                  child:
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                if (usage != null || controller.usage.eligible) ...[
                  ContextUsageButton(info: usage, controller: controller),
                  const SizedBox(width: 4),
                ],
                Flexible(
                    child: Builder(
                        builder: (anchor) => _Chip(
                              id: 'model',
                              icon: labelModel ? null : 'package',
                              label: labelModel ? '$prefix$modelName' : null,
                              tooltip:
                                  '${uiText(context, '选择模型', 'Select model')}: $provider/$modelName',
                              pending: controller.configuring,
                              onTap: controller.canConfigureModel &&
                                      options.models.isNotEmpty
                                  ? () => _choose(anchor, options.models,
                                      model?.value, controller.selectModel,
                                      providers: true)
                                  : null,
                            ))),
                if (levels.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: math.min(148, width * .27)),
                      child: Builder(
                          builder: (anchor) => _Chip(
                                id: 'thought',
                                icon: 'brain',
                                label: labelThought
                                    ? thoughtLabel(context, thought)
                                    : null,
                                tooltip:
                                    '${uiText(context, '思考等级', 'Thought level')}: ${thoughtLabel(context, thought)}',
                                meter: queryWidth >= 384 && queryWidth < 576
                                    ? thoughtFraction(levels, thought)
                                    : null,
                                onTap: controller.canConfigureModel &&
                                        levels.length > 1
                                    ? () => _choose(
                                        anchor,
                                        [
                                          for (final value in levels)
                                            ConfigOptionValue.fromRaw({
                                              'value': value,
                                              'name':
                                                  thoughtLabel(context, value)
                                            })
                                        ],
                                        thought,
                                        controller.selectThought)
                                    : null,
                              ))),
                ],
                const SizedBox(width: 6),
                _Submit(controller: controller, onSend: onSend),
              ])),
            ]);
      });

  Future<void> _choose(BuildContext context, List<ConfigOptionValue> values,
      String? selected, Future<bool> Function(String) select,
      {bool providers = false, bool modes = false}) async {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final entries = <Widget>[];
    String? previous;
    for (final value in values) {
      final provider = value.modelProviderName ??
          value.modelProviderId ??
          modelReference(value.value).provider;
      if (providers && provider != previous) {
        entries.add(Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
            child: Text(provider,
                style: TextStyle(color: ink.subtlest, fontSize: 12))));
        previous = provider;
      }
      final name =
          modes ? modeLabel(context, value.value, value.name) : value.name;
      final description =
          modes ? modeDescription(context, value) : value.description;
      entries.add(Builder(
          builder: (menuContext) => InkWell(
              onTap: () => Navigator.pop(menuContext, value.value),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                  constraints: BoxConstraints(minHeight: modes ? 52 : 32),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Row(children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Text(name,
                              style: TextStyle(color: ink.text, fontSize: 14)),
                          if (description?.isNotEmpty == true && !providers)
                            Text(description!,
                                style: TextStyle(
                                    color: ink.subtlest, fontSize: 12)),
                        ])),
                    if (value.value == selected) ...[
                      const SizedBox(width: 8),
                      LucideIcon('check', size: 16, color: ink.subtlest)
                    ],
                  ])))));
    }
    final picked = await showComposerPopover<String>(context,
        width: providers
            ? 256
            : modes
                ? 256
                : 160,
        gap: providers ? 0 : 4,
        child: Padding(
            padding: const EdgeInsets.all(4),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: entries)));
    if (picked != null) await select(picked);
  }
}

String modeLabel(BuildContext context, String value, [String? fallback]) =>
    switch (value) {
      'build' => uiText(context, '变更前确认', 'Ask before changes'),
      'edit' => uiText(context, '自动编辑', 'Edit automatically'),
      'plan' => uiText(context, '计划模式', 'Plan mode'),
      'yolo' || 'fullAccess' => uiText(context, '完全访问', 'Full access'),
      'default' => uiText(context, '默认模式', 'Default'),
      _ => fallback ?? value,
    };

String? modeDescription(BuildContext context, ConfigOptionValue option) =>
    switch (option.value) {
      'build' => uiText(context, '改文件前先问我。', 'Ask before file changes.'),
      'edit' => uiText(context, '自动编辑文件。', 'Edit files automatically.'),
      'plan' => uiText(context, '编辑前先出计划。', 'Plan before editing.'),
      'yolo' => uiText(context, '减少确认次数。', 'Run with fewer confirmations.'),
      _ => option.description,
    };

String thoughtLabel(BuildContext context, String value) =>
    switch (value.toLowerCase()) {
      'off' ||
      'disabled' ||
      'nothink' ||
      'none' =>
        uiText(context, '关闭', 'Off'),
      'enabled' => uiText(context, '开启', 'On'),
      'minimal' => uiText(context, '最低', 'Minimal'),
      'low' => uiText(context, '低', 'Low'),
      'medium' => uiText(context, '中', 'Medium'),
      'high' => uiText(context, '高', 'High'),
      'max' => uiText(context, '最高', 'Max'),
      _ => value,
    };

double thoughtFraction(List<String> levels, String current) {
  bool off(String e) => thoughtRank(e) == 0;
  final active = sortedThoughtLevels(levels).where((e) => !off(e)).toList();
  if (off(current) || active.isEmpty) return 0;
  return ((active.indexOf(current) + 1) / active.length).clamp(0, 1);
}

class _Chip extends StatelessWidget {
  const _Chip(
      {required this.id,
      this.icon,
      this.label,
      required this.tooltip,
      this.onTap,
      this.pending = false,
      this.color,
      this.meter});
  final String id;
  final String? icon;
  final String? label;
  final String tooltip;
  final VoidCallback? onTap;
  final bool pending;
  final double? meter;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Tooltip(
        message: tooltip,
        child: Semantics(
            button: true,
            label: tooltip,
            child: InkWell(
                key: ValueKey('composer-$id'),
                onTap: onTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 28, minHeight: 28),
                    padding: EdgeInsets.symmetric(
                        horizontal: label == null ? 6 : 8, vertical: 4),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      if (pending)
                        SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(
                                strokeWidth: 1.5, color: ink.text))
                      else if (icon != null)
                        LucideIcon(icon!,
                            key: ValueKey('composer-$id-icon'),
                            size: 16,
                            color: color ?? ink.text),
                      if (label != null) ...[
                        if (icon != null || pending) const SizedBox(width: 4),
                        Flexible(
                            child: Text(label!,
                                key: ValueKey('composer-$id-label'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                    fontSize: 14,
                                    height: 20 / 14,
                                    color: color ?? ink.text))),
                        const SizedBox(width: 3),
                        LucideIcon('chevron-down',
                            size: 12, color: ink.subtlest),
                      ],
                      if (meter != null) ...[
                        const SizedBox(width: 4),
                        Container(
                            key: const ValueKey('composer-thought-meter'),
                            width: 4,
                            height: 16,
                            decoration: BoxDecoration(
                                color: ink.hover,
                                borderRadius: BorderRadius.circular(4)),
                            alignment: Alignment.bottomCenter,
                            child: AnimatedContainer(
                                duration: const Duration(milliseconds: 300),
                                width: 4,
                                height:
                                    meter == 0 ? 0 : math.max(4, 16 * meter!),
                                decoration: BoxDecoration(
                                    color: ink.diffAdded,
                                    borderRadius: BorderRadius.circular(4)))),
                      ],
                    ])))));
  }
}

class _Submit extends StatelessWidget {
  const _Submit({required this.controller, required this.onSend});
  final ComposerController controller;
  final VoidCallback onSend;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final showStop = controller.input.text.trim().isEmpty &&
        (controller.canStop ||
            controller.stopping ||
            controller.serverStopping);
    final busy =
        controller.sending || controller.stopping || controller.serverStopping;
    final enabled = showStop ? controller.canStop : controller.canSend;
    final text = showStop
        ? uiText(context, '停止', 'Stop')
        : switch (controller.routing) {
            'enqueue' => uiText(context, '加入队列', 'Queue message'),
            'guide' => uiText(context, '引导当前任务', 'Guide task'),
            _ => uiText(context, '发送', 'Send'),
          };
    return Tooltip(
        message: text,
        child: Semantics(
            label: text,
            button: true,
            enabled: enabled,
            child: Material(
                color: enabled
                    ? scheme.primary
                    : scheme.primary.withValues(alpha: .2),
                borderRadius: BorderRadius.circular(8),
                child: InkWell(
                    key: const ValueKey('composer-submit'),
                    onTap: enabled
                        ? (showStop
                            ? () {
                                controller.stop();
                              }
                            : onSend)
                        : null,
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(
                            child: busy
                                ? SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 1.5,
                                        color: scheme.onPrimary))
                                : LucideIcon(
                                    showStop ? 'circle-stop' : 'arrow-up',
                                    size: 16,
                                    color: scheme.onPrimary)))))));
  }
}
