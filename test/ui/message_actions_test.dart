import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'fake_workspace.dart';

ConversationState _stateWithRows(List<Map<String, dynamic>> rows) =>
    ConversationState()
      ..applyFrame({
        'toSeq': 20,
        'payload': {
          'kind': 'snapshot',
          'snapshot': {
            ...composerSnapshotFixture,
            'logEpoch': 'msg-actions-fixture',
            'rows': {'window': rows, 'firstRowId': 1, 'totalCount': rows.length}
          }
        }
      }, onGap: () {});

Widget _chatPage(
  FakeBridge bridge, {
  ValueChanged<String>? onSessionCreated,
}) {
  return MaterialApp(
      home: ChatPage(
          session: bridge,
          scope: const {},
          workspaceKey: 'work',
          deviceId: 'A',
          sessionId: 'task',
          title: 'Actions',
          embedded: true,
          viewStates: {
            composerKey('A', 'work', 'task'): ConversationViewState()
          },
          onSessionCreated: onSessionCreated));
}

void main() {
  testWidgets('user bubble shows copy and edit when entityId exists',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge();
    bridge.conversationTransport.states['task'] = _stateWithRows([
      {
        'rowId': 1,
        'kind': 'userInput',
        'text': 'Hello world',
        'entityId': 'entity-1'
      }
    ]);
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
            session: bridge,
            scope: const {},
            workspaceKey: 'work',
            deviceId: 'A',
            sessionId: 'task',
            title: 'Actions',
            embedded: true,
            viewStates: {
              composerKey('A', 'work', 'task'): ConversationViewState()
            })));
    await tester.pumpAndSettle();
    expect(find.text('Hello world'), findsOneWidget);
    // Copy icon should be visible
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    // Edit icon should be visible because entityId exists
    expect(find.byIcon(Icons.edit_outlined), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('user bubble shows copy only when entityId is absent',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge();
    bridge.conversationTransport.states['task'] = _stateWithRows([
      {'rowId': 1, 'kind': 'userInput', 'text': 'No entity'}
    ]);
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
            session: bridge,
            scope: const {},
            workspaceKey: 'work',
            deviceId: 'A',
            sessionId: 'task',
            title: 'Actions',
            embedded: true,
            viewStates: {
              composerKey('A', 'work', 'task'): ConversationViewState()
            })));
    await tester.pumpAndSettle();
    expect(find.text('No entity'), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    expect(find.byIcon(Icons.edit_outlined), findsNothing,
        reason: 'no entityId: edit button hidden');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'latest assistant feedback buttons persist like and rollback on failure',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge();
    bridge.conversationTransport.states['task'] = _stateWithRows([
      {
        'rowId': 2,
        'kind': 'assistantText',
        'text': 'Assistant reply',
        'entityId': 'entity-2',
        'state': 'complete'
      }
    ]);
    await tester.pumpWidget(_chatPage(bridge));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.thumb_up_alt_outlined), findsOneWidget);
    expect(find.byIcon(Icons.thumb_down_alt_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.thumb_up_alt_outlined));
    await tester.pumpAndSettle();
    final likeCall = bridge.conversationTransport.commands.single;
    expect(likeCall.type, 'setAssistantFeedback');
    expect(likeCall.payload, {
      'target': {'rowId': 2, 'entityId': 'entity-2'},
      'feedback': 'like'
    });
    expect(find.byIcon(Icons.thumb_up), findsOneWidget);

    bridge.conversationTransport.commands.clear();
    await tester.tap(find.byIcon(Icons.thumb_up));
    await tester.pumpAndSettle();
    final clearCall = bridge.conversationTransport.commands.single;
    expect(clearCall.payload['feedback'], isNull);
    expect(find.byIcon(Icons.thumb_up), findsNothing);
    expect(find.byIcon(Icons.thumb_up_alt_outlined), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('latest complete assistant row supports fork with entityId',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge();
    bridge.conversationTransport.states['task'] = _stateWithRows([
      {'rowId': 1, 'kind': 'userInput', 'text': 'Question'},
      {
        'rowId': 2,
        'kind': 'assistantText',
        'state': 'complete',
        'text': 'Answer',
        'entityId': 'assistant-1',
        'actions': {'canFork': true}
      }
    ]);
    final created = <String>[];
    bridge.conversationTransport.commandHandler =
        (sessionId, type, payload) async {
      expect(sessionId, 'task');
      expect(type, 'forkAssistant');
      expect(payload['target'], {'rowId': 2, 'entityId': 'assistant-1'});
      return {
        'status': 'accepted',
        'result': {'type': 'forkAssistant', 'sessionId': 'forked'}
      };
    };
    await tester.pumpWidget(_chatPage(bridge, onSessionCreated: created.add));
    await tester.pumpAndSettle();
    expect(find.text('Answer'), findsOneWidget);
    expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.account_tree_outlined));
    await tester.pumpAndSettle();
    expect(created, ['forked']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('assistant actions are gated by completion and entityId',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge();
    bridge.conversationTransport.states['task'] = _stateWithRows([
      {
        'rowId': 1,
        'kind': 'assistantText',
        'state': 'streaming',
        'text': 'Still streaming',
        'entityId': 'streaming-entity'
      },
      {
        'rowId': 2,
        'kind': 'assistantText',
        'state': 'complete',
        'text': 'No entity answer',
        'actions': {'canFork': true}
      },
      {
        'rowId': 3,
        'kind': 'assistantText',
        'state': 'complete',
        'text': 'Fork unavailable answer',
        'entityId': 'assistant-3',
        'actions': {'canFork': false}
      }
    ]);
    await tester.pumpWidget(_chatPage(bridge));
    await tester.pumpAndSettle();
    expect(find.text('Fork unavailable answer'), findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    expect(find.byIcon(Icons.account_tree_outlined), findsNothing,
        reason: 'latest complete row without entityId cannot fork');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('rejected fork keeps the current session', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge();
    bridge.conversationTransport.states['task'] = _stateWithRows([
      {
        'rowId': 1,
        'kind': 'assistantText',
        'state': 'complete',
        'text': 'Answer',
        'entityId': 'assistant-1',
        'actions': {'canFork': true}
      }
    ]);
    final created = <String>[];
    bridge.conversationTransport.commandHandler =
        (sessionId, type, payload) async => const {'status': 'rejected'};
    await tester.pumpWidget(_chatPage(bridge, onSessionCreated: created.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_tree_outlined));
    await tester.pump();
    await tester.pump();
    expect(find.text('Fork failed. Try again.'), findsOneWidget);
    expect(created, isEmpty);
    await tester.pump(const Duration(seconds: 5));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('late accepted fork cannot override a newer fork',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge();
    bridge.conversationTransport.states['task'] = _stateWithRows([
      {
        'rowId': 1,
        'kind': 'assistantText',
        'state': 'complete',
        'text': 'First answer',
        'entityId': 'assistant-1',
        'actions': {'canFork': true}
      },
      {'rowId': 3, 'kind': 'userInput', 'text': 'Follow up question'},
      {
        'rowId': 2,
        'kind': 'assistantText',
        'state': 'complete',
        'text': 'Second answer',
        'entityId': 'assistant-2',
        'actions': {'canFork': true}
      }
    ]);
    final created = <String>[];
    final completers = [Completer<Object?>(), Completer<Object?>()];
    var call = 0;
    bridge.conversationTransport.commandHandler =
        (sessionId, type, payload) async => completers[call++].future;
    await tester.pumpWidget(_chatPage(bridge, onSessionCreated: created.add));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.account_tree_outlined).first);
    await tester.pump();
    await tester.tap(find.byIcon(Icons.account_tree_outlined).last);
    await tester.pump();
    completers[0].complete({
      'status': 'accepted',
      'result': {'type': 'forkAssistant', 'sessionId': 'fork-old'}
    });
    await tester.pump();
    completers[1].complete({
      'status': 'accepted',
      'result': {'type': 'forkAssistant', 'sessionId': 'fork-new'}
    });
    await tester.pumpAndSettle();
    expect(created, ['fork-new']);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
