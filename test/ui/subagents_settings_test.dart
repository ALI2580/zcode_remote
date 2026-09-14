import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/remote_agent_catalogs.dart';
import 'package:zcode_remote/ui/subagents_settings.dart';
import 'fake_features.dart';

void main() {
  testWidgets('subagent page groups sources and filters locally',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'list') {
        return {
          'agents': [
            {
              'id': 'reviewer',
              'name': 'reviewer',
              'description': 'Reviews code',
              'scope': 'user',
              'source': 'user',
              'enabled': true,
            },
            {
              'id': 'general-purpose',
              'name': 'general-purpose',
              'scope': 'built-in',
              'source': 'built-in',
            },
          ],
          'pluginAgents': [
            {
              'id': 'plugin-reviewer',
              'name': 'plugin-reviewer',
              'description': 'Plugin review',
              'source': 'plugin',
            },
          ],
          'capability': {'supported': true, 'userScopeAvailable': true},
        };
      }
      return null;
    };
    final catalog = SubagentsCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'synthetic'},
      scopeKey: 'device|synthetic',
    );
    addTearDown(catalog.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SubagentsSettingsPage(
          catalog: catalog,
          modelOptions: const [
            SubagentModelOption(value: 'glm/GLM-5.3', label: 'GLM-5.3'),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Installed'), findsOneWidget);
    expect(find.text('Plugin subagents'), findsOneWidget);
    expect(find.text('Built-in subagents'), findsOneWidget);
    expect(find.byKey(const ValueKey('subagent-enabled-reviewer')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('subagent-model-general-purpose')),
        findsOneWidget);

    await tester.enterText(
        find.byKey(const ValueKey('subagents-search')), 'plugin-reviewer');
    await tester.pump();
    expect(find.byKey(const ValueKey('subagent-row-plugin-reviewer')),
        findsOneWidget);
    expect(find.byKey(const ValueKey('subagent-row-reviewer')), findsNothing);
  });

  testWidgets('new subagent form validates and sends a complete config',
      (tester) async {
    final bridge = FeatureBridge();
    final calls = <({String method, List<Object?> args})>[];
    bridge.channels.handler = (channel, method, args) async {
      calls.add((method: method, args: args));
      if (method == 'list') {
        return {
          'agents': <Map<String, dynamic>>[],
          'capability': {'userScopeAvailable': true},
        };
      }
      return null;
    };
    final catalog = SubagentsCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'synthetic'},
      scopeKey: 'device|synthetic',
    );
    addTearDown(catalog.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SubagentsSettingsPage(
          catalog: catalog,
          modelOptions: const [
            SubagentModelOption(
              value: 'glm/GLM-5.3',
              label: 'GLM-5.3',
              thoughtLevels: ['high', 'max'],
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('subagents-create')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).at(0), 'review-agent');
    await tester.enterText(
        find.byType(TextField).at(1), 'Reviews pull requests');
    await tester.enterText(
        find.byType(TextField).at(2), 'Review the provided change');
    await tester.tap(find.byKey(const ValueKey('subagent-model-field')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('GLM-5.3').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('subagent-save')));
    await tester.tap(find.byKey(const ValueKey('subagent-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('subagent-save')), findsNothing);
    final create = calls.firstWhere((call) => call.method == 'createAgent');
    final payload = (create.args.single as Map).cast<String, dynamic>();
    final config = (payload['config'] as Map).cast<String, dynamic>();
    expect(config['name'], 'review-agent');
    expect(config['description'], 'Reviews pull requests');
    expect(config['systemPrompt'], 'Review the provided change');
    expect(config['model'], 'glm/GLM-5.3');
    expect(payload['scope'], 'user');
  });

  testWidgets('inline draft closes when the catalog source changes',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) async {
      if (method == 'list') {
        return {
          'agents': <Map<String, dynamic>>[],
          'capability': {'userScopeAvailable': true},
        };
      }
      return null;
    };
    final catalog = SubagentsCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'A'},
      scopeKey: 'device|A',
    );
    addTearDown(catalog.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: ThemeData.dark(),
      home: Scaffold(
        body: SubagentsSettingsPage(catalog: catalog),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('subagents-create')));
    await tester.pump();
    expect(find.byKey(const ValueKey('subagent-save')), findsOneWidget);

    catalog.updateScope(
      nextScope: const {'workspaceIdentity': 'B'},
      nextScopeKey: 'device|B',
    );
    await tester.pump();
    expect(find.byKey(const ValueKey('subagent-save')), findsNothing);
    expect(find.byKey(const ValueKey('subagents-search')), findsOneWidget);
  });

  testWidgets('scope options may switch to a catalog owned by another bridge',
      (tester) async {
    final bridgeA = FeatureBridge();
    final bridgeB = FeatureBridge();
    bridgeA.channels.handler = (channel, method, args) async => {
          'agents': [
            {
              'id': 'agent-a',
              'name': 'agent-a',
              'scope': 'user',
              'source': 'user',
            }
          ],
          'capability': {'userScopeAvailable': true},
        };
    bridgeB.channels.handler = (channel, method, args) async => {
          'agents': [
            {
              'id': 'agent-b',
              'name': 'agent-b',
              'scope': 'workspace',
              'source': 'user',
              'projectPath': 'D:/B',
            }
          ],
          'capability': {'userScopeAvailable': true},
        };
    final catalogA = SubagentsCatalog(
      session: bridgeA,
      scope: const {'workspaceIdentity': 'A'},
      scopeKey: 'device|A',
    );
    final catalogB = SubagentsCatalog(
      session: bridgeB,
      scope: const {'workspaceIdentity': 'B'},
      scopeKey: 'device|B',
      workspacePath: 'D:/B',
    );
    addTearDown(catalogA.dispose);
    addTearDown(catalogB.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SubagentsSettingsPage(
          catalog: catalogA,
          scopes: [
            SubagentScopeOption(
              key: 'a',
              label: 'A',
              scope: 'user',
              identity: const {'workspaceIdentity': 'A'},
              catalog: catalogA,
            ),
            SubagentScopeOption(
              key: 'b',
              label: 'B',
              scope: 'workspace',
              identity: const {'workspaceIdentity': 'B'},
              workspacePath: 'D:/B',
              catalog: catalogB,
            ),
          ],
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('agent-a'), findsOneWidget);
    await tester.tap(find.text('A').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('B').last);
    await tester.pumpAndSettle();
    expect(find.text('agent-b'), findsOneWidget);
    expect(find.text('agent-a'), findsNothing);
  });
}
