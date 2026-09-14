import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/mcp_status.dart';

import '../ui/fake_features.dart';

void main() {
  test('MCP status catalog parses workspace server statuses', () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      expect(channel, 'mcp-sync');
      expect(method, 'listWorkspaceMcpServerStatuses');
      final scope = args.single as Map;
      expect(scope['mode'], 'status');
      return {
        'statuses': [
          {
            'name': 'docs-server',
            'status': 'connected',
            'enabled': true,
            'toolCount': 3
          }
        ]
      };
    };
    final controller = McpStatusCatalog(
        session: bridge,
        scope: const {'workspacePath': 'D:/Synthetic'},
        scopeKey: 'device|workspace');
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.status, McpStatusStatus.loaded);
    expect(controller.error, isNull);
    expect(controller.items.single.name, 'docs-server');
    expect(controller.items.single.state, 'connected');
    expect(controller.items.single.enabled, isTrue);
    expect(controller.items.single.toolCount, 3);
  });

  test('MCP status reports unsupported mode without auto-connecting', () async {
    final bridge = FeatureBridge();
    var modes = <String>[];
    bridge.channels.handler = (channel, method, args) {
      modes.add((args.single as Map)['mode'] as String);
      throw StateError('status mode unsupported');
    };
    final controller = McpStatusCatalog(
        session: bridge,
        scope: const {'workspacePath': 'D:/Synthetic'},
        scopeKey: 'device|workspace');
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(modes, ['status']);
    expect(controller.statusModeUnsupported, isTrue);
    expect(controller.status, McpStatusStatus.error);
    expect(controller.error, isA<StateError>());

    bridge.channels.handler = (channel, method, args) {
      modes.add((args.single as Map)['mode'] as String);
      expect((args.single as Map)['mode'], 'connect');
      return {
        'statuses': [
          {'name': 'docs-server', 'status': 'connected'}
        ]
      };
    };
    await controller.connect();
    expect(modes, ['status', 'connect']);
    expect(controller.status, McpStatusStatus.loaded);
    expect(controller.items.single.name, 'docs-server');
  });
}
