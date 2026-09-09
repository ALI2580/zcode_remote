import 'package:flutter/material.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_controller.dart';
import '../official_icons.dart';
import '../theme.dart';
import 'composer_popover.dart';

class ComposerActions extends StatelessWidget {
  const ComposerActions(
      {super.key,
      required this.controller,
      required this.onTrigger,
      this.onAddAttachment});
  final ComposerController controller;
  final ValueChanged<String> onTrigger;
  final VoidCallback? onAddAttachment;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final enabled = controller.ready &&
        !controller.sending &&
        !controller.preparingAttachments;
    Future<void> show(BuildContext anchor) async {
      final choice = await showComposerPopover<String>(anchor,
          width: 208,
          gap: 0,
          child: Padding(
              padding: const EdgeInsets.all(4),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (final item in [
                  if (onAddAttachment != null)
                    (
                      value: 'file',
                      icon: 'paperclip',
                      label: uiText(context, '添加附件', 'Add attachment')
                    ),
                  (
                    value: '@',
                    icon: 'at-sign',
                    label: uiText(context, '使用 @ 添加上下文', 'Use @ to add context')
                  ),
                  (
                    value: '/',
                    icon: 'square-slash',
                    label: uiText(
                        context, '使用 / 选择能力', 'Use / to select a command')
                  ),
                  (
                    value: r'$',
                    icon: 'dollar-sign',
                    label: uiText(
                        context, r'使用 $ 选择技能', r'Use $ to select a skill')
                  ),
                ])
                  Builder(
                      builder: (menuContext) => InkWell(
                          key: ValueKey('composer-action-${item.value}'),
                          onTap: () => Navigator.pop(menuContext, item.value),
                          borderRadius: BorderRadius.circular(8),
                          child: Padding(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 7),
                              child: Row(children: [
                                LucideIcon(item.icon,
                                    size: 16, color: ink.text),
                                const SizedBox(width: 8),
                                Expanded(
                                    child: Text(item.label,
                                        style: TextStyle(
                                            fontSize: 14, color: ink.text)))
                              ])))),
              ])));
      if (choice == null) return;
      if (choice == 'file') {
        onAddAttachment?.call();
      } else {
        onTrigger(choice);
      }
    }

    return Builder(
        builder: (anchor) => Tooltip(
            message: uiText(context, '添加附件和上下文', 'Add attachments and context'),
            child: Semantics(
                button: true,
                label:
                    uiText(context, '添加附件和上下文', 'Add attachments and context'),
                child: InkWell(
                    key: const ValueKey('composer-actions'),
                    onTap: enabled ? () => show(anchor) : null,
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                        width: 28,
                        height: 28,
                        child: Center(
                            child: LucideIcon('plus',
                                size: 16,
                                color: enabled ? ink.text : ink.subtlest)))))));
  }
}
