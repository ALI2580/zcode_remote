import 'dart:async';

import 'package:flutter/material.dart';

import '../protocol/zemote_client.dart';
import '../state/client_preferences.dart';
import '../state/git_summary.dart';
import 'official_icons.dart';
import 'theme.dart';

/// Official top-bar branch indicator in read-only mobile form. The full
/// branch switcher and git mutation actions remain desktop/host capabilities.
class GitBranchChip extends StatefulWidget {
  const GitBranchChip({
    super.key,
    required this.session,
    required this.scope,
  });

  final BridgeSession session;
  final Map<String, dynamic> scope;

  @override
  State<GitBranchChip> createState() => _GitBranchChipState();
}

class _GitBranchChipState extends State<GitBranchChip> {
  late GitSummaryController _controller;

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    _controller =
        GitSummaryController(session: widget.session, scope: widget.scope);
    _controller.addListener(_changed);
    unawaited(_controller.refresh());
  }

  @override
  void didUpdateWidget(GitBranchChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextKey =
        '${widget.scope['workspaceIdentity'] ?? widget.scope['workspacePath'] ?? ''}';
    final oldKey =
        '${oldWidget.scope['workspaceIdentity'] ?? oldWidget.scope['workspacePath'] ?? ''}';
    if (identical(widget.session, oldWidget.session) && nextKey == oldKey) {
      return;
    }
    _controller.dispose();
    _controller =
        GitSummaryController(session: widget.session, scope: widget.scope);
    _controller.addListener(_changed);
    unawaited(_controller.refresh());
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final summary = _controller.summary;
    final label = summary?.available == true
        ? (summary!.displayBranchName.isNotEmpty
            ? summary.displayBranchName
            : uiText(context, '未命名分支', 'Unnamed branch'))
        : null;
    if (label == null) return const SizedBox.shrink();
    return Tooltip(
      message: uiText(
        context,
        '分支：$label\n脏文件：${summary!.isDirty ? '是' : '否'}\n领先/落后：${summary.ahead}/${summary.behind}',
        'Branch: $label\nDirty files: ${summary.isDirty ? 'yes' : 'no'}\nAhead/behind: ${summary.ahead}/${summary.behind}',
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: ink.hover,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          LucideIcon('git-branch', size: 14, color: ink.subtlest),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: ink.text),
            ),
          ),
          if (summary.isDirty) ...[
            const SizedBox(width: 4),
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: ink.text, shape: BoxShape.circle),
            ),
          ],
        ]),
      ),
    );
  }
}
