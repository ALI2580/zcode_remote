import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';

import '../notifications/task_notification_controller.dart';
import '../notifications/task_progress.dart';
import '../notifications/task_target.dart';
import '../protocol/conversation.dart';
import '../protocol/channel_client.dart';
import '../protocol/zemote_client.dart';
import 'device_session.dart';
import 'device_store.dart';
import 'workspace_catalog.dart';
import 'conversation_view_state.dart';
import 'workspace_view_state.dart';
import 'composer_store.dart';
import 'composer_controller.dart';
import 'plugin_catalog.dart';
import 'recovery_collections.dart';
import 'recovery_journal.dart';
import '../attachments/attachment_picker.dart';
import 'composer_attachments.dart';

/// App-owned connections survive route pops and device switches.
class AppSessions extends ChangeNotifier with WidgetsBindingObserver {
  AppSessions(
      {required this.store,
      this.recovery,
      Future<PickedAttachment> Function(Map<String, dynamic>)?
          restoreAttachment,
      TaskNotificationController? notifications,
      DeviceSession Function(Device)? sessionFactory})
      : notifications = notifications ?? TaskNotificationController(),
        _sessionFactory =
            sessionFactory ?? ((device) => DeviceSession(device.params!)),
        _restoreAttachment = restoreAttachment ?? restorePickedAttachment {
    _knownDeviceIds.addAll(store.devices.map((d) => d.id));
    WidgetsBinding.instance.addObserver(this);
    store.addListener(_onDevicesChanged);
    recovery?.capture = _recoverySnapshot;
    recovery?.addListener(_changed);
  }
  final DeviceStore store;
  final RecoveryJournal? recovery;
  final Future<PickedAttachment> Function(Map<String, dynamic>)
      _restoreAttachment;
  Future<void>? _loadingRecovery;
  bool _hydrating = false;
  final _knownDeviceIds = <String>{};
  final _forgottenDeviceIds = <String>{};
  bool _forgottenScope(String key) {
    try {
      final parts = jsonDecode(key);
      return parts is List &&
          parts.isNotEmpty &&
          _forgottenDeviceIds.contains(parts.first);
    } catch (_) {
      return false;
    }
  }

  final TaskNotificationController notifications;
  final DeviceSession Function(Device) _sessionFactory;
  final _sessions = <String, DeviceSession>{};
  final _urls = <String, String>{};
  final _monitors = <String, WorkspaceMonitor>{};
  late final drafts = RecoveryMap<String, String>(_saveRecovery);
  late final lastLocations = RecoveryMap<String, TaskTarget>(_saveRecovery);
  late final conversationViewStates =
      RecoveryMap<String, ConversationViewState>(_saveRecovery,
          added: (value) => value.onChanged = _saveRecovery);
  late final workspaceViewStates = RecoveryMap<String, WorkspaceViewState>(
      _saveRecovery,
      added: (value) => value.onChanged = _saveRecovery);
  late final sideChats = RecoveryMap<String, String>(_saveRecovery);
  late final sidebarStates = RecoveryMap<String, SidebarViewState>(
      _saveRecovery,
      added: (value) => value.onChanged = _saveRecovery);
  final _pluginCatalogs = <(String, String), PluginCatalog>{};
  PluginCatalog pluginCatalog(String deviceId, String workspace,
          BridgeSession bridge, Map<String, dynamic> scope) =>
      _pluginCatalogs.putIfAbsent((deviceId, workspace),
          () => PluginCatalog(bridge: bridge, scope: scope));
  late final composers = ComposerStore(
      drafts: drafts,
      viewStates: conversationViewStates,
      onChanged: _saveRecovery,
      persist: recovery == null ? null : flushRecovery,
      recovery: recovery,
      referenceSessions: (deviceId, workspace, allWorkspaces) async {
        final session = _sessions[deviceId];
        final entries = <(Object?, Object?), Map<String, dynamic>>{};
        for (final raw
            in session?.taskIndex ?? const <Map<String, dynamic>>[]) {
          final key = raw['workspaceIdentity'] ?? raw['workspacePath'];
          if (!allWorkspaces && key != workspace) continue;
          final id = raw['sessionId'] ?? raw['taskId'];
          if (id is String && raw['archived'] != true) {
            entries[(key, id)] = raw;
          }
        }
        for (final monitor in _monitors.values) {
          if (monitor.source.deviceId != deviceId ||
              (!allWorkspaces && monitor.source.workspaceKey != workspace)) {
            continue;
          }
          for (final task in monitor.tasks) {
            entries[(monitor.source.workspaceKey, task.sessionId)] = {
              ...task.raw,
              ...monitor.scope
            };
          }
        }
        return entries.values.toList();
      },
      onPromoted: _promoteComposer);

  void _saveRecovery() {
    if (!_disposed && !_hydrating) recovery?.schedule();
  }

  Future<void> flushRecovery() => recovery?.flush() ?? Future.value();
  Map<String, dynamic> _recoverySnapshot() => {
        'schemaVersion': 1,
        'composers': composers.exportRecovery(),
        'locations': {
          for (final item in lastLocations.entries)
            item.key: item.value.toJson()
        },
        'reading': {
          for (final item in conversationViewStates.entries)
            item.key: item.value.toJson()
        },
        'panels': {
          for (final item in workspaceViewStates.entries)
            item.key: item.value.toJson()
        },
        'sidebar': {
          for (final item in sidebarStates.entries)
            item.key: item.value.toJson()
        },
        'sideChats': Map<String, String>.from(sideChats),
      };
  Future<void> loadRecovery() {
    if (recovery == null) return Future.value();
    return _loadingRecovery ??= _restoreRecovery().catchError((Object error) {
      _loadingRecovery = null;
      throw error;
    });
  }

  Future<void> _restoreRecovery() async {
    final saved = await recovery!.load();
    if (_disposed) return;
    _hydrating = true;
    try {
      if (saved['composers'] case final Map values) {
        await composers.importRecovery(values, _restoreAttachment);
      }
      if (_disposed) return;
      if (saved['locations'] case final Map values) {
        for (final item in values.entries) {
          final target = TaskTarget.parse(item.value, allowDraft: true);
          if (target != null &&
              item.key == target.deviceId &&
              !_forgottenDeviceIds.contains(target.deviceId)) {
            lastLocations.putIfAbsent(target.deviceId, () => target);
          }
        }
      }
      if (saved['reading'] case final Map values) {
        for (final item in values.entries) {
          if (item.key is String &&
              item.value is Map &&
              !_forgottenScope(item.key)) {
            conversationViewStates.putIfAbsent(
                item.key, () => ConversationViewState.fromJson(item.value));
          }
        }
      }
      if (saved['panels'] case final Map values) {
        for (final item in values.entries) {
          if (item.key is String &&
              item.value is Map &&
              !_forgottenScope(item.key)) {
            workspaceViewStates.putIfAbsent(
                item.key, () => WorkspaceViewState.fromJson(item.value));
          }
        }
      }
      if (saved['sidebar'] case final Map values) {
        for (final item in values.entries) {
          if (item.key is String &&
              item.value is Map &&
              !_forgottenDeviceIds.contains(item.key)) {
            sidebarStates.putIfAbsent(
                item.key, () => SidebarViewState.fromJson(item.value));
          }
        }
      }
      if (saved['sideChats'] case final Map values) {
        for (final item in values.entries) {
          if (item.key is String &&
              item.value is String &&
              !_forgottenScope(item.key)) {
            sideChats.putIfAbsent(item.key, () => item.value);
          }
        }
      }
    } finally {
      _hydrating = false;
    }
    recovery!.activate();
    _saveRecovery();
    unawaited(prunePickedAttachments(composers.retainedAttachmentTokens)
        .catchError((_) {}));
    _changed();
  }

  void _promoteComposer(ComposerController composer, String sessionId) {
    final deviceId = composer.deviceId;
    if (deviceId == null) return;
    final previous = lastLocations[deviceId];
    final old = TaskTarget(
        deviceId: deviceId,
        workspaceKey: composer.workspaceKey,
        sessionId: composer.sessionId ?? '',
        title: '');
    final next = TaskTarget(
        deviceId: deviceId,
        workspaceKey: composer.workspaceKey,
        sessionId: sessionId,
        title: previous?.title ?? '',
        workspacePath: previous?.workspacePath);
    final layout = workspaceViewStates.remove(old.key);
    if (layout != null) workspaceViewStates[next.key] = layout;
    final side = sideChats.remove(old.key);
    if (side != null) sideChats[next.key] = side;
    if (previous?.key == old.key) lastLocations[deviceId] = next;
  }

  bool _disposed = false;
  int _navigationGeneration = 0;
  int beginNavigation() => ++_navigationGeneration;
  bool navigationIsCurrent(int generation) =>
      !_disposed && generation == _navigationGeneration;
  List<WorkspaceMonitor> monitorsFor(String deviceId) => _monitors.values
      .where((monitor) => monitor.source.deviceId == deviceId)
      .toList();
  WorkspaceMonitor? monitorFor(String deviceId, String workspaceKey) =>
      _monitors.values
          .where((monitor) =>
              monitor.source.deviceId == deviceId &&
              monitor.source.workspaceKey == workspaceKey)
          .firstOrNull;
  DeviceSession? sessionOf(String id) => _sessions[id];
  DeviceSession sessionFor(Device device) {
    if (_disposed) throw StateError('app sessions disposed');
    if (device.params == null) throw const FormatException('设备凭据不可用，请重新添加链接');
    final existing = _sessions[device.id];
    if (existing != null && _urls[device.id] == device.url) return existing;
    disconnect(device.id);
    final session = _sessionFactory(device);
    _sessions[device.id] = session;
    _urls[device.id] = device.url;
    session.addListener(_changed);
    return session;
  }

  Future<WorkspaceMonitor> openWorkspace(
      Device device, String key, Map<String, dynamic> scope) async {
    final session = sessionFor(device);
    final bridge = await session.openWorkspace(key);
    if (_disposed || !identical(_sessions[device.id], session)) {
      throw StateError('workspace opening cancelled');
    }
    final source = WorkspaceTaskSource(
        deviceId: device.id,
        deviceLabel: device.label,
        workspaceKey: key,
        workspacePath: scope['workspacePath'] as String?);
    return _monitors.putIfAbsent(source.key, () {
      final monitor = WorkspaceMonitor(
          bridge: bridge,
          scope: scope,
          source: source,
          notifications: notifications);
      unawaited(monitor.start());
      return monitor;
    });
  }

  void _onDevicesChanged() {
    final devices = {for (final device in store.devices) device.id: device};
    for (final id in _sessions.keys.toList()) {
      if (devices[id] == null || devices[id]!.url != _urls[id]) disconnect(id);
    }
    for (final id in _knownDeviceIds.difference(devices.keys.toSet())) {
      _forgottenDeviceIds.add(id);
      composers.forgetDevice(id);
      lastLocations.remove(id);
      sidebarStates.remove(id);
      bool belongs(String key) {
        try {
          final parts = jsonDecode(key);
          return parts is List && parts.isNotEmpty && parts.first == id;
        } catch (_) {
          return false;
        }
      }

      workspaceViewStates.removeWhere((key, _) => belongs(key));
      sideChats.removeWhere((key, _) => belongs(key));
    }
    _knownDeviceIds
      ..clear()
      ..addAll(devices.keys);
  }

  void disconnect(String id) {
    for (final entry in _pluginCatalogs.entries.toList()) {
      if (entry.key.$1 != id) continue;
      entry.value.dispose();
      _pluginCatalogs.remove(entry.key);
    }
    composers.disconnect(id);
    for (final entry in _monitors.entries.toList()) {
      if (entry.value.source.deviceId == id) {
        entry.value.dispose();
        _monitors.remove(entry.key);
      }
    }
    final session = _sessions.remove(id);
    session?.removeListener(_changed);
    session?.dispose();
    _urls.remove(id);
    _changed();
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && recovery != null) {
      unawaited(flushRecovery().catchError((_) {}));
    }
    notifications.setForeground(state == AppLifecycleState.resumed);
    if (state == AppLifecycleState.resumed) {
      unawaited(notifications.refreshCapabilities().catchError((_) {}));
      for (final session in _sessions.values) {
        session.client?.pokeRelay();
      }
    }
  }

  @override
  void dispose() {
    if (recovery != null) {
      unawaited(flushRecovery().catchError((_) {}));
      recovery!.removeListener(_changed);
    }
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_onDevicesChanged);
    for (final id in _sessions.keys.toList()) {
      disconnect(id);
    }
    composers.dispose();
    notifications.dispose();
    super.dispose();
  }
}

class WorkspaceMonitor extends ChangeNotifier {
  WorkspaceMonitor(
      {required this.bridge,
      required this.scope,
      required this.source,
      required this.notifications})
      : catalog = WorkspaceTaskCatalog(scope) {
    bridge.recovered.addListener(_onRecovered);
  }
  final BridgeSession bridge;
  final Map<String, dynamic> scope;
  final WorkspaceTaskSource source;
  final TaskNotificationController notifications;
  final WorkspaceTaskCatalog catalog;
  final _mutating = <String>{};
  bool isMutating(String id) => _mutating.contains(id);
  SessionsIndexSubscription? _subscription;
  Timer? _retry;
  bool _disposed = false;
  bool _starting = false;
  String? _error;
  bool _channelReady = false;
  int _channelGeneration = 0;
  String? get error => _error;
  bool get ready => (_subscription?.state.ready ?? false) || _channelReady;
  List<SessionEntry> get tasks => catalog.visible;
  List<SessionEntry> get archivedTasks => catalog.archiveList;
  bool isPinned(String id) => catalog.isPinned(id);

  Future<void> start() async {
    if (_disposed || _starting || _subscription != null) return;
    _starting = true;
    _retry?.cancel();
    if (!_channelReady) unawaited(refreshTasks());
    try {
      final sub = await bridge.conversation(scope).subscribeSessionsIndex();
      if (_disposed) {
        await sub.dispose();
        return;
      }
      _subscription = sub;
      _error = null;
      sub.state.addListener(_onState);
      _onState();
    } catch (_) {
      if (!_disposed) {
        _error = '任务列表暂时不可用，正在恢复';
        notifyListeners();
        _retry = Timer(const Duration(seconds: 3), () => unawaited(start()));
      }
    } finally {
      _starting = false;
    }
  }

  void _onState() {
    if (_disposed) return;
    if (_subscription?.state.ready == true) {
      catalog.index = _subscription!.state.list;
      notifications.update(source, _subscription!.state.list);
    }
    notifyListeners();
  }

  void _onRecovered() => unawaited(refreshTasks());

  Future<void> refreshTasks() async {
    final generation = ++_channelGeneration;
    final pinRevision = catalog.pinRevision;
    final archiveRevision = catalog.archiveRevision;
    Future<void> read(
        String method, void Function(List<SessionEntry>) accept) async {
      try {
        final result = await bridge.channels.call(
            Channels.zcodeTask, method, [scope],
            timeout: const Duration(seconds: 12));
        if (_disposed || generation != _channelGeneration || result is! List) {
          return;
        }
        accept(catalog.parseChannel(result));
        _channelReady = true;
        notifyListeners();
      } catch (_) {
        /* Keep the independent sessions-index source and cached list. */
      }
    }

    await Future.wait([
      read('listTasks', (entries) => catalog.channel = entries),
      read(
          'listPinnedTasks',
          (entries) =>
              catalog.replacePinned(entries, requestRevision: pinRevision)),
      read(
          'listArchivedTasks',
          (entries) => catalog.replaceArchived(entries,
              requestRevision: archiveRevision)),
    ]);
  }

  Future<void> setPinned(SessionEntry task, bool pinned) async {
    await _mutate(task, 'setTaskPinned', {'pinned': pinned},
        () => catalog.setPinned(task.sessionId, pinned));
  }

  Future<void> setArchived(SessionEntry task, bool archived) async {
    await _mutate(task, archived ? 'archiveTask' : 'unarchiveTask', {},
        () => catalog.setArchived(task.sessionId, archived));
  }

  Future<void> rename(SessionEntry task, String title) async {
    if (title.trim().isEmpty) return;
    await _mutate(task, 'renameTask', {'title': title.trim()},
        () => catalog.setTitle(task.sessionId, title.trim()));
  }

  Future<void> setUnread(SessionEntry task, bool unread) => _mutate(
      task,
      'setTaskUnread',
      {'unread': unread},
      () => catalog.setUnread(task.sessionId, unread));

  Future<void> deleteArchived(SessionEntry task) {
    if (!catalog.isArchived(task.sessionId)) {
      return Future.error(StateError('task is not archived'));
    }
    return _mutate(
        task, 'deleteTask', {}, () => catalog.remove(task.sessionId));
  }

  Future<void> _mutate(SessionEntry task, String method,
      Map<String, dynamic> values, VoidCallback apply) async {
    if (_disposed || !_mutating.add(task.sessionId)) {
      throw StateError('task mutation unavailable');
    }
    notifyListeners();
    try {
      await bridge.channels.call(Channels.zcodeTask, method, [
        {...scope, 'taskId': task.sessionId, ...values}
      ]);
      if (_disposed) return;
      apply();
      unawaited(refreshTasks());
    } finally {
      _mutating.remove(task.sessionId);
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _channelGeneration++;
    bridge.recovered.removeListener(_onRecovered);
    _retry?.cancel();
    final sub = _subscription;
    sub?.state.removeListener(_onState);
    if (sub != null) unawaited(sub.dispose().catchError((_) {}));
    notifications.remove(source.key);
    super.dispose();
  }
}
