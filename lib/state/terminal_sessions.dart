import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/terminal.dart';
import 'terminal_session.dart';

String terminalScopeKey(String? deviceId, String workspaceKey) =>
    [deviceId ?? '', workspaceKey].join('|');

/// Workspace-owned terminal tabs survive route changes and panel switches.
class TerminalWorkspaceSessions extends ChangeNotifier {
  TerminalWorkspaceSessions({
    required this.client,
    required this.cwd,
    this.maxSessions = 4,
  }) {
    controllers.add(TerminalSessionController(client: client, cwd: cwd));
  }

  final TerminalClient client;
  final String cwd;
  final int maxSessions;
  final controllers = <TerminalSessionController>[];
  int activeIndex = 0;

  TerminalSessionController? get activeController => controllers.isEmpty
      ? null
      : controllers[activeIndex.clamp(0, controllers.length - 1)];

  bool get canAdd => controllers.length < maxSessions;

  TerminalSessionController add() {
    if (!canAdd) {
      throw StateError('terminal tab limit reached');
    }
    final controller = TerminalSessionController(client: client, cwd: cwd);
    controllers.add(controller);
    activeIndex = controllers.length - 1;
    notifyListeners();
    return controller;
  }

  void activate(int index) {
    if (index < 0 || index >= controllers.length) return;
    activeIndex = index;
    notifyListeners();
  }

  Future<void> closeAt(int index) async {
    if (index < 0 || index >= controllers.length) return;
    final controller = controllers.removeAt(index);
    await controller.close();
    controller.dispose();
    if (controllers.isEmpty) {
      controllers.add(TerminalSessionController(client: client, cwd: cwd));
      activeIndex = 0;
    }
    if (activeIndex >= controllers.length) {
      activeIndex = controllers.length - 1;
    }
    if (activeIndex < 0) activeIndex = 0;
    notifyListeners();
  }

  Future<void> disposeAll() async {
    final closing = List.of(controllers);
    controllers.clear();
    activeIndex = 0;
    for (final controller in closing) {
      await controller.close();
      controller.dispose();
    }
  }
}

/// Owns terminal workspaces by device/workspace, like other app-level state.
class TerminalSessionStore {
  final _workspaces = <String, TerminalWorkspaceSessions>{};

  TerminalWorkspaceSessions workspace({
    required String? deviceId,
    required String workspaceKey,
    required TerminalClient client,
    required String cwd,
  }) {
    final key = terminalScopeKey(deviceId, workspaceKey);
    return _workspaces.putIfAbsent(
      key,
      () => TerminalWorkspaceSessions(client: client, cwd: cwd),
    );
  }

  void forgetDevice(String deviceId) {
    final prefix = '$deviceId|';
    for (final key
        in _workspaces.keys.where((key) => key.startsWith(prefix)).toList()) {
      final workspace = _workspaces.remove(key);
      if (workspace != null) {
        unawaited(workspace.disposeAll().catchError((_) {}));
      }
    }
  }

  Future<void> dispose() async {
    final workspaces = List.of(_workspaces.values);
    _workspaces.clear();
    for (final workspace in workspaces) {
      await workspace.disposeAll().catchError((_) {});
    }
  }
}
