import 'package:flutter/material.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_controller.dart';
import '../theme.dart';

/// Server-backed minimum queue loop: inspect, pause/resume, send now, remove.
class ComposerQueue extends StatelessWidget {
  const ComposerQueue({super.key, required this.controller});
  final ComposerController controller;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Container(
        margin: const EdgeInsets.only(bottom: 6),
        decoration: BoxDecoration(
            border: Border.all(color: ink.border),
            borderRadius: BorderRadius.circular(12)),
        child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 150),
            child: SingleChildScrollView(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Row(children: [
                const SizedBox(width: 12),
                Expanded(
                    child: Text(
                        '${uiText(context, '待发队列', 'Queue')} · ${controller.queue.length}',
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
              for (final item in controller.queue)
                Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Row(children: [
                      Expanded(
                          child: Text('${item['text'] ?? ''}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 13, color: ink.text))),
                      IconButton(
                          tooltip: uiText(context, '立即发送', 'Send now'),
                          icon: const Icon(Icons.arrow_upward, size: 16),
                          onPressed: controller.canSendQueued &&
                                  (item['dispatch'] as Map?)?['state'] ==
                                      'queued'
                              ? () => controller.queueAction('sendQueuedNow',
                                  id: '${item['queueItemId']}')
                              : null),
                      IconButton(
                          tooltip: uiText(
                              context, '移除待发消息', 'Remove queued message'),
                          icon: const Icon(Icons.close, size: 16),
                          onPressed: controller.canEditQueue &&
                                  (item['dispatch'] as Map?)?['state'] ==
                                      'queued'
                              ? () => controller.queueAction('deleteQueueItem',
                                  id: '${item['queueItemId']}')
                              : null),
                    ])),
            ]))));
  }
}
