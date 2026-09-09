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
  StreamSubscription<dynamic>? _workspacesSub;
  bool _disposed = false;
  bool _ready = false;
  String? _error;
  List<Map<String, dynamic>> _workspaces = const [];
  List<Map<String, dynamic>> _taskIndex = const [];
  int _taskIndexVersion = 0;
  String? initialWorkspaceKey;
  String? initialTaskId;
  ZemoteClient? get client => _client;
  bool get connected => _ready && _client?.relay.state == RelayState.paired;
  bool get connecting => _connecting != null;
  String? get error => _error;
  List<Map<String, dynamic>> get workspaces => List.unmodifiable(_workspaces);
  List<Map<String, dynamic>> get taskIndex => List.unmodifiable(_taskIndex);
  int get taskIndexVersion => _taskIndexVersion;

  Future<void> connect({void Function(String)? onLog}) {
    if (_disposed) return Future.error(StateError('device session disposed'));
    if (_ready) return Future.value();
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
    final client = _clientFactory(params);
    _client = client;
    client.relay.stateListenable.addListener(_changed);
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
      onLog?.call('设备已配对');
    } catch (_) {
      if (!_disposed && identical(_client, client)) {
        _error = '设备连接失败，请检查桌面远程控制状态后重试';
        _client = null;
      }
      await _release(client);
      rethrow;
    } finally {
      _changed();
    }
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
        return client.dispose();
      });
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
    if (client != null) unawaited(_release(client).catchError((_) {}));
    _bridges.clear();
    super.dispose();
  }
}
