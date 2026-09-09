import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../notifications/task_target.dart';
import '../protocol/conversation.dart';
import '../state/app_sessions.dart';
import '../state/client_preferences.dart';
import '../state/device_store.dart';
import '../state/remote_profile.dart';
import '../state/workspace_catalog.dart';
import '../state/workspace_view_state.dart';
import '../state/plugin_catalog.dart';
import '../state/composer_input.dart';
import 'chat_page.dart';
import 'device_connection_status.dart';
import 'navigation.dart';
import 'official_icons.dart';
import 'shell/shell_layout.dart';
import 'shell/task_navigation.dart';
import 'theme.dart';
import 'plugin_marketplace.dart';

class WorkspaceShell extends StatefulWidget {
  const WorkspaceShell(
      {super.key,
      required this.device,
      required this.workspace,
      required this.monitor,
      required this.sessions,
      required this.preferences,
      this.sessionId,
      this.initialTitle,
      this.onSessionCreated,
      this.conversationBuilder});
  final Device device;
  final WorkspaceDescriptor workspace;
  final WorkspaceMonitor monitor;
  final AppSessions sessions;
  final ClientPreferences preferences;
  final String? sessionId;
  final String? initialTitle;
  final ValueChanged<String>? onSessionCreated;
  final Widget Function(BuildContext, String?)? conversationBuilder;
  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

enum _WorkPanel { summary, sideChat }

class _WorkspaceShellState extends State<WorkspaceShell> {
  final _search = TextEditingController();
  final _chatKey = GlobalKey();
  late String? _sessionId;
  late final SidebarViewState _sidebarView;
  final _remoteCatalogs = <String, WorkspaceTaskCatalog>{};
  int _seenTaskIndexVersion = -1;
  final _monitors = <String, WorkspaceMonitor>{};
  final _loadingProjects = <String>{};
  late final WorkspaceViewState _view;
  bool get _sidebarCollapsed => _view.sidebarCollapsed;
  set _sidebarCollapsed(bool value) => _view.sidebarCollapsed = value;
  bool _searchOpen = false;
  _WorkPanel? _panel;
  _WorkPanel get _lastPanel =>
      _WorkPanel.values
          .where((panel) => panel.name == _view.panelTab)
          .firstOrNull ??
      _WorkPanel.summary;
  set _lastPanel(_WorkPanel value) => _view.panelTab = value.name;
  LocalHistoryEntry? _panelHistory;
  RemoteProfile? _profile;
  bool _creatingSide = false;
  String? _sideId;
  ConversationState? _conversationState;
  PluginCatalog? _pluginCatalog;
  bool _pluginOpen = false;
  LocalHistoryEntry? _pluginHistory;
  String get _viewKey => TaskTarget(
          deviceId: _device.id,
          workspaceKey: widget.workspace.key,
          sessionId: _sessionId ?? '',
          title: '')
      .key;

  Device get _device =>
      widget.sessions.store.devices
          .where((device) => device.id == widget.device.id)
          .firstOrNull ??
      widget.device;
  List<WorkspaceDescriptor> get _projects => [
        for (final raw
            in widget.sessions.sessionOf(widget.device.id)?.workspaces ??
                const <Map<String, dynamic>>[])
          if (WorkspaceDescriptor.parse(raw)
              case final WorkspaceDescriptor project)
            project
      ];
  SessionEntry? get _task => [
        ...widget.monitor.tasks,
        ...widget.monitor.archivedTasks
      ].where((task) => task.sessionId == _sessionId).firstOrNull;
  String _title(BuildContext context) => _task?.title.isNotEmpty == true
      ? _task!.title
      : widget.initialTitle?.isNotEmpty == true
          ? widget.initialTitle!
          : uiText(context, _sessionId == null ? '新建任务' : '任务',
              _sessionId == null ? 'New task' : 'Task');

  @override
  void initState() {
    super.initState();
    _sessionId = widget.sessionId;
    _view = widget.sessions.workspaceViewStates
        .putIfAbsent(_viewKey, WorkspaceViewState.new);
    _sidebarView = widget.sessions.sidebarStates
        .putIfAbsent(_device.id, SidebarViewState.new);
    _sidebarView.expandedProjects.add(widget.workspace.key);
    _monitors[widget.workspace.key] = widget.monitor;
    widget.monitor.addListener(_changed);
    widget.sessions.addListener(_changed);
    widget.sessions.store.addListener(_changed);
    _search.addListener(_changed);
    _syncRemoteIndex();
    final sideKey = TaskTarget(
            deviceId: _device.id,
            workspaceKey: widget.workspace.key,
            sessionId: _sessionId ?? '',
            title: '')
        .key;
    _sideId = widget.sessions.sideChats[sideKey];
    if (_view.panelOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _showPanel(_lastPanel);
      });
    }
    if (widget.conversationBuilder == null) unawaited(_loadProfile());
  }

  Future<void> _loadProfile() async {
    try {
      final profile = await RemoteProfile.load(widget.monitor.bridge);
      if (mounted) setState(() => _profile = profile);
    } catch (_) {/* The workspace stays usable without account metadata. */}
  }

  void _changed() {
    _syncRemoteIndex();
    if (mounted) setState(() {});
  }

  void _syncRemoteIndex() {
    final device = widget.sessions.sessionOf(_device.id);
    if (device == null || _seenTaskIndexVersion == device.taskIndexVersion) {
      return;
    }
    _seenTaskIndexVersion = device.taskIndexVersion;
    for (final project in [..._projects, widget.workspace]) {
      final catalog = _remoteCatalogs.putIfAbsent(
          project.key, () => WorkspaceTaskCatalog(project.scope));
      final rows = catalog.parseChannel(device.taskIndex
          .where((row) =>
              row['workspaceIdentity'] is String ||
              row['workspacePath'] is String)
          .toList());
      catalog.replaceRemote(rows);
      _monitors[project.key]?.catalog.replaceRemote(rows);
    }
  }

  @override
  void dispose() {
    for (final monitor in _monitors.values) {
      monitor.removeListener(_changed);
    }
    widget.sessions.removeListener(_changed);
    widget.sessions.store.removeListener(_changed);
    _search.dispose();
    super.dispose();
  }

  void _toast(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _ensureProject(WorkspaceDescriptor project) async {
    if (_monitors.containsKey(project.key) ||
        _loadingProjects.contains(project.key)) {
      return;
    }
    setState(() => _loadingProjects.add(project.key));
    try {
      final monitor = await widget.sessions
          .openWorkspace(_device, project.key, project.scope);
      if (!mounted) return;
      _monitors[project.key] = monitor;
      monitor.catalog.replaceRemote(_remoteCatalogs[project.key]?.remote ?? []);
      monitor.addListener(_changed);
    } catch (_) {
      if (!mounted) return;
      _toast(uiText(
          context, '项目加载失败，请重试', 'Could not load the project. Try again.'));
    } finally {
      if (mounted) setState(() => _loadingProjects.remove(project.key));
    }
  }

  Future<void> _openTask(
      WorkspaceDescriptor project, SessionEntry? task) async {
    if (task != null &&
        project.key == widget.workspace.key &&
        task.sessionId == _sessionId) {
      _closeDrawer();
      return;
    }
    _closeDrawer();
    final target = TaskTarget(
        deviceId: _device.id,
        workspaceKey: project.key,
        workspacePath: project.scope['workspacePath'] as String?,
        sessionId: task?.sessionId ?? '',
        title: task?.title ?? uiText(context, '新建任务', 'New task'));
    try {
      await openDeviceWorkspace(
          context, widget.sessions, widget.preferences, _device,
          target: target, workspace: project);
    } catch (_) {
      if (!mounted) return;
      _toast(
          uiText(context, '无法打开任务，请重试', 'Could not open the task. Try again.'));
    }
  }

  void _showPluginStore() {
    if (_pluginOpen) {
      _closePluginStore();
      return;
    }
    _closePanel();
    _pluginCatalog ??= widget.sessions.pluginCatalog(_device.id,
        widget.workspace.key, widget.monitor.bridge, widget.workspace.scope);
    unawaited(_pluginCatalog!.refresh());
    _pluginHistory = LocalHistoryEntry(onRemove: () {
      _pluginHistory = null;
      if (mounted) setState(() => _pluginOpen = false);
    });
    ModalRoute.of(context)?.addLocalHistoryEntry(_pluginHistory!);
    setState(() => _pluginOpen = true);
  }

  void _closePluginStore() {
    _pluginHistory?.remove();
  }

  void _usePlugin(CatalogPlugin plugin) {
    final composer = widget.sessions.composers.obtain(
        transport: widget.monitor.bridge.conversation(widget.workspace.scope),
        deviceId: _device.id,
        workspaceKey: widget.workspace.key);
    final end = composer.input.text.length;
    composer.input.insertReference(
        TextRange(start: end, end: end),
        ComposerReference(
            id: 'plugin:${plugin.id}',
            category: 'plugins',
            label: plugin.name,
            value: plugin.id));
    _closePluginStore();
    unawaited(_openTask(widget.workspace, null));
  }

  Future<void> _sidebarAction(
      SidebarTask entry, SidebarTaskAction action) async {
    final project = entry.project.workspace;
    if (action == SidebarTaskAction.copyId ||
        action == SidebarTaskAction.copyProjectPath) {
      await Clipboard.setData(ClipboardData(
          text: action == SidebarTaskAction.copyId
              ? entry.task.sessionId
              : project.scope['workspacePath'] as String? ?? project.title));
      return;
    }
    await _ensureProject(project);
    final monitor = _monitors[project.key];
    if (monitor == null) throw StateError('workspace unavailable');
    switch (action) {
      case SidebarTaskAction.pin:
        await monitor.setPinned(entry.task, !entry.pinned);
      case SidebarTaskAction.archive:
        await monitor.setArchived(entry.task, true);
      case SidebarTaskAction.unarchive:
        await monitor.setArchived(entry.task, false);
      case SidebarTaskAction.delete:
        await monitor.deleteArchived(entry.task);
        if (_sessionId == entry.task.sessionId &&
            widget.workspace.key == project.key &&
            mounted) {
          await _openTask(project, null);
        }
      case SidebarTaskAction.rename:
        if (mounted) await _renameTask(monitor, entry.task);
      case SidebarTaskAction.unread:
        await monitor.setUnread(entry.task, true);
      case SidebarTaskAction.copyId || SidebarTaskAction.copyProjectPath:
        break;
    }
  }

  void _closeDrawer() {
    final scaffold = Scaffold.maybeOf(context);
    if (scaffold?.isDrawerOpen == true) scaffold!.closeDrawer();
    // The sidebar itself also closes its owning Scaffold before dispatching.
  }

  Future<void> _action(Future<void> Function() run) async {
    try {
      await run();
    } catch (_) {
      if (!mounted) return;
      _toast(uiText(context, '操作失败，请重试', 'Operation failed. Try again.'));
    }
  }

  Future<void> _renameTask(WorkspaceMonitor monitor, SessionEntry task) async {
    final input = TextEditingController(text: task.title);
    final title = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(uiText(context, '重命名任务', 'Rename task')),
                content: TextField(controller: input, autofocus: true),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(uiText(context, '取消', 'Cancel'))),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, input.text.trim()),
                      child: Text(uiText(context, '保存', 'Save')))
                ]));
    Future<void>.delayed(const Duration(milliseconds: 350), input.dispose);
    if (title != null && title.isNotEmpty) {
      await _action(() => monitor.rename(task, title));
    }
  }

  void _showPanel(_WorkPanel panel) {
    if (_panel == panel) {
      _closePanel();
      return;
    }
    if (_panelHistory == null) {
      _panelHistory = LocalHistoryEntry(onRemove: () {
        _panelHistory = null;
        _view.panelOpen = false;
        if (mounted) setState(() => _panel = null);
      });
      ModalRoute.of(context)?.addLocalHistoryEntry(_panelHistory!);
    }
    setState(() {
      _view.panelOpen = true;
      _panel = panel;
      _lastPanel = panel;
    });
  }

  void _closePanel() {
    _view.panelOpen = false;
    final history = _panelHistory;
    _panelHistory = null;
    history?.remove();
    if (mounted) setState(() => _panel = null);
  }

  Future<void> _startSideChat() async {
    if (_sessionId == null || _creatingSide) return;
    final parentId = _sessionId!;
    setState(() => _creatingSide = true);
    try {
      final key = TaskTarget(
              deviceId: _device.id,
              workspaceKey: widget.workspace.key,
              sessionId: parentId,
              title: '')
          .key;
      final cached = widget.sessions.sideChats[key];
      final id = cached ??
          await widget.monitor.bridge
              .conversation(widget.workspace.scope)
              .createSelectionSideSession(parentId);
      widget.sessions.sideChats[key] = id;
      if (mounted && _sessionId == parentId) setState(() => _sideId = id);
    } catch (_) {
      if (!mounted) return;
      _toast(uiText(context, '辅助对话暂时无法打开', 'Could not open side chat'));
    } finally {
      if (mounted) setState(() => _creatingSide = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final saved = widget.sessions.store.devices
        .where((device) => device.id == widget.device.id)
        .firstOrNull;
    final usable = widget.conversationBuilder != null ||
        (saved != null &&
            saved.url == widget.device.url &&
            widget.sessions
                    .monitorFor(widget.device.id, widget.workspace.key) ==
                widget.monitor);
    if (usable && ModalRoute.of(context)?.isCurrent == true) {
      widget.sessions.lastLocations[_device.id] = TaskTarget(
          deviceId: _device.id,
          workspaceKey: widget.workspace.key,
          sessionId: _sessionId ?? '',
          title: _title(context),
          workspacePath: widget.workspace.scope['workspacePath'] as String?);
    }
    final content = usable
        ? (widget.conversationBuilder?.call(context, _sessionId) ??
            ChatPage(
                key: _chatKey,
                session: widget.monitor.bridge,
                scope: widget.workspace.scope,
                workspaceKey: widget.workspace.key,
                deviceId: _device.id,
                drafts: widget.sessions.drafts,
                composerStore: widget.sessions.composers,
                viewStates: widget.sessions.conversationViewStates,
                sessionId: _sessionId,
                title: _title(context),
                workspaceName: widget.workspace.title,
                embedded: true,
                onSessionCreated: (id) {
                  widget.sessions.workspaceViewStates.remove(_viewKey);
                  if (mounted) setState(() => _sessionId = id);
                  widget.sessions.workspaceViewStates[_viewKey] = _view;
                  widget.onSessionCreated?.call(id);
                },
                onStateChanged: (state) {
                  _conversationState = state;
                  if (mounted && _panel != null) setState(() {});
                }))
        : Center(
            child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(uiText(context, '连接已关闭或链接已更新',
                      'The connection is closed or its link has changed')),
                  const SizedBox(height: 16),
                  FilledButton(
                      onPressed: saved == null
                          ? null
                          : () => openDeviceWorkspace(context, widget.sessions,
                              widget.preferences, saved,
                              replace: true),
                      child: Text(uiText(context, '重新连接', 'Reconnect')))
                ])));
    return WorkspaceShellLayout(
        title: _pluginOpen
            ? uiText(context, '插件市场', 'Plugin marketplace')
            : _title(context),
        project: widget.workspace.title,
        sidebarCollapsed: _sidebarCollapsed,
        onSidebarCollapsed: (value) =>
            setState(() => _sidebarCollapsed = value),
        sidebar: _sidebar(context, ink),
        conversation: Stack(fit: StackFit.expand, children: [
          ExcludeFocus(
              excluding: _pluginOpen,
              child: Offstage(offstage: _pluginOpen, child: content)),
          if (_pluginCatalog != null)
            ExcludeFocus(
                excluding: !_pluginOpen,
                child: Offstage(
                    offstage: !_pluginOpen,
                    child: PluginMarketplace(
                        catalog: _pluginCatalog!, onUse: _usePlugin))),
        ]),
        onMore: _pluginOpen ? null : () => _showTaskMenu(context),
        actions: [
          if (_pluginOpen)
            ShellIconButton(
                icon: 'x',
                label: uiText(context, '返回任务', 'Back to task'),
                onPressed: _closePluginStore),
          ShellIconButton(
              icon: 'panel-right',
              label: uiText(context, '工作面板', 'Work panel'),
              selected: _panel != null,
              onPressed: usable && !_pluginOpen
                  ? () {
                      if (_panel != null) {
                        _closePanel();
                      } else {
                        _showPanel(_lastPanel);
                      }
                    }
                  : null)
        ],
        panelOpen: _panel != null,
        panel: usable ? _workPanel(context, ink) : null,
        onClosePanel: _closePanel);
  }

  Widget _sidebar(BuildContext context, InkTokens ink) =>
      Builder(builder: (sidebarContext) {
        void closeDrawer() {
          final scaffold = Scaffold.maybeOf(sidebarContext);
          if (scaffold?.isDrawerOpen == true) scaffold!.closeDrawer();
        }

        final projects = _projects.isEmpty ? [widget.workspace] : _projects;
        final query = _search.text.trim().toLowerCase();
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              _navButton(ink, 'plus', uiText(context, '新建任务', 'New task'), () {
                closeDrawer();
                unawaited(_openTask(widget.workspace, null));
              }),
              _navButton(ink, 'search', uiText(context, '搜索', 'Search'), () {
                setState(() => _searchOpen = !_searchOpen);
                if (_searchOpen) {
                  for (final project in projects) {
                    unawaited(_ensureProject(project));
                  }
                }
              }),
              _navButton(
                  ink, 'blocks', uiText(context, '插件市场', 'Plugin marketplace'),
                  () {
                closeDrawer();
                _showPluginStore();
              }),
              if (_searchOpen)
                Padding(
                    padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                    child: TextField(
                        controller: _search,
                        autofocus: true,
                        decoration: InputDecoration(
                            isDense: true,
                            hintText: uiText(context, '搜索任务…', 'Search tasks…'),
                            border: const OutlineInputBorder()))),
              Expanded(
                  child: TaskNavigation(
                      projects: [
                    for (final project in projects)
                      SidebarProject(
                          project,
                          _monitors[project.key]?.catalog ??
                              _remoteCatalogs.putIfAbsent(project.key,
                                  () => WorkspaceTaskCatalog(project.scope)))
                  ],
                      view: _sidebarView,
                      preferences: widget.preferences,
                      query: query,
                      activeWorkspace: widget.workspace.key,
                      activeTask: _sessionId,
                      connected:
                          widget.sessions.sessionOf(_device.id)?.connected ==
                              true,
                      loading: !widget.monitor.ready,
                      onOpen: (entry) {
                        closeDrawer();
                        return _openTask(entry.project.workspace, entry.task);
                      },
                      onAction: _sidebarAction,
                      onExpand: (project) =>
                          unawaited(_ensureProject(project)))),
              Padding(
                  padding: const EdgeInsets.fromLTRB(10, 8, 10, 0),
                  child: Divider(height: 1, color: ink.border)),
              Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  child: PopupMenuButton<String>(
                      tooltip: uiText(context, '切换设备', 'Switch device'),
                      offset: const Offset(0, -220),
                      constraints:
                          const BoxConstraints(minWidth: 230, maxWidth: 290),
                      onSelected: (id) {
                        closeDrawer();
                        if (id == '@manage') {
                          showDeviceDirectory(
                              context, widget.sessions, widget.preferences);
                        } else if (id != _device.id) {
                          final device = widget.sessions.store.devices
                              .where((device) => device.id == id)
                              .firstOrNull;
                          if (device != null) {
                            unawaited(_action(() => openDeviceWorkspace(context,
                                widget.sessions, widget.preferences, device)));
                          }
                        }
                      },
                      itemBuilder: (context) => [
                            for (final device in widget.sessions.store.devices)
                              PopupMenuItem(
                                  value: device.id,
                                  child: Row(children: [
                                    LucideIcon('monitor',
                                        size: 16, color: ink.subtlest),
                                    const SizedBox(width: 8),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                          Text(device.label,
                                              overflow: TextOverflow.ellipsis),
                                          Text(
                                              deviceConnectionStatus(
                                                  context,
                                                  widget.sessions
                                                      .sessionOf(device.id)),
                                              style: TextStyle(
                                                  fontSize: 11,
                                                  color: ink.subtlest)),
                                        ])),
                                    if (device.id == _device.id)
                                      LucideIcon('check',
                                          size: 14, color: ink.subtlest)
                                  ])),
                            const PopupMenuDivider(),
                            PopupMenuItem(
                                value: '@manage',
                                child: Text(
                                    uiText(context, '管理设备', 'Manage devices')))
                          ],
                      child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 12),
                          child: Row(children: [
                            LucideIcon('monitor',
                                size: 16, color: ink.subtlest),
                            const SizedBox(width: 9),
                            Expanded(
                                child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                  Text(_device.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(fontSize: 13)),
                                  Text(
                                      deviceConnectionStatus(
                                          context,
                                          widget.sessions
                                              .sessionOf(_device.id)),
                                      style: TextStyle(
                                          fontSize: 11, color: ink.subtlest)),
                                ])),
                            LucideIcon('chevrons-up-down',
                                size: 14, color: ink.subtlest)
                          ])))),
              Padding(
                  padding: const EdgeInsets.fromLTRB(12, 0, 8, 10),
                  child: Row(children: [
                    Expanded(
                        child: PopupMenuButton<String>(
                            tooltip: uiText(context, '账户菜单', 'Account menu'),
                            offset: const Offset(0, -190),
                            constraints: const BoxConstraints(
                                minWidth: 200, maxWidth: 260),
                            onSelected: (section) {
                              closeDrawer();
                              showSettingsCenter(
                                  context, widget.sessions, widget.preferences,
                                  section: section);
                            },
                            itemBuilder: (context) => [
                                  PopupMenuItem(
                                      value: 'general',
                                      child: Text(
                                          uiText(context, '语言', 'Language'))),
                                  PopupMenuItem(
                                      value: 'appearance',
                                      child: Text(uiText(
                                          context, '主题与文字', 'Theme and text'))),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                      value: 'notifications',
                                      child: Text(uiText(context, '通知与上岛',
                                          'Task notifications'))),
                                  PopupMenuItem(
                                      value: 'general',
                                      child: Text(
                                          uiText(context, '设置', 'Settings'))),
                                ],
                            child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 8),
                                child: Row(children: [
                                  CircleAvatar(
                                      radius: 13,
                                      backgroundColor: ink.card,
                                      foregroundColor: ink.text,
                                      backgroundImage: _profile?.avatarUrl ==
                                              null
                                          ? null
                                          : NetworkImage(_profile!.avatarUrl!),
                                      onBackgroundImageError:
                                          _profile?.avatarUrl == null
                                              ? null
                                              : (_, __) {},
                                      child: _profile?.avatarUrl == null
                                          ? Text(
                                              (_profile?.name ?? 'Z')
                                                  .characters
                                                  .first,
                                              style:
                                                  const TextStyle(fontSize: 12))
                                          : null),
                                  const SizedBox(width: 8),
                                  Expanded(
                                      child: Text(_profile?.name ?? 'ZCode',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.w500))),
                                ])))),
                    ShellIconButton(
                        icon: 'settings',
                        label: uiText(context, '设置', 'Settings'),
                        onPressed: () {
                          closeDrawer();
                          showSettingsCenter(
                              context, widget.sessions, widget.preferences);
                        }),
                  ])),
            ]);
      });

  Widget _navButton(
          InkTokens ink, String icon, String text, VoidCallback tap) =>
      Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: InkWell(
              onTap: tap,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(children: [
                    LucideIcon(icon, size: 16, color: ink.text),
                    const SizedBox(width: 10),
                    Expanded(
                        child: Text(text,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14)))
                  ]))));

  Future<void> _showTaskMenu(BuildContext context) async {
    final task = _task;
    final action = await showModalBottomSheet<String>(
        context: context,
        showDragHandle: true,
        builder: (context) => SafeArea(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (task != null)
                ListTile(
                    title: Text(uiText(context, '重命名任务', 'Rename task')),
                    onTap: () => Navigator.pop(context, 'rename')),
              ListTile(
                  title: Text(uiText(context, '复制项目路径', 'Copy project path')),
                  onTap: () => Navigator.pop(context, 'path')),
              ListTile(
                  title: Text(uiText(context, '辅助对话', 'Side chat')),
                  onTap: () => Navigator.pop(context, 'side')),
            ])));
    if (!mounted) return;
    if (action == 'rename' && task != null) {
      await _renameTask(widget.monitor, task);
    }
    if (action == 'path') {
      await Clipboard.setData(ClipboardData(
          text: widget.workspace.scope['workspacePath'] as String? ??
              widget.workspace.title));
      if (!context.mounted) return;
      _toast(uiText(context, '项目路径已复制', 'Project path copied'));
    }
    if (action == 'side') _showPanel(_WorkPanel.sideChat);
  }

  Widget _workPanel(BuildContext context, InkTokens ink) => Column(children: [
        Wrap(children: [
          TextButton(
              onPressed: () => setState(() {
                    _panel = _WorkPanel.summary;
                    _lastPanel = _panel!;
                  }),
              child: Text(uiText(context, '任务状态', 'Task status'))),
          TextButton(
              onPressed: () => setState(() {
                    _panel = _WorkPanel.sideChat;
                    _lastPanel = _panel!;
                  }),
              child: Text(uiText(context, '辅助对话', 'Side chat')))
        ]),
        Expanded(
            child: IndexedStack(
                index: _lastPanel == _WorkPanel.sideChat ? 0 : 1,
                children: [
              (_sideId != null
                  ? ChatPage(
                      key: ValueKey(_sideId),
                      session: widget.monitor.bridge,
                      scope: widget.workspace.scope,
                      workspaceKey: widget.workspace.key,
                      deviceId: _device.id,
                      drafts: widget.sessions.drafts,
                      composerStore: widget.sessions.composers,
                      viewStates: widget.sessions.conversationViewStates,
                      sessionId: _sideId,
                      title: uiText(context, '辅助对话', 'Side chat'),
                      embedded: true)
                  : Center(
                      child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: _sessionId == null
                              ? Text(uiText(context, '开始主对话后可打开辅助对话',
                                  'Start the main task before opening side chat'))
                              : FilledButton(
                                  onPressed:
                                      _creatingSide ? null : _startSideChat,
                                  child: Text(_creatingSide
                                      ? uiText(context, '正在打开…', 'Opening…')
                                      : uiText(context, '打开辅助对话',
                                          'Open side chat')))))),
              ListView(padding: const EdgeInsets.all(16), children: [
                Text(_title(context),
                    style: const TextStyle(fontWeight: FontWeight.w500)),
                const SizedBox(height: 16),
                Text(widget.workspace.title,
                    style: TextStyle(color: ink.subtlest)),
                const SizedBox(height: 12),
                Text(_task?.pendingInteraction != null
                    ? uiText(context, '等待你的处理', 'Waiting for your input')
                    : _task?.phase == 'running'
                        ? uiText(context, '任务运行中', 'Task running')
                        : uiText(context, '任务已就绪', 'Task ready')),
                if (_conversationState != null) ...[
                  const SizedBox(height: 18),
                  for (final row in _conversationState!.rows
                      .where((row) => row['kind'] == 'changeSummary'))
                    ConversationChangeSummary(row: row)
                ],
              ])
            ])),
      ]);
}
