import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/mcp_catalog.dart';
import '../ui/fake_features.dart';

void main() {
  test(
      'review: a workspace MCP save without a path cannot fall back to user scope',
      () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, method, __) =>
        method == 'loadMcpFromUserDirectory' ? {'servers': []} : {};
    final catalog =
        McpCatalog(session: bridge, scope: const {}, scopeKey: 'no-workspace');
    addTearDown(catalog.dispose);
    final saved = await catalog.upsert(McpFormDraft(
        name: 'workspace-server', command: 'node', storageLevel: 'workspace'));
    expect(saved, isFalse);
    expect(
        bridge.channels.calls
            .where((call) => call.method == 'saveMcpToUserDirectory'),
        isEmpty,
        reason: 'Omitting projectPath would target another settings file.');
  });

  test('review: a project-only status must not update a same-name user MCP row',
      () async {
    final bridge = FeatureBridge();
    bridge.channels.handler =
        (_, method, __) => method == 'loadMcpFromUserDirectory'
            ? {
                'servers': [
                  {
                    'id': 'user:docs',
                    'name': 'docs',
                    'scope': 'user',
                    'source': 'zcodeagentmcp',
                    'config': {'command': 'user-command'}
                  },
                  {
                    'id': 'project:docs',
                    'name': 'docs',
                    'scope': 'workspace',
                    'projectPath': 'D:/Project',
                    'source': 'zcodeagentmcp',
                    'config': {'command': 'project-command'}
                  },
                ]
              }
            : {
                'statuses': [
                  {
                    'name': 'docs',
                    'projectPath': 'D:/Project',
                    'status': 'connected',
                    'toolCount': 3
                  }
                ]
              };
    final catalog = McpCatalog(
        session: bridge,
        scope: const {'workspacePath': 'D:/Project'},
        scopeKey: 'project');
    addTearDown(catalog.dispose);
    await catalog.loadConfigs();
    await catalog.refreshStatus();
    expect(catalog.items.first.status, 'unknown',
        reason:
            'A name match alone does not authorize crossing config scopes.');
    expect(catalog.items.last.status, 'connected');
  });

  test(
      'review: a failed MCP save does not expose an echoed configured credential',
      () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, method, __) {
      if (method == 'saveMcpToUserDirectory') {
        throw StateError(
            'Synthetic failure Authorization: Bearer synthetic-mcp-secret');
      }
      return {'servers': []};
    };
    final catalog =
        McpCatalog(session: bridge, scope: const {}, scopeKey: 'secrets');
    addTearDown(catalog.dispose);
    final saved = await catalog.upsert(McpFormDraft(
        name: 'docs',
        type: McpServerType.http,
        url: 'https://synthetic.invalid',
        headers: '{"Authorization":"Bearer synthetic-mcp-secret"}'));
    expect(saved, isFalse);
    final feedback = catalog.operationError('zcodeagentmcp:docs:');
    expect(feedback, isNotNull);
    expect(feedback.toString(), isNot(contains('synthetic-mcp-secret')));
  });
}
