import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/mcp_catalog.dart';
import 'package:zcode_remote/ui/mcp_settings.dart';
import 'package:zcode_remote/ui/settings_scope.dart';

import 'fake_features.dart';
import 'review_capture.dart';

Map<String, dynamic> _server(String name) => {
      'id': name,
      'name': name,
      'source': 'zcodeagentmcp',
      'scope': 'user',
      'enabled': true,
      'config': {'type': 'http', 'url': 'https://synthetic.invalid/mcp'},
    };

McpCatalog _catalog(String name, List<String> modes, {bool auth = false}) {
  final bridge = FeatureBridge();
  bridge.channels.handler = (channel, method, args) {
    if (method == 'loadMcpFromUserDirectory') {
      return {
        'servers': [_server(name)]
      };
    }
    if (method == 'listWorkspaceMcpServerStatuses') {
      final mode = (args.single as Map)['mode'] as String;
      modes.add(mode);
      return {
        'statuses': [
          {
            'name': name,
            'status': auth && mode == 'connect' ? 'error' : 'connected',
            if (auth && mode == 'connect') ...{
              'failureKind': 'auth_required',
              'authorizationUrl': 'https://synthetic.invalid/authorize',
            },
            'toolCount': 2,
          }
        ]
      };
    }
    return {};
  };
  return McpCatalog(
      session: bridge, scope: {'workspaceIdentity': name}, scopeKey: name);
}

Widget _page(McpCatalog catalog) => MaterialApp(
      home: Scaffold(
          body: McpSettingsPage(
              key: const ValueKey('same-page'), catalog: catalog)),
    );

void main() {
  testWidgets(
      'review: visible MCP authorization waits poll status and stop on hide',
      (tester) async {
    final modes = <String>[];
    final catalog = _catalog('auth-server', modes, auth: true);
    try {
      await tester.pumpWidget(_page(catalog));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1100));
      await tester.pump();
      expect(modes.first, 'connect');
      expect(modes.where((mode) => mode == 'status'), isNotEmpty,
          reason:
              'Authorization completion must update without another connect.');
      expect(catalog.items.single.status, 'connected');
      await tester.pumpWidget(const SizedBox.shrink());
      final count = modes.length;
      await tester.pump(const Duration(seconds: 15));
      expect(modes, hasLength(count));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    }
  });

  testWidgets(
      'review: switching a visible MCP catalog clears the previous inline draft',
      (tester) async {
    final modesA = <String>[];
    final modesB = <String>[];
    final a = _catalog('catalog-A', modesA);
    final b = _catalog('catalog-B', modesB);
    await b.loadConfigs();
    try {
      await tester.pumpWidget(_page(a));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('mcp-create')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mcp-save')), findsOneWidget);
      await tester.pumpWidget(_page(b));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('mcp-save')), findsNothing,
          reason: 'An A draft must not be rebound to B by widget update.');
      expect(find.text('catalog-B'), findsOneWidget);
      expect(modesB, ['connect']);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      a.dispose();
      b.dispose();
    }
  });

  testWidgets(
      'review: MCP workspace scope and controls fit 344px at 140 percent',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(344, 760);
    addTearDown(tester.view.reset);
    final catalog = _catalog('A-long-server-name-for-layout-review', []);
    final boundary = GlobalKey();
    const device = Device(
        id: 'fake-device',
        label: 'Synthetic development workstation',
        url: '',
        addedAt: 0,
        lastUsedAt: 0);
    final options = [
      for (final key in ['first-long-workspace-name', 'second-workspace'])
        SettingsScopeOption(
            deviceId: device.id,
            deviceLabel: device.label,
            workspaceKey: key,
            workspaceName: key,
            workspacePath: 'D:/Synthetic/$key',
            scope: const {},
            device: device),
    ];
    try {
      await tester.runAsync(loadReviewCaptureFonts);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(344, 760), textScaler: TextScaler.linear(1.4)),
              child: RepaintBoundary(
                  key: boundary,
                  child: Scaffold(
                      body: McpSettingsPage(
                          catalog: catalog,
                          workspaceScopeOptions: options,
                          selectedWorkspaceScope: options.first,
                          onWorkspaceScopeChanged: (_) {}))))));
      await tester.pumpAndSettle();
      await captureReviewBoundary(tester, boundary, 'u16-mcp-344-en-140');
      expect(tester.takeException(), isNull,
          reason:
              'Long workspace labels and row controls must remain reachable.');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    }
  });
}
