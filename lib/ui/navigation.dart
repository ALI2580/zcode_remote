import 'package:flutter/material.dart';
import '../notifications/task_target.dart';
import '../state/app_sessions.dart';
import '../state/client_preferences.dart';
import '../state/device_store.dart';
import '../state/workspace_catalog.dart';
import 'device_directory.dart';
import 'settings_center_page.dart';
import 'settings_navigation_result.dart';
import 'workspace_shell.dart';

final _workspaceRoutes = Expando<List<_WorkspaceRoute>>();
int _nextSearchRequestId = 0;

class _WorkspaceTarget {
  const _WorkspaceTarget({
    required this.device,
    required this.workspace,
    required this.monitor,
    required this.sessionId,
    this.initialTitle,
    this.searchSnippet,
    this.searchSnippetIndex,
    this.searchQuery,
    this.searchRequestId,
  });

  final Device device;
  final WorkspaceDescriptor workspace;
  final WorkspaceMonitor monitor;
  final String? sessionId;
  final String? initialTitle;
  final String? searchSnippet;
  final int? searchSnippetIndex;
  final String? searchQuery;
  final int? searchRequestId;
}

class _WorkspaceRoute extends MaterialPageRoute<void> {
  _WorkspaceRoute({required _WorkspaceTarget target, required super.builder})
      : target = ValueNotifier(target);
  final ValueNotifier<_WorkspaceTarget> target;
  String get deviceId => target.value.device.id;
  String get workspaceKey => target.value.workspace.key;
  WorkspaceMonitor get monitor => target.value.monitor;
  String? get sessionId => target.value.sessionId;

  void updateTarget(_WorkspaceTarget value) => target.value = value;

  @override
  void dispose() {
    target.dispose();
    super.dispose();
  }
}

Future<void> openDeviceWorkspace(BuildContext context, AppSessions sessions,
    ClientPreferences preferences, Device device,
    {TaskTarget? target,
    WorkspaceDescriptor? workspace,
    String? searchSnippet,
    int? searchSnippetIndex,
    String? searchQuery,
    bool replace = false,
    bool preserveCaller = false}) async {
  final generation = sessions.beginNavigation();
  final navigator = Navigator.of(context);
  final route = ModalRoute.of(context);
  await sessions.loadRecovery();
  if (!context.mounted || !sessions.navigationIsCurrent(generation)) return;
  final session = sessions.sessionFor(device);
  await session.connect();
  if (!context.mounted ||
      !sessions.navigationIsCurrent(generation) ||
      route?.isCurrent == false) {
    return;
  }
  final workspaces = [
    for (final entry in session.workspaces)
      if (WorkspaceDescriptor.parse(entry) case final WorkspaceDescriptor item)
        item
  ];
  final previous = target ?? sessions.lastLocations[device.id];
  final preferredKey =
      workspace?.key ?? previous?.workspaceKey ?? session.initialWorkspaceKey;
  final chosen = workspace ??
      workspaces.where((entry) => entry.key == preferredKey).firstOrNull ??
      workspaces.firstOrNull;
  if (chosen == null) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(uiText(
            context, '桌面暂时没有打开的工作区', 'No workspace is open on the desktop'))));
    return;
  }
  final monitor =
      await sessions.openWorkspace(device, chosen.key, chosen.scope);
  if (!context.mounted ||
      !sessions.navigationIsCurrent(generation) ||
      route?.isCurrent == false ||
      navigator.userGestureInProgress) {
    return;
  }
  final id = previous?.workspaceKey == chosen.key
      ? previous?.sessionId
      : chosen.key == session.initialWorkspaceKey
          ? session.initialTaskId
          : null;
  final nextTarget = _WorkspaceTarget(
      device: device,
      workspace: chosen,
      monitor: monitor,
      sessionId: id?.isNotEmpty == true ? id : null,
      initialTitle:
          previous?.workspaceKey == chosen.key ? previous?.title : null,
      searchSnippet: searchSnippet,
      searchSnippetIndex: searchSnippetIndex,
      searchQuery: searchQuery,
      searchRequestId: (searchQuery?.trim().isNotEmpty == true ||
              searchSnippet?.trim().isNotEmpty == true)
          ? ++_nextSearchRequestId
          : null);
  if (_canSwitchInline(context) && route is _WorkspaceRoute) {
    await sessions.store.touch(device.id);
    if (!context.mounted ||
        !sessions.navigationIsCurrent(generation) ||
        route.isCurrent != true ||
        navigator.userGestureInProgress) {
      return;
    }
    route.updateTarget(nextTarget);
    return;
  }
  final routes = _workspaceRoutes[navigator] ??= [];
  final existing = routes
      .where((page) =>
          page.isActive &&
          page.deviceId == device.id &&
          page.workspaceKey == chosen.key &&
          page.sessionId == (id?.isNotEmpty == true ? id : null) &&
          identical(page.monitor, monitor))
      .firstOrNull;
  late final _WorkspaceRoute page;
  page = _WorkspaceRoute(
      target: nextTarget,
      builder: (_) => ValueListenableBuilder<_WorkspaceTarget>(
          valueListenable: page.target,
          builder: (context, value, _) => WorkspaceShell(
              device: value.device,
              workspace: value.workspace,
              monitor: value.monitor,
              sessions: sessions,
              preferences: preferences,
              sessionId: value.sessionId,
              searchSnippet: value.searchSnippet,
              searchSnippetIndex: value.searchSnippetIndex,
              searchQuery: value.searchQuery,
              searchRequestId: value.searchRequestId,
              onSessionCreated: (sessionId) {
                if (!identical(page.target.value, value)) return;
                page.updateTarget(_WorkspaceTarget(
                    device: page.target.value.device,
                    workspace: page.target.value.workspace,
                    monitor: page.target.value.monitor,
                    sessionId: sessionId,
                    initialTitle: page.target.value.initialTitle,
                    searchSnippet: page.target.value.searchSnippet,
                    searchSnippetIndex: page.target.value.searchSnippetIndex,
                    searchQuery: page.target.value.searchQuery,
                    searchRequestId: page.target.value.searchRequestId));
              },
              initialTitle: value.initialTitle)));
  await sessions.store.touch(device.id);
  if (!context.mounted ||
      !sessions.navigationIsCurrent(generation) ||
      route?.isCurrent == false ||
      navigator.userGestureInProgress) {
    return;
  }
  if (existing != null && !preserveCaller) {
    navigator.popUntil((route) => identical(route, existing));
    return;
  }
  routes.add(page);
  page.popped.then((_) => routes.remove(page));
  if (replace) {
    navigator.pushReplacement(page);
  } else {
    navigator.push(page);
  }
}

bool _canSwitchInline(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= 640;

void showDeviceDirectory(
    BuildContext context, AppSessions sessions, ClientPreferences preferences) {
  sessions.beginNavigation();
  Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (context) => Scaffold(
              appBar: AppBar(title: Text(uiText(context, '设备', 'Devices'))),
              body: SafeArea(
                  top: false,
                  child: DeviceDirectory(
                      store: sessions.store,
                      sessions: sessions,
                      onOpen: (device) => openDeviceWorkspace(
                          context, sessions, preferences, device,
                          replace: true),
                      onSettings: () => showSettingsCenter(
                          context, sessions, preferences))))));
}

Future<void> showSettingsCenter(
    BuildContext context, AppSessions sessions, ClientPreferences preferences,
    {WorkspaceMonitor? remoteMonitor, String section = 'general'}) {
  sessions.beginNavigation();
  final result = Navigator.push<SettingsNavigationResult>(
      context,
      MaterialPageRoute<SettingsNavigationResult>(
          builder: (context) => SettingsCenterPage(
              preferences: preferences,
              sessions: sessions,
              remoteMonitor: remoteMonitor,
              initialSection: section,
              onOpenDevice: (device) => openDeviceWorkspace(
                  context, sessions, preferences, device, preserveCaller: true),
              onManageDevices: () =>
                  showDeviceDirectory(context, sessions, preferences))));
  return result.then((request) async {
    if (request == null || !context.mounted) return;
    final device = sessions.store.devices
        .where((item) => item.id == request.target.deviceId)
        .firstOrNull;
    if (device == null) return;
    await openDeviceWorkspace(context, sessions, preferences, device,
        target: request.target);
  });
}
