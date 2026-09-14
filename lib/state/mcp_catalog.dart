import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../protocol/channel_client.dart';
import '../protocol/zemote_client.dart';
import 'mcp_status.dart';

enum McpCatalogStatus { idle, loading, loaded, error }

enum McpServerType { stdio, http, sse, streamableHttp }

extension McpServerTypeValue on McpServerType {
  String get value => switch (this) {
        McpServerType.stdio => 'stdio',
        McpServerType.http => 'http',
        McpServerType.sse => 'sse',
        McpServerType.streamableHttp => 'streamableHttp',
      };

  static McpServerType parse(Object? value, {Object? command, Object? url}) {
    if (value is String) {
      for (final type in McpServerType.values) {
        if (type.value == value) return type;
      }
    }
    return command is String && command.trim().isNotEmpty
        ? McpServerType.stdio
        : McpServerType.http;
  }
}

String _stringValue(Object? value) => value is String ? value : '';

String? _optionalString(Object? value) {
  final result = _stringValue(value).trim();
  return result.isEmpty ? null : result;
}

Map<String, dynamic> _mapValue(Object? value) => value is Map
    ? Map<String, dynamic>.from(
        value.map((key, value) => MapEntry(key.toString(), value)))
    : <String, dynamic>{};

String _prettyJson(Object value) =>
    const JsonEncoder.withIndent('  ').convert(value);

bool _isSecretKey(String key) {
  final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  return normalized.contains('token') ||
      normalized.contains('secret') ||
      normalized.contains('password') ||
      normalized.contains('apikey') ||
      normalized == 'authorization' ||
      normalized == 'auth';
}

Object? redactMcpSecrets(Object? value, {String? key}) {
  if (key != null && _isSecretKey(key)) return '<redacted>';
  if (value is Map) {
    return <String, dynamic>{
      for (final entry in value.entries)
        entry.key.toString():
            redactMcpSecrets(entry.value, key: entry.key.toString()),
    };
  }
  if (value is List) {
    return [for (final item in value) redactMcpSecrets(item)];
  }
  return value;
}

String redactMcpErrorText(Object? value,
    {Iterable<String> secrets = const []}) {
  var text = value?.toString() ?? 'MCP operation failed';
  for (final secret in secrets) {
    final candidate = secret.trim();
    if (candidate.length >= 3) text = text.replaceAll(candidate, '<redacted>');
  }
  // Remote bridges sometimes stringify a map before returning it. Strip the
  // common credential forms while retaining the surrounding diagnostics.
  text = text.replaceAll(
      RegExp(
          r'((?:authorization|bearer|token|secret|password|api[_-]?key)\s*[:=]\s*)([^,;\s}\]]+)',
          caseSensitive: false),
      r'\1<redacted>');
  return text;
}

Iterable<String> _mcpSecretValues(Object? value, {String? key}) sync* {
  if (key != null && _isSecretKey(key)) {
    if (value is String && value.trim().isNotEmpty) yield value;
    return;
  }
  if (value is Map) {
    for (final entry in value.entries) {
      yield* _mcpSecretValues(entry.value, key: entry.key.toString());
    }
  } else if (value is List) {
    for (final item in value) {
      yield* _mcpSecretValues(item);
    }
  }
}

/// The editable projection used by the official form. Unknown fields are
/// retained in [extras] and copied back into the save payload.
class McpFormDraft {
  McpFormDraft({
    this.name = '',
    this.type = McpServerType.stdio,
    this.command = '',
    this.args = '',
    this.env = '',
    this.url = '',
    this.headers = '',
    this.timeoutMs = '',
    this.oauth = '',
    this.protocolVersion = '',
    this.storageLevel = 'user',
    Map<String, dynamic>? extras,
  }) : extras = Map<String, dynamic>.from(extras ?? const {});

  factory McpFormDraft.fromEntry(McpServerEntry entry) {
    final config = entry.config;
    final type = McpServerTypeValue.parse(
      config['type'],
      command: config['command'],
      url: config['url'],
    );
    final known = <String>{
      'type',
      'command',
      'args',
      'env',
      'url',
      'headers',
      'timeoutMs',
      'oauth',
      'protocolVersion',
      'enable',
      'enabled',
    };
    return McpFormDraft(
      name: entry.name,
      type: type,
      command: _stringValue(config['command']),
      args: config['args'] is List
          ? (config['args'] as List).whereType<String>().join(' ')
          : _stringValue(config['args']),
      env: config['env'] is Map ? _prettyJson(config['env'] as Map) : '',
      url: _stringValue(config['url']),
      headers:
          config['headers'] is Map ? _prettyJson(config['headers'] as Map) : '',
      timeoutMs: config['timeoutMs'] is num
          ? '${config['timeoutMs']}'
          : _stringValue(config['timeoutMs']),
      oauth: config['oauth'] is Map ? _prettyJson(config['oauth'] as Map) : '',
      protocolVersion: config['protocolVersion'] is String &&
              config['protocolVersion'] != 'auto'
          ? config['protocolVersion'] as String
          : '',
      storageLevel: entry.scope == 'workspace' ? 'workspace' : 'user',
      extras: {
        for (final entry in config.entries)
          if (!known.contains(entry.key)) entry.key: entry.value,
      },
    );
  }

  factory McpFormDraft.fromConfig(
    Map<String, dynamic> config, {
    required String name,
    String storageLevel = 'user',
  }) {
    final entry = McpServerEntry(
      id: '',
      name: name,
      config: config,
      enabled: config['enable'] != false,
      source: 'zcodeagentmcp',
      scope: storageLevel,
      projectPath: null,
      raw: const {},
    );
    return McpFormDraft.fromEntry(entry);
  }

  final String name;
  final McpServerType type;
  final String command;
  final String args;
  final String env;
  final String url;
  final String headers;
  final String timeoutMs;
  final String oauth;
  final String protocolVersion;
  final String storageLevel;
  final Map<String, dynamic> extras;

  McpFormDraft copyWith({
    String? name,
    McpServerType? type,
    String? command,
    String? args,
    String? env,
    String? url,
    String? headers,
    String? timeoutMs,
    String? oauth,
    String? protocolVersion,
    String? storageLevel,
  }) =>
      McpFormDraft(
        name: name ?? this.name,
        type: type ?? this.type,
        command: command ?? this.command,
        args: args ?? this.args,
        env: env ?? this.env,
        url: url ?? this.url,
        headers: headers ?? this.headers,
        timeoutMs: timeoutMs ?? this.timeoutMs,
        oauth: oauth ?? this.oauth,
        protocolVersion: protocolVersion ?? this.protocolVersion,
        storageLevel: storageLevel ?? this.storageLevel,
        extras: extras,
      );

  /// Matches the official `vYt`: arguments split on whitespace and timeout is
  /// a positive finite number floored to an integer. Invalid optional JSON is
  /// omitted from the payload, while the original text remains in the form.
  Map<String, dynamic> toConfig() {
    final config = <String, dynamic>{
      ...extras,
      'type': type.value,
    };
    config.remove('command');
    config.remove('args');
    config.remove('env');
    config.remove('url');
    config.remove('headers');
    config.remove('oauth');
    config.remove('timeoutMs');
    config.remove('protocolVersion');
    if (type == McpServerType.stdio) {
      config['command'] = command;
      config['args'] =
          args.trim().isEmpty ? <String>[] : args.trim().split(RegExp(r'\s+'));
      final parsed = _parseObject(env);
      if (parsed != null) config['env'] = parsed;
    } else {
      config['url'] = url;
      final headersValue = _parseObject(headers);
      if (headersValue != null) config['headers'] = headersValue;
      final oauthValue = _parseObject(oauth);
      if (oauthValue != null) config['oauth'] = oauthValue;
    }
    final timeout = _positiveFloor(timeoutMs);
    if (timeout != null) config['timeoutMs'] = timeout;
    final protocol = protocolVersion.trim();
    if (protocol == 'legacy' || protocol == '2026-07-28') {
      config['protocolVersion'] = protocol;
    }
    return config;
  }

  static Map<String, dynamic>? _parseObject(String value) {
    if (value.trim().isEmpty) return null;
    try {
      final decoded = jsonDecode(value);
      return decoded is Map ? _mapValue(decoded) : null;
    } on Object {
      return null;
    }
  }

  static int? _positiveFloor(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    final number = num.tryParse(text);
    if (number == null || !number.isFinite || number <= 0) return null;
    return number.floor();
  }

  bool get nameValid => name.trim().isNotEmpty;

  bool get endpointValid => type == McpServerType.stdio
      ? command.trim().isNotEmpty
      : url.trim().isNotEmpty;

  String? get validationError {
    if (!nameValid) return 'MCP server name is required';
    if (!endpointValid) {
      return type == McpServerType.stdio
          ? 'Command is required'
          : 'URL is required';
    }
    return null;
  }

  String toJson() {
    final displayName = name.trim().isEmpty ? 'my-mcp-server' : name.trim();
    return _prettyJson({displayName: toConfig()});
  }

  /// Parses a direct config, a single-name wrapper, or a single `mcpServers`
  /// wrapper. Multiple servers are rejected exactly as the official editor.
  static McpFormDraft parseJson(
    String text, {
    McpFormDraft? fallback,
  }) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException('JSON is not an MCP server object');
    }
    var name = fallback?.name.trim() ?? '';
    Map<String, dynamic> config = _mapValue(decoded);
    final servers = decoded['mcpServers'];
    if (servers is Map) {
      final entries =
          servers.entries.where((entry) => entry.value is Map).toList();
      if (entries.length != 1) {
        throw const FormatException(
            'JSON mode supports editing one MCP server at a time');
      }
      name = '${entries.single.key}';
      config = _mapValue(entries.single.value);
    } else {
      final entries = decoded.entries
          .where((entry) => entry.value is Map)
          .toList(growable: false);
      final looksLikeWrapper = entries.length == 1 &&
          !decoded.containsKey('type') &&
          !decoded.containsKey('command') &&
          !decoded.containsKey('url');
      if (looksLikeWrapper) {
        name = '${entries.single.key}';
        config = _mapValue(entries.single.value);
      }
    }
    if (config.isEmpty) {
      throw const FormatException('JSON is not a valid MCP server config');
    }
    if (name.isEmpty) {
      throw const FormatException('JSON mode requires a server name');
    }
    return McpFormDraft.fromConfig(
      config,
      name: name,
      storageLevel: fallback?.storageLevel ?? 'user',
    );
  }
}

class McpServerEntry {
  const McpServerEntry({
    required this.id,
    required this.name,
    required this.config,
    required this.enabled,
    required this.source,
    required this.scope,
    required this.projectPath,
    required this.raw,
    this.status = 'unknown',
    this.toolCount,
    this.error,
    this.failureKind,
    this.authorizationUrl,
    this.lastConnected,
    this.location,
    this.file,
  });

  factory McpServerEntry.fromRaw(Map raw) {
    final map = Map<String, dynamic>.from(
        raw.map((key, value) => MapEntry(key.toString(), value)));
    final config = _mapValue(map['config']);
    final source = _optionalString(map['source']) ?? 'zcodeagentmcp';
    final projectPath = _optionalString(map['projectPath']);
    final scope = _optionalString(map['scope']) ??
        (projectPath == null ? 'user' : 'workspace');
    final authorization = _mapValue(map['authorization']);
    final authUrl = _optionalString(map['authorizationUrl']) ??
        _optionalString(authorization['authorizationUrl']);
    final name = _optionalString(map['name']) ?? '';
    final id =
        _optionalString(map['id']) ?? _mcpIdentity(source, name, projectPath);
    return McpServerEntry(
      id: id,
      name: name,
      config: config,
      enabled: map['enabled'] is bool
          ? map['enabled'] as bool
          : config['enable'] != false,
      source: source == 'mcp' ? 'zcodeagentmcp' : source,
      scope: scope,
      projectPath: projectPath,
      raw: map,
      status: _optionalString(map['status']) ?? 'unknown',
      toolCount:
          map['toolCount'] is num ? (map['toolCount'] as num).toInt() : null,
      error: _optionalString(map['error']) == null
          ? null
          : redactMcpErrorText(map['error']),
      failureKind: _optionalString(map['failureKind']),
      authorizationUrl: authUrl,
      lastConnected: map['lastConnected'],
      location: map['location'] is Map ? _mapValue(map['location']) : null,
      file: _optionalString(map['file']),
    );
  }

  final String id;
  final String name;
  final Map<String, dynamic> config;
  final bool enabled;
  final String source;
  final String scope;
  final String? projectPath;
  final Map<String, dynamic> raw;
  final String status;
  final int? toolCount;
  final String? error;
  final String? failureKind;
  final String? authorizationUrl;
  final Object? lastConnected;
  final Map<String, dynamic>? location;
  final String? file;

  bool get isReadOnly =>
      scope == 'common' ||
      source != 'zcodeagentmcp' ||
      raw['readOnly'] == true ||
      location?['source'] == 'plugin';

  bool get canManage =>
      !isReadOnly && (scope == 'user' || scope == 'workspace');

  McpServerType get type => McpServerTypeValue.parse(
        config['type'],
        command: config['command'],
        url: config['url'],
      );

  Map<String, dynamic> get redactedConfig =>
      Map<String, dynamic>.from(redactMcpSecrets(config) as Map);

  String get identity =>
      id.isNotEmpty ? id : _mcpIdentity(source, name, projectPath);

  McpServerEntry withStatus(McpServerStatus status) {
    final merged = <String, dynamic>{...raw};
    merged['status'] = status.state ?? raw['status'] ?? 'unknown';
    if (status.toolCount != null) {
      merged['toolCount'] = status.toolCount;
    } else if (status.state == 'connected' || status.state == 'connecting') {
      merged.remove('toolCount');
    }
    if (status.error != null) {
      merged['error'] = redactMcpErrorText(
        status.error,
        secrets: _mcpSecretValues(config),
      );
    } else {
      merged.remove('error');
    }
    if (status.failureKind != null) {
      merged['failureKind'] = status.failureKind;
    } else {
      merged.remove('failureKind');
    }
    if (status.authorizationUrl != null) {
      merged['authorizationUrl'] = status.authorizationUrl;
      if (status.raw['authorization'] is Map) {
        merged['authorization'] = status.raw['authorization'];
      } else {
        merged.remove('authorization');
      }
    } else {
      // A connected/disconnected result clears an earlier OAuth challenge.
      merged.remove('authorizationUrl');
      merged.remove('authorization');
    }
    if (status.updatedAt != null) merged['updatedAt'] = status.updatedAt;
    return McpServerEntry.fromRaw(merged);
  }
}

String _mcpIdentity(String source, String name, String? projectPath) =>
    '${source == 'mcp' ? 'zcodeagentmcp' : source}:$name:${projectPath ?? ''}';

class McpCatalog extends ChangeNotifier {
  McpCatalog({
    required this.session,
    required Map<String, dynamic> scope,
    required this.scopeKey,
    this.workspacePath,
    this.onConfigurationChanged,
  }) : scope = Map<String, dynamic>.from(scope);

  final BridgeSession session;
  Map<String, dynamic> scope;
  String scopeKey;
  String? workspacePath;

  /// Runs after an MCP write has completed and its authoritative read-back
  /// succeeded. SettingsCenter supplies a monitor-specific Composer refresh.
  final FutureOr<void> Function()? onConfigurationChanged;

  int _configGeneration = 0;
  int _statusGeneration = 0;
  int _sourceGeneration = 0;
  Future<void>? _pendingLoad;
  Future<void>? _pendingStatus;
  McpStatusMode? _pendingStatusMode;
  String? _pendingStatusFilter;
  bool _disposed = false;

  McpCatalogStatus status = McpCatalogStatus.idle;
  List<McpServerEntry> items = const [];
  Object? error;
  McpStatusStatus statusListStatus = McpStatusStatus.idle;
  Object? statusListError;
  bool statusModeUnsupported = false;

  final Map<String, int> _operatingTokens = <String, int>{};
  int _nextOperationToken = 0;
  final Map<String, Object?> _operationErrors = <String, Object?>{};
  String? _lastVisibleConnectSignature;

  bool isOperating(String identity) => _operatingTokens.containsKey(identity);

  Object? operationError(String identity) => _operationErrors[identity];

  /// Stable signature used by the visible page to detect a config change
  /// without treating status-only notifications as a new connection request.
  String get configSignature => _configSignature();

  String get _workspace => workspacePath?.trim().isNotEmpty == true
      ? workspacePath!.trim()
      : _optionalString(scope['workspacePath']) ?? '';

  Map<String, dynamic> _readPayload() => {
        if (_workspace.isNotEmpty) 'workspacePath': _workspace,
      };

  Map<String, dynamic> _statusPayload(
    McpStatusMode mode, {
    List<Map<String, dynamic>>? mcpServers,
  }) =>
      {
        ...scope,
        if (_workspace.isNotEmpty) 'workspacePath': _workspace,
        if (mcpServers != null) 'mcpServers': mcpServers,
        'mode': mode.value,
      };

  void updateScope({
    required Map<String, dynamic> nextScope,
    required String nextScopeKey,
    String? nextWorkspacePath,
  }) {
    if (_disposed) return;
    final same = scopeKey == nextScopeKey &&
        workspacePath == nextWorkspacePath &&
        _sameMap(scope, nextScope);
    if (same) return;
    _configGeneration++;
    _statusGeneration++;
    _sourceGeneration++;
    _pendingLoad = null;
    _pendingStatus = null;
    _pendingStatusMode = null;
    _pendingStatusFilter = null;
    _statusSnapshots.clear();
    _lastVisibleConnectSignature = null;
    statusModeUnsupported = false;
    _operatingTokens.clear();
    _operationErrors.clear();
    scope = Map<String, dynamic>.from(nextScope);
    scopeKey = nextScopeKey;
    workspacePath = nextWorkspacePath;
    items = const [];
    status = McpCatalogStatus.idle;
    error = null;
    statusListStatus = McpStatusStatus.idle;
    statusListError = null;
    notifyListeners();
  }

  Future<void> refresh() => loadConfigs();

  Future<void> loadConfigs({bool force = false}) {
    if (_disposed) return Future.value();
    final pending = _pendingLoad;
    if (pending != null) {
      if (!force) return pending;
      return pending.then((_) => loadConfigs());
    }
    final generation = ++_configGeneration;
    final sourceGeneration = _sourceGeneration;
    status = McpCatalogStatus.loading;
    error = null;
    notifyListeners();
    Future<void>? future;
    Future<void> operation() async {
      try {
        final raw = await session.channels.call(
          Channels.mcpSync,
          'loadMcpFromUserDirectory',
          [_readPayload()],
          timeout: const Duration(seconds: 30),
        );
        if (_disposed ||
            generation != _configGeneration ||
            sourceGeneration != _sourceGeneration) {
          return;
        }
        final rows = raw is Map && raw['servers'] is List
            ? (raw['servers'] as List).whereType<Map>()
            : const Iterable<Map>.empty();
        items = [
          for (final row in rows)
            if (McpServerEntry.fromRaw(row).name.isNotEmpty)
              McpServerEntry.fromRaw(row),
        ];
        if (_statusSnapshots.isNotEmpty) {
          _mergeStatuses(_statusSnapshots.values.toList());
        }
        status = McpCatalogStatus.loaded;
        error = null;
      } catch (value) {
        if (_disposed ||
            generation != _configGeneration ||
            sourceGeneration != _sourceGeneration) {
          return;
        }
        status = McpCatalogStatus.error;
        error = value;
      } finally {
        if (_pendingLoad == future) _pendingLoad = null;
        if (!_disposed &&
            generation == _configGeneration &&
            sourceGeneration == _sourceGeneration) {
          notifyListeners();
        }
      }
    }

    future = operation();
    _pendingLoad = future;
    return future;
  }

  /// Passive status reads never become connects when the remote does not
  /// support `mode: status`.
  Future<void> refreshStatus() => refreshStatusWithMode(McpStatusMode.status);

  /// Native servers whose current snapshot still carries an OAuth challenge.
  /// The official passive poll sends this narrowed list in `mcpServers`.
  List<Map<String, dynamic>> get oauthStatusServers => [
        for (final entry in items)
          if (entry.source == 'zcodeagentmcp' &&
              entry.enabled &&
              entry.authorizationUrl?.trim().isNotEmpty == true)
            {'name': entry.name, ...entry.config},
      ];

  /// Stable pending key for the 5-minute OAuth polling deadline. Include the
  /// authorization start marker when the bridge provides one so a new OAuth
  /// challenge starts a fresh lifecycle even when its URL is reused.
  String? get oauthPendingSignature {
    final pending = items
        .where((entry) =>
            entry.source == 'zcodeagentmcp' &&
            entry.enabled &&
            entry.authorizationUrl?.trim().isNotEmpty == true)
        .map((entry) {
      final authorization = entry.raw['authorization'];
      final startedAt = authorization is Map ? authorization['startedAt'] : '';
      return '${entry.identity}:${entry.authorizationUrl}:$startedAt';
    }).toList()
      ..sort();
    return pending.isEmpty ? null : pending.join('|');
  }

  /// Finds a status belonging to a plugin-management projection. Native
  /// config rows and plugin rows can share display names, so prefer the
  /// verified plugin id/runtime name carried by the status response.
  McpServerStatus? statusForPlugin({
    required String pluginId,
    required String runtimeServerName,
    required String displayName,
  }) {
    for (final status in _statusSnapshots.values) {
      final rawPluginId = status.raw['pluginId'];
      final rawRuntime = status.raw['runtimeServerName'];
      if (rawPluginId == pluginId &&
          (rawRuntime == runtimeServerName ||
              status.name == runtimeServerName ||
              status.name.endsWith(':$runtimeServerName') ||
              status.name.endsWith(':$displayName'))) {
        return status;
      }
    }
    for (final status in _statusSnapshots.values) {
      if (status.name == runtimeServerName || status.name == displayName) {
        final rawPluginId = status.raw['pluginId'];
        if (rawPluginId == null || rawPluginId == pluginId) return status;
      }
    }
    return null;
  }

  /// Passive OAuth status refresh. It never upgrades to `connect`.
  Future<void> refreshOAuthStatus() => refreshStatusWithMode(
        McpStatusMode.status,
        mcpServers: oauthStatusServers,
      );

  /// Explicit user action which is allowed to start MCP connections.
  Future<void> connectAndRefreshStatus() =>
      refreshStatusWithMode(McpStatusMode.connect);

  /// Official MCP page behavior: once the page is visible and its config read
  /// is ready, connect once per config signature. This is deliberately lazy;
  /// constructing the settings center while another section is open does not
  /// invoke this method.
  Future<void> ensureConnectedForVisible({String? additionalSignature}) async {
    if (_disposed) return;
    if (status != McpCatalogStatus.loaded) await loadConfigs();
    if (_disposed || status != McpCatalogStatus.loaded) return;
    final signature = additionalSignature == null || additionalSignature.isEmpty
        ? _configSignature()
        : '${_configSignature()}|$additionalSignature';
    if (signature == _lastVisibleConnectSignature) return;
    _lastVisibleConnectSignature = signature;
    await connectAndRefreshStatus();
  }

  String _configSignature() {
    final rows = items
        .where((item) => item.source == 'zcodeagentmcp')
        .map((item) =>
            '${item.identity}:${item.enabled}:${jsonEncode(item.config)}')
        .toList()
      ..sort();
    return rows.join('|');
  }

  Future<void> refreshStatusWithMode(
    McpStatusMode mode, {
    List<Map<String, dynamic>>? mcpServers,
  }) {
    if (_disposed) return Future.value();
    final pending = _pendingStatus;
    final requestedFilter = mcpServers == null ? null : jsonEncode(mcpServers);
    if (pending != null) {
      if (_pendingStatusMode == mode &&
          _pendingStatusFilter == requestedFilter) {
        return pending;
      }
      // Preserve the strict mode distinction when a manual connect arrives
      // during a passive OAuth poll (or vice versa). The second operation is
      // queued behind the first instead of being silently swallowed.
      return pending.whenComplete(() => refreshStatusWithMode(
            mode,
            mcpServers: mcpServers,
          ));
    }
    final generation = ++_statusGeneration;
    final sourceGeneration = _sourceGeneration;
    statusListStatus = McpStatusStatus.loading;
    statusListError = null;
    _pendingStatusMode = mode;
    _pendingStatusFilter = requestedFilter;
    notifyListeners();
    Future<void>? future;
    Future<void> operation() async {
      try {
        final raw = await session.channels.call(
          Channels.mcpSync,
          'listWorkspaceMcpServerStatuses',
          [_statusPayload(mode, mcpServers: mcpServers)],
          timeout: const Duration(seconds: 30),
        );
        if (_disposed ||
            generation != _statusGeneration ||
            sourceGeneration != _sourceGeneration) {
          return;
        }
        final statuses = raw is Map && raw['statuses'] is List
            ? (raw['statuses'] as List)
                .whereType<Map>()
                .map(McpServerStatus.fromRaw)
                .where((item) => item.name.isNotEmpty)
                .toList()
            : const <McpServerStatus>[];
        _statusSnapshots
          ..clear()
          ..addEntries([
            for (final item in statuses) MapEntry(_statusIdentity(item), item),
          ]);
        _mergeStatuses(statuses);
        if (mode == McpStatusMode.status) statusModeUnsupported = false;
        statusListStatus = McpStatusStatus.loaded;
        statusListError = null;
      } catch (value) {
        if (_disposed ||
            generation != _statusGeneration ||
            sourceGeneration != _sourceGeneration) {
          return;
        }
        if (mode == McpStatusMode.status && _unsupported(value)) {
          statusModeUnsupported = true;
        }
        statusListStatus = McpStatusStatus.error;
        statusListError = StateError(redactMcpErrorText(value,
            secrets: _mcpSecretValues(items.map((e) => e.config))));
      } finally {
        if (_pendingStatus == future) _pendingStatus = null;
        if (_pendingStatus == null) {
          _pendingStatusMode = null;
          _pendingStatusFilter = null;
        }
        if (!_disposed &&
            generation == _statusGeneration &&
            sourceGeneration == _sourceGeneration) {
          notifyListeners();
        }
      }
    }

    future = operation();
    _pendingStatus = future;
    return future;
  }

  void _mergeStatuses(List<McpServerStatus> statuses) {
    final next = <McpServerEntry>[];
    for (final item in items) {
      if (item.source != 'zcodeagentmcp') {
        next.add(item);
        continue;
      }
      final matches = statuses.where((status) {
        if (status.name != item.name) return false;
        final project = status.raw['projectPath'];
        if (project is String) {
          return item.projectPath != null && project == item.projectPath;
        }
        // A workspace entry must never consume a user/common status which
        // omitted its project path. This keeps same-named sources isolated.
        if (item.projectPath != null) return false;
        final statusScope = status.raw['scope'];
        if (statusScope is String &&
            statusScope.isNotEmpty &&
            statusScope != item.scope) {
          return false;
        }
        final source = status.raw['source'];
        return source == null || source == 'mcp' || source == 'zcodeagentmcp';
      }).toList(growable: false);
      next.add(matches.length == 1 ? item.withStatus(matches.single) : item);
    }
    items = next;
  }

  final Map<String, McpServerStatus> _statusSnapshots =
      <String, McpServerStatus>{};

  static String _statusIdentity(McpServerStatus status) =>
      '${status.raw['pluginId'] ?? status.raw['source'] ?? ''}:${status.name}:${status.raw['runtimeServerName'] ?? ''}:${status.raw['projectPath'] ?? ''}';

  Future<bool> upsert(
    McpFormDraft draft, {
    McpServerEntry? editing,
  }) async {
    if (_disposed) return false;
    final validation = draft.validationError;
    if (validation != null) {
      if (editing != null) {
        _operationErrors[editing.identity] = StateError(validation);
      }
      notifyListeners();
      return false;
    }
    if (editing != null &&
        (editing.name != draft.name.trim() || editing.isReadOnly)) {
      _operationErrors[editing.identity] =
          StateError('MCP identity cannot change');
      notifyListeners();
      return false;
    }
    final targetScope = editing?.scope ?? draft.storageLevel;
    if (targetScope == 'workspace' && _workspace.isEmpty) {
      final missingPathIdentity = editing?.identity ??
          _mcpIdentity('zcodeagentmcp', draft.name.trim(), null);
      _operationErrors[missingPathIdentity] =
          StateError('Workspace MCP configuration requires workspacePath');
      notifyListeners();
      return false;
    }
    final identity = editing?.identity ??
        _mcpIdentity('zcodeagentmcp', draft.name.trim(),
            targetScope == 'workspace' ? _workspace : null);
    final config = draft.toConfig();
    return _runWrite(identity, () async {
      if (editing != null && !editing.enabled) config['enable'] = false;
      await session.channels.call(
        Channels.mcpSync,
        'saveMcpToUserDirectory',
        [
          {
            'action': 'upsert',
            'source': 'zcodeagentmcp',
            'name': draft.name.trim(),
            'config': config,
            if (targetScope == 'workspace' && _workspace.isNotEmpty)
              'projectPath': editing?.projectPath ?? _workspace,
          }
        ],
        timeout: const Duration(seconds: 30),
      );
    }, secretValues: _mcpSecretValues(config));
  }

  Future<bool> setEnabled(McpServerEntry entry, bool enabled) async {
    if (_disposed || !entry.canManage) return false;
    return _runWrite(entry.identity, () async {
      await session.channels.call(
        Channels.mcpSync,
        'saveMcpToUserDirectory',
        [
          {
            'action': 'set-enabled',
            'source': entry.source,
            'name': entry.name,
            'enabled': enabled,
            if (entry.projectPath != null) 'projectPath': entry.projectPath,
            if (entry.location != null) 'location': entry.location,
          }
        ],
        timeout: const Duration(seconds: 30),
      );
    }, secretValues: _mcpSecretValues(entry.config));
  }

  Future<bool> delete(McpServerEntry entry) async {
    if (_disposed || !entry.canManage) return false;
    return _runWrite(entry.identity, () async {
      await session.channels.call(
        Channels.mcpSync,
        'saveMcpToUserDirectory',
        [
          {
            'action': 'delete',
            'source': entry.source,
            'name': entry.name,
            if (entry.projectPath != null) 'projectPath': entry.projectPath,
          }
        ],
        timeout: const Duration(seconds: 30),
      );
    }, secretValues: _mcpSecretValues(entry.config));
  }

  Future<bool> _runWrite(String identity, Future<void> Function() operation,
      {Iterable<String> secretValues = const []}) async {
    if (_disposed || _operatingTokens.containsKey(identity)) return false;
    final generation = _sourceGeneration;
    final operationToken = ++_nextOperationToken;
    _operatingTokens[identity] = operationToken;
    _operationErrors.remove(identity);
    notifyListeners();
    try {
      await operation();
      if (_disposed || generation != _sourceGeneration) return false;
      await loadConfigs(force: true);
      if (_disposed || generation != _sourceGeneration) return false;
      if (status == McpCatalogStatus.error) {
        throw error ?? StateError('MCP configuration read-back failed');
      }
      final callback = onConfigurationChanged;
      if (callback != null) await callback();
      return true;
    } catch (value) {
      if (!_disposed && generation == _sourceGeneration) {
        _operationErrors[identity] =
            StateError(redactMcpErrorText(value, secrets: secretValues));
        notifyListeners();
      }
      return false;
    } finally {
      if (_operatingTokens[identity] == operationToken) {
        _operatingTokens.remove(identity);
        if (!_disposed) notifyListeners();
      }
    }
  }

  static bool _sameMap(Map<String, dynamic> left, Map<String, dynamic> right) {
    if (left.length != right.length) return false;
    for (final entry in left.entries) {
      if (right[entry.key] != entry.value) return false;
    }
    return true;
  }

  static bool _unsupported(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('status mode unsupported') ||
        message.contains('not supported') ||
        message.contains('unknown method') ||
        message.contains('method not found');
  }

  @override
  void dispose() {
    _disposed = true;
    _configGeneration++;
    _statusGeneration++;
    _sourceGeneration++;
    super.dispose();
  }
}
