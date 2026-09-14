import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../state/client_preferences.dart';
import '../state/workspace_search.dart';
import 'official_icons.dart';
import 'shell/task_navigation.dart';
import 'theme.dart';

enum CommandCenterScope { all, commands, conversations, files }

class CommandCenterFileChange {
  const CommandCenterFileChange({
    required this.path,
    required this.added,
    required this.removed,
    this.lastTurnIndex = 0,
    this.writeCount = 0,
  });
  final String path;
  final int added;
  final int removed;
  final int lastTurnIndex;
  final int writeCount;
}

class CommandCenterActions {
  const CommandCenterActions({
    required this.newTask,
    required this.openWorkspace,
    required this.openSettings,
    required this.toggleSidebar,
    required this.toggleTerminal,
    required this.addTerminalTab,
    required this.openTask,
    this.openSearchResult,
  });
  final VoidCallback newTask;
  final VoidCallback openWorkspace;
  final VoidCallback openSettings;
  final VoidCallback toggleSidebar;
  final VoidCallback toggleTerminal;
  final VoidCallback addTerminalTab;
  final ValueChanged<SidebarTask> openTask;
  final ValueChanged<WorkspaceSearchResult>? openSearchResult;
}

Future<void> showCommandCenter(
  BuildContext context, {
  required CommandCenterActions actions,
  required List<SidebarTask> tasks,
  required String? activeTaskId,
  List<CommandCenterFileChange> changes = const [],
  WorkspaceSearchController? search,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: uiText(context, '命令面板', 'Command center'),
    // Official scrim measures ~0.60 black over the same page regions
    // (rog-search-dialog vs rog-task-9am luminance 91/98 vs 228/247);
    // black54 measured 0.54 locally.
    barrierColor: Colors.black.withValues(alpha: 0.6),
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (_, __, ___) => CommandCenter(
      actions: actions,
      tasks: tasks,
      activeTaskId: activeTaskId,
      changes: changes,
      search: search,
    ),
    transitionBuilder: (_, animation, __, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
      child: child,
    ),
  );
}

class CommandCenter extends StatefulWidget {
  const CommandCenter({
    super.key,
    required this.actions,
    required this.tasks,
    required this.activeTaskId,
    this.changes = const [],
    this.search,
  });

  final CommandCenterActions actions;
  final List<SidebarTask> tasks;
  final String? activeTaskId;
  final List<CommandCenterFileChange> changes;
  final WorkspaceSearchController? search;

  @override
  State<CommandCenter> createState() => _CommandCenterState();
}

class _CommandCenterState extends State<CommandCenter> {
  final _query = TextEditingController();
  final _focus = FocusNode();
  CommandCenterScope _scope = CommandCenterScope.all;
  int _selectedRemoteIndex = 0;
  bool _expandedResults = false;

  @override
  void initState() {
    super.initState();
    widget.search?.addListener(_searchChanged);
    unawaited(widget.search?.loadHistory());
    _applyQueryPrefix(_query.text);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    widget.search?.removeListener(_searchChanged);
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _searchChanged() {
    if (mounted) setState(() {});
  }

  List<WorkspaceSearchResult> get _remoteSelectable => [
        if (_scope == CommandCenterScope.all ||
            _scope == CommandCenterScope.conversations)
          ..._remoteConversations,
        if (_scope == CommandCenterScope.all ||
            _scope == CommandCenterScope.files)
          ..._remoteFiles,
      ];

  void _moveRemoteSelection(int delta) {
    final count = _remoteSelectable.length;
    if (count == 0) return;
    setState(() => _selectedRemoteIndex =
        (_selectedRemoteIndex + delta).clamp(0, count - 1));
  }

  void _activateRemoteSelection() {
    final rows = _remoteSelectable;
    if (rows.isEmpty || _selectedRemoteIndex >= rows.length) return;
    final result = rows[_selectedRemoteIndex];
    widget.search?.recordSelection(_query.text);
    Navigator.of(context).pop();
    widget.actions.openSearchResult?.call(result);
  }

  void _applyQueryPrefix(String value) {
    final trimmed = value.trimLeft();
    final scope = switch (trimmed.isEmpty ? '' : trimmed[0]) {
      '>' => CommandCenterScope.commands,
      '#' => CommandCenterScope.conversations,
      '@' => CommandCenterScope.files,
      _ => CommandCenterScope.all,
    };
    if (_scope != scope) {
      setState(() => _scope = scope);
    }
  }

  bool _matches(String text, Iterable<String> keywords) {
    final query = _query.text.trim().toLowerCase();
    if (query.isEmpty) return true;
    final normalized =
        query.startsWith('>') || query.startsWith('#') || query.startsWith('@')
            ? query.substring(1).trim()
            : query;
    if (normalized.isEmpty) return true;
    final haystack =
        '$text ${keywords.join(' ')}'.toLowerCase().split(RegExp(r'\s+'));
    return normalized
        .split(RegExp(r'\s+'))
        .every((term) => haystack.any((item) => item.contains(term)));
  }

  /// Official Quick Pick task rows show compact recency, not workspace titles.
  String _relative(BuildContext context, int timestamp) {
    if (timestamp <= 0) return '';
    final delta = DateTime.now().millisecondsSinceEpoch - timestamp;
    if (delta < const Duration(minutes: 1).inMilliseconds) {
      return uiText(context, '刚刚', 'now');
    }
    if (delta < const Duration(hours: 1).inMilliseconds) {
      final minutes =
          (delta / const Duration(minutes: 1).inMilliseconds).floor();
      return uiText(context, '$minutes分', '${minutes}m');
    }
    if (delta < const Duration(days: 1).inMilliseconds) {
      final hours = (delta / const Duration(hours: 1).inMilliseconds).floor();
      return uiText(context, '$hours小时', '${hours}h');
    }
    final days = (delta / const Duration(days: 1).inMilliseconds).floor();
    return uiText(context, '$days天', '${days}d');
  }

  List<SidebarTask> get _tasks {
    final sameWorkspace = widget.tasks
        .where((entry) => entry.task.sessionId != widget.activeTaskId)
        .toList()
      ..sort((a, b) => b.task.lastActivityAt.compareTo(a.task.lastActivityAt));
    final query = _query.text.trim();
    if (query.isEmpty) return sameWorkspace.take(3).toList();
    return sameWorkspace
        .where((entry) => _matches(
              [
                entry.task.title,
                entry.project.workspace.title,
                entry.project.workspace.key,
                entry.task.lastAssistantPreview ?? '',
              ].join(' '),
              const [],
            ))
        .take(3)
        .toList();
  }

  List<CommandCenterFileChange> get _changes {
    final query = _query.text.trim();
    final keyword =
        query.startsWith('@') ? query.substring(1).trim() : query.trim();
    final sorted = [...widget.changes]..sort((a, b) {
        final primary = b.lastTurnIndex.compareTo(a.lastTurnIndex);
        return primary != 0 ? primary : b.writeCount.compareTo(a.writeCount);
      });
    return sorted
        .where((change) =>
            change.path.toLowerCase().contains(keyword.toLowerCase()))
        .take(3)
        .toList();
  }

  List<WorkspaceSearchResult> get _remoteConversations =>
      widget.search?.results
          .where(
              (result) => result.kind == WorkspaceSearchResultKind.conversation)
          .toList() ??
      const [];

  List<WorkspaceSearchResult> get _remoteFiles =>
      widget.search?.results
          .where((result) => result.kind == WorkspaceSearchResultKind.file)
          .toList() ??
      const [];

  List<Widget> get _commands {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final groups = <String, List<Widget>>{};
    void command(
      String label,
      String icon,
      VoidCallback onTap, {
      String? shortcut,
      List<String> keywords = const [],
      String section = '',
    }) {
      if (!_matches('$label ${shortcut ?? ''}', keywords)) return;
      groups.putIfAbsent(section, () => []).add(_CommandRow(
          label: label,
          icon: icon,
          shortcut: shortcut,
          ink: ink,
          onTap: () {
            Navigator.of(context).pop();
            onTap();
          }));
    }

    command(
        uiText(context, '新任务', 'New task'), 'message', widget.actions.newTask,
        keywords: const ['new task 新任务 新建任务'],
        shortcut: 'Ctrl+N',
        section: uiText(context, '建议', 'Suggested'));
    command(uiText(context, '打开工作区', 'Open workspace'), 'folder',
        widget.actions.openWorkspace,
        keywords: const ['workspace folder 工作区 项目'],
        shortcut: 'Ctrl+O',
        section: uiText(context, '建议', 'Suggested'));
    command(uiText(context, '设置', 'Settings'), 'settings',
        widget.actions.openSettings,
        keywords: const ['settings preferences 设置 配置'],
        section: uiText(context, '建议', 'Suggested'));
    command(uiText(context, '切换侧栏', 'Toggle sidebar'), 'panel-left',
        widget.actions.toggleSidebar,
        keywords: const ['sidebar 侧栏 侧边栏'],
        shortcut: 'Ctrl+B',
        section: uiText(context, '面板', 'Panels'));
    command(uiText(context, '切换终端', 'Toggle terminal'), 'terminal',
        widget.actions.toggleTerminal,
        keywords: const ['terminal shell 终端'],
        shortcut: 'Ctrl+J',
        section: uiText(context, '面板', 'Panels'));
    command(uiText(context, '添加终端标签', 'Add terminal tab'), 'terminal',
        widget.actions.addTerminalTab,
        keywords: const ['add terminal tab 终端标签'],
        section: uiText(context, '面板', 'Panels'));
    return [
      for (final entry in groups.entries) ...[
        _SectionHeader(label: entry.key, ink: ink),
        ...entry.value,
      ]
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final commands = _scope == CommandCenterScope.all ||
            _scope == CommandCenterScope.commands
        ? _commands
        : const <Widget>[];
    final tasks = _scope == CommandCenterScope.all ||
            _scope == CommandCenterScope.conversations
        ? _tasks
        : const <SidebarTask>[];
    final changes =
        _scope == CommandCenterScope.all || _scope == CommandCenterScope.files
            ? _changes
            : const <CommandCenterFileChange>[];
    final remoteConversations = _scope == CommandCenterScope.all ||
            _scope == CommandCenterScope.conversations
        ? _remoteConversations
        : const <WorkspaceSearchResult>[];
    final remoteFiles =
        _scope == CommandCenterScope.all || _scope == CommandCenterScope.files
            ? _remoteFiles
            : const <WorkspaceSearchResult>[];
    final visibleRemoteConversations = _expandedResults
        ? remoteConversations
        : remoteConversations.take(3).toList();
    final visibleRemoteFiles =
        _expandedResults ? remoteFiles : remoteFiles.take(3).toList();
    final empty = commands.isEmpty &&
        tasks.isEmpty &&
        changes.isEmpty &&
        remoteConversations.isEmpty &&
        remoteFiles.isEmpty &&
        widget.search?.loading != true &&
        _scope == CommandCenterScope.all;
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).pop(),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveRemoteSelection(1),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveRemoteSelection(-1),
        const SingleActivator(LogicalKeyboardKey.enter):
            _activateRemoteSelection,
      },
      child: Focus(
        autofocus: true,
        child: Dialog(
          backgroundColor: ink.card,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.only(top: 64, left: 24, right: 24),
          alignment: Alignment.topCenter,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZRadius.twoXl),
            side: BorderSide(color: ink.border),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 512, maxHeight: 524),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                  child: Column(children: [
                    Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: ink.surfaceFill,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: ink.border),
                      ),
                      child: Row(children: [
                        LucideIcon('search', size: 16, color: ink.subtlest),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _query,
                            focusNode: _focus,
                            onChanged: (value) {
                              _applyQueryPrefix(value);
                              _selectedRemoteIndex = 0;
                              _expandedResults = false;
                              widget.search?.search(value);
                            },
                            style: const TextStyle(fontSize: 14, height: 1.25),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              hintText: uiText(context, '搜索操作、任务或文件',
                                  'Search actions, tasks or files'),
                              hintStyle:
                                  TextStyle(fontSize: 14, color: ink.subtlest),
                            ),
                          ),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      height: 28,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        shrinkWrap: true,
                        children: [
                          for (final scope in CommandCenterScope.values)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: _ScopeTab(
                                key: ValueKey('command-scope-${scope.name}'),
                                icon: switch (scope) {
                                  CommandCenterScope.all => 'list-filter',
                                  CommandCenterScope.commands => 'sparkles',
                                  CommandCenterScope.conversations => 'message',
                                  CommandCenterScope.files => 'file-code',
                                },
                                label: switch (scope) {
                                  CommandCenterScope.all =>
                                    uiText(context, '全部', 'All'),
                                  CommandCenterScope.commands =>
                                    uiText(context, '操作', 'Actions'),
                                  CommandCenterScope.conversations =>
                                    uiText(context, '任务', 'Tasks'),
                                  CommandCenterScope.files =>
                                    uiText(context, '文件', 'Files'),
                                },
                                active: _scope == scope,
                                ink: ink,
                                onTap: () => setState(() => _scope = scope),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ]),
                ),
                Flexible(
                  child: empty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 20),
                          child: Text(
                            uiText(context, '暂无相关结果', 'No results'),
                            style: TextStyle(fontSize: 14, color: ink.subtlest),
                          ),
                        )
                      : ListView(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          children: [
                            if (widget.search?.loading == true)
                              const LinearProgressIndicator(minHeight: 2),
                            if (widget.search?.error != null)
                              Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                      uiText(context, '搜索失败，请重试',
                                          'Search failed. Try again.'),
                                      style: TextStyle(
                                          fontSize: 12,
                                          color: ink.diffRemoved))),
                            if (_query.text.trim().isEmpty &&
                                widget.search?.history.isNotEmpty == true) ...[
                              _SectionHeader(
                                  label:
                                      uiText(context, '搜索历史', 'Search history'),
                                  ink: ink),
                              for (final item in widget.search!.history.take(3))
                                _CommandRow(
                                  label: item,
                                  icon: 'history',
                                  ink: ink,
                                  onTap: () {
                                    _query.text = item;
                                    _query.selection = TextSelection.collapsed(
                                        offset: item.length);
                                    _applyQueryPrefix(item);
                                    widget.search?.search(item);
                                  },
                                ),
                              TextButton(
                                  onPressed: widget.search!.clearHistory,
                                  child: Text(uiText(
                                      context, '清空历史', 'Clear history'))),
                            ],
                            if (remoteConversations.isNotEmpty) ...[
                              _SectionHeader(
                                  label:
                                      uiText(context, '搜索结果', 'Search results'),
                                  ink: ink),
                              for (var index = 0;
                                  index < visibleRemoteConversations.length;
                                  index++)
                                _CommandRow(
                                  selected: _selectedRemoteIndex == index,
                                  label:
                                      visibleRemoteConversations[index].title,
                                  icon: 'message',
                                  ink: ink,
                                  trailing: visibleRemoteConversations[index]
                                              .snippet
                                              ?.isNotEmpty ==
                                          true
                                      ? visibleRemoteConversations[index]
                                          .snippet
                                      : visibleRemoteConversations[index]
                                          .workspaceTitle,
                                  onTap: () {
                                    final result =
                                        visibleRemoteConversations[index];
                                    widget.search?.recordSelection(_query.text);
                                    Navigator.of(context).pop();
                                    widget.actions.openSearchResult
                                        ?.call(result);
                                  },
                                ),
                            ],
                            if (remoteFiles.isNotEmpty) ...[
                              _SectionHeader(
                                  label: uiText(context, '文件', 'Files'),
                                  ink: ink),
                              for (var index = 0;
                                  index < visibleRemoteFiles.length;
                                  index++)
                                _CommandRow(
                                  selected: _selectedRemoteIndex ==
                                      remoteConversations.length + index,
                                  label:
                                      visibleRemoteFiles[index].relativePath ??
                                          visibleRemoteFiles[index].filePath ??
                                          visibleRemoteFiles[index].title,
                                  icon: 'file-code',
                                  ink: ink,
                                  trailing:
                                      visibleRemoteFiles[index].workspaceTitle,
                                  onTap: () {
                                    final result = visibleRemoteFiles[index];
                                    widget.search?.recordSelection(_query.text);
                                    Navigator.of(context).pop();
                                    widget.actions.openSearchResult
                                        ?.call(result);
                                  },
                                ),
                            ],
                            if (remoteConversations.length >
                                    visibleRemoteConversations.length ||
                                remoteFiles.length > visibleRemoteFiles.length)
                              TextButton(
                                  onPressed: () =>
                                      setState(() => _expandedResults = true),
                                  child: Text(uiText(context, '更多', 'More'))),
                            if (changes.isNotEmpty) ...[
                              _SectionHeader(
                                  label:
                                      uiText(context, '最近变更', 'Recent changes'),
                                  ink: ink),
                              for (final change in changes)
                                _CommandRow(
                                  label: change.path,
                                  icon: 'file-code',
                                  ink: ink,
                                  trailing:
                                      '+${change.added} -${change.removed}',
                                  added: change.added,
                                  removed: change.removed,
                                  onTap: () {},
                                ),
                            ] else if (_scope == CommandCenterScope.files)
                              _SectionHeader(
                                  label:
                                      uiText(context, '最近变更', 'Recent changes'),
                                  ink: ink),
                            if (_scope == CommandCenterScope.files &&
                                changes.isEmpty)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 20),
                                child: Text(
                                  uiText(context, '当前任务暂无最近变更',
                                      'No recent changes in this task'),
                                  style: TextStyle(
                                      fontSize: 14, color: ink.subtlest),
                                ),
                              ),
                            if (tasks.isNotEmpty) ...[
                              _SectionHeader(
                                  label:
                                      uiText(context, '最近任务', 'Recent tasks'),
                                  ink: ink),
                              for (final entry in tasks)
                                _CommandRow(
                                  label: entry.task.title.isEmpty
                                      ? uiText(
                                          context, '未命名任务', 'Untitled task')
                                      : entry.task.title,
                                  icon: 'message',
                                  ink: ink,
                                  trailing: _relative(
                                      context, entry.task.lastActivityAt),
                                  onTap: () {
                                    Navigator.of(context).pop();
                                    widget.actions.openTask(entry);
                                  },
                                ),
                            ] else if (_scope ==
                                CommandCenterScope.conversations)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 20),
                                child: Text(
                                  uiText(context, '暂无最近任务', 'No recent tasks'),
                                  style: TextStyle(
                                      fontSize: 14, color: ink.subtlest),
                                ),
                              ),
                            ...commands,
                          ],
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ScopeTab extends StatelessWidget {
  const _ScopeTab({
    super.key,
    required this.icon,
    required this.label,
    required this.active,
    required this.ink,
    required this.onTap,
  });
  final String icon;
  final String label;
  final bool active;
  final InkTokens ink;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: active ? ink.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: active ? ink.border : Colors.transparent),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            LucideIcon(icon, size: 12, color: ink.subtlest),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: active ? ink.text : ink.subtlest,
                    fontWeight: FontWeight.w500)),
          ]),
        ),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.ink});
  final String label;
  final InkTokens ink;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Text(label,
            style: TextStyle(
                fontSize: 12,
                color: ink.subtlest,
                fontWeight: FontWeight.w500)),
      );
}

class _CommandRow extends StatelessWidget {
  const _CommandRow({
    required this.label,
    required this.icon,
    required this.ink,
    required this.onTap,
    this.trailing,
    this.shortcut,
    this.added,
    this.removed,
    this.selected = false,
  });
  final String label;
  final String icon;
  final InkTokens ink;
  final VoidCallback onTap;
  final String? trailing;
  final String? shortcut;
  final int? added;
  final int? removed;
  final bool selected;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          color: selected ? ink.hover : null,
          child: Row(children: [
            LucideIcon(icon, size: 14, color: ink.subtlest),
            const SizedBox(width: 10),
            Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 14))),
            if (added != null || removed != null) ...[
              Text('+${added ?? 0}',
                  style: TextStyle(fontSize: 12, color: ink.diffAdded)),
              const SizedBox(width: 4),
              Text('-${removed ?? 0}',
                  style: TextStyle(fontSize: 12, color: ink.diffRemoved)),
            ] else if (shortcut != null)
              Container(
                height: 16,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: ink.surfaceFill,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(shortcut!,
                    style: TextStyle(fontSize: 11, color: ink.subtlest)),
              )
            else if (trailing != null)
              Flexible(
                child: Text(trailing!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: ink.subtlest)),
              ),
          ]),
        ),
      );
}

List<CommandCenterFileChange> commandCenterChangesFromRows(
        Iterable<Map<String, dynamic>> rows) =>
    [
      for (final row in rows)
        if (row['kind'] == 'changeSummary')
          for (final raw in switch (row['files']) {
            final List files => files,
            _ => const <Object?>[],
          })
            if (raw is Map)
              CommandCenterFileChange(
                path: raw['path'] as String? ?? '',
                added: (raw['addedLines'] as num?)?.toInt() ?? 0,
                removed: (raw['removedLines'] as num?)?.toInt() ?? 0,
                lastTurnIndex: (raw['turnIndex'] as num?)?.toInt() ??
                    (row['turnIndex'] as num?)?.toInt() ??
                    0,
                writeCount: (raw['writeCount'] as num?)?.toInt() ?? 0,
              )
    ].where((change) => change.path.isNotEmpty).toList();

List<SidebarTask> commandCenterTasks(List<SidebarProject> projects) => [
      for (final project in projects)
        for (final task in project.catalog.visible) SidebarTask(project, task)
    ];
