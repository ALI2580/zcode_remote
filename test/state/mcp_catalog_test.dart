import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/mcp_catalog.dart';
import 'package:zcode_remote/state/mcp_status.dart';

import '../ui/fake_features.dart';

Map<String, dynamic> _server({
  String name = 'docs-server',
  String scope = 'user',
  String? projectPath,
  bool enabled = true,
  Map<String, dynamic>? config,
}) =>
    {
      'id': '$scope:$name:${projectPath ?? ''}',
      'name': name,
      'scope': scope,
      'source': 'zcodeagentmcp',
      'enabled': enabled,
      if (projectPath != null) 'projectPath': projectPath,
      'config': config ??
          {
            'type': 'stdio',
            'command': 'node',
            'args': ['server.js'],
            'unknownFutureField': {'keep': true},
            'env': {'API_TOKEN': 'fake-secret'},
          },
    };

void main() {
  test('MCP config form follows the official payload rules', () {
    final entry = McpServerEntry.fromRaw(_server(enabled: false));
    final draft = McpFormDraft.fromEntry(entry);
    expect(draft.args, 'server.js');
    expect(draft.toConfig()['args'], ['server.js']);
    expect(draft.toConfig()['unknownFutureField'], {'keep': true});
    expect(entry.redactedConfig, isNotEmpty);
    expect(entry.redactedConfig['env'], {'API_TOKEN': '<redacted>'});

    final parsed = McpFormDraft.parseJson('''
      {"mcpServers":{"remote":{"type":"streamableHttp","url":"https://example.test/mcp","timeoutMs":12.9,"protocolVersion":"auto"}}}
    ''');
    expect(parsed.name, 'remote');
    expect(parsed.type, McpServerType.streamableHttp);
    expect(parsed.toConfig()['timeoutMs'], 12);
    expect(parsed.toConfig().containsKey('protocolVersion'), isFalse);
  });

  test('a successful status read clears stale error and authorization', () {
    final old = McpServerEntry.fromRaw({
      ..._server(),
      'status': 'error',
      'error': 'expired',
      'failureKind': 'connection_failed',
      'authorization': {'authorizationUrl': 'https://old.example/auth'},
      'authorizationUrl': 'https://old.example/auth',
    });
    final merged = old.withStatus(const McpServerStatus(
      name: 'docs-server',
      state: 'connected',
      toolCount: 4,
    ));
    expect(merged.status, 'connected');
    expect(merged.error, isNull);
    expect(merged.failureKind, isNull);
    expect(merged.authorizationUrl, isNull);
    expect(merged.toolCount, 4);
  });

  test('MCP config writes use exact save payload and read back', () async {
    final bridge = FeatureBridge();
    final calls = <({String method, Map<String, dynamic> payload})>[];
    bridge.channels.handler = (channel, method, args) {
      expect(channel, 'mcp-sync');
      final payload = (args.single as Map).cast<String, dynamic>();
      calls.add((method: method, payload: payload));
      if (method == 'loadMcpFromUserDirectory') {
        return {
          'servers': [_server()]
        };
      }
      if (method == 'saveMcpToUserDirectory') return {'success': true};
      if (method == 'listWorkspaceMcpServerStatuses') return {'statuses': []};
      return {};
    };
    final catalog = McpCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'fake'},
      scopeKey: 'device|workspace',
      workspacePath: 'D:/Synthetic',
    );
    addTearDown(catalog.dispose);

    await catalog.loadConfigs();
    expect(catalog.items.single.name, 'docs-server');
    final created = await catalog.upsert(McpFormDraft(
      name: 'new-server',
      type: McpServerType.http,
      url: 'https://example.test/mcp',
      storageLevel: 'workspace',
    ));
    expect(created, isTrue);
    final upsert = calls
        .where((call) =>
            call.method == 'saveMcpToUserDirectory' &&
            call.payload['action'] == 'upsert')
        .single
        .payload;
    expect(upsert['source'], 'zcodeagentmcp');
    expect(upsert['name'], 'new-server');
    expect(upsert['projectPath'], 'D:/Synthetic');
    expect((upsert['config'] as Map)['url'], 'https://example.test/mcp');
  });

  test('old source operation cannot clear a newer same-id operation', () async {
    final bridge = FeatureBridge();
    final firstSave = Completer<void>();
    final secondSave = Completer<void>();
    var saveCount = 0;
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'saveMcpToUserDirectory') {
        final call = ++saveCount;
        if (call == 1) await firstSave.future;
        if (call == 2) await secondSave.future;
        return {'success': true};
      }
      if (method == 'loadMcpFromUserDirectory') return {'servers': []};
      return {'statuses': []};
    };
    final catalog = McpCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'A'},
      scopeKey: 'device|A',
      workspacePath: 'D:/A',
    );
    addTearDown(catalog.dispose);
    final draft = McpFormDraft(
      name: 'same-id',
      type: McpServerType.http,
      url: 'https://example.test/mcp',
    );
    final oldOperation = catalog.upsert(draft);
    await Future<void>.delayed(Duration.zero);
    catalog.updateScope(
      nextScope: const {'workspaceIdentity': 'B'},
      nextScopeKey: 'device|B',
      nextWorkspacePath: 'D:/B',
    );
    final newOperation = catalog.upsert(draft);
    await Future<void>.delayed(Duration.zero);
    expect(
        catalog.isOperating(catalog.items.isEmpty
            ? 'zcodeagentmcp:same-id:'
            : catalog.items.single.identity),
        isTrue);
    firstSave.complete();
    await oldOperation;
    expect(catalog.isOperating('zcodeagentmcp:same-id:'), isTrue);
    secondSave.complete();
    await newOperation;
    expect(catalog.isOperating('zcodeagentmcp:same-id:'), isFalse);
  });

  test('passive status does not auto-upgrade to connect', () async {
    final bridge = FeatureBridge();
    final modes = <String>[];
    bridge.channels.handler = (channel, method, args) {
      final mode = (args.single as Map)['mode'] as String;
      modes.add(mode);
      throw StateError('status mode unsupported');
    };
    final catalog = McpCatalog(
      session: bridge,
      scope: const {'workspacePath': 'D:/Synthetic'},
      scopeKey: 'device|workspace',
    );
    addTearDown(catalog.dispose);
    await catalog.refreshStatus();
    expect(modes, ['status']);
    expect(catalog.statusModeUnsupported, isTrue);
    expect(catalog.statusListStatus, McpStatusStatus.error);
  });

  test('visible MCP page connects once per config signature', () async {
    final bridge = FeatureBridge();
    final modes = <String>[];
    bridge.channels.handler = (channel, method, args) {
      if (method == 'loadMcpFromUserDirectory') {
        return {
          'servers': [_server()]
        };
      }
      if (method == 'listWorkspaceMcpServerStatuses') {
        modes.add((args.single as Map)['mode'] as String);
        return {'statuses': []};
      }
      return {};
    };
    final catalog = McpCatalog(
      session: bridge,
      scope: const {},
      scopeKey: 'fake',
    );
    addTearDown(catalog.dispose);
    await catalog.loadConfigs();
    expect(modes, isEmpty);
    await catalog.ensureConnectedForVisible();
    await catalog.ensureConnectedForVisible();
    expect(modes, ['connect']);
  });

  test('workspace MCP write is gated when the selected scope has no path',
      () async {
    final bridge = FeatureBridge();
    var writes = 0;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'saveMcpToUserDirectory') writes++;
      return {'servers': []};
    };
    final catalog = McpCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'without-path'},
      scopeKey: 'device|without-path',
    );
    addTearDown(catalog.dispose);
    final saved = await catalog.upsert(McpFormDraft(
      name: 'workspace-only',
      type: McpServerType.http,
      url: 'https://example.test/mcp',
      storageLevel: 'workspace',
    ));
    expect(saved, isFalse);
    expect(writes, 0);
    expect(catalog.operationError('zcodeagentmcp:workspace-only:'), isNotNull);
  });

  test('same-name workspace status cannot update the user row', () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (method == 'loadMcpFromUserDirectory') {
        return {
          'servers': [
            _server(scope: 'user'),
            _server(scope: 'workspace', projectPath: 'D:/B'),
          ]
        };
      }
      if (method == 'listWorkspaceMcpServerStatuses') {
        return {
          'statuses': [
            {
              'name': 'docs-server',
              'projectPath': 'D:/B',
              'status': 'connected',
              'toolCount': 3,
            }
          ]
        };
      }
      return {};
    };
    final catalog = McpCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'B'},
      scopeKey: 'device|B',
      workspacePath: 'D:/B',
    );
    addTearDown(catalog.dispose);
    await catalog.loadConfigs();
    await catalog.refreshStatus();
    final rows = catalog.items.where((item) => item.name == 'docs-server');
    expect(rows.where((item) => item.scope == 'user').single.status, 'unknown');
    expect(rows.where((item) => item.scope == 'workspace').single.status,
        'connected');
  });

  test('OAuth status payload contains only challenged native servers',
      () async {
    final bridge = FeatureBridge();
    Map<String, dynamic>? payload;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'listWorkspaceMcpServerStatuses') {
        payload = (args.single as Map).cast<String, dynamic>();
        return {'statuses': []};
      }
      return {
        'servers': [
          {
            ..._server(name: 'oauth-server'),
            'authorization': {'authorizationUrl': 'https://example.test/auth'},
          },
          _server(name: 'plain-server'),
        ]
      };
    };
    final catalog = McpCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'oauth'},
      scopeKey: 'device|oauth',
    );
    addTearDown(catalog.dispose);
    await catalog.loadConfigs();
    await catalog.refreshOAuthStatus();
    expect(payload?['mode'], 'status');
    expect(payload?['mcpServers'], [
      {
        'name': 'oauth-server',
        'type': 'stdio',
        'command': 'node',
        'args': ['server.js'],
        'unknownFutureField': {'keep': true},
        'env': {'API_TOKEN': 'fake-secret'},
      }
    ]);
  });

  test('write failures redact known MCP credentials while retaining context',
      () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (method == 'saveMcpToUserDirectory') {
        throw StateError('headers Authorization: Bearer synthetic-secret');
      }
      if (method == 'loadMcpFromUserDirectory') return {'servers': []};
      return {'statuses': []};
    };
    final catalog = McpCatalog(
      session: bridge,
      scope: const {},
      scopeKey: 'fake',
    );
    addTearDown(catalog.dispose);
    final draft = McpFormDraft(
      name: 'secret-server',
      type: McpServerType.http,
      url: 'https://example.test/mcp',
      headers: '{"Authorization":"Bearer synthetic-secret"}',
    );
    expect(await catalog.upsert(draft), isFalse);
    final error =
        catalog.operationError('zcodeagentmcp:secret-server:').toString();
    expect(error, contains('headers'));
    expect(error, isNot(contains('synthetic-secret')));
    expect(error, contains('<redacted>'));
  });
}
