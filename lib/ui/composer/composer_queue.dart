import 'package:flutter/material.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_controller.dart';
import '../theme.dart';

/// Server-backed minimum queue loop: inspect, pause/resume, send now,
/// remove, edit, reorder.
class ComposerQueue extends StatelessWidget {
  const ComposerQueue({super.key, required this.controller});
  final ComposerController controller;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final items = controller.queue;
    return Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
            border: Border.all(color: ink.border),
            borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 200),
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                        '${uiText(context, '待发队列', 'Queue')} · ${items.length}',
                        style: const TextStyle(fontSize: 12))),
                TextButton(
                    onPressed: controller.canEditQueue
                        ? () => controller.queueAction('setAutoDrain',
                            autoDrain: !(controller.state?.autoDrain ?? true))
                        : null,
                    child: Text(controller.state?.autoDrain == true
                        ? uiText(context, '暂停', 'Pause')
                        : uiText(context, '继续', 'Resume'))),
              ]),
              for (final item in items) _buildItem(context, item, items),
            ]))));
  }

  Widget _buildItem(BuildContext context, Map<String, dynamic> item,
      List<Map<String, dynamic>> items) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final id = '${item['queueItemId']}';
    final isQueued = (item['dispatch'] as Map?)?['state'] == 'queued';
    final idx = items.indexOf(item);
    return Padding(
        padding: const EdgeInsets.only(left: 12),
        child: Row(children: [
          Expanded(
              child: Text('${item['text'] ?? ''}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: ink.text))),
          if (controller.canEditQueue && isQueued)
            IconButton(
                tooltip: uiText(context, '编辑', 'Edit'),
                icon: const Icon(Icons.edit_outlined, size: 14),
                onPressed: () => controller.editQueuedItem(id)),
          if (controller.canSendQueued && isQueued)
            IconButton(
                tooltip: uiText(context, '立即发送', 'Send now'),
                icon: const Icon(Icons.arrow_upward, size: 16),
                onPressed: () =>
                    controller.queueAction('sendQueuedNow', id: id)),
          if (controller.canEditQueue && isQueued && idx > 0)
            IconButton(
                tooltip: uiText(context, '上移', 'Move up'),
                icon: const Icon(Icons.arrow_back, size: 14),
                onPressed: () => controller.queueAction('reorderQueueItem',
                    id: id, beforeId: '${items[idx - 1]['queueItemId']}')),
          if (controller.canEditQueue && isQueued && idx < items.length - 1)
            IconButton(
                tooltip: uiText(context, '下移', 'Move down'),
                icon: const Icon(Icons.arrow_forward, size: 14),
                onPressed: () {
                  if (idx + 2 < items.length) {
                    controller.queueAction('reorderQueueItem',
                        id: id, beforeId: '${items[idx + 2]['queueItemId']}');
                  } else {
                    controller.queueAction('reorderQueueItem',
                        id: id, beforeId: null);
                  }
                }),
          if (controller.canEditQueue && isQueued)
            IconButton(
                tooltip: uiText(context, '移除待发消息', 'Remove queued message'),
                icon: const Icon(Icons.close, size: 16),
                onPressed: () =>
                    controller.queueAction('deleteQueueItem', id: id)),
        ]));
  }
}
