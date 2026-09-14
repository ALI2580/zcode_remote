import 'dart:async';
import 'package:flutter/foundation.dart';
import '../protocol/connection_params.dart';
import '../protocol/relay_client.dart';
import '../protocol/zemote_client.dart';

typedef DeviceClientFactory = ZemoteClient Function(
    ZemoteConnectionParams params);

class DeviceSession extends ChangeNotifier {
  DeviceSession(this.params, {DeviceClientFactory? clientFactory})
      : _clientFactory = clientFactory ?? ((params) => ZemoteClient(params));
  final ZemoteConnectionParams params;
  final DeviceClientFactory _clientFactory;
  ZemoteClient? _client;
  Future<void>? _connecting;
  final _closing = <ZemoteClient, Future<void>>{};
  final _bridges = <String, Future<BridgeSession>>{};
  final _bridgeSessions = <String, BridgeSession>{};
  StreamSubscription<dynamic>? _workspacesSub;
  StreamSubscription<RelayFailure>? _failureSub;
  bool _disposed = false;
  bool _ready = false;
  String? _error;
  RelayFailure? _lastFailure;
  bool _manuallyDisconnected = false;
  List<Map<String, dynamic>> _workspaces = const [];
  List<Map<String, dynamic>> _taskIndex = const [];
  int _taskIndexVersion = 0;
  String? initialWorkspaceKey;
  String? initialTaskId;
  ZemoteClient? get client => _client;
  bool get connected =>
      _ready &&
      _client?.relay.state == RelayState.paired &&
      _bridgeSessions.values.every((bridge) => bridge.degraded.value == null);
  bool get bridgeRecovering =>
      _bridgeSessions.values.any((bridge) => bridge.degraded.value != null);
  bool get connecting => _connecting != null;
  String? get error => _error;
  RelayFailure? get lastFailure => _lastFailure;
  String? get failureReason => _lastFailure?.reason;
  bool get manuallyDisconnected => _manuallyDisconnected;
  List<Map<String, dynamic>> get workspaces => List.unmodifiable(_workspaces);
  List<Map<String, dynamic>> get taskIndex => List.unmodifiable(_taskIndex);
  int get taskIndexVersion => _taskIndexVersion;

  Future<void> connect({void Function(String)? onLog}) {
    if (_disposed) return Future.error(StateError('device session disposed'));
    final current = _client;
    if (_ready && current?.relay.state == RelayState.paired) {
      return Future.value();
    }
    // During an automatic relay recovery, keep the existing client and let
    // its single reconnect loop finish. Creating a second client here would
    // race the active socket and lose the bridge recovery generation.
    if (_ready &&
        current != null &&
        (current.relay.state == RelayState.reconnecting ||
            current.relay.state == RelayState.waiting ||
            current.relay.state == RelayState.authenticating ||
            current.relay.state == RelayState.connecting)) {
      return _waitForPaired();
    }
    if (_manuallyDisconnected &&
        current != null &&
        current.relay.state == RelayState.closed) {
      return _resumeExisting(current, onLog);
    }
    if (current != null &&
        _bridgeSessions.isNotEmpty &&
        (current.relay.state == RelayState.error ||
            current.relay.state == RelayState.kicked) &&
        _lastFailure?.reason != 'session-not-found' &&
        _lastFailure?.reason != 'session-expired' &&
        _lastFailure?.reason != 'invalid-mobile-connection') {
      return _resumeExisting(current, onLog);
    }
    if (_connecting != null) return _connecting!;
    final operation = Completer<void>();
    _connecting = operation.future;
    unawaited(() async {
      try {
        await _connect(onLog);
        operation.complete();
      } catch (error, stack) {
        operation.completeError(error, stack);
      } finally {
        _connecting = null;
        _changed();
      }
    }());
    return operation.future;
  }

  Future<void> _connect(void Function(String)? onLog) async {
    _error = null;
    _lastFailure = null;
    _manuallyDisconnected = false;
    final previous = _client;
    if (previous != null &&
        (previous.relay.state == RelayState.closed ||
            previous.relay.state == RelayState.error ||
            previous.relay.state == RelayState.kicked)) {
      _client = null;
      await _release(previous);
    }
    final client = _clientFactory(params);
    _client = client;
    client.relay.stateListenable.addListener(_changed);
    _failureSub = client.relay.failures.listen((failure) {
      if (!identical(_client, client) || _disposed) return;
      _lastFailure = failure;
      _error = _safeFailureMessage(failure.reason);
      if (failure.reason == 'kicked' ||
          failure.reason == 'session-not-found' ||
          failure.reason == 'session-expired' ||
          failure.reason == 'invalid-mobile-connection') {
        for (final bridge in _bridgeSessions.values) {
          bridge.degraded.value = 'credentials-invalid';
        }
      }
      _changed();
    });
    _changed();
    try {
      onLog?.call('正在连接设备');
      await client.connect();
      _checkCurrent(client);
      await client.waitPaired();
      _checkCurrent(client);
      final bootstrap = await client.bootstrap();
      _checkCurrent(client);
      initialWorkspaceKey = bootstrap['activeWorkspaceKey'] as String?;
      initialTaskId = bootstrap['activeTaskId'] as String?;
      final result = bootstrap['workspaces'] != null
          ? bootstrap
          : await client.listWorkspaces();
      _checkCurrent(client);
      _setWorkspaces(result);
      _workspacesSub = client.workspaceListUpdated.listen((result) {
        if (!_disposed && identical(_client, client)) _setWorkspaces(result);
      });
      _ready = true;
      _lastFailure = null;
      onLog?.call('设备已配对');
    } catch (_) {
      if (!_disposed && identical(_client, client)) {
        _error = _safeFailureMessage(_lastFailure?.reason);
        _client = null;
      }
      await _release(client);
      rethrow;
    } finally {
      _changed();
    }
  }

  Future<void> _resumeExisting(
      ZemoteClient client, void Function(String)? onLog) async {
    if (_connecting != null) return _connecting!;
    final operation = Completer<void>();
    _connecting = operation.future;
    unawaited(() async {
      try {
        _error = null;
        _lastFailure = null;
        _manuallyDisconnected = false;
        onLog?.call('正在恢复设备连接');
        await client.connect();
        await client.waitPaired();
        _checkCurrent(client);
        _ready = true;
        operation.complete();
      } catch (error, stack) {
        if (!_disposed && identical(_client, client)) {
          _error = _safeFailureMessage(_lastFailure?.reason);
        }
        operation.completeError(error, stack);
      } finally {
        _connecting = null;
        _changed();
      }
    }());
    return operation.future;
  }

  void _checkCurrent(ZemoteClient client) {
    if (_disposed || !identical(_client, client)) {
      throw StateError('device connection cancelled');
    }
  }

  void _setWorkspaces(dynamic result) {
    if (result is Map && result['tasks'] is List) {
      _taskIndex = (result['tasks'] as List)
          .whereType<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .toList();
      _taskIndexVersion++;
    }
    final list = result is List
        ? result
        : result is Map
            ? result['workspaces']
            : null;
    if (list is List) {
      _workspaces = list
          .whereType<Map>()
          .map((entry) => entry.cast<String, dynamic>())
          .toList();
      _changed();
    }
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  Future<void> _release(ZemoteClient client) =>
      _closing.putIfAbsent(client, () {
        client.relay.stateListenable.removeListener(_changed);
        unawaited(_failureSub?.cancel());
        _failureSub = null;
        return client.dispose();
      });

  Future<void> _waitForPaired(
      {Duration timeout = const Duration(seconds: 60)}) {
    if (_client?.relay.state == RelayState.paired) return Future.value();
    final client = _client;
    if (client == null) return connect();
    final completer = Completer<void>();
    Timer? timer;
    void listener() {
      if (client.relay.state == RelayState.paired && !completer.isCompleted) {
        timer?.cancel();
        completer.complete();
      }
      if ((client.relay.state == RelayState.error ||
              client.relay.state == RelayState.kicked ||
              client.relay.state == RelayState.closed) &&
          !completer.isCompleted) {
        timer?.cancel();
        completer.completeError(
            StateError(_safeFailureMessage(_lastFailure?.reason)));
      }
    }

    client.relay.stateListenable.addListener(listener);
    timer = Timer(timeout, () {
      if (!completer.isCompleted) {
        completer.completeError(TimeoutException('device reconnect timeout'));
      }
    });
    listener();
    return completer.future.whenComplete(() {
      timer?.cancel();
      client.relay.stateListenable.removeListener(listener);
    });
  }

  /// Explicitly asks the existing relay recovery loop to make progress, or
  /// starts a fresh connection after a terminal/intentional close.
  Future<void> reconnect({void Function(String)? onLog}) {
    final client = _client;
    if (client != null &&
        (client.relay.state == RelayState.reconnecting ||
            client.relay.state == RelayState.waiting ||
            client.relay.state == RelayState.authenticating ||
            client.relay.state == RelayState.connecting)) {
      client.pokeRelay();
      return _waitForPaired();
    }
    return connect(onLog: onLog);
  }

  /// Cancels automatic recovery while retaining this session's cached UI
  /// state, so drafts/history/scroll remain available on the current route.
  Future<void> cancelRecovery() async {
    final client = _client;
    if (client == null) return;
    _manuallyDisconnected = true;
    _ready = false;
    _error = '连接已断开';
    await client.close();
    _changed();
  }

  String _safeFailureMessage(String? reason) {
    switch (reason) {
      case 'session-not-found':
      case 'session-expired':
      case 'invalid-mobile-connection':
        return '配对或凭据已失效，请重新配对';
      case 'session-conflict':
        return '设备正在其他位置连接，请重新连接';
      case 'desktop-disconnected':
        return '远端桌面已断开，正在尝试恢复';
      case 'workspace-closed':
        return '远端工作区已关闭，正在尝试恢复';
      case 'kicked':
        return '远端连接已被关闭，请重新连接';
      default:
        return '设备连接失败，请检查桌面远程控制状态后重试';
    }
  }

  Future<BridgeSession> openWorkspace(String workspaceKey,
      {String? taskId}) async {
    await connect();
    if (_disposed || _client == null) throw StateError('device not connected');
    final existing = _bridges[workspaceKey];
    if (existing != null) return existing;
    final pending = _client!.openBridge(workspaceKey, taskId: taskId);
    _bridges[workspaceKey] = pending;
    try {
      final bridge = await pending;
      if (_disposed) {
        bridge.dispose();
        throw StateError('device session disposed');
      }
      _bridgeSessions[workspaceKey] = bridge;
      bridge.degraded.addListener(_changed);
      return bridge;
    } catch (_) {
      if (identical(_bridges[workspaceKey], pending)) {
        _bridges.remove(workspaceKey);
      }
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    unawaited(_workspacesSub?.cancel());
    final client = _client;
    _client = null;
    unawaited(_failureSub?.cancel());
    _failureSub = null;
    if (client != null) unawaited(_release(client).catchError((_) {}));
    _bridges.clear();
    for (final bridge in _bridgeSessions.values) {
      bridge.degraded.removeListener(_changed);
    }
    _bridgeSessions.clear();
    super.dispose();
  }
}
