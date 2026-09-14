import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/state/remote_agent_catalogs.dart';
import '../ui/fake_features.dart';

void main() {
  test('subagents and commands read the official channels and stay read-only',
      () async {
    final bridge = FeatureBridge();
    final calls = <(String, String, List<Object?>)>[];
    bridge.channels.handler = (channel, method, args) async {
      calls.add((channel, method, args));
      if (channel == Channels.subagents) {
        return {
          'agents': [
            {
              'id': 'reviewer',
              'name': 'Reviewer',
              'description': 'Reviews changes',
              'enabled': true,
              'scope': 'user',
            }
          ],
          'capability': {'supported': true},
        };
      }
      return {
        'commands': [
          {'id': 'goal', 'name': 'goal', 'description': 'Set a goal'}
        ],
        'userCommands': [
          {'id': 'compact', 'name': 'compact', 'enabled': false}
        ],
        'pluginCommands': [
          {'id': 'deploy', 'name': 'deploy'}
        ],
        'capability': {'userScopeAvailable': true},
      };
    };

    final subagents = SubagentsCatalog(
        session: bridge,
        scope: {'workspaceIdentity': 'workspace'},
        scopeKey: 'A|workspace',
        workspacePath: 'D:/Synthetic');
    final commands = CommandsCatalog(
        session: bridge,
        scope: {'workspaceIdentity': 'workspace'},
        scopeKey: 'A|workspace',
        workspacePath: 'D:/Synthetic');
    addTearDown(subagents.dispose);
    addTearDown(commands.dispose);
    await Future.wait([subagents.refresh(), commands.refresh()]);

    expect(calls.any((call) => call.$1 == 'subagents' && call.$2 == 'list'),
        isTrue);
    expect(calls.any((call) => call.$1 == 'commands' && call.$2 == 'list'),
        isTrue);
    expect(subagents.status, RemoteAgentCatalogStatus.loaded);
    expect(subagents.items.single.title, 'Reviewer');
    expect(subagents.items.single.enabled, isTrue);
    expect(subagents.supported, isTrue);
    expect(
        commands.items.map((e) => e.group).toList(), ['all', 'user', 'plugin']);
    expect(commands.status, RemoteAgentCatalogStatus.loaded);
  });

  test('catalog failures keep prior data and empty retry clears it', () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      if (channel == Channels.subagents) {
        return {
          'agents': [
            {'id': 'old', 'name': 'Old reviewer'}
          ],
        };
      }
      return {
        'commands': [
          {'id': 'old-command', 'name': 'old-command'}
        ],
      };
    };
    final subagents = SubagentsCatalog(
        session: bridge,
        scope: const {'workspaceIdentity': 'workspace'},
        scopeKey: 'A|workspace');
    final commands = CommandsCatalog(
        session: bridge,
        scope: const {'workspaceIdentity': 'workspace'},
        scopeKey: 'A|workspace');
    addTearDown(subagents.dispose);
    addTearDown(commands.dispose);
    await Future.wait([subagents.refresh(), commands.refresh()]);

    bridge.channels.handler = (_, __, ___) => throw StateError('offline');
    await Future.wait([subagents.refresh(), commands.refresh()]);
    expect(subagents.status, RemoteAgentCatalogStatus.error);
    expect(subagents.items.single.title, 'Old reviewer');
    expect(commands.status, RemoteAgentCatalogStatus.error);
    expect(commands.items.single.title, 'old-command');

    bridge.channels.handler = (_, __, ___) => {};
    await Future.wait([subagents.refresh(), commands.refresh()]);
    expect(subagents.status, RemoteAgentCatalogStatus.loaded);
    expect(subagents.items, isEmpty);
    expect(commands.status, RemoteAgentCatalogStatus.loaded);
    expect(commands.items, isEmpty);
  });

  test('a disposed catalog does not apply its late list response', () async {
    final bridge = FeatureBridge();
    final response = Completer<Object?>();
    bridge.channels.handler = (_, __, ___) => response.future;
    final controller = CommandsCatalog(
        session: bridge,
        scope: const {'workspaceIdentity': 'workspace'},
        scopeKey: 'A|workspace');
    final pending = controller.refresh();
    await pumpEventQueue();
    controller.dispose();
    response.complete({
      'commands': [
        {'id': 'late', 'name': 'late-command'}
      ]
    });
    await pending;
    expect(controller.items, isEmpty);
  });

  test('command enable writes the official row and renders the read-back',
      () async {
    final bridge = FeatureBridge();
    var enabled = true;
    Map<String, Object?>? lastPatch;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'setCommandEnabled') {
        lastPatch = (args.single as Map).cast<String, Object?>();
        enabled = lastPatch!['enabled'] as bool;
        return null;
      }
      return {
        'commands': [
          {
            'id': 'goal',
            'name': 'goal',
            'description': 'Set a goal',
            'enabled': enabled,
          }
        ],
        'userCommands': [],
        'pluginCommands': [],
        'capability': {'userScopeAvailable': true},
      };
    };
    final controller = CommandsCatalog(
        session: bridge,
        scope: const {'workspaceIdentity': 'workspace'},
        scopeKey: 'A|workspace');
    addTearDown(controller.dispose);
    await controller.refresh();
    final entry = controller.items.single;

    await controller.setEnabled(entry, enabled: false);
    expect(lastPatch, {
      'agentSource': 'user',
      'commandId': 'goal',
      'filePath': '',
      'enabled': false,
    });
    expect(controller.items.single.enabled, isFalse);
    expect(controller.saveError('goal'), isNull);
    expect(controller.isSaving('goal'), isFalse);
  });

  test('a failed command enable keeps the prior read-back value', () async {
    final bridge = FeatureBridge();
    bool fail = true;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'setCommandEnabled') {
        if (fail) throw StateError('rejected');
      }
      return {
        'commands': [
          {'id': 'goal', 'name': 'goal', 'enabled': true}
        ],
        'capability': {'userScopeAvailable': true},
      };
    };
    final controller = CommandsCatalog(
        session: bridge,
        scope: const {'workspaceIdentity': 'workspace'},
        scopeKey: 'A|workspace');
    addTearDown(controller.dispose);
    await controller.refresh();

    await controller.setEnabled(controller.items.single, enabled: false);
    expect(controller.items.single.enabled, isTrue);
    expect(controller.saveError('goal'), isA<StateError>());
  });

  test('subagents merge pluginAgents and send scoped CRUD payloads', () async {
    final bridge = FeatureBridge();
    final calls = <(String, String, List<Object?>)>[];
    bridge.channels.handler = (channel, method, args) {
      calls.add((channel, method, args));
      if (method == 'list') {
        return {
          'agents': [
            {
              'id': 'user-agent',
              'name': 'user-agent',
              'description': 'User agent',
              'scope': 'user',
              'source': 'user',
              'path': '/user/user-agent.md',
            },
            {
              'id': 'agent-plugin-source',
              'name': 'should-not-duplicate',
              'source': 'plugin',
            },
          ],
          'pluginAgents': [
            {
              'id': 'plugin-agent',
              'name': 'plugin-agent',
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
      scope: const {'workspaceIdentity': 'workspace'},
      scopeKey: 'device|workspace',
      workspacePath: 'D:/Synthetic',
    );
    addTearDown(catalog.dispose);

    await catalog.refresh();
    expect(
        catalog.items.map((entry) => entry.id), ['user-agent', 'plugin-agent']);
    expect(catalog.userScopeAvailable, isTrue);
    expect(catalog.canEdit(catalog.items.first), isTrue);
    expect(catalog.canToggle(catalog.items.first), isTrue);

    await catalog.createAgent(
      targetScope: 'workspace',
      config: {
        'name': 'new-agent',
        'description': 'A new agent',
        'systemPrompt': 'Review the change',
      },
    );
    final create = calls.firstWhere((call) => call.$2 == 'createAgent');
    final createPayload = (create.$3.single as Map).cast<String, dynamic>();
    expect(createPayload['scope'], 'workspace');
    expect(createPayload['workspacePath'], 'D:/Synthetic');
    expect(createPayload['workspaceIdentity'], 'workspace');
    expect(createPayload['provider'], 'glm');
    expect(
        (createPayload['config'] as Map)['systemPrompt'], 'Review the change');

    await catalog.updateAgent(catalog.items.first, config: {
      'name': 'user-agent',
      'description': 'Updated',
      'systemPrompt': 'Updated prompt',
    });
    final update = calls.firstWhere((call) => call.$2 == 'updateAgent');
    final updatePayload = (update.$3.single as Map).cast<String, dynamic>();
    expect(updatePayload['agentId'], 'user-agent');
    expect(updatePayload['oldFilePath'], '/user/user-agent.md');
    expect(updatePayload['scope'], 'user');
  });

  test('subagent writes dedupe and failures retain confirmed rows', () async {
    final bridge = FeatureBridge();
    final enabledCalls = <List<Object?>>[];
    var fail = false;
    bridge.channels.handler = (channel, method, args) {
      if (method == 'setEnabled') {
        enabledCalls.add(args);
        if (fail) throw StateError('rejected');
        return null;
      }
      return {
        'agents': [
          {
            'id': 'reviewer',
            'name': 'reviewer',
            'scope': 'user',
            'source': 'user',
            'enabled': true,
          }
        ],
        'capability': {'userScopeAvailable': true},
      };
    };
    final catalog = SubagentsCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'workspace'},
      scopeKey: 'device|workspace',
    );
    addTearDown(catalog.dispose);
    await catalog.refresh();
    final entry = catalog.items.single;

    final first = catalog.setEnabled(entry, enabled: false);
    final duplicate = catalog.setEnabled(entry, enabled: false);
    expect(await duplicate, isFalse);
    expect(await first, isTrue);
    expect(enabledCalls, hasLength(1));
    expect(catalog.items.single.enabled, isTrue);

    fail = true;
    expect(await catalog.setEnabled(entry, enabled: false), isFalse);
    expect(catalog.items.single.enabled, isTrue);
    expect(catalog.operationError('enabled:reviewer'), isA<StateError>());
  });

  test('a late list response from an old scope cannot replace the new source',
      () async {
    final bridge = FeatureBridge();
    final responses = <Completer<Object?>>[];
    bridge.channels.handler = (_, method, __) {
      if (method != 'list') return null;
      final response = Completer<Object?>();
      responses.add(response);
      return response.future;
    };
    final catalog = SubagentsCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'first'},
      scopeKey: 'device|first',
    );
    addTearDown(catalog.dispose);
    final oldRequest = catalog.refresh();
    await pumpEventQueue();
    catalog.updateScope(
      nextScope: const {'workspaceIdentity': 'second'},
      nextScopeKey: 'device|second',
    );
    final newRequest = catalog.refresh();
    await pumpEventQueue();
    expect(responses, hasLength(2));
    responses[1].complete({
      'agents': [
        {'id': 'new', 'name': 'new', 'scope': 'user', 'source': 'user'}
      ]
    });
    await newRequest;
    responses[0].complete({
      'agents': [
        {'id': 'old', 'name': 'old', 'scope': 'user', 'source': 'user'}
      ]
    });
    await oldRequest;
    expect(catalog.scopeKey, 'device|second');
    expect(catalog.items.single.id, 'new');
  });

  test(
      'built-in model override sends only allowed names and rolls back on failure',
      () async {
    final bridge = FeatureBridge();
    var fail = false;
    final calls = <(String, List<Object?>)>[];
    bridge.channels.handler = (channel, method, args) {
      calls.add((method, args));
      if (method == 'setBuiltInModelOverride' && fail) {
        throw StateError('override rejected');
      }
      return {
        'agents': [
          {
            'id': 'general-purpose',
            'name': 'general-purpose',
            'scope': 'built-in',
            'source': 'built-in',
            'modelOverride': 'glm/GLM-5.2',
            'thoughtLevelOverride': 'high',
          },
          {
            'id': 'other-built-in',
            'name': 'Other',
            'scope': 'built-in',
            'source': 'built-in',
          },
        ],
      };
    };
    final catalog = SubagentsCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'workspace'},
      scopeKey: 'device|workspace',
    );
    addTearDown(catalog.dispose);
    await catalog.refresh();
    final general = catalog.items.first;
    expect(catalog.builtInOverrideName(general), 'general-purpose');
    expect(catalog.builtInOverrideName(catalog.items[1]), isNull);

    expect(
        await catalog.setBuiltInModelOverride(
          entry: general,
          model: 'glm/GLM-5.3',
          thoughtLevel: 'max',
        ),
        isTrue);
    final call =
        calls.firstWhere((entry) => entry.$1 == 'setBuiltInModelOverride');
    expect(call.$2.single, {
      'agentName': 'general-purpose',
      'model': 'glm/GLM-5.3',
      'thoughtLevel': 'max',
    });

    fail = true;
    expect(
        await catalog.setBuiltInModelOverride(
          entry: catalog.items.first,
          model: 'glm/GLM-6',
          thoughtLevel: 'low',
        ),
        isFalse);
    expect(catalog.items.first.modelOverride, 'glm/GLM-5.2');
    expect(catalog.operationError('model:general-purpose'), isA<StateError>());
  });

  test('hYt scope projection filters user and workspace rows', () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, method, __) {
      if (method != 'list') return null;
      return {
        'agents': [
          {'id': 'user', 'name': 'user', 'scope': 'user', 'source': 'user'},
          {
            'id': 'workspace-match',
            'name': 'workspace-match',
            'scope': 'workspace',
            'source': 'user',
            'projectPath': 'D:/Selected',
          },
          {
            'id': 'workspace-other',
            'name': 'workspace-other',
            'scope': 'workspace',
            'source': 'user',
            'projectPath': 'D:/Other',
          },
          {
            'id': 'plugin-match',
            'name': 'plugin-match',
            'scope': 'workspace',
            'source': 'plugin',
            'projectPath': 'D:/Selected',
          },
          {
            'id': 'plugin-other',
            'name': 'plugin-other',
            'scope': 'workspace',
            'source': 'plugin',
            'projectPath': 'D:/Other',
          },
          {
            'id': 'builtin',
            'name': 'general-purpose',
            'scope': 'built-in',
            'source': 'built-in',
          },
        ],
      };
    };
    final catalog = SubagentsCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'workspace'},
      scopeKey: 'device|workspace',
      workspacePath: 'D:/Selected',
    );
    addTearDown(catalog.dispose);
    await catalog.refresh();
    expect(catalog.visibleItems.map((entry) => entry.id), ['user', 'builtin']);

    catalog.updateScope(
      nextScope: const {'workspaceIdentity': 'workspace'},
      nextWorkspacePath: 'D:/Selected',
      nextScopeKey: 'device|workspace',
      nextScopeKind: 'workspace',
    );
    expect(catalog.visibleItems, isEmpty);
    await catalog.refresh();
    expect(catalog.visibleItems.map((entry) => entry.id),
        ['workspace-match', 'plugin-match']);
  });

  test('a scope change gives a new pending token for the same enabled id',
      () async {
    final bridge = FeatureBridge();
    final writes = <Completer<Object?>>[];
    bridge.channels.handler = (_, method, __) {
      if (method == 'setEnabled') {
        final pending = Completer<Object?>();
        writes.add(pending);
        return pending.future;
      }
      return {
        'agents': [
          {'id': 'review', 'name': 'review', 'scope': 'user', 'source': 'user'}
        ],
        'capability': {'userScopeAvailable': true},
      };
    };
    final catalog = SubagentsCatalog(
      session: bridge,
      scope: const {'workspaceIdentity': 'A'},
      scopeKey: 'device|A',
    );
    addTearDown(catalog.dispose);
    await catalog.refresh();
    final oldEntry = catalog.items.single;
    final oldWrite = catalog.setEnabled(oldEntry, enabled: false);
    await pumpEventQueue();
    catalog.updateScope(
      nextScope: const {'workspaceIdentity': 'B'},
      nextScopeKey: 'device|B',
    );
    final newEntry = RemoteAgentEntry.fromSubagent(const {
      'id': 'review',
      'name': 'review',
      'scope': 'user',
      'source': 'user',
    });
    final newWrite = catalog.setEnabled(newEntry, enabled: false);
    await pumpEventQueue();
    expect(writes, hasLength(2));
    expect(catalog.isOperating('enabled:review'), isTrue);
    writes[0].complete(null);
    writes[1].complete(null);
    await Future.wait([oldWrite, newWrite]);
    expect(catalog.isOperating('enabled:review'), isFalse);
  });
}
