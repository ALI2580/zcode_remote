import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/interaction_requests.dart';

import '../ui/fake_workspace.dart';

ConversationState _state(List<Map<String, dynamic>> interactions) {
  final state = ConversationState();
  state.applyFrame({
    'toSeq': 1,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {
        'sessionId': 'task',
        'revision': 1,
        'logEpoch': 'epoch',
        'control': {'phase': 'running'},
        'pendingInteractions': interactions,
      },
    },
  }, onGap: () {});
  return state;
}

Map<String, dynamic> _permission(String id) => {
      'interactionId': id,
      'kind': 'permission',
      'createdAt': 1,
      'payload': {
        'kind': 'permission',
        'toolCallId': 'call-$id',
        'toolName': 'Bash',
        'summary': 'Run a synthetic command',
        'options': [
          {'optionId': 'allow', 'label': 'Allow', 'kind': 'allowOnce'},
          {'optionId': 'deny', 'label': 'Deny', 'kind': 'deny'},
        ],
      },
    };

Map<String, dynamic> _hookReview(String id,
        {String trustState = 'pending_trust'}) =>
    {
      'interactionId': id,
      'kind': 'workspaceHookReview',
      'createdAt': 1,
      'payload': {
        'kind': 'workspaceHookReview',
        'interactionId': id,
        'reviewFlowId': 'flow-$id',
        'generation': 2,
        'sessionId': 'task',
        'taskId': 'task',
        'runId': 'run-1',
        'workspaceIdentity': 'synthetic-workspace',
        'workspaceLabel': 'Synthetic',
        'bundleDigest': 'a' * 64,
        'createdAt': 1,
        'deadlineAt': 20,
        'sourceFiles': [
          {
            'path': '.zcode/hooks.json',
            'displayPath': 'hooks.json',
            'editable': true
          },
        ],
        'summary': {
          'eventCount': 2,
          'hookCount': 2,
          'pendingCount': trustState == 'pending_trust' ? 2 : 0,
        },
        'items': [
          {
            'reviewItemId': 'hook-a',
            'event': 'PreToolUse',
            'type': 'command',
            'displayName': 'Audit command',
            'displayCommand': 'echo synthetic',
            'sourcePath': '.zcode/hooks.json',
            'resolvedTimeoutMs': 1000,
            'resolvedMaxOutputBytes': 1024,
            'executionMode': 'foreground',
            'configuredEnabled': true,
            'editable': true,
            'trustState': trustState,
          },
          {
            'reviewItemId': 'hook-b',
            'event': 'Stop',
            'type': 'process',
            'displayName': 'Audit process',
            'displayCommand': 'node synthetic.js',
            'sourcePath': '.zcode/hooks.json',
            'resolvedTimeoutMs': 1000,
            'resolvedMaxOutputBytes': 1024,
            'executionMode': 'background',
            'configuredEnabled': true,
            'editable': true,
            'trustState': trustState,
          },
        ],
        'warningCode': 'workspace_hooks_execute_code',
      },
    };

void main() {
  test('permission request resolves once and removes the accepted request',
      () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final state = _state([_permission('i-1')]);
    final controller = InteractionController(
        transport: transport, sessionId: 'task', state: state);
    addTearDown(controller.dispose);

    expect(controller.active?['interactionId'], 'i-1');
    final ok = await controller.resolve('i-1', optionId: 'allow');
    expect(ok, isTrue);
    expect(transport.commands.single.sessionId, 'task');
    expect(transport.commands.single.type, 'resolveInteraction');
    expect(transport.commands.single.payload, {
      'interactionId': 'i-1',
      'answer': {'optionId': 'allow'},
    });
    expect(controller.active, isNull);
    expect(state.pendingInteractions, isEmpty);
  });

  test('the same interaction does not submit twice while an RPC is pending',
      () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final state = _state([_permission('i-1')]);
    final controller = InteractionController(
        transport: transport, sessionId: 'task', state: state);
    addTearDown(controller.dispose);
    final gate = Completer<dynamic>();
    transport.commandHandler = (_, __, ___) => gate.future;

    final first = controller.resolve('i-1', optionId: 'allow');
    final second = controller.resolve('i-1', optionId: 'deny');
    expect(controller.resolvingIds, {'i-1'});
    expect(transport.commands, hasLength(1));
    gate.complete({
      'status': 'accepted',
      'revisionAtDecision': 1,
    });
    expect(await first, isTrue);
    expect(await second, isTrue);
  });

  test('a rejected response stays visible and does not remove the request',
      () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final state = _state([_permission('i-1')]);
    final controller = InteractionController(
        transport: transport, sessionId: 'task', state: state);
    addTearDown(controller.dispose);
    transport.response = {'status': 'failed', 'reasonCode': 'stale'};

    expect(await controller.resolve('i-1', optionId: 'deny'), isFalse);
    expect(controller.failureFor('i-1')?.status, 'failed');
    expect(controller.failureFor('i-1')?.reasonCode, 'stale');
    expect(controller.active?['interactionId'], 'i-1');
  });

  test('a late response for an invalidated interaction is ignored', () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final state = _state([_permission('i-1')]);
    final controller = InteractionController(
        transport: transport, sessionId: 'task', state: state);
    addTearDown(controller.dispose);
    final gate = Completer<dynamic>();
    transport.commandHandler = (_, __, ___) => gate.future;

    final pending = controller.resolve('i-1', optionId: 'allow');
    state.removePendingInteraction('i-1');
    gate.complete({'status': 'failed', 'reasonCode': 'invalidated'});
    expect(await pending, isFalse);
    expect(controller.failureFor('i-1'), isNull);
    expect(controller.active, isNull);
  });

  test('another session uses its own id and state', () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final aliState = _state([_permission('ali-1')]);
    final rogState = _state([_permission('rog-1')]);
    final ali = InteractionController(
        transport: transport, sessionId: 'ali', state: aliState);
    final rog = InteractionController(
        transport: transport, sessionId: 'rog', state: rogState);
    addTearDown(ali.dispose);
    addTearDown(rog.dispose);

    expect(ali.active?['interactionId'], 'ali-1');
    expect(rog.active?['interactionId'], 'rog-1');
    expect(await rog.resolve('rog-1', optionId: 'allow'), isTrue);
    expect(transport.commands.single.sessionId, 'rog');
    expect(aliState.pendingInteractions, hasLength(1));
    expect(rogState.pendingInteractions, isEmpty);
  });

  test(
      'a reconnect replacement ignores a late response from the old controller',
      () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final oldState = _state([_permission('i-1')]);
    final old = InteractionController(
        transport: transport, sessionId: 'task', state: oldState);
    final gate = Completer<dynamic>();
    transport.commandHandler = (_, __, ___) => gate.future;

    final pending = old.resolve('i-1', optionId: 'allow');
    old.dispose();
    final reconnectedState = _state([_permission('i-1')]);
    final reconnected = InteractionController(
        transport: transport, sessionId: 'task', state: reconnectedState);
    addTearDown(reconnected.dispose);
    gate.complete({'status': 'accepted'});
    expect(await pending, isFalse);

    expect(reconnectedState.pendingInteractions, hasLength(1));
    expect(reconnected.active?['interactionId'], 'i-1');
    expect(reconnected.failureFor('i-1'), isNull);
  });

  test('snoozing auto-resolution keeps the request visible', () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final state = _state([
      {
        'interactionId': 'auto-1',
        'kind': 'userInput',
        'createdAt': 1,
        'autoResolution': {
          'state': 'visibleCountdown',
          'startedAt': 1,
          'visibleAt': 1,
          'deadlineAt': 20,
        },
        'payload': {
          'kind': 'userInput',
          'prompt': '继续吗？',
          'freeText': false,
          'options': [
            {'optionId': 'yes', 'label': 'Yes'},
          ],
        },
      },
    ]);
    final controller = InteractionController(
        transport: transport, sessionId: 'task', state: state);
    addTearDown(controller.dispose);

    expect(await controller.snoozeAutoResolution('auto-1'), isTrue);
    expect(transport.commands.single.type, 'snoozeInteractionAutoResolution');
    expect(transport.commands.single.payload, {'interactionId': 'auto-1'});
    expect(controller.active?['interactionId'], 'auto-1');
    expect(state.pendingInteractions, hasLength(1));
  });

  test(
      'workspace hook trust sends the immutable flow identity and removes on accept',
      () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final state = _state([_hookReview('hook-1')]);
    final controller = WorkspaceHookReviewController(
        transport: transport,
        sessionId: 'task',
        state: state,
        workspaceIdentity: 'synthetic-workspace');
    addTearDown(controller.dispose);

    expect(controller.pendingCount, 2);
    expect(
        await controller
            .trustItems(state.pendingInteractions.single, ['hook-a', 'hook-b']),
        isTrue);
    expect(transport.commands.single.sessionId, 'task');
    expect(transport.commands.single.type, 'respondWorkspaceHookReview');
    expect(transport.commands.single.payload, {
      'sessionId': 'task',
      'taskId': 'task',
      'runId': 'run-1',
      'workspaceIdentity': 'synthetic-workspace',
      'bundleDigest': 'a' * 64,
      'reviewFlowId': 'flow-hook-1',
      'generation': 2,
      'interactionId': 'hook-1',
      'decision': {
        'action': 'trust_selected',
        'reviewItemIds': ['hook-a', 'hook-b'],
      },
    });
    expect(controller.active, isNull);
    expect(state.pendingInteractions, isEmpty);
  });

  test('non-actionable hook items cannot be trusted', () async {
    final bridge = FakeBridge();
    final state =
        _state([_hookReview('hook-1', trustState: 'trusted_persistent')]);
    final controller = WorkspaceHookReviewController(
        transport: bridge.conversationTransport,
        sessionId: 'task',
        state: state);
    addTearDown(controller.dispose);

    expect(controller.active, isNull);
    expect(
      await controller.trustItem(
          state.pendingInteractions.single, const {'reviewItemId': 'hook-a'}),
      isFalse,
    );
    expect(bridge.conversationTransport.commands, isEmpty);
  });

  test('hook trust failure remains scoped to the current flow', () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    transport.response = {
      'status': 'failed',
      'reasonCode': 'snapshot_mismatch'
    };
    final state = _state([_hookReview('hook-1')]);
    final controller = WorkspaceHookReviewController(
        transport: transport, sessionId: 'task', state: state);
    addTearDown(controller.dispose);

    expect(
        await controller.trustItem(
            state.pendingInteractions.single, const {'reviewItemId': 'hook-a'}),
        isFalse);
    expect(controller.failureFor('hook-1', 'hook-a')?.reasonCode,
        'snapshot_mismatch');
    expect(controller.active?['interactionId'], 'hook-1');
    expect(transport.commands.single.payload['interactionId'], 'hook-1');
  });

  test('a late hook response never creates a new failure', () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final state = _state([_hookReview('hook-1')]);
    final controller = WorkspaceHookReviewController(
        transport: transport, sessionId: 'task', state: state);
    addTearDown(controller.dispose);
    final gate = Completer<dynamic>();
    transport.commandHandler = (_, __, ___) => gate.future;

    final pending = controller.trustItem(
        state.pendingInteractions.single, const {'reviewItemId': 'hook-a'});
    state.removePendingInteraction('hook-1');
    gate.complete({'status': 'failed', 'reasonCode': 'review_superseded'});
    expect(await pending, isFalse);
    expect(controller.failures, isEmpty);
    expect(controller.active, isNull);
  });

  test('pending hook trust does not submit twice', () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final state = _state([_hookReview('hook-1')]);
    final controller = WorkspaceHookReviewController(
        transport: transport, sessionId: 'task', state: state);
    addTearDown(controller.dispose);
    final gate = Completer<dynamic>();
    transport.commandHandler = (_, __, ___) => gate.future;

    final request = state.pendingInteractions.single;
    final first =
        controller.trustItem(request, const {'reviewItemId': 'hook-a'});
    final second =
        controller.trustItem(request, const {'reviewItemId': 'hook-a'});
    expect(controller.resolvingOperationIds, hasLength(1));
    expect(transport.commands, hasLength(1));
    gate.complete({'status': 'accepted'});
    expect(await first, isTrue);
    expect(await second, isTrue);
  });

  test('hook review controllers are isolated by session state', () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final aliState = _state([_hookReview('ali-hook')]);
    final rogState = _state([_hookReview('rog-hook')]);
    final ali = WorkspaceHookReviewController(
        transport: transport, sessionId: 'ali', state: aliState);
    final rog = WorkspaceHookReviewController(
        transport: transport, sessionId: 'rog', state: rogState);
    addTearDown(ali.dispose);
    addTearDown(rog.dispose);

    expect(ali.active?['interactionId'], 'ali-hook');
    expect(rog.active?['interactionId'], 'rog-hook');
    expect(
      await rog.trustItem(rogState.pendingInteractions.single,
          const {'reviewItemId': 'hook-a'}),
      isTrue,
    );
    expect(transport.commands.single.sessionId, 'rog');
    expect(aliState.pendingInteractions, hasLength(1));
    expect(rogState.pendingInteractions, isEmpty);
  });

  test('a newer generation wins within the same hook review flow', () {
    final bridge = FakeBridge();
    final old = _hookReview('hook-old');
    final next = _hookReview('hook-next');
    old['payload']['reviewFlowId'] = 'flow-shared';
    old['payload']['generation'] = 2;
    old['createdAt'] = 30;
    next['payload']['reviewFlowId'] = 'flow-shared';
    next['payload']['generation'] = 3;
    next['createdAt'] = 20;
    final state = _state([old, next]);
    final controller = WorkspaceHookReviewController(
        transport: bridge.conversationTransport,
        sessionId: 'task',
        state: state);
    addTearDown(controller.dispose);

    expect(controller.active?['interactionId'], 'hook-next');
  });

  test('a hook trust response after bundle replacement is stale and discarded',
      () async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final state = _state([_hookReview('hook-1')]);
    final controller = WorkspaceHookReviewController(
        transport: transport, sessionId: 'task', state: state);
    addTearDown(controller.dispose);
    final gate = Completer<dynamic>();
    transport.commandHandler = (_, __, ___) => gate.future;

    final pending = controller.trustItem(
        state.pendingInteractions.single, const {'reviewItemId': 'hook-a'});
    final replaced = _hookReview('hook-1');
    replaced['payload']['generation'] = 9;
    replaced['payload']['bundleDigest'] = 'c' * 64;
    state.applyFrame({
      'toSeq': 2,
      'payload': {
        'kind': 'snapshot',
        'snapshot': {
          'sessionId': 'task',
          'revision': 2,
          'logEpoch': 'epoch',
          'pendingInteractions': [replaced],
        },
      },
    }, onGap: () {});
    gate.complete({'status': 'failed', 'reasonCode': 'stale'});

    expect(await pending, isFalse);
    expect(controller.failures, isEmpty);
    expect(controller.active?['interactionId'], 'hook-1');
    expect(state.pendingInteractions.single['payload']['generation'], 9);
  });
}
