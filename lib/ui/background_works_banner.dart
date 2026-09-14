import 'dart:async';

import 'package:flutter/material.dart';

import '../state/background_works.dart';
import '../state/client_preferences.dart';
import 'official_icons.dart';
import 'theme.dart';

/// Mobile projection of the official summary panel's running background work.
/// Official copy is `chat.summaryPanel.runningBackgroundTasks` and
/// `chat.summaryPanel.stopRunningBackgroundTask`.
class BackgroundWorksBanner extends StatelessWidget {
  const BackgroundWorksBanner({super.key, required this.controller});

  final BackgroundWorksController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final works = controller.running;
        if (works.isEmpty) return const SizedBox.shrink();
        final ink = ZInk.of(Theme.of(context).colorScheme);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: ink.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: ink.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  uiText(
                    context,
                    '${works.length} 个运行中的后台任务',
                    '${works.length} running background task(s)',
                  ),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: ink.text,
                  ),
                ),
                for (final work in works) _work(context, ink, work),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _work(
    BuildContext context,
    InkTokens ink,
    Map<String, dynamic> work,
  ) {
    final workId = '${work['workId'] ?? ''}';
    final busy = controller.isCancelling(workId);
    final failure = controller.failureFor(workId);
    final kind = '${work['kind'] ?? ''}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          LucideIcon(
            kind == 'subagent' ? 'bot' : 'terminal',
            size: 16,
            color: ink.subtlest,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${work['title'] ?? workId}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: ink.text),
                ),
                if (failure != null)
                  Text(
                    uiText(
                      context,
                      '取消未受理：$failure',
                      'Cancel was not accepted: $failure',
                    ),
                    style: TextStyle(fontSize: 12, color: ink.diffRemoved),
                  ),
              ],
            ),
          ),
          if (controller.isCancellable(work))
            TextButton(
              onPressed:
                  busy ? null : () => unawaited(controller.cancel(workId)),
              style: TextButton.styleFrom(
                minimumSize: const Size(0, 28),
                padding: const EdgeInsets.symmetric(horizontal: 8),
                textStyle: const TextStyle(fontSize: 12),
              ),
              child: Text(uiText(context, '停止', 'Stop')),
            ),
        ],
      ),
    );
  }
}
