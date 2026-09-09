import 'package:flutter/material.dart';
import '../notifications/task_target.dart';
import '../state/app_sessions.dart';
import '../state/client_preferences.dart';
import '../state/device_store.dart';
import '../state/workspace_catalog.dart';
import 'device_directory.dart';
import 'settings_center_page.dart';
import 'workspace_shell.dart';

final _workspaceRoutes = Expando<List<_WorkspaceRoute>>();

class _WorkspaceRoute extends MaterialPageRoute<void> {
  _WorkspaceRoute(
      {required this.deviceId,
      required this.workspaceKey,
      required this.monitor,
      required this.sessionId,
      required super.builder});
  final String deviceId;
  final String workspaceKey;
  final WorkspaceMonitor monitor;
  String? sessionId;
}

Future<void> openDeviceWorkspace(BuildContext context, AppSessions sessions,
    ClientPreferences preferences, Device device,
    {TaskTarget? target,
    WorkspaceDescriptor? workspace,
    bool replace = false}) async {
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
      deviceId: device.id,
      workspaceKey: chosen.key,
      monitor: monitor,
      sessionId: id?.isNotEmpty == true ? id : null,
      builder: (_) => WorkspaceShell(
          device: device,
          workspace: chosen,
          monitor: monitor,
          sessions: sessions,
          preferences: preferences,
          sessionId: id?.isNotEmpty == true ? id : null,
          onSessionCreated: (value) => page.sessionId = value,
          initialTitle:
              previous?.workspaceKey == chosen.key ? previous?.title : null));
  await sessions.store.touch(device.id);
  if (!context.mounted ||
      !sessions.navigationIsCurrent(generation) ||
      route?.isCurrent == false ||
      navigator.userGestureInProgress) {
    return;
  }
  if (existing != null) {
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

void showSettingsCenter(
    BuildContext context, AppSessions sessions, ClientPreferences preferences,
    {String section = 'general'}) {
  sessions.beginNavigation();
  Navigator.push(
      context,
      MaterialPageRoute<void>(
          builder: (context) => SettingsCenterPage(
              preferences: preferences,
              sessions: sessions,
              initialSection: section,
              onManageDevices: () =>
                  showDeviceDirectory(context, sessions, preferences))));
}
