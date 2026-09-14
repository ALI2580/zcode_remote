import 'dart:async';

import 'package:flutter/foundation.dart';

import '../protocol/channel_client.dart';
import '../protocol/zemote_client.dart';

enum McpStatusStatus { idle, loading, loaded, error }

/// The MCP service exposes two deliberately different status paths. `status`
/// is passive and may be unavailable on older attachments; `connect` is an
/// explicit user action that may start a server connection.
enum McpStatusMode { status, connect }

extension McpStatusModeValue on McpStatusMode {
  String get value => name;
}

class McpServerStatus {
  const McpServerStatus({
    required this.name,
    this.state,
    this.enabled,
    this.toolCount,
    this.error,
    this.failureKind,
    this.authorizationUrl,
    this.updatedAt,
    this.raw = const {},
  });

  factory McpServerStatus.fromRaw(Map raw) {
    final map = raw.cast<String, dynamic>();
    return McpServerStatus(
      name: map['name'] is String ? map['name'] as String : '',
      state: map['status'] is String ? map['status'] as String : null,
      enabled: map['enabled'] is bool ? map['enabled'] as bool : null,
      toolCount:
          map['toolCount'] is num ? (map['toolCount'] as num).toInt() : null,
      error: map['error'] is String ? map['error'] as String : null,
      failureKind:
          map['failureKind'] is String ? map['failureKind'] as String : null,
      authorizationUrl: _authorizationUrl(map),
      updatedAt: map['updatedAt'],
      raw: map,
    );
  }

  static String? _authorizationUrl(Map<String, dynamic> map) {
    final direct = map['authorizationUrl'];
    if (direct is String && direct.trim().isNotEmpty) return direct;
    final authorization = map['authorization'];
    if (authorization is Map) {
      final value = authorization['authorizationUrl'];
      if (value is String && value.trim().isNotEmpty) return value;
    }
    return null;
  }

  final String name;
  final String? state;
  final bool? enabled;
  final int? toolCount;
  final String? error;
  final String? failureKind;
  final String? authorizationUrl;
  final Object? updatedAt;
  final Map<String, dynamic> raw;
}

/// Read-only workspace MCP status. Configuration writes, import/export and
/// server connections are separate workflows and are not exposed here.
class McpStatusCatalog extends ChangeNotifier {
  McpStatusCatalog({
    required this.session,
    required this.scope,
    required this.scopeKey,
  });

  final BridgeSession session;
  final Map<String, dynamic> scope;
  final String scopeKey;

  int _generation = 0;
  Future<void>? _pending;
  McpStatusMode? _pendingMode;
  bool _disposed = false;
  bool _statusModeUnsupported = false;

  McpStatusStatus status = McpStatusStatus.idle;
  List<McpServerStatus> items = const [];
  Object? error;

  bool get statusModeUnsupported => _statusModeUnsupported;

  /// Reads the passive status snapshot. It never falls back to [connect].
  Future<void> refresh() => refreshStatus();

  Future<void> refreshStatus() => refreshWithMode(McpStatusMode.status);

  /// Explicitly asks the remote MCP service to connect and report status.
  Future<void> connect() => refreshWithMode(McpStatusMode.connect);

  Future<void> refreshWithMode(McpStatusMode mode) {
    if (_disposed) return Future.value();
    final pending = _pending;
    if (pending != null && _pendingMode == mode) return pending;
    if (pending != null) return pending;
    final generation = ++_generation;
    status = McpStatusStatus.loading;
    notifyListeners();
    Future<void>? operationFuture;
    Future<void> operation() async {
      try {
        final raw = await session.channels.call(
          Channels.mcpSync,
          'listWorkspaceMcpServerStatuses',
          [
            {
              ...scope,
              'mode': mode.name,
            }
          ],
          timeout: const Duration(seconds: 30),
        );
        if (_disposed || generation != _generation) return;
        final statuses = raw is Map && raw['statuses'] is List
            ? (raw['statuses'] as List).whereType<Map>().toList()
            : const <Map>[];
        items = [
          for (final item in statuses)
            if (McpServerStatus.fromRaw(item).name.isNotEmpty)
              McpServerStatus.fromRaw(item),
        ];
        status = McpStatusStatus.loaded;
        error = null;
      } catch (value) {
        if (_disposed || generation != _generation) return;
        if (mode == McpStatusMode.status && _unsupported(value)) {
          _statusModeUnsupported = true;
        }
        status = McpStatusStatus.error;
        error = value;
      } finally {
        if (_pending == operationFuture) _pending = null;
        if (_pending == null) _pendingMode = null;
        if (!_disposed && generation == _generation) notifyListeners();
      }
    }

    operationFuture = operation();
    _pending = operationFuture;
    _pendingMode = mode;
    return operationFuture;
  }

  bool _unsupported(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('status mode unsupported') ||
        message.contains('not supported') ||
        message.contains('unknown method') ||
        message.contains('method not found');
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    super.dispose();
  }
}
