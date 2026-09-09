import 'dart:convert';
import 'package:flutter/material.dart';
import '../../protocol/conversation.dart';
import '../../state/client_preferences.dart';
import '../../state/workspace_catalog.dart';
import '../../state/workspace_view_state.dart';
import '../official_icons.dart';
import '../theme.dart';

class SidebarProject {
  const SidebarProject(this.workspace, this.catalog);
  final WorkspaceDescriptor workspace;
  final WorkspaceTaskCatalog catalog;
}

class SidebarTask {
  const SidebarTask(this.project, this.task);
  final SidebarProject project;
  final SessionEntry task;
  String get key => jsonEncode([project.workspace.key, task.sessionId]);
  bool get pinned => project.catalog.isPinned(task.sessionId);
  bool get archived => project.catalog.isArchived(task.sessionId);
}

enum SidebarTaskAction {
  pin,
  archive,
  unarchive,
  delete,
  rename,
  unread,
  copyId,
  copyProjectPath
}

List<SidebarTask> sortSidebarTasks(
        Iterable<SidebarTask> entries, String sort) =>
    entries.toList()
      ..sort((a, b) {
        final primary = sort == 'created'
            ? b.task.createdAt.compareTo(a.task.createdAt)
            : b.task.lastActivityAt.compareTo(a.task.lastActivityAt);
        if (primary != 0) return primary;
        final secondary = sort == 'created'
            ? b.task.lastActivityAt.compareTo(a.task.lastActivityAt)
            : b.task.createdAt.compareTo(a.task.createdAt);
        return secondary != 0
            ? secondary
            : b.task.sessionId.compareTo(a.task.sessionId);
      });

/// Official remote XEt/ECt/KEt. Touch exposes row actions on the selected row
/// and a long press menu; mouse hover uses the same pin/archive controls.
class TaskNavigation extends StatefulWidget {
  const TaskNavigation(
      {super.key,
      required this.projects,
      required this.view,
      required this.preferences,
      required this.query,
      required this.activeWorkspace,
      required this.activeTask,
      required this.onOpen,
      required this.onAction,
      required this.onExpand,
      this.connected = true,
      this.loading = false});
  final List<SidebarProject> projects;
  final SidebarViewState view;
  final ClientPreferences preferences;
  final String query, activeWorkspace;
  final String? activeTask;
  final Future<void> Function(SidebarTask) onOpen;
  final Future<void> Function(SidebarTask, SidebarTaskAction) onAction;
  final void Function(WorkspaceDescriptor) onExpand;
  final bool connected, loading;
  @override
  State<TaskNavigation> createState() => _TaskNavigationState();
}

class _TaskNavigationState extends State<TaskNavigation> {
  @override
  void initState() {
    super.initState();
    widget.preferences.addListener(_preferencesChanged);
  }

  @override
  void didUpdateWidget(TaskNavigation old) {
    super.didUpdateWidget(old);
    if (old.preferences != widget.preferences) {
      old.preferences.removeListener(_preferencesChanged);
      widget.preferences.addListener(_preferencesChanged);
    }
    if (old.query != widget.query) _pendingArchive = null;
  }

  void _preferencesChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.preferences.removeListener(_preferencesChanged);
    super.dispose();
  }

  String? _pendingArchive;
  String? _opening;
  final _busy = <String>{};
  bool _matches(SidebarTask entry) => [
        entry.task.title,
        entry.project.workspace.title,
        entry.project.workspace.scope['workspacePath'] ?? '',
        entry.project.workspace.scope['workspaceIdentity'] ?? '',
        entry.task.raw['workspaceLabel'] ?? '',
        entry.task.raw['remoteSessionId'] ?? '',
      ].join(' ').toLowerCase().contains(widget.query.trim().toLowerCase());
  Future<void> _open(SidebarTask entry) async {
    if (!widget.connected || _opening != null || _busy.contains(entry.key)) {
      return;
    }
    setState(() {
      _pendingArchive = null;
      _opening = entry.key;
    });
    try {
      await widget.onOpen(entry);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(uiText(context, '无法打开任务，请重试',
                'Could not open the task. Try again.'))));
      }
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  Future<void> _action(SidebarTask entry, SidebarTaskAction action) async {
    if (!widget.connected || _opening != null || !_busy.add(entry.key)) return;
    setState(() => _pendingArchive = null);
    try {
      await widget.onAction(entry, action);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(uiText(context, '任务操作失败，请重试',
                'Could not update the task. Try again.'))));
      }
    } finally {
      if (mounted) setState(() => _busy.remove(entry.key));
    }
  }

  Future<void> _delete(SidebarTask entry) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(uiText(context, '删除已归档任务', 'Delete archived task')),
                content: Text(uiText(context, '删除后无法恢复此任务。',
                    'This task cannot be recovered after deletion.')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(uiText(context, '取消', 'Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(uiText(context, '删除任务', 'Delete task')))
                ]));
    if (confirmed == true && mounted) {
      await _action(entry, SidebarTaskAction.delete);
    }
  }

  void _archive(SidebarTask entry) {
    if (_pendingArchive != entry.key) {
      setState(() => _pendingArchive = entry.key);
      return;
    }
    _action(entry, SidebarTaskAction.archive);
  }

  String _label(
          BuildContext context, SidebarTask entry, SidebarTaskAction action) =>
      switch (action) {
        SidebarTaskAction.pin => entry.pinned
            ? uiText(context, '取消置顶', 'Unpin task')
            : uiText(context, '置顶任务', 'Pin task'),
        SidebarTaskAction.archive => uiText(context, '归档任务', 'Archive task'),
        SidebarTaskAction.unarchive =>
          uiText(context, '取消归档任务', 'Unarchive task'),
        SidebarTaskAction.delete => uiText(context, '删除任务', 'Delete task'),
        SidebarTaskAction.rename => uiText(context, '重命名任务', 'Rename task'),
        SidebarTaskAction.unread => uiText(context, '标记为未读', 'Mark as unread'),
        SidebarTaskAction.copyId =>
          uiText(context, '复制会话 ID', 'Copy session ID'),
        SidebarTaskAction.copyProjectPath =>
          uiText(context, '复制项目路径', 'Copy project path'),
      };
  Future<void> _menu(BuildContext anchor, SidebarTask entry) async {
    final box = anchor.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
    final rect = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
    final choice = await showMenu<SidebarTaskAction>(
        context: context,
        position: RelativeRect.fromRect(rect, Offset.zero & overlay.size),
        items: [
          for (final action in [
            if (!entry.archived) ...[
              SidebarTaskAction.pin,
              SidebarTaskAction.rename,
              SidebarTaskAction.archive,
              SidebarTaskAction.unread
            ],
            if (entry.archived) ...[
              SidebarTaskAction.unarchive,
              SidebarTaskAction.delete
            ],
            SidebarTaskAction.copyId,
            SidebarTaskAction.copyProjectPath,
          ])
            PopupMenuItem(
                value: action, child: Text(_label(context, entry, action)))
        ]);
    if (choice == null || !mounted) return;
    if (choice == SidebarTaskAction.delete) {
      await _delete(entry);
      return;
    }
    if (choice == SidebarTaskAction.archive) {
      _archive(entry);
      return;
    }
    await _action(entry, choice);
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final all = [
      for (final project in widget.projects)
        for (final task in [
          ...project.catalog.visible,
          ...project.catalog.archiveList
        ])
          SidebarTask(project, task)
    ].where(_matches).toList();
    final pinned = sortSidebarTasks(
        all.where((e) => e.pinned && !e.archived), widget.preferences.taskSort);
    final regular = sortSidebarTasks(all.where((e) => !e.pinned && !e.archived),
        widget.preferences.taskSort);
    final archived = sortSidebarTasks(
        all.where((e) => e.archived), widget.preferences.taskSort);
    final groups = widget.projects
        .where((project) => regular
            .any((e) => e.project.workspace.key == project.workspace.key))
        .toList();
    final expanded = groups.isNotEmpty &&
        groups.every(
            (e) => widget.view.expandedProjects.contains(e.workspace.key));
    Widget row(SidebarTask entry, {bool projectLabel = false}) => Padding(
        key: ValueKey(entry.key),
        padding: const EdgeInsets.only(bottom: 2),
        child: _TaskRow(
            entry: entry,
            selected: entry.project.workspace.key == widget.activeWorkspace &&
                entry.task.sessionId == widget.activeTask,
            busy: _busy.contains(entry.key) || _opening == entry.key,
            enabled: widget.connected && _opening == null,
            projectLabel: projectLabel,
            sort: widget.preferences.taskSort,
            confirmingArchive: _pendingArchive == entry.key,
            onOpen: () => _open(entry),
            onPin: () => _action(entry, SidebarTaskAction.pin),
            onArchive: () => _archive(entry),
            onUnarchive: () => _action(entry, SidebarTaskAction.unarchive),
            onDelete: () => _delete(entry),
            onMenu: (anchor) => _menu(anchor, entry)));
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 10),
          child: Row(children: [
            Expanded(
                child: Row(children: [
              Flexible(
                  child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                          color: ink.messageSurface,
                          border: Border.all(color: ink.border),
                          borderRadius: BorderRadius.circular(20)),
                      child: Center(
                          widthFactor: 1,
                          child: Text(uiText(context, '项目', 'Projects'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  TextStyle(fontSize: 12, color: ink.text))))),
              if (!widget.view.archived &&
                  widget.preferences.taskView == 'project')
                _ActionIcon(
                    icon: expanded ? 'chevrons-down-up' : 'chevrons-up-down',
                    label: expanded
                        ? uiText(context, '全部折叠', 'Collapse all')
                        : uiText(context, '全部展开', 'Expand all'),
                    onTap: groups.isEmpty
                        ? null
                        : () => setState(() {
                              if (expanded) {
                                widget.view.expandedProjects.clear();
                              } else {
                                widget.view.expandedProjects
                                    .addAll(groups.map((e) => e.workspace.key));
                                for (final project in groups) {
                                  widget.onExpand(project.workspace);
                                }
                              }
                            })),
            ])),
            PopupMenuButton<String>(
                tooltip: uiText(context, '筛选和排序', 'Filter and sort'),
                padding: EdgeInsets.zero,
                child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Center(
                        child: LucideIcon('list-filter',
                            size: 16, color: ink.subtlest))),
                onSelected: (value) {
                  if (value == 'project' || value == 'timeline') {
                    widget.preferences.setTaskView(value);
                  } else {
                    widget.preferences.setTaskSort(value);
                  }
                  setState(() {});
                },
                itemBuilder: (context) => [
                      if (!widget.view.archived) ...[
                        PopupMenuItem(
                            enabled: false,
                            height: 28,
                            child: Text(uiText(context, '视图', 'View'))),
                        CheckedPopupMenuItem(
                            value: 'project',
                            checked: widget.preferences.taskView == 'project',
                            child: Text(uiText(context, '按项目', 'By project'))),
                        CheckedPopupMenuItem(
                            value: 'timeline',
                            checked: widget.preferences.taskView == 'timeline',
                            child: Text(uiText(context, '时间线', 'Timeline'))),
                        const PopupMenuDivider(),
                      ],
                      PopupMenuItem(
                          enabled: false,
                          height: 28,
                          child: Text(uiText(context, '排序方式', 'Sort by'))),
                      CheckedPopupMenuItem(
                          value: 'updated',
                          checked: widget.preferences.taskSort == 'updated',
                          child: Text(uiText(context, '更新时间', 'Updated time'))),
                      CheckedPopupMenuItem(
                          value: 'created',
                          checked: widget.preferences.taskSort == 'created',
                          child: Text(uiText(context, '创建时间', 'Created time'))),
                    ]),
            _ActionIcon(
                icon: widget.view.archived ? 'x' : 'archive',
                label: widget.view.archived
                    ? uiText(context, '关闭归档', 'Close archive')
                    : uiText(context, '归档', 'Archived tasks'),
                selected: widget.view.archived,
                onTap: () => setState(() {
                      widget.view.archived = !widget.view.archived;
                      _pendingArchive = null;
                    })),
          ])),
      Expanded(
          child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
            if (pinned.isNotEmpty) ...[
              Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                  child: Text(uiText(context, '已置顶', 'Pinned'),
                      style: TextStyle(fontSize: 14, color: ink.subtlest))),
              ...pinned.map(row),
              const SizedBox(height: 8),
            ],
            if (widget.loading && all.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(8),
                  child:
                      Text(uiText(context, '正在获取任务...', 'Loading tasks...'))),
            if (!widget.loading &&
                (widget.view.archived ? archived : regular).isEmpty &&
                pinned.isEmpty)
              Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(
                      widget.view.archived
                          ? uiText(context, '暂无归档任务', 'No archived tasks')
                          : uiText(context, '暂无任务', 'No tasks'),
                      style: TextStyle(fontSize: 14, color: ink.subtlest))),
            if (widget.view.archived)
              ...archived.map((e) => row(e, projectLabel: true))
            else if (widget.preferences.taskView == 'timeline')
              ...regular.map((e) => row(e, projectLabel: true))
            else
              for (final project in groups) ...[
                InkWell(
                    onTap: () {
                      setState(() {
                        if (!widget.view.expandedProjects
                            .add(project.workspace.key)) {
                          widget.view.expandedProjects
                              .remove(project.workspace.key);
                        }
                      });
                      if (widget.view.expandedProjects
                          .contains(project.workspace.key)) {
                        widget.onExpand(project.workspace);
                      }
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                        constraints: const BoxConstraints(minHeight: 32),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        child: Row(children: [
                          LucideIcon(
                              widget.view.expandedProjects
                                      .contains(project.workspace.key)
                                  ? 'chevron-down'
                                  : 'chevron-right',
                              size: 12,
                              color: ink.subtlest),
                          const SizedBox(width: 8),
                          LucideIcon('folder', size: 16, color: ink.subtlest),
                          const SizedBox(width: 8),
                          Expanded(
                              child: Text(project.workspace.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                      fontSize: 14, color: ink.subtlest))),
                          const SizedBox(width: 4),
                          if (!widget.view.expandedProjects
                                  .contains(project.workspace.key) &&
                              regular.any((entry) =>
                                  entry.project.workspace.key ==
                                      project.workspace.key &&
                                  entry.task.raw['unreadAt'] is num))
                            Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: Container(
                                    key: ValueKey(
                                        'sidebar-project-unread-${project.workspace.key}'),
                                    width: 6,
                                    height: 6,
                                    decoration: BoxDecoration(
                                        color: ink.usageChart,
                                        shape: BoxShape.circle))),
                          Text(
                              '${regular.where((e) => e.project.workspace.key == project.workspace.key).length}',
                              style:
                                  TextStyle(fontSize: 14, color: ink.subtlest)),
                        ]))),
                if (widget.view.expandedProjects
                        .contains(project.workspace.key) ||
                    widget.query.isNotEmpty)
                  ...regular
                      .where((e) =>
                          e.project.workspace.key == project.workspace.key)
                      .map(row),
                const SizedBox(height: 8),
              ],
          ])),
    ]);
  }
}

class _TaskRow extends StatefulWidget {
  const _TaskRow(
      {required this.entry,
      required this.selected,
      required this.busy,
      required this.enabled,
      required this.projectLabel,
      required this.sort,
      required this.confirmingArchive,
      required this.onOpen,
      required this.onPin,
      required this.onArchive,
      required this.onUnarchive,
      required this.onDelete,
      required this.onMenu});
  final SidebarTask entry;
  final bool selected, busy, enabled, projectLabel, confirmingArchive;
  final String sort;
  final VoidCallback onOpen, onPin, onArchive, onUnarchive, onDelete;
  final void Function(BuildContext) onMenu;
  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _hovered = false;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final entry = widget.entry;
    final actions = widget.enabled &&
        (_hovered || widget.selected || widget.confirmingArchive);
    final enabled = widget.enabled && !widget.busy;
    final age = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(
        widget.sort == 'created'
            ? entry.task.createdAt
            : entry.task.lastActivityAt));
    final time = age.inMinutes < 1
        ? uiText(context, '刚刚', 'now')
        : age.inHours < 1
            ? uiText(context, '${age.inMinutes}分', '${age.inMinutes}m')
            : age.inDays < 1
                ? uiText(context, '${age.inHours}小时', '${age.inHours}h')
                : uiText(context, '${age.inDays}天', '${age.inDays}d');
    return MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: Material(
            color: widget.selected ? ink.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            child: Builder(
                builder: (anchor) => Semantics(
                    onLongPress: enabled ? () => widget.onMenu(anchor) : null,
                    child: InkWell(
                        key: ValueKey('sidebar-task-${entry.key}'),
                        onTap: enabled ? widget.onOpen : null,
                        // Let the initiating pointer finish before adding a route.
                        // Opening on down can leave Android's row gesture active
                        // after a popup action rebuilds or moves this row.
                        onLongPressUp:
                            enabled ? () => widget.onMenu(anchor) : null,
                        onSecondaryTap:
                            enabled ? () => widget.onMenu(anchor) : null,
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                            constraints: const BoxConstraints(minHeight: 32),
                            padding: const EdgeInsets.only(left: 6, right: 4),
                            child: Row(children: [
                              if (widget.busy)
                                const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Padding(
                                        padding: EdgeInsets.all(4),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 1.5)))
                              else if (actions && !entry.archived)
                                _ActionIcon(
                                    icon: 'pin',
                                    size: 24,
                                    label: entry.pinned
                                        ? uiText(context, '取消置顶', 'Unpin task')
                                        : uiText(context, '置顶任务', 'Pin task'),
                                    onTap: enabled ? widget.onPin : null)
                              else
                                SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: Center(
                                        child:
                                            entry.task.raw['unreadAt'] != null
                                                ? Container(
                                                    width: 6,
                                                    height: 6,
                                                    decoration: BoxDecoration(
                                                        color: ink.usageChart,
                                                        shape: BoxShape.circle))
                                                : entry.pinned
                                                    ? LucideIcon('pin',
                                                        size: 16,
                                                        color: ink.subtlest)
                                                    : null)),
                              const SizedBox(width: 4),
                              Expanded(
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 5),
                                      child: Text(
                                          entry.task.title.isEmpty
                                              ? uiText(
                                                  context, '新任务', 'New task')
                                              : entry.task.title,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: TextStyle(
                                              fontSize: 14, color: ink.text)))),
                              if (!actions) ...[
                                if (widget.projectLabel)
                                  Flexible(
                                      child: Padding(
                                          padding:
                                              const EdgeInsets.only(left: 6),
                                          child: Text(
                                              entry.project.workspace.title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 12,
                                                  color: ink.subtlest)))),
                                Padding(
                                    padding: const EdgeInsets.only(left: 6),
                                    child: Text(time,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: ink.subtlest))),
                              ],
                              if (actions && !entry.archived)
                                widget.confirmingArchive
                                    ? TextButton(
                                        style: TextButton.styleFrom(
                                            foregroundColor: ink.diffRemoved,
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 6),
                                            minimumSize: const Size(40, 28),
                                            tapTargetSize: MaterialTapTargetSize
                                                .shrinkWrap),
                                        onPressed:
                                            enabled ? widget.onArchive : null,
                                        child: Text(
                                            uiText(context, '确认', 'Confirm')))
                                    : _ActionIcon(
                                        icon: 'archive',
                                        size: 24,
                                        label: uiText(
                                            context, '归档任务', 'Archive task'),
                                        onTap:
                                            enabled ? widget.onArchive : null),
                              if (actions && entry.archived) ...[
                                _ActionIcon(
                                    icon: 'archive-restore',
                                    size: 24,
                                    label: uiText(
                                        context, '取消归档任务', 'Unarchive task'),
                                    onTap: enabled ? widget.onUnarchive : null),
                                _ActionIcon(
                                    icon: 'trash-2',
                                    size: 24,
                                    label:
                                        uiText(context, '删除任务', 'Delete task'),
                                    color: ink.diffRemoved,
                                    onTap: enabled ? widget.onDelete : null),
                              ],
                            ])))))));
  }
}

class _ActionIcon extends StatelessWidget {
  const _ActionIcon(
      {required this.icon,
      required this.label,
      required this.onTap,
      this.selected = false,
      this.size = 28,
      this.color});
  final String icon, label;
  final VoidCallback? onTap;
  final bool selected;
  final double size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Tooltip(
        message: label,
        child: Semantics(
            label: label,
            button: true,
            child: InkWell(
                onTap: onTap,
                borderRadius: BorderRadius.circular(6),
                child: Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                        color: selected ? ink.hover : null,
                        borderRadius: BorderRadius.circular(6)),
                    alignment: Alignment.center,
                    child: LucideIcon(icon,
                        size: 16, color: color ?? ink.subtlest)))));
  }
}
