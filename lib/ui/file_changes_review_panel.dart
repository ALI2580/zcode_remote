import 'package:flutter/material.dart';

import '../protocol/file_changes.dart';
import '../state/client_preferences.dart';
import '../state/file_changes_review.dart';
import 'code_renderer.dart';
import 'official_icons.dart';
import 'theme.dart';

/// Lets deep conversation rows (change summary cards) ask the workspace shell
/// to open the official-style diff review panel for one file.
class FileChangesReviewHost extends InheritedWidget {
  final void Function(Map<String, dynamic> row, String path) openReview;

  const FileChangesReviewHost({
    super.key,
    required this.openReview,
    required super.child,
  });

  static FileChangesReviewHost? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<FileChangesReviewHost>();

  @override
  bool updateShouldNotify(FileChangesReviewHost oldWidget) =>
      openReview != oldWidget.openReview;
}

/// Official remote diff review: a side panel with a file tab bar, a
/// breadcrumb line and the selected file's unified hunks.
class FileChangesReviewPanel extends StatefulWidget {
  final FileChangesReviewController controller;
  final String initialPath;
  final VoidCallback? onLastTabClosed;

  const FileChangesReviewPanel({
    super.key,
    required this.controller,
    required this.initialPath,
    this.onLastTabClosed,
  });

  @override
  State<FileChangesReviewPanel> createState() => _FileChangesReviewPanelState();
}

class _FileChangesReviewPanelState extends State<FileChangesReviewPanel> {
  late final List<String> _openPaths;
  late String _active;

  @override
  void initState() {
    super.initState();
    _openPaths = [widget.initialPath];
    _active = widget.initialPath;
    _select(_active);
  }

  void _select(String path) {
    _active = path;
    widget.controller.select(path);
    _ensureLoaded();
  }

  @override
  void didUpdateWidget(FileChangesReviewPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.initialPath;
    if (next.isNotEmpty && next != oldWidget.initialPath && next != _active) {
      if (!_openPaths.contains(next)) _openPaths.add(next);
      _select(next);
    }
  }

  void _ensureLoaded() {
    if (widget.controller.status == FileChangesStatus.idle) {
      unawaitedSafe(widget.controller.load());
    }
  }

  void _closeTab(String path) {
    _openPaths.remove(path);
    if (_openPaths.isEmpty) {
      widget.onLastTabClosed?.call();
      return;
    }
    if (_active == path) _select(_openPaths.last);
  }

  Future<void> unawaitedSafe(Future<void> future) async {
    try {
      await future;
    } catch (_) {
      // The panel body renders the error and a retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return AnimatedBuilder(
        animation: widget.controller,
        builder: (context, _) {
          final result = widget.controller.result;
          FileChangeItem? item;
          for (final candidate in result?.items ?? const <FileChangeItem>[]) {
            if (candidate.path == _active) item = candidate;
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(color: ink.border))),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  reverse: true,
                  child: Row(children: [
                    for (final path in _openPaths)
                      _ReviewTab(
                        label: _basename(path),
                        selected: _active == path,
                        onTap: () => setState(() => _select(path)),
                        onClose: () => setState(() => _closeTab(path)),
                      ),
                  ]),
                ),
              ),
              Expanded(child: _body(context, ink, result, item)),
            ],
          );
        });
  }

  Widget _body(BuildContext context, InkTokens ink, FileChangesResult? result,
      FileChangeItem? item) {
    final controller = widget.controller;
    if (controller.status == FileChangesStatus.loading && result == null) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    }
    if (controller.status == FileChangesStatus.error && result == null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(uiText(context, '无法加载文件差异', 'Could not load the file diff'),
              style: TextStyle(fontSize: 13, color: ink.text)),
          const SizedBox(height: 8),
          TextButton(
              onPressed: () => unawaitedSafe(controller.load(refresh: true)),
              child: Text(uiText(context, '重试', 'Retry'))),
        ]),
      );
    }
    if (item == null) {
      return Center(
          child: Text(uiText(context, '没有该文件的差异内容', 'No diff for this file'),
              style: TextStyle(fontSize: 12, color: ink.subtlest)));
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Flexible(
              child: Text(_directory(item.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: ink.subtlest))),
          Flexible(
              child: Text(_basename(item.path),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: ink.text))),
          const SizedBox(width: 8),
          Text(
              '${item.statsComplete ? '' : '~'}+${item.additions} '
              '${item.statsComplete ? '' : '~'}-${item.deletions}',
              style: TextStyle(
                  fontSize: 12, fontFamily: 'monospace', color: ink.subtlest)),
        ]),
        const SizedBox(height: 8),
        if (item.looksBinary)
          Text(
              uiText(
                  context, '二进制文件不显示文本差异。', 'Binary files show no text diff.'),
              style: TextStyle(fontSize: 12, color: ink.subtlest))
        else if (item.patches.isEmpty && item.problems.isNotEmpty)
          for (final problem in item.problems)
            Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(problem,
                    style: TextStyle(fontSize: 12, color: ink.subtlest)))
        else if (item.patches.isEmpty)
          Text(uiText(context, '没有文本差异。', 'No text diff.'),
              style: TextStyle(fontSize: 12, color: ink.subtlest))
        else
          FileChangesHunksView(hunks: item.patches),
        if (item.patches.isNotEmpty && item.problems.isNotEmpty)
          for (final problem in item.problems)
            Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(problem,
                    style: TextStyle(fontSize: 11, color: ink.subtlest))),
      ]),
    );
  }

  String _basename(String path) {
    if (path.isEmpty) return '';
    final slash = path.lastIndexOf('/');
    final back = path.lastIndexOf('\\');
    final cut = slash > back ? slash : back;
    return cut >= 0 ? path.substring(cut + 1) : path;
  }

  String _directory(String path) {
    final slash = path.lastIndexOf('/');
    final back = path.lastIndexOf('\\');
    final cut = slash > back ? slash : back;
    return cut >= 0 ? path.substring(0, cut + 1) : '';
  }
}

/// Unified diff hunks shared by the inline review body and the review panel.
class FileChangesHunksView extends StatelessWidget {
  final List<FileChangesHunk> hunks;
  final bool showHeaders;

  const FileChangesHunksView({
    super.key,
    required this.hunks,
    this.showHeaders = true,
  });

  @override
  Widget build(BuildContext context) {
    final prefs = ClientPreferencesScope.maybeOf(context);
    final codeTheme = CodeThemeCatalog.fromContext(context);
    return Container(
      decoration: BoxDecoration(color: codeTheme.background),
      child: CodeDiffViewer(
        hunks: hunks,
        theme: codeTheme,
        fontSize: prefs?.codeFontSize ?? 12,
        showLineNumbers: prefs?.showLineNumbers ?? true,
        wrapLongLines: prefs?.wrapLongLines ?? false,
        showHeaders: showHeaders,
      ),
    );
  }
}

/// The compact diff body used by an expanded edit/write/delete tool row.
/// Text ranges deliberately hide unified absolute line headers because the
/// tool only supplied the selected old/new text, not the whole file.
class ToolInlineDiffView extends StatelessWidget {
  final ToolInlineDiff diff;

  const ToolInlineDiffView({super.key, required this.diff});

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final added = diff.hunks.fold<int>(0,
        (sum, hunk) => sum + hunk.lines.where((l) => l.startsWith('+')).length);
    final removed = diff.hunks.fold<int>(0,
        (sum, hunk) => sum + hunk.lines.where((l) => l.startsWith('-')).length);
    final rangeText = diff.fromPatch
        ? uiText(context, '补丁', 'Patch')
        : uiText(context, '文本范围', 'Text range');
    final partialStats = diff.truncated || diff.partial;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
            color: ink.card,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: ink.border)),
        padding: const EdgeInsets.all(10),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            LucideIcon('file-diff', size: 14, color: ink.subtlest),
            const SizedBox(width: 6),
            Expanded(
                child: Text(diff.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: ink.text))),
            const SizedBox(width: 8),
            Text(rangeText,
                style: TextStyle(fontSize: 11, color: ink.subtlest)),
            if (partialStats) ...[
              const SizedBox(width: 6),
              Text(uiText(context, '部分统计', 'Partial stats'),
                  style: TextStyle(fontSize: 11, color: ink.subtlest)),
            ],
            const SizedBox(width: 8),
            Text('${partialStats ? '~' : ''}+$added',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: ink.diffAdded)),
            const SizedBox(width: 4),
            Text('${partialStats ? '~' : ''}-$removed',
                style: TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    color: ink.diffRemoved)),
          ]),
          const SizedBox(height: 6),
          if (diff.hunks.isEmpty)
            Text(uiText(context, '没有文本差异。', 'No text diff.'),
                style: TextStyle(fontSize: 12, color: ink.subtlest))
          else
            FileChangesHunksView(
                hunks: diff.hunks, showHeaders: diff.fromPatch),
          if (diff.truncated)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  uiText(context, '差异内容过大，已明确截断显示。',
                      'Diff is large; the displayed range is explicitly truncated.'),
                  style: TextStyle(fontSize: 11, color: ink.subtlest)),
            ),
          if (diff.partial)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                  uiText(context, '补丁结构与声明不一致，当前内容仅为部分诊断。',
                      'Patch structure does not match its declaration; this is a partial diagnostic.'),
                  style: TextStyle(fontSize: 11, color: ink.subtlest)),
            ),
          for (final hunk in diff.hunks)
            if (hunk.oldHasTrailingNewline != hunk.newHasTrailingNewline)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(
                    uiText(context, '末尾换行差异已保留。',
                        'The trailing newline difference is preserved.'),
                    style: TextStyle(fontSize: 11, color: ink.subtlest)),
              ),
        ]),
      ),
    );
  }
}

class _ReviewTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onClose;

  const _ReviewTab({
    required this.label,
    required this.selected,
    required this.onTap,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: Material(
        color: selected ? ink.hover : Colors.transparent,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side:
                BorderSide(color: selected ? ink.border : Colors.transparent)),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 12,
                        color: selected ? ink.text : ink.subtlest)),
              ),
              SizedBox(
                width: 22,
                height: 22,
                child: IconButton(
                  padding: const EdgeInsets.all(4),
                  iconSize: 12,
                  tooltip: uiText(context, '关闭文件标签', 'Close file tab'),
                  onPressed: onClose,
                  icon: LucideIcon('x', size: 12, color: ink.subtlest),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
