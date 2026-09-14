import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../notifications/task_target.dart';
import '../protocol/conversation.dart';
import '../protocol/terminal.dart';
import '../state/app_sessions.dart';
import '../state/coding_plan_upgrade.dart';
import '../state/client_preferences.dart';
import '../state/device_store.dart';
import '../state/file_changes_review.dart';
import '../state/remote_profile.dart';
import '../state/remote_settings.dart';
import '../state/workspace_catalog.dart';
import '../state/workspace_view_state.dart';
import '../state/workspace_search.dart';
import '../state/plugin_catalog.dart';
import '../state/terminal_sessions.dart';
import '../state/composer_input.dart';
import 'chat_page.dart';
import 'command_center.dart';
import 'device_connection_status.dart';
import 'file_changes_review_panel.dart';
import 'git_branch_chip.dart';
import 'navigation.dart';
import 'official_icons.dart';
import 'shell/shell_layout.dart';
import 'shell/task_navigation.dart';
import 'theme.dart';
import 'plugin_marketplace.dart';
import 'mobile/mobile_layout.dart';
import 'terminal_panel.dart';
import 'usage/usage_page.dart';
import 'upgrade_page.dart';
import 'workspace_file_viewer.dart';

BoxConstraints _deviceMenuConstraints(BuildContext context) {
  final media = MediaQuery.of(context);
  final textScale =
      (media.textScaler.scale(14) / 14).clamp(1.0, 2.0).toDouble();
  final safeLeft = math.max(media.padding.left, media.viewPadding.left);
  final safeRight = math.max(media.padding.right, media.viewPadding.right);
  final availableWidth =
      math.max(1.0, media.size.width - safeLeft - safeRight - 16.0);
  final maxWidth = math.min(320.0 * textScale, availableWidth);
  final minWidth = math.min(230.0 * textScale, maxWidth);
  final safeTop = math.max(media.padding.top, media.viewPadding.top);
  final safeBottom = math.max(media.padding.bottom,
      math.max(media.viewPadding.bottom, media.viewInsets.bottom));
  final availableHeight =
      math.max(1.0, media.size.height - safeTop - safeBottom - 16.0);
  return BoxConstraints(
      minWidth: minWidth,
      maxWidth: maxWidth,
      maxHeight: math.min(480.0 * textScale, availableHeight));
}

/// P4-shell deterministic counters (references/optimization/
/// performance-todolist.md): bounded-retention evidence for the per-source
/// Offstage chat page cache.
int workspaceShellChatPagesBuilt = 0;
int workspaceShellRetainedPagesMax = 0;

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
      this.searchSnippet,
      this.searchSnippetIndex,
      this.searchQuery,
      this.searchRequestId,
      this.onSessionCreated,
      this.conversationBuilder});
  final Device device;
  final WorkspaceDescriptor workspace;
  final WorkspaceMonitor monitor;
  final AppSessions sessions;
  final ClientPreferences preferences;
  final String? sessionId;
  final String? initialTitle;
  final String? searchSnippet;
  final int? searchSnippetIndex;
  final String? searchQuery;
  final int? searchRequestId;
  final ValueChanged<String>? onSessionCreated;
  final Widget Function(BuildContext, String?)? conversationBuilder;
  @override
  State<WorkspaceShell> createState() => _WorkspaceShellState();
}

enum _WorkPanel { summary, sideChat, review }

class _WorkspaceShellState extends State<WorkspaceShell> {
  late String? _sessionId;
  late SidebarViewState _sidebarView;
  final _remoteCatalogs = <String, WorkspaceTaskCatalog>{};
  int _seenTaskIndexVersion = -1;
  final _monitors = <String, WorkspaceMonitor>{};
  final _loadingProjects = <String>{};
  late WorkspaceViewState _view;
  int _sourceGeneration = 0;
  bool get _sidebarCollapsed => _view.sidebarCollapsed;
  set _sidebarCollapsed(bool value) => _view.sidebarCollapsed = value;
  _WorkPanel? _panel;
  _WorkPanel get _lastPanel =>
      _WorkPanel.values
          .where((panel) => panel.name == _view.panelTab)
          .firstOrNull ??
      _WorkPanel.summary;
  set _lastPanel(_WorkPanel value) => _view.panelTab = value.name;
  LocalHistoryEntry? _panelHistory;
  bool _terminalOpen = false;
  bool _terminalMaximized = false;
  bool _panelExpanded = false;
  LocalHistoryEntry? _terminalHistory;
  FileChangesReviewController? _reviewController;
  String? _reviewKey;
  String _reviewInitialPath = '';
  RemoteProfile? _profile;
  bool _creatingSide = false;
  int _sideCreationOperation = 0;
  String? _sideId;
  ConversationState? _conversationState;
  final _chatPages = <String, ChatPage>{};
  PluginCatalog? _pluginCatalog;
  bool _pluginOpen = false;
  LocalHistoryEntry? _pluginHistory;
  RemoteSettingsController? _settingsController;

  void _refreshSettingsAfterFrame(RemoteSettingsController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_settingsController, controller)) return;
      unawaited(controller.refresh());
    });
  }

  void _openUsagePage(BuildContext context) {
    final monitor = widget.monitor;
    final transport = monitor.bridge.conversation(monitor.scope);
    // Statistics render from the dedicated plan selection, never from the
    // chat composer's provider (official sidebar usage preference).
    final planSelection = widget.sessions.usagePlanSelectionFor(
        deviceId: monitor.source.deviceId,
        workspaceKey: monitor.source.workspaceKey,
        transport: transport,
        preferences: widget.preferences);
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (context) => UsagePage(
                usage: planSelection.usage,
                planSelection: planSelection,
                onConfigurePlans: () => showSettingsCenter(
                    context, widget.sessions, widget.preferences,
                    remoteMonitor: monitor, section: 'modelProvider'))));
  }

  void _openUpgradePage(BuildContext context) {
    final monitor = widget.monitor;
    final catalog = CodingPlanUpgradeCatalog(
        session: monitor.bridge,
        transport: monitor.bridge.conversation(monitor.scope),
        scopeKey: '${monitor.source.deviceId}|${monitor.source.workspaceKey}');
    Navigator.push(
        context,
        MaterialPageRoute<void>(
            builder: (context) => UpgradePage(catalog: catalog)));
  }

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
    _settingsController = widget.sessions.remoteSettingsFor(
        deviceId: _device.id,
        workspaceKey: widget.workspace.key,
        bridge: widget.monitor.bridge)
      ..addListener(_changed);
    _refreshSettingsAfterFrame(_settingsController!);
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

  Future<void> _loadProfile({int? generation}) async {
    final sourceGeneration = generation ?? _sourceGeneration;
    final monitor = widget.monitor;
    var oauthActive = false;
    try {
      final profile = await RemoteProfile.load(monitor.bridge);
      if (!mounted || sourceGeneration != _sourceGeneration) return;
      setState(() => _profile = profile);
      oauthActive = profile != null;
    } catch (_) {/* The workspace stays usable without account metadata. */}
    try {
      if (!mounted || sourceGeneration != _sourceGeneration) return;
      // Official Root startup migration: after the OAuth state restore the
      // provider family keys are validated once per session; an invalid key
      // is reset to the mode default and a just-reset oauth key may upgrade
      // to the first subscribed team key. Failures keep remote values.
      await migrateProviderFamilySelections(
          session: monitor.bridge, upgradeTeamPlan: oauthActive);
    } catch (_) {/* The official flow only logs this failure. */}
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
  void didUpdateWidget(covariant WorkspaceShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sourceChanged = oldWidget.device.id != widget.device.id ||
        oldWidget.workspace.key != widget.workspace.key ||
        oldWidget.monitor != widget.monitor ||
        oldWidget.sessions != widget.sessions;
    final sessionChanged = oldWidget.sessionId != widget.sessionId;
    // A new search request is forwarded by build without resetting workspace
    // catalogs, pending side-chat work, or the open terminal.
    if (!sourceChanged && !sessionChanged) return;
    final sidebarWasCollapsed = _sidebarCollapsed;
    if (sourceChanged) {
      _sourceGeneration++;
      _sideCreationOperation++;
      _settingsController?.removeListener(_changed);
      // Cache only within one device/workspace source. A complete source
      // switch removes the old ChatPage subtree so its focus and voice
      // controller dispose with the page; drafts/view state remain in stores.
      _chatPages.clear();
      for (final monitor in _monitors.values) {
        monitor.removeListener(_changed);
      }
      _monitors
        ..clear()
        ..[widget.workspace.key] = widget.monitor;
      _remoteCatalogs.clear();
      _loadingProjects.clear();
      _seenTaskIndexVersion = -1;
      widget.monitor.addListener(_changed);
      _settingsController = widget.sessions.remoteSettingsFor(
          deviceId: _device.id,
          workspaceKey: widget.workspace.key,
          bridge: widget.monitor.bridge)
        ..addListener(_changed);
      _refreshSettingsAfterFrame(_settingsController!);
      _pluginHistory?.remove();
      _pluginHistory = null;
      _pluginCatalog?.dispose();
      _pluginCatalog = null;
      _pluginOpen = false;
      _closeTerminalDrawer();
      _profile = null;
    }
    _sessionId = widget.sessionId;
    if (sourceChanged || sessionChanged) {
      _view = widget.sessions.workspaceViewStates
          .putIfAbsent(_viewKey, WorkspaceViewState.new);
      if (!sourceChanged) _view.sidebarCollapsed = sidebarWasCollapsed;
      if (sourceChanged) {
        _sidebarView = widget.sessions.sidebarStates
            .putIfAbsent(_device.id, SidebarViewState.new);
        _sidebarView.expandedProjects.add(widget.workspace.key);
      }
      _reviewController?.dispose();
      _reviewController = null;
      _reviewKey = null;
      _reviewInitialPath = '';
      _conversationState = null;
    }
    if (sourceChanged || sessionChanged) {
      // Invalidate a pending operation when its parent/source changes. Its
      // result may still populate that parent's cache, but must not affect
      // the newly selected pane or its loading indicator.
      _sideCreationOperation++;
    }
    _creatingSide = false;
    final sideKey = TaskTarget(
            deviceId: _device.id,
            workspaceKey: widget.workspace.key,
            sessionId: _sessionId ?? '',
            title: '')
        .key;
    _sideId = widget.sessions.sideChats[sideKey];
    if (sourceChanged) _syncRemoteIndex();
    if (sourceChanged && widget.conversationBuilder == null) {
      unawaited(_loadProfile(generation: _sourceGeneration));
    }
  }

  @override
  void dispose() {
    _reviewController?.dispose();
    for (final monitor in _monitors.values) {
      monitor.removeListener(_changed);
    }
    _settingsController?.removeListener(_changed);
    widget.sessions.removeListener(_changed);
    widget.sessions.store.removeListener(_changed);
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
    final sourceGeneration = _sourceGeneration;
    final deviceId = _device.id;
    setState(() => _loadingProjects.add(project.key));
    try {
      final monitor = await widget.sessions
          .openWorkspace(_device, project.key, project.scope);
      if (!mounted ||
          sourceGeneration != _sourceGeneration ||
          deviceId != _device.id) {
        monitor.dispose();
        return;
      }
      _monitors[project.key] = monitor;
      monitor.catalog.replaceRemote(_remoteCatalogs[project.key]?.remote ?? []);
      monitor.addListener(_changed);
    } catch (_) {
      if (!mounted) return;
      _toast(uiText(
          context, '项目加载失败，请重试', 'Could not load the project. Try again.'));
    } finally {
      if (mounted && sourceGeneration == _sourceGeneration) {
        setState(() => _loadingProjects.remove(project.key));
      }
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
    // E1.3: invalidate composer plugin reference candidates after marketplace
    // closes, so enable/disable/uninstall changes are reflected on next open.
    final composer = widget.sessions.composers.obtain(
        transport: widget.monitor.bridge.conversation(widget.workspace.scope),
        deviceId: _device.id,
        workspaceKey: widget.workspace.key);
    composer.references.invalidateCategory('plugins');
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
    _panelExpanded = false;
    final history = _panelHistory;
    _panelHistory = null;
    history?.remove();
    if (mounted) setState(() => _panel = null);
  }

  /// Official remote keeps terminals in a bottom drawer with its own
  /// predictive-back entry, independent from the side work panel.
  void _toggleTerminal() {
    if (_terminalOpen) {
      _closeTerminalDrawer();
      return;
    }
    _terminalHistory ??= LocalHistoryEntry(onRemove: () {
      _terminalHistory = null;
      if (mounted) setState(() => _terminalOpen = false);
    });
    ModalRoute.of(context)?.addLocalHistoryEntry(_terminalHistory!);
    setState(() => _terminalOpen = true);
  }

  void _closeTerminalDrawer() {
    final history = _terminalHistory;
    _terminalHistory = null;
    history?.remove();
    if (mounted) setState(() => _terminalOpen = false);
  }

  TerminalWorkspaceSessions _terminalWorkspace() =>
      widget.sessions.terminalSessions.workspace(
        deviceId: _device.id,
        workspaceKey: widget.workspace.key,
        client: TerminalClient(session: widget.monitor.bridge),
        cwd: widget.workspace.scope['workspacePath'] as String? ??
            widget.workspace.title,
      );

  /// Official diff review opens as a side panel whose controller is owned by
  /// the shell, so tabs survive conversation row recycling.
  void _openFileReview(Map<String, dynamic> row, String path) {
    if (path.isEmpty) return;
    final key =
        '${row['rowId'] ?? 0}|${row['entityId']}|${_device.id}|${widget.workspace.key}|${_sessionId ?? ''}';
    if (_reviewKey != key || _reviewController == null) {
      _reviewController?.dispose();
      _reviewKey = key;
      _reviewController = FileChangesReviewController(
        transport: widget.monitor.bridge.conversation(widget.workspace.scope),
        scope: FileChangesScope(
          deviceId: _device.id,
          workspaceKey: widget.workspace.key,
          sessionId: _sessionId ?? '',
          rowId: row['rowId'] as int? ?? 0,
          entityId: row['entityId'],
        ),
        revision: () => _conversationState?.revision ?? 0,
        logEpoch: () => _conversationState?.logEpoch,
      );
    }
    _reviewInitialPath = path;
    if (_panel != _WorkPanel.review) {
      _showPanel(_WorkPanel.review);
    } else {
      setState(() {});
    }
  }

  List<SidebarProject> _commandProjects() => [
        for (final project
            in _projects.isEmpty ? [widget.workspace] : _projects)
          SidebarProject(
              project,
              _monitors[project.key]?.catalog ??
                  _remoteCatalogs.putIfAbsent(
                      project.key, () => WorkspaceTaskCatalog(project.scope)))
      ];

  void _openCommandCenter(BuildContext context) {
    final search = WorkspaceSearchController(
        transport: widget.monitor.bridge.conversation(widget.workspace.scope),
        currentWorkspaceKey: widget.workspace.key,
        scopes: [
          for (final project
              in _projects.isEmpty ? [widget.workspace] : _projects)
            WorkspaceSearchScope(
                workspaceKey: project.key,
                title: project.title,
                scope: project.scope),
        ],
        currentTaskId: _sessionId);
    unawaited(() async {
      try {
        await showCommandCenter(
          context,
          search: search,
          actions: CommandCenterActions(
            newTask: () => unawaited(_openTask(widget.workspace, null)),
            openWorkspace: () => showDeviceDirectory(
                context, widget.sessions, widget.preferences),
            openSettings: () => showSettingsCenter(
                context, widget.sessions, widget.preferences,
                remoteMonitor: widget.monitor),
            toggleSidebar: () =>
                setState(() => _sidebarCollapsed = !_sidebarCollapsed),
            toggleTerminal: () => _toggleTerminal(),
            addTerminalTab: () {
              if (!_terminalOpen) _toggleTerminal();
              _terminalWorkspace().add();
            },
            openTask: (entry) =>
                unawaited(_openTask(entry.project.workspace, entry.task)),
            openSearchResult: (result) => unawaited(_openSearchResult(result)),
          ),
          tasks: commandCenterTasks(_commandProjects()),
          activeTaskId: _sessionId,
          changes: commandCenterChangesFromRows(
              _conversationState?.rows ?? const []),
        );
      } finally {
        search.dispose();
      }
    }());
  }

  Future<void> _openSearchResult(WorkspaceSearchResult result) async {
    if (result.kind == WorkspaceSearchResultKind.file) {
      final project = _projects
          .where((project) => project.key == result.workspaceKey)
          .firstOrNull;
      if (project == null || result.filePath == null) return;
      await _ensureProject(project);
      final monitor = _monitors[project.key];
      final root = project.scope['workspacePath'] as String?;
      if (monitor == null || root == null || root.isEmpty) return;
      final relative = result.filePath!;
      final path = root.endsWith('/') || root.endsWith('\\')
          ? '$root$relative'
          : '$root/${relative.replaceAll('\\', '/')}';
      if (!mounted) return;
      await showDialog<void>(
          context: context,
          builder: (_) => WorkspaceFileViewer(
              transport: monitor.bridge.conversation(project.scope),
              path: path,
              title: relative));
      return;
    }
    final project = _projects
        .where((project) => project.key == result.workspaceKey)
        .firstOrNull;
    if (project == null || result.sessionId == null) return;
    final target = TaskTarget(
        deviceId: _device.id,
        workspaceKey: project.key,
        workspacePath: project.scope['workspacePath'] as String?,
        sessionId: result.sessionId!,
        title: result.title);
    await openDeviceWorkspace(
        context, widget.sessions, widget.preferences, _device,
        target: target,
        workspace: project,
        searchSnippet: result.snippet,
        searchSnippetIndex: result.snippetIndex,
        searchQuery: result.query);
  }

  Future<void> _startSideChat() async {
    if (_sessionId == null || _creatingSide) return;
    final parentId = _sessionId!;
    final sourceGeneration = _sourceGeneration;
    final operation = ++_sideCreationOperation;
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
      // Keep a completed side id for its own parent even if the user has
      // already switched to another parent in the same device/workspace.
      // The operation token below still prevents this late result from
      // changing the active pane or loading indicator.
      if (sourceGeneration == _sourceGeneration) {
        widget.sessions.sideChats[key] = id;
      }
      if (!mounted ||
          sourceGeneration != _sourceGeneration ||
          operation != _sideCreationOperation) {
        return;
      }
      if (mounted && _sessionId == parentId) {
        setState(() => _sideId = id);
      }
    } catch (_) {
      if (!mounted ||
          sourceGeneration != _sourceGeneration ||
          operation != _sideCreationOperation) {
        return;
      }
      _toast(uiText(context, '辅助对话暂时无法打开', 'Could not open side chat'));
    } finally {
      if (mounted &&
          sourceGeneration == _sourceGeneration &&
          operation == _sideCreationOperation) {
        setState(() => _creatingSide = false);
      }
    }
  }

  Widget _conversationForSource(BuildContext context) {
    final sourceKey = '${_device.id}|${widget.workspace.key}';
    final page = ChatPage(
        key: ValueKey('chat:$sourceKey'),
        session: widget.monitor.bridge,
        deviceSession: widget.sessions.sessionOf(_device.id),
        onPairAgain: () async =>
            showDeviceDirectory(context, widget.sessions, widget.preferences),
        scope: widget.workspace.scope,
        workspaceKey: widget.workspace.key,
        deviceId: _device.id,
        drafts: widget.sessions.drafts,
         composerStore: widget.sessions.composers,
         settingsController: _settingsController,
        viewStates: widget.sessions.conversationViewStates,
        sessionId: _sessionId,
        searchSnippet: widget.searchSnippet,
        searchSnippetIndex: widget.searchSnippetIndex,
        searchQuery: widget.searchQuery,
        searchRequestId: widget.searchRequestId,
        title: _title(context),
        workspaceName: widget.workspace.title,
        embedded: true,
        onSessionCreated: (id) {
          if (sourceKey != '${_device.id}|${widget.workspace.key}') return;
          widget.sessions.workspaceViewStates.remove(_viewKey);
          if (mounted) setState(() => _sessionId = id);
          widget.sessions.workspaceViewStates[_viewKey] = _view;
          widget.onSessionCreated?.call(id);
        },
        onStateChanged: (state) {
          if (sourceKey != '${_device.id}|${widget.workspace.key}') return;
          _conversationState = state;
          if (mounted && _panel != null) setState(() {});
        },
        onOpenHooks: () => showSettingsCenter(
            context, widget.sessions, widget.preferences,
            remoteMonitor: widget.monitor, section: 'hooks'),
        onOpenModels: () => showSettingsCenter(
            context, widget.sessions, widget.preferences,
            remoteMonitor: widget.monitor, section: 'modelProvider'));
    _chatPages[sourceKey] = page;
    workspaceShellChatPagesBuilt++;
    if (_chatPages.length > workspaceShellRetainedPagesMax) {
      workspaceShellRetainedPagesMax = _chatPages.length;
    }
    final keys = _chatPages.keys.toList();
    return Stack(fit: StackFit.expand, children: [
      for (final key in keys)
        Offstage(offstage: key != sourceKey, child: _chatPages[key]!)
    ]);
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
            _conversationForSource(context))
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
    // Compact phones collapse the header to navigation + more; the
    // low-frequency controls move into the labelled task menu with their
    // active state, instead of a dense icon row.
    final compact = MobileLayout.isCompact(
        MediaQuery.sizeOf(context).width - MediaQuery.paddingOf(context).horizontal,
        MediaQuery.textScalerOf(context));
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () =>
            _openCommandCenter(context),
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () =>
            unawaited(_openTask(widget.workspace, null)),
        const SingleActivator(LogicalKeyboardKey.keyB, control: true): () =>
            setState(() => _sidebarCollapsed = !_sidebarCollapsed),
        const SingleActivator(LogicalKeyboardKey.keyJ, control: true): () =>
            _toggleTerminal(),
      },
      child: Focus(
        autofocus: true,
        skipTraversal: true,
        child: WorkspaceShellLayout(
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
                child: Offstage(
                    offstage: _pluginOpen,
                    child: FileChangesReviewHost(
                        openReview: _openFileReview, child: content))),
            if (_pluginCatalog != null)
              ExcludeFocus(
                  excluding: !_pluginOpen,
                  child: Offstage(
                      offstage: !_pluginOpen,
                      child: PluginMarketplace(
                          catalog: _pluginCatalog!, onUse: _usePlugin))),
          ]),
          onMore: _pluginOpen
              ? null
              : () => _showTaskMenu(context,
                  compact: compact, usable: usable),
          actions: [
            if (usable && !_pluginOpen && !compact)
              GitBranchChip(
                session: widget.monitor.bridge,
                scope: widget.workspace.scope,
              ),
            if (_pluginOpen)
              ShellIconButton(
                  icon: 'x',
                  label: uiText(context, '返回任务', 'Back to task'),
                  onPressed: _closePluginStore),
            if (usable && !_pluginOpen && !compact)
              ShellIconButton(
                  icon: 'square-terminal',
                  label: uiText(context, '切换终端', 'Toggle terminal'),
                  selected: _terminalOpen,
                  onPressed: _toggleTerminal),
            if (!compact)
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
          panelExpanded: _panel == _WorkPanel.review && _panelExpanded,
          panel: usable ? _workPanel(context, ink) : null,
          onClosePanel: _closePanel,
          bottomPanel: usable ? _terminalDrawer(context) : null,
          bottomPanelOpen: _terminalOpen,
          bottomPanelFullHeight: _terminalOpen && _terminalMaximized,
          onCloseBottomPanel: _closeTerminalDrawer,
        ),
      ),
    );
  }

  Widget _sidebar(BuildContext context, InkTokens ink) =>
      Builder(builder: (sidebarContext) {
        void closeDrawer() {
          final scaffold = Scaffold.maybeOf(sidebarContext);
          if (scaffold?.isDrawerOpen == true) scaffold!.closeDrawer();
        }

        final projects = _projects.isEmpty ? [widget.workspace] : _projects;
        const query = '';
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 8),
              _navButton(ink, 'plus', uiText(context, '新建任务', 'New task'), () {
                closeDrawer();
                unawaited(_openTask(widget.workspace, null));
              }),
              _navButton(ink, 'search', uiText(context, '搜索', 'Search'), () {
                closeDrawer();
                _openCommandCenter(context);
              }),
              _navButton(
                  ink, 'blocks', uiText(context, '插件市场', 'Plugin marketplace'),
                  () {
                closeDrawer();
                _showPluginStore();
              }),
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
                      // PopupMenuButton resolves the current RenderBox into
                      // the overlay at open/layout time. Let its under/over
                      // placement choose the available side instead of
                      // applying a fixed negative offset that overflows on
                      // short screens and with large text.
                      position: PopupMenuPosition.under,
                      offset: Offset.zero,
                      constraints: _deviceMenuConstraints(context),
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
                              if (section == 'usage') {
                                _openUsagePage(context);
                                return;
                              }
                              if (section == 'logout') {
                                // Official remote-control account menu has
                                // no login entry and its logout label is
                                // 断开连接 (E2.1 evidence): disconnect the
                                // current remote session and return to the
                                // device page. Desktop OAuth login stays
                                // out of scope for remote control.
                                widget.sessions.disconnect(_device.id);
                                return;
                              }
                              if (section == 'upgrade') {
                                _openUpgradePage(context);
                                return;
                              }
                              showSettingsCenter(
                                  context, widget.sessions, widget.preferences,
                                  section: section,
                                  remoteMonitor: widget.monitor);
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
                                  // Usage entry (official AOt component: usage
                                  // click always visible when account scope exists).
                                  PopupMenuItem(
                                      value: 'usage',
                                      child: Text(
                                          uiText(context, '使用统计', 'Usage'))),
                                  if (_profile != null)
                                    PopupMenuItem(
                                        value: 'upgrade',
                                        child: Text(
                                            uiText(context, '升级', 'Upgrade'))),
                                  const PopupMenuDivider(),
                                  PopupMenuItem(
                                      value: 'notifications',
                                      child: Text(uiText(context, '通知与上岛',
                                          'Task notifications'))),
                                  PopupMenuItem(
                                      value: 'general',
                                      child: Text(
                                          uiText(context, '设置', 'Settings'))),
                                  // Official remote-control menu: only the
                                  // disconnect entry (E2.1 evidence, the
                                  // 断开连接 label is the official logout
                                  // action); desktop OAuth login is not
                                  // applicable to remote control.
                                  PopupMenuItem(
                                      value: 'logout',
                                      child: Text(uiText(
                                          context, '断开连接', 'Disconnect'))),
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
                              context, widget.sessions, widget.preferences,
                              remoteMonitor: widget.monitor);
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

  Future<void> _showTaskMenu(BuildContext context,
      {required bool compact, required bool usable}) async {
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
              if (compact && usable) ...[
                ListTile(
                    key: const ValueKey('task-menu-terminal'),
                    title: Text(uiText(context, '切换终端', 'Toggle terminal') +
                        (_terminalOpen
                            ? uiText(context, '（已打开）', ' (open)')
                            : uiText(context, '（已关闭）', ' (closed)'))),
                    onTap: () => Navigator.pop(context, 'terminal')),
                ListTile(
                    key: const ValueKey('task-menu-panel'),
                    title: Text(uiText(context, '工作面板', 'Work panel') +
                        (_panel != null
                            ? uiText(context, '（打开）', ' (open)')
                            : uiText(context, '（关闭）', ' (closed)'))),
                    onTap: () => Navigator.pop(context, 'panel')),
              ],
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
    if (action == 'terminal') _toggleTerminal();
    if (action == 'panel') {
      if (_panel != null) {
        _closePanel();
      } else {
        _showPanel(_lastPanel);
      }
    }
  }

  Widget _workPanel(BuildContext context, InkTokens ink) {
    if (_panel == _WorkPanel.review) {
      final controller = _reviewController;
      if (controller != null) {
        return FileChangesReviewPanel(
          controller: controller,
          initialPath: _reviewInitialPath,
          onLastTabClosed: _closePanel,
          expanded: _panelExpanded,
          onToggleExpanded: (value) => setState(() => _panelExpanded = value),
        );
      }
      // Restored from persisted state without row context: summary instead.
      _panel = _WorkPanel.summary;
    }
    return Column(children: [
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
            child: Text(uiText(context, '辅助对话', 'Side chat'))),
      ]),
      Expanded(
          child: IndexedStack(
              index: switch (_panel) {
                _WorkPanel.sideChat => 0,
                _WorkPanel.summary => 1,
                _ => 1,
              },
              children: [
            (_sideId != null
                ? ChatPage(
                    key: ValueKey(_sideId),
                    session: widget.monitor.bridge,
                    deviceSession: widget.sessions.sessionOf(_device.id),
                    onPairAgain: () async => showDeviceDirectory(
                        context, widget.sessions, widget.preferences),
                    scope: widget.workspace.scope,
                    workspaceKey: widget.workspace.key,
                    deviceId: _device.id,
                    drafts: widget.sessions.drafts,
                    composerStore: widget.sessions.composers,
                    settingsController: _settingsController,
                    viewStates: widget.sessions.conversationViewStates,
                    sessionId: _sideId,
                    title: uiText(context, '辅助对话', 'Side chat'),
                    embedded: true,
                    isSideChat: true,
                    onOpenHooks: () => showSettingsCenter(
                        context, widget.sessions, widget.preferences,
                        remoteMonitor: widget.monitor, section: 'hooks'),
                    onOpenModels: () => showSettingsCenter(
                        context, widget.sessions, widget.preferences,
                        remoteMonitor: widget.monitor,
                        section: 'modelProvider'))
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
                for (final row in _summaryRows())
                  ConversationChangeSummary(
                    key: ValueKey('summary-${row['rowId'] ?? row['entityId']}'),
                    row: row,
                    reviewCacheVersion:
                        '${_conversationState!.logEpoch}|${row['state']}|${row['fileChanges']}',
                    createReview: _createSummaryReview,
                    onOpenReview: (path) => _openFileReview(row, path),
                  )
              ],
            ]),
          ])),
    ]);
  }

  List<Map<String, dynamic>> _summaryRows() {
    return conversationFileChangeSummaryRows(
        _conversationState?.rows ?? const <Map<String, dynamic>>[]);
  }

  FileChangesReviewController _createSummaryReview(
      Map<String, dynamic> row) {
    return FileChangesReviewController(
      transport: widget.monitor.bridge.conversation(widget.workspace.scope),
      scope: FileChangesScope(
        deviceId: _device.id,
        workspaceKey: widget.workspace.key,
        sessionId: _sessionId ?? '',
        rowId: row['rowId'] as int? ?? 0,
        entityId: row['entityId'],
      ),
      revision: () => _conversationState?.revision ?? 0,
      logEpoch: () => _conversationState?.logEpoch,
    );
  }

  Widget _terminalDrawer(BuildContext context) => TerminalDrawer(
        client: TerminalClient(session: widget.monitor.bridge),
        cwd: widget.workspace.scope['workspacePath'] as String? ??
            widget.workspace.title,
        visible: _terminalOpen,
        workspace: _terminalWorkspace(),
        maximized: _terminalMaximized,
        onToggleMaximize: () =>
            setState(() => _terminalMaximized = !_terminalMaximized),
        onCloseDrawer: _closeTerminalDrawer,
      );
}
