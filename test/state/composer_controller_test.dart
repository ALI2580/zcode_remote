import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/composer_config.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/workspace_view_state.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import '../ui/fake_workspace.dart';

void snapshot(ConversationState state, Map<String, dynamic> patch) {
  state.applyFrame({
    'toSeq': state.seq + 1,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {...composerSnapshotFixture, ...patch}
    }
  }, onGap: () => fail('unexpected gap'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ComposerStore store;
  late FakeBridge bridge;
  late ComposerController controller;
  late ConversationState state;
  setUp(() async {
    store = ComposerStore();
    bridge = FakeBridge();
    controller = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace',
        sessionId: 'task');
    state = ConversationState();
    snapshot(state, {});
    controller.bind(state);
    await controller.loadOptions();
  });
  tearDown(() => store.dispose());

  test('plan mode preparation cannot admit two concurrent first submissions',
      () async {
    final draft = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace');
    await draft.loadOptions();
    draft.input.text = '/plan first input';
    final first = draft.send();
    final second = draft.send();
    expect(await second, ComposerSendResult.blocked);
    expect(await first, ComposerSendResult.sent);
    final creates = bridge.conversationTransport.commands
        .where((e) => e.type == 'createSession');
    expect(creates, hasLength(1));
    expect(creates.single.payload['firstInput'], {'text': 'first input'});
  });

  test(
      'creation after route detach still promotes application layout and navigation cache',
      () async {
    final apps = FakeAppSessions(
        store:
            DeviceStore(requireEncryption: false, encrypt: (_) async => null),
        sessionFactory: (device) => FakeDeviceSession(device.params!, bridge));
    final draft = apps.composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace');
    const target = TaskTarget(
        deviceId: 'A',
        workspaceKey: 'workspace',
        sessionId: '',
        title: 'Draft');
    final layout = WorkspaceViewState()..sidebarCollapsed = true;
    apps.lastLocations['A'] = target;
    apps.workspaceViewStates[target.key] = layout;
    await draft.loadOptions();
    draft.input.text = 'first';
    expect(await draft.send(), ComposerSendResult.sent);
    final next = apps.lastLocations['A']!;
    expect(next.sessionId, 'created-task');
    expect(apps.workspaceViewStates[next.key], same(layout));
    expect(apps.workspaceViewStates.containsKey(target.key), isFalse);
    apps.dispose();
    await apps.notifications.settled;
  });

  test('a draft choice removed remotely is retained visibly but cannot be sent',
      () async {
    final draft = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace');
    await draft.loadOptions();
    await draft.selectModel('custom:provider-b:second-model');
    draft.input.text = 'keep';
    final raw = <String, dynamic>{...composerPrepFixture};
    raw['configOptions'] = [
      for (final entry in composerPrepFixture['configOptions'] as List)
        if (entry['category'] == 'model')
          {
            ...entry as Map,
            'options': [(entry['options'] as List).first]
          }
        else
          entry
    ];
    bridge.conversationTransport.prepHandler =
        () async => WorkspacePrep.fromRaw(raw);
    await draft.loadOptions(refresh: true);
    expect(draft.config['model'], 'second-model');
    expect(draft.draftConfigurationAvailable, isFalse);
    expect(draft.canSend, isFalse);
    expect(bridge.conversationTransport.commands, isEmpty);
  });

  test('late stop receipt does not mark a newer execution as stopping',
      () async {
    Map<String, dynamic> control(String id) => {
          'phase': 'running',
          'canStop': true,
          'stopState': 'stoppable',
          'activeWorks': [
            {'foregroundExecutionId': id}
          ]
        };
    snapshot(state, {'control': control('run-1')});
    final gate = Completer<dynamic>();
    bridge.conversationTransport.commandHandler =
        (sid, type, payload) => gate.future;
    final stopping = controller.stop();
    snapshot(state, {'revision': 4, 'control': control('run-2')});
    gate.complete({'status': 'accepted'});
    expect(await stopping, isTrue);
    expect(controller.serverStopping, isFalse);
    expect(controller.canStop, isTrue);
    expect(bridge.conversationTransport.commands.single.payload,
        {'expectedForegroundExecutionId': 'run-1'});
  });

  test(
      'old in-flight configuration blocks new writes until its late reply settles',
      () async {
    final gate = Completer<dynamic>();
    bridge.conversationTransport.commandHandler =
        (sid, type, payload) => gate.future;
    final pending = controller.selectThought('high');
    bridge.recovered.value++;
    snapshot(state, {'revision': 4});
    await Future<void>.delayed(Duration.zero);
    expect(await pending, isFalse);
    expect(await controller.selectMode('plan'), isFalse);
    controller.input.text = 'text';
    expect(controller.canSend, isFalse);
    gate.complete({'status': 'accepted', 'revisionAtDecision': 1});
    await Future<void>.delayed(Duration.zero);
    expect(controller.canSend, isTrue);
    expect(bridge.conversationTransport.commands, hasLength(1));
  });

  test(
      'A and B with identical workspace/session IDs retain independent config and operations',
      () async {
    final otherBridge = FakeBridge();
    final other = store.obtain(
        transport: otherBridge.conversationTransport,
        deviceId: 'B',
        workspaceKey: 'workspace',
        sessionId: 'task');
    final otherState = ConversationState();
    snapshot(otherState, {});
    other.bind(otherState);
    await other.loadOptions();
    await controller.selectModel('custom:provider-b:second-model');
    expect(controller.config['model'], 'second-model');
    expect(other.config['model'], 'GLM-5.2');
    await other.selectMode('plan');
    expect(controller.config['mode'], 'build');
    expect(other.config['mode'], 'plan');
    expect(bridge.conversationTransport.commands.single.sessionId, 'task');
    expect(otherBridge.conversationTransport.commands.single.type,
        'switchCollaborationMode');
    expect(
        store.obtain(
            transport: bridge.conversationTransport,
            deviceId: 'A',
            workspaceKey: 'workspace',
            sessionId: 'task'),
        same(controller));
  });

  test(
      'workspace draft choices never propagate to existing main or side sessions',
      () async {
    final draft = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace');
    final other = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'other-workspace');
    await draft.loadOptions();
    await other.loadOptions();
    await draft.selectModel('custom:provider-b:second-model');
    await draft.selectMode('plan');
    expect(draft.config['thought'], 'enabled');
    expect(other.config['model'], 'GLM-5.2');
    expect(controller.config['model'], 'GLM-5.2');
    expect(bridge.conversationTransport.commands, isEmpty);
  });

  test(
      'first send submits once and promotes editor, draft, configuration and reading cache',
      () async {
    final draft = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace');
    await draft.loadOptions();
    await draft.selectMode('plan');
    draft.input.text = 'first message';
    final view = ConversationViewState()..anchor = 'row-7';
    final oldKey = draft.key;
    store.viewStates[oldKey] = view;
    final gate = Completer<dynamic>();
    bridge.conversationTransport.commandHandler =
        (sid, type, payload) => gate.future;
    final sending = draft.send();
    expect(await draft.send(), ComposerSendResult.blocked);
    draft.input.text = 'next draft while sending';
    gate.complete({
      'status': 'accepted',
      'result': {'sessionId': 'new-session'}
    });
    expect(await sending, ComposerSendResult.sent);
    expect(bridge.conversationTransport.commands, hasLength(1));
    final command = bridge.conversationTransport.commands.single;
    expect(command.type, 'createSession');
    expect(command.sessionId, isNull);
    expect(command.payload['firstInput'], {'text': 'first message'});
    expect((command.payload['config'] as Map)['mode'], 'plan');
    expect(draft.sessionId, 'new-session');
    expect(draft.config['mode'], 'plan');
    expect(store.drafts.containsKey(oldKey), isFalse);
    expect(store.drafts[draft.key], 'next draft while sending');
    expect(store.viewStates[draft.key], same(view));
    expect(store.viewStates.containsKey(oldKey), isFalse);
    expect(
        store.obtain(
            transport: bridge.conversationTransport,
            deviceId: 'A',
            workspaceKey: 'workspace',
            sessionId: 'new-session'),
        same(draft));
    expect(
        store
            .obtain(
                transport: bridge.conversationTransport,
                deviceId: 'A',
                workspaceKey: 'workspace')
            .input
            .text,
        isEmpty);
  });

  test('failed first send retains text, identity, view and selected config',
      () async {
    final draft = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace');
    await draft.loadOptions();
    await draft.selectMode('plan');
    draft.input.text = 'keep';
    final oldKey = draft.key;
    bridge.conversationTransport.commandHandler =
        (sid, type, payload) async => {'status': 'rejected'};
    expect(await draft.send(), ComposerSendResult.failed);
    expect(draft.sessionId, isNull);
    expect(draft.key, oldKey);
    expect(store.drafts[oldKey], 'keep');
    expect(draft.config['mode'], 'plan');
    expect(bridge.conversationTransport.commands, hasLength(1));
  });

  test('rejected configuration rolls back without guessed reasoning fallback',
      () async {
    bridge.conversationTransport.response = {
      'status': 'rejected',
      'message': 'Unsupported reasoning effort'
    };
    expect(await controller.selectModel('custom:provider-b:second-model'),
        isFalse);
    expect(controller.config['model'], 'GLM-5.2');
    expect(controller.failure, ComposerFailure.configuration);
    expect(bridge.conversationTransport.commands, hasLength(1));
  });

  test(
      'consecutive changes are serialized and dependent thought follows selected model',
      () async {
    final gates = <Completer<dynamic>>[];
    bridge.conversationTransport.commandHandler = (sid, type, payload) {
      final gate = Completer<dynamic>();
      gates.add(gate);
      return gate.future;
    };
    final model = controller.selectModel('custom:provider-b:second-model');
    final thought = controller.selectThought('off');
    final mode = controller.selectMode('plan');
    controller.input.text = 'blocked until confirmed';
    expect(controller.canSend, isFalse);
    expect(bridge.conversationTransport.commands, hasLength(1));
    expect(controller.config['thought'], 'off');
    gates[0].complete({'status': 'accepted', 'revisionAtDecision': 1});
    expect(await model, isTrue);
    expect(gates, hasLength(2));
    expect(bridge.conversationTransport.commands[1].payload,
        {'provider': 'provider-b', 'model': 'second-model', 'thought': 'off'});
    gates[1].complete({'status': 'duplicate', 'revisionAtDecision': 2});
    expect(await thought, isTrue);
    gates[2].complete({'status': 'noop', 'revisionAtDecision': 3});
    expect(await mode, isTrue);
    expect(controller.canSend, isTrue);
    expect(controller.config['mode'], 'plan');
    expect(controller.config['thought'], 'off');
  });

  test(
      'failed model change cancels a dependent thought but continues independent mode choice',
      () async {
    final gate = Completer<dynamic>();
    bridge.conversationTransport.commandHandler = (sid, type, payload) async =>
        type == 'switchModelConfig'
            ? await gate.future
            : {'status': 'accepted'};
    final model = controller.selectModel('custom:provider-b:second-model');
    final thought = controller.selectThought('off');
    final mode = controller.selectMode('plan');
    gate.complete({'status': 'rejected'});
    expect(await model, isFalse);
    expect(await thought, isFalse);
    expect(await mode, isTrue);
    expect(bridge.conversationTransport.commands.map((e) => e.type),
        ['switchModelConfig', 'switchCollaborationMode']);
    expect(controller.config['model'], 'GLM-5.2');
    expect(controller.config['mode'], 'plan');
  });

  test(
      'late older projection cannot undo accepted config; newer server configuration wins',
      () async {
    bridge.conversationTransport.response = {
      'status': 'accepted',
      'revisionAtDecision': 3
    };
    await controller.selectThought('high');
    snapshot(state, {'revision': 2});
    expect(controller.config['thought'], 'high');
    snapshot(state, {
      'revision': 5,
      'config': {
        ...composerSnapshotFixture['config'] as Map,
        'thought': 'nothink'
      }
    });
    expect(controller.config['thought'], 'nothink');
  });

  test(
      'recovery invalidates pending config, ignores late ack and does not restore by writing',
      () async {
    final gate = Completer<dynamic>();
    bridge.conversationTransport.commandHandler =
        (sid, type, payload) => gate.future;
    final pending = controller.selectThought('high');
    bridge.recovered.value++;
    expect(await pending, isFalse);
    snapshot(state, {
      'revision': 9,
      'config': {
        ...composerSnapshotFixture['config'] as Map,
        'thought': 'nothink'
      }
    });
    gate.complete({'status': 'accepted', 'revisionAtDecision': 1});
    await Future<void>.delayed(Duration.zero);
    expect(controller.config['thought'], 'nothink');
    expect(controller.configuring, isFalse);
    expect(bridge.conversationTransport.commands, hasLength(1));
  });

  test(
      'late prepare result cannot replace a newer response or a draft selection',
      () async {
    final draft = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace');
    await draft.loadOptions();
    await draft.selectMode('plan');
    final gate = Completer<WorkspacePrep>();
    bridge.conversationTransport.prepHandler = () => gate.future;
    final first = draft.loadOptions(refresh: true);
    bridge.conversationTransport.prepHandler =
        () async => WorkspacePrep.fromRaw(composerPrepFixture);
    await draft.loadOptions(refresh: true);
    gate.complete(WorkspacePrep.fromRaw({'configOptions': []}));
    await first;
    expect(draft.options.models, hasLength(3));
    expect(draft.config['mode'], 'plan');
    expect(bridge.conversationTransport.commands, isEmpty);
  });

  test('configuration prepare failure can be retried without losing draft',
      () async {
    final draft = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace');
    bridge.conversationTransport.prepHandler =
        () async => throw StateError('offline');
    draft.input.text = 'draft';
    await draft.loadOptions();
    expect(draft.canSend, isFalse);
    expect(draft.failure, ComposerFailure.preparation);
    bridge.conversationTransport.prepHandler = null;
    await draft.loadOptions(refresh: true);
    expect(draft.canSend, isTrue);
    expect(draft.input.text, 'draft');
  });

  test('send respects server routing and healthy timeout never repeats',
      () async {
    controller.input.text = 'keep';
    snapshot(state, {
      'inputRouting': {'mode': 'reject'}
    });
    expect(await controller.send(), ComposerSendResult.blocked);
    expect(bridge.conversationTransport.sent, isEmpty);
    snapshot(state, {
      'inputRouting': {'mode': 'enqueue'}
    });
    bridge.conversationTransport.commandHandler =
        (sid, type, payload) async => throw TimeoutException('test');
    expect(await controller.send(), ComposerSendResult.failed);
    expect(controller.failure, ComposerFailure.uncertain);
    expect(bridge.conversationTransport.sent, ['keep']);
    expect(controller.input.text, 'keep');
  });

  test('duplicate send clears submitted text; rejected/noop send retains it',
      () async {
    for (final status in ['rejected', 'noop', 'duplicate']) {
      bridge.conversationTransport.response = {'status': status};
      controller.input.text = 'text';
      final result = await controller.send();
      expect(
          result,
          status == 'duplicate'
              ? ComposerSendResult.sent
              : ComposerSendResult.failed);
      expect(controller.input.text, status == 'duplicate' ? '' : 'text');
    }
  });

  test(
      'stop uses active execution and exact session; disabled and double stops dispatch nothing',
      () async {
    expect(await controller.stop(), isFalse);
    snapshot(state, {
      'control': {
        'phase': 'running',
        'canStop': true,
        'stopState': 'stoppable',
        'activeWorks': [
          {'foregroundExecutionId': 'execution-1'}
        ]
      }
    });
    expect(await controller.stop(), isTrue);
    expect(await controller.stop(), isFalse);
    expect(bridge.conversationTransport.commands.single.sessionId, 'task');
    expect(bridge.conversationTransport.commands.single.payload,
        {'expectedForegroundExecutionId': 'execution-1'});
    snapshot(state, {
      'control': {'phase': 'running', 'canStop': false}
    });
    expect(await controller.stop(), isFalse);
  });

  test(
      'capability denied, unknown options and degraded bridge cannot issue configuration writes',
      () async {
    snapshot(state, {
      'availability': {
        'switchModelConfig': {'allowed': false}
      }
    });
    expect(await controller.selectThought('high'), isFalse);
    expect(await controller.selectMode('invented-mode'), isFalse);
    bridge.degraded.value = 'reconnecting';
    controller.input.text = 'text';
    expect(controller.canSend, isFalse);
    expect(await controller.selectMode('plan'), isFalse);
    bridge.degraded.value = null;
    bridge.recovered.value++;
    expect(controller.canSend, isFalse); // wait for the new snapshot
    await Future<void>.delayed(Duration.zero);
    snapshot(state, {});
    expect(controller.canSend, isTrue);
    expect(bridge.conversationTransport.commands, isEmpty);
  });

  test('queue choice is explicit and queue change requires reconfirmation',
      () async {
    Map<String, dynamic> queue(String id) => {
          'items': [
            {
              'queueItemId': id,
              'text': 'held',
              'dispatch': {'state': 'queued'}
            }
          ],
          'autoDrain': false
        };
    snapshot(state, {
      'inputRouting': {'mode': 'choice'},
      'queue': queue('q1')
    });
    controller.input.text = 'next';
    expect(await controller.send(), ComposerSendResult.confirmationRequired);
    expect(bridge.conversationTransport.commands, isEmpty);
    snapshot(state, {
      'inputRouting': {'mode': 'choice'},
      'queue': queue('q2')
    });
    expect(await controller.send(heldQueueDisposition: 'keepQueueAndSend'),
        ComposerSendResult.confirmationRequired);
    expect(await controller.send(heldQueueDisposition: 'keepQueueAndSend'),
        ComposerSendResult.sent);
    expect(bridge.conversationTransport.commands.single.payload, {
      'text': 'next',
      'heldQueueDisposition': 'keepQueueAndSend',
      'expectedHeldQueueItemIds': ['q2']
    });
  });

  test('queue operations enforce availability and lock reserved items',
      () async {
    snapshot(state, {
      'queue': {
        'autoDrain': false,
        'items': [
          {
            'queueItemId': 'q1',
            'text': 'one',
            'dispatch': {'state': 'queued'}
          },
          {
            'queueItemId': 'q2',
            'text': 'two',
            'dispatch': {'state': 'reserved'}
          },
        ]
      }
    });
    expect(await controller.queueAction('deleteQueueItem', id: 'q2'), isFalse);
    expect(await controller.queueAction('sendQueuedNow', id: 'q1'), isTrue);
    expect(
        await controller.queueAction('setAutoDrain', autoDrain: true), isTrue);
    snapshot(state, {'availability': {}});
    expect(await controller.queueAction('setAutoDrain', autoDrain: false),
        isFalse);
    expect(bridge.conversationTransport.commands.map((e) => e.sessionId),
        ['task', 'task']);
  });

  test(
      'model parsing, metadata and injected-option filtering use official wire shape',
      () {
    expect(modelReference('custom:builtin:zai:GLM-5.2'),
        (provider: 'builtin:zai', model: 'GLM-5.2'));
    expect(modelReference('custom:provider%3Ab:model%2Fone'),
        (provider: 'provider:b', model: 'model/one'));
    final options = ComposerOptions(WorkspacePrep.fromRaw({
      'configOptions': [
        {
          'category': 'model',
          'type': 'select',
          'options': [
            {'value': 'provider/x', 'origin': 'injected'},
            {'value': 'provider/y', 'description': 'Custom model generated'},
            {
              'value': 'provider/z',
              'origin': 'native',
              'description': 'Custom model configured',
              'modelThoughtLevels': []
            },
          ]
        }
      ]
    }));
    expect(options.models.map((e) => e.value), ['provider/z']);
    expect(
        options.levels({
          'provider': 'provider',
          'model': 'z',
          'thoughtLevels': ['high']
        }),
        isEmpty);
  });
}
