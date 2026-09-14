import 'dart:async';

import 'package:flutter/material.dart';

import '../../protocol/file_changes.dart';
import '../../state/client_preferences.dart';
import '../../state/file_changes_review.dart';
import '../official_icons.dart';
import '../theme.dart';
import 'turn_projection.dart';

/// 变更摘要卡（utt，§3）：`rounded-xl border bg-card`，头部 chevron +
/// 「N 个文件已更改」+ 独立新增/删除统计，展开文件行。
class ConversationChangeSummary extends StatefulWidget {
  final Map<String, dynamic> row;
  final FileChangesReviewController Function(Map<String, dynamic> row)?
      createReview;
  final void Function(String path)? onOpenReview;
  final String? reviewCacheVersion;

  const ConversationChangeSummary({
    super.key,
    required this.row,
    this.createReview,
    this.onOpenReview,
    this.reviewCacheVersion,
  });

  @override
  State<ConversationChangeSummary> createState() => _ChangeSummaryCardState();
}

class _ChangeSummaryCardState extends State<ConversationChangeSummary> {
  bool _expanded = false;
  FileChangesReviewController? _review;

  bool get _canRewind {
    final fileChanges = widget.row['fileChanges'];
    final state = fileChanges is Map ? fileChanges['state'] : null;
    final actions = widget.row['actions'];
    return widget.row['state'] != 'running' &&
        state != 'reverted' &&
        actions is Map &&
        actions['canRewindFiles'] == true;
  }

  void _loadReview() {
    final future = _review?.load();
    if (future != null) {
      unawaited(future.then(
        (_) {
          // The file rows may come from the loaded payload when the summary
          // row carries no inline files; rebuild once data arrives.
          if (mounted) setState(() {});
        },
        onError: (Object _) {/* The review body shows retry. */},
      ));
    }
  }

  String _summaryText(BuildContext context, String chinese, String english) {
    return turnFileChangeStats(widget.row) == null
        ? chinese
        : uiText(context, chinese, english);
  }

  @override
  void initState() {
    super.initState();
    _review = widget.createReview?.call(widget.row);
    if (_expanded) _loadReview();
  }

  @override
  void didUpdateWidget(ConversationChangeSummary oldWidget) {
    super.didUpdateWidget(oldWidget);
    final nextScope = widget.createReview?.call(widget.row);
    final oldKey = _review?.scope.cacheKey;
    final newKey = nextScope?.scope.cacheKey;
    if (oldKey != newKey ||
        oldWidget.reviewCacheVersion != widget.reviewCacheVersion) {
      _review?.dispose();
      _review = nextScope;
      if (_expanded) _loadReview();
    } else {
      nextScope?.dispose();
    }
  }

  @override
  void dispose() {
    _review?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    var files = switch (widget.row['files']) {
      final List l =>
        l.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(),
      _ => const <Map<String, dynamic>>[],
    };
    final reviewResult = _review?.result;
    if (files.isEmpty &&
        reviewResult != null &&
        reviewResult.items.isNotEmpty) {
      // Some turns carry only aggregate stats in the summary row; the file
      // rows come from the loaded review payload instead (U21 on-device
      // follow-up: expanding must never render an empty list).
      files = [
        for (final item in reviewResult.items)
          {
            'path': item.path,
            'addedLines': item.additions,
            'removedLines': item.deletions,
          },
      ];
    }
    final officialStats = turnFileChangeStats(widget.row);
    final count = (widget.row['count'] as num?)?.toInt() ?? files.length;
    final count2 = (widget.row['fileChanges'] as Map?)?['fileCount'] as num?;
    final displayCount = officialStats?.files ?? (count2 ?? count);
    var added = officialStats?.additions ?? 0;
    var removed = officialStats?.deletions ?? 0;
    if (officialStats == null) {
      for (final f in files) {
        added += (f['addedLines'] as num?)?.toInt() ?? 0;
        removed += (f['removedLines'] as num?)?.toInt() ?? 0;
      }
    }
    return Container(
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(ZRadius.xl),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              final next = !_expanded;
              setState(() => _expanded = next);
              if (next) _loadReview();
            },
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: LucideIcon('chevron-right',
                        size: 12, color: ink.subtlest),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            _summaryText(context, '$displayCount 个文件已更改',
                                '$displayCount files changed'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink.text,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '+$added',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: ink.diffAdded,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '-$removed',
                          style: TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontFeatures: const [FontFeature.tabularFigures()],
                            color: ink.diffRemoved,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_canRewind) ...[
                    const SizedBox(width: 8),
                    TextButton(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        minimumSize: const Size(0, 32),
                      ),
                      onPressed: _review?.rewindOpen != true
                          ? () => _showRewindDialog(context)
                          : null,
                      child: Text(_summaryText(context, '撤销', 'Undo')),
                    ),
                  ],
                ],
              ),
            ),
          ),
          if (_expanded) _buildReviewBody(ink),
          if (_expanded)
            for (final f in files)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: InkWell(
                  // U21: the whole row opens the file's diff in the review
                  // panel — same destination as the Review button.
                  onTap: widget.onOpenReview == null
                      ? null
                      : () =>
                          widget.onOpenReview!(f['path'] as String? ?? ''),
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      const SizedBox(width: 12),
                      LucideIcon(_fileIconFor(f['path'] as String? ?? ''),
                          size: 14, color: ink.subtlest),
                      const SizedBox(width: 6),
                      Flexible(
                          flex: 3,
                          child: Text(_fileBasename(f['path'] as String? ?? ''),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                color: ink.text,
                              ))),
                    if (_fileDirectory(f['path'] as String? ?? '')
                        .isNotEmpty) ...[
                      const SizedBox(width: 4),
                      Flexible(
                          flex: 2,
                          child:
                              Text(_fileDirectory(f['path'] as String? ?? ''),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: ink.subtlest,
                                  ))),
                    ],
                    const SizedBox(width: 8),
                    Text(
                      '+${f['addedLines'] ?? 0} -${f['removedLines'] ?? 0}',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: ink.text.withValues(alpha: 0.5),
                      ),
                    ),
                    if (widget.onOpenReview != null)
                      TextButton(
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          minimumSize: const Size(0, 28),
                        ),
                        onPressed: () =>
                            widget.onOpenReview!(f['path'] as String? ?? ''),
                        child: Text(uiText(context, '审查', 'Review')),
                      ),
                    const SizedBox(width: 8),
                  ],
                ),
              ),
              ),
        ],
      ),
    );
  }

  /// Official file rows separate a type icon, file name and directory.
  String _fileBasename(String path) {
    if (path.isEmpty) return '';
    final slash = path.lastIndexOf('/');
    final back = path.lastIndexOf('\\');
    final cut = slash > back ? slash : back;
    return cut >= 0 ? path.substring(cut + 1) : path;
  }

  String _fileDirectory(String path) {
    final slash = path.lastIndexOf('/');
    final back = path.lastIndexOf('\\');
    final cut = slash > back ? slash : back;
    return cut >= 0 ? path.substring(0, cut + 1) : '';
  }

  String _fileIconFor(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.md') || lower.endsWith('.markdown')) {
      return 'file-text';
    }
    if (lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp')) {
      return 'file-image';
    }
    const codeExtensions = [
      '.dart',
      '.js',
      '.ts',
      '.json',
      '.yaml',
      '.yml',
      '.py',
      '.kt',
      '.java',
      '.c',
      '.cc',
      '.cpp',
      '.h',
      '.hpp',
      '.sh',
      '.html',
      '.css',
      '.rs',
      '.go',
    ];
    for (final extension in codeExtensions) {
      if (lower.endsWith(extension)) return 'file-code';
    }
    return 'file';
  }

  /// Expanded summaries list the changed files and surface load failures;
  /// the red/green diff itself opens in the right-hand review panel when a
  /// file row is activated (official flow: summary → file list → file diff).
  Widget _buildReviewBody(InkTokens ink) {
    final review = _review;
    if (review == null) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: review,
      builder: (context, _) {
        final result = review.result;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (review.status == FileChangesStatus.loading && result == null)
              const Padding(
                padding: EdgeInsets.all(12),
                child: Center(
                    child: SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )),
              )
            else if (review.status == FileChangesStatus.error && result == null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(children: [
                  Text(
                    '暂时无法读取文件变更。',
                    style: TextStyle(
                        color: ink.text.withValues(alpha: 0.65), fontSize: 13),
                  ),
                  TextButton(onPressed: review.retry, child: const Text('重试')),
                ]),
              ),
          ],
        );
      },
    );
  }

  Future<void> _showRewindDialog(BuildContext context) async {
    final review = _review;
    if (review == null) return;
    review.openRewind();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedBuilder(
        animation: review,
        builder: (context, _) {
          final preview = review.rewindPreview;
          final failure = review.rewindResult?.status == 'rejected' ||
                  review.rewindResult?.status == 'failed' ||
                  review.rewindResult?.status == 'stale'
              ? (review.rewindResult?.message ?? '文件撤销请求失败，请稍后再试。')
              : review.rewindApplyError != null
                  ? '文件撤销请求失败，请稍后再试。'
                  : null;
          return AlertDialog(
            title: const Text('撤销文件改动'),
            content: SizedBox(
              width: 460,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('撤销前会重新检查当前文件内容；如果文件已被其他进程修改，本次不会写入任何文件。'),
                    const SizedBox(height: 12),
                    if (review.rewindLoading)
                      const Padding(
                        padding: EdgeInsets.all(12),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (review.rewindError != null)
                      Text('文件撤销请求失败，请稍后再试。')
                    else if (preview == null)
                      const Text('暂时没有预检结果。')
                    else ...[
                      _RewindFileSection(
                        title: preview.safeFiles.isEmpty
                            ? null
                            : '可安全撤销 ${preview.safeFiles.length}',
                        files: preview.safeFiles,
                      ),
                      _RewindFileSection(
                        title: preview.unsafeFiles.isEmpty
                            ? null
                            : '不能安全撤销 ${preview.unsafeFiles.length}',
                        files: preview.unsafeFiles,
                      ),
                      _RewindFileSection(
                        title: preview.ignoredFiles.isEmpty
                            ? null
                            : '已忽略 ${preview.ignoredFiles.length}',
                        files: preview.ignoredFiles,
                      ),
                      if (!preview.canApply)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('存在不能安全撤销的文件，未写入任何文件。'),
                        ),
                    ],
                    if (failure != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(failure),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    review.rewindApplying ? null : () => Navigator.pop(context),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: review.rewindApplying ||
                        preview == null ||
                        !preview.canApply
                    ? null
                    : () async {
                        final result = await review.applyRewind();
                        if ((result.status == 'accepted' ||
                                result.status == 'duplicate') &&
                            context.mounted) {
                          Navigator.pop(context);
                        }
                      },
                child: const Text('撤销文件'),
              ),
            ],
          );
        },
      ),
    );
    review.closeRewind();
  }
}

class _RewindFileSection extends StatelessWidget {
  final String? title;
  final List<FileRewindPreviewFile> files;

  const _RewindFileSection({required this.title, required this.files});

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    if (title == null || files.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title!, style: const TextStyle(fontWeight: FontWeight.w600)),
          for (final file in files)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
              decoration: BoxDecoration(
                border: Border.all(color: ink.border),
                borderRadius: BorderRadius.circular(ZRadius.sm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      file.path,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: ink.text.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                  Text(
                    '${file.operationCount} 次修改',
                    style: TextStyle(
                      fontSize: 11,
                      color: ink.subtlest,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}


