import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/interaction_requests.dart';
import 'package:zcode_remote/ui/interaction_request_card.dart';
import 'package:zcode_remote/ui/workspace_hook_review_card.dart';
import 'package:zcode_remote/ui/theme.dart';

import 'fake_workspace.dart';

ConversationState _state(
  List<Map<String, dynamic>> interactions, {
  Map<String, dynamic>? admission,
}) {
  final state = ConversationState();
  state.applyFrame({
    'toSeq': 1,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {
        'sessionId': 'task',
        'revision': 1,
        'logEpoch': 'epoch',
        'pendingInteractions': interactions,
        if (admission != null) 'workspaceHookAdmission': admission,
      },
    },
  }, onGap: () {});
  return state;
}

Map<String, dynamic> _permission(String id, String tool) => {
      'interactionId': id,
      'kind': 'permission',
      'createdAt': 1,
      'payload': {
        'kind': 'permission',
        'toolCallId': 'call-$id',
        'toolName': tool,
        'summary': 'Run $tool',
        'options': [
          {'optionId': 'allow', 'label': 'Allow', 'kind': 'allowOnce'},
          {'optionId': 'deny', 'label': 'Deny', 'kind': 'deny'},
        ],
      },
    };

Map<String, dynamic> _hookReview(String id) => {
      'interactionId': id,
      'kind': 'workspaceHookReview',
      'createdAt': 1,
      'payload': {
        'kind': 'workspaceHookReview',
        'interactionId': id,
        'reviewFlowId': 'flow-$id',
        'generation': 1,
        'sessionId': 'task',
        'taskId': 'task',
        'runId': 'run',
        'workspaceIdentity': 'synthetic-workspace',
        'workspaceLabel': 'Synthetic',
        'bundleDigest': 'b' * 64,
        'createdAt': 1,
        'deadlineAt': 20,
        'summary': {'eventCount': 1, 'hookCount': 1, 'pendingCount': 1},
        'items': [
          {
            'reviewItemId': 'hook-a',
            'event': 'PreToolUse',
            'type': 'command',
            'displayName': 'Audit command',
            'displayCommand': 'echo synthetic',
            'sourcePath': 'hooks.json',
            'resolvedTimeoutMs': 1000,
            'resolvedMaxOutputBytes': 1024,
            'executionMode': 'foreground',
            'configuredEnabled': true,
            'editable': true,
            'trustState': 'pending_trust',
          },
        ],
        'warningCode': 'workspace_hooks_execute_code',
      },
    };

void main() {
  testWidgets('permission options submit the official optionId answer',
      (tester) async {
    final bridge = FakeBridge();
    final state = _state([_permission('perm-1', 'Bash')]);
    final controller = InteractionController(
        transport: bridge.conversationTransport,
        sessionId: 'task',
        state: state);
    addTearDown(controller.dispose);

    expect(controller.pendingCount, 1);
    expect(controller.active, isNotNull);
    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: Stack(children: [
          InteractionRequestCard(controller: controller),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bash'), findsOneWidget);
    expect(find.text('Allow'), findsOneWidget);
    await tester.tap(find.text('Allow'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(bridge.conversationTransport.commands.single.payload, {
      'interactionId': 'perm-1',
      'answer': {'optionId': 'allow'},
    });
    expect(find.text('Bash'), findsNothing);
  });

  testWidgets('free-text user input submits the official freeText answer',
      (tester) async {
    final bridge = FakeBridge();
    final state = _state([
      {
        'interactionId': 'input-1',
        'kind': 'userInput',
        'createdAt': 1,
        'payload': {
          'kind': 'userInput',
          'prompt': 'What should I do next?',
          'freeText': true,
        },
      }
    ]);
    final controller = InteractionController(
        transport: bridge.conversationTransport,
        sessionId: 'task',
        state: state);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: Stack(children: [
          InteractionRequestCard(controller: controller),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '继续检查布局');
    await tester.tap(find.text('确认'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(bridge.conversationTransport.commands.single.payload, {
      'interactionId': 'input-1',
      'answer': {'freeText': '继续检查布局'},
    });
    expect(find.text('What should I do next?'), findsNothing);
  });

  testWidgets('resolving one request exposes the next pending request',
      (tester) async {
    final bridge = FakeBridge();
    final state = _state([
      _permission('first', 'Bash'),
      _permission('second', 'Edit'),
    ]);
    final controller = InteractionController(
        transport: bridge.conversationTransport,
        sessionId: 'task',
        state: state);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: Stack(children: [
          InteractionRequestCard(controller: controller),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Bash'), findsOneWidget);
    expect(find.text('还有 1 个请求等待处理'), findsOneWidget);
    await tester.tap(find.text('Allow').first);
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(find.text('Bash'), findsNothing);
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('还有 1 个请求等待处理'), findsNothing);
    expect(bridge.conversationTransport.commands.single.sessionId, 'task');
  });

  testWidgets('visible auto-resolution can be snoozed and keeps the request',
      (tester) async {
    final bridge = FakeBridge();
    final now = DateTime.now().millisecondsSinceEpoch;
    final state = _state([
      {
        'interactionId': 'auto-1',
        'kind': 'userInput',
        'createdAt': now,
        'autoResolution': {
          'state': 'visibleCountdown',
          'startedAt': now,
          'visibleAt': now,
          'deadlineAt': now + 10000,
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
        transport: bridge.conversationTransport,
        sessionId: 'task',
        state: state);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: Stack(children: [
          InteractionRequestCard(controller: controller),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('继续吗？'), findsOneWidget);
    expect(find.text('挂起'), findsOneWidget);
    await tester.tap(find.text('挂起'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(bridge.conversationTransport.commands.single.type,
        'snoozeInteractionAutoResolution');
    expect(bridge.conversationTransport.commands.single.payload,
        {'interactionId': 'auto-1'});
    expect(find.text('继续吗？'), findsOneWidget);
  });

  testWidgets('workspace hook review banner dismisses locally', (tester) async {
    final bridge = FakeBridge();
    final state = _state([_hookReview('hook-1')]);
    final controller = WorkspaceHookReviewController(
        transport: bridge.conversationTransport,
        sessionId: 'task',
        state: state);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: WorkspaceHookReviewBanner(controller: controller),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('1 hooks need review'), findsOneWidget);
    expect(find.text('echo synthetic'), findsNothing);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();

    expect(controller.active, isNull);
    expect(find.text('1 hooks need review'), findsNothing);
    expect(bridge.conversationTransport.commands, isEmpty);
  });

  testWidgets('admission banner uses the official copy and review request',
      (tester) async {
    final bridge = FakeBridge();
    var hooksOpened = false;
    final state = _state(const [], admission: {
      'pendingCount': 2,
      'bundleDigest': 'd' * 64,
      'workspaceIdentity': 'admission-scope',
    });
    final controller = WorkspaceHookReviewController(
        transport: bridge.conversationTransport,
        sessionId: 'task',
        state: state,
        workspaceIdentity: 'controller-scope');
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: WorkspaceHookReviewBanner(
          controller: controller,
          onOpenHooks: () => hooksOpened = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(controller.admissionCount, 2);
    expect(
      find.text(
          '2 workspace hook(s) pending review; disabled for this session'),
      findsOneWidget,
    );
    expect(find.text('Review'), findsOneWidget);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(hooksOpened, isTrue);
    final command = bridge.conversationTransport.commands.single;
    expect(command.sessionId, 'task');
    expect(command.type, 'requestWorkspaceHookReview');
    expect(command.payload, {
      'sessionId': 'task',
      'workspaceIdentity': 'admission-scope',
      'bundleDigest': 'd' * 64,
    });
  });

  testWidgets(
      'admission count 0 falls back to pending review and dismisses by bundle',
      (tester) async {
    final bridge = FakeBridge();
    final state = _state([
      _hookReview('hook-1')
    ], admission: {
      'pendingCount': 0,
      'bundleDigest': 'd' * 64,
    });
    final controller = WorkspaceHookReviewController(
        transport: bridge.conversationTransport,
        sessionId: 'task',
        state: state);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: WorkspaceHookReviewBanner(controller: controller),
      ),
    ));
    await tester.pumpAndSettle();

    expect(controller.admission, isNull);
    expect(find.text('1 hooks need review'), findsOneWidget);
    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    expect(controller.active, isNull);
  });

  testWidgets('admission dismiss is scoped by session and bundle digest',
      (tester) async {
    final bridge = FakeBridge();
    final state = _state(const [], admission: {
      'pendingCount': 1,
      'bundleDigest': 'd' * 64,
    });
    final ali = WorkspaceHookReviewController(
        transport: bridge.conversationTransport,
        sessionId: 'ali-task',
        state: state);
    final rog = WorkspaceHookReviewController(
        transport: bridge.conversationTransport,
        sessionId: 'rog-task',
        state: state);
    addTearDown(ali.dispose);
    addTearDown(rog.dispose);

    ali.dismissAdmission();
    expect(ali.admission, isNull);
    expect(rog.admission, isNotNull);

    state.applyFrame({
      'toSeq': 2,
      'payload': {
        'kind': 'deltas',
        'fromSeq': 1,
        'deltas': [
          {
            'op': 'state.updated',
            'patch': {
              'workspaceHookAdmission': {
                'pendingCount': 3,
                'bundleDigest': 'd' * 64,
              },
            },
          },
        ],
      },
    }, onGap: () {});
    expect(ali.admission, isNull);
    expect(rog.admissionCount, 3);
  });

  testWidgets('hook review trust sends the official immutable identity',
      (tester) async {
    final bridge = FakeBridge();
    final state = _state([_hookReview('hook-1')]);
    final controller = WorkspaceHookReviewController(
        transport: bridge.conversationTransport,
        sessionId: 'task',
        state: state);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: WorkspaceHookReviewBanner(controller: controller),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();

    expect(find.text('Audit command'), findsOneWidget);
    expect(find.text('echo synthetic'), findsOneWidget);
    await tester.tap(find.text('Trust'));
    await tester.pumpAndSettle();

    expect(bridge.conversationTransport.commands.single.type,
        'respondWorkspaceHookReview');
    expect(bridge.conversationTransport.commands.single.payload, {
      'sessionId': 'task',
      'taskId': 'task',
      'runId': 'run',
      'workspaceIdentity': 'synthetic-workspace',
      'bundleDigest': 'b' * 64,
      'reviewFlowId': 'flow-hook-1',
      'generation': 1,
      'interactionId': 'hook-1',
      'decision': {
        'action': 'trust_selected',
        'reviewItemIds': ['hook-a'],
      },
    });
    expect(find.text('Audit command'), findsNothing);
  });

  testWidgets('multi-question drafts restore, navigate, and serialize',
      (tester) async {
    final bridge = FakeBridge();
    final state = _state([
      {
        'interactionId': 'questions-1',
        'kind': 'userInput',
        'createdAt': 1,
        'payload': {
          'kind': 'userInput',
          'prompt': 'Choose options',
          'questions': [
            {
              'question': 'First question',
              'header': 'First header',
              'multiSelect': true,
              'options': [
                {'value': 'A', 'label': 'A'},
                {'value': 'B', 'label': 'B'},
              ],
            },
            {
              'question': 'Second question',
              'header': 'Second header',
              'options': [
                {'value': 'X', 'label': 'X'},
                {'value': 'Y', 'label': 'Y'},
              ],
            },
          ],
          'currentQuestionIndex': 1,
          'answerDrafts': {
            'answer_0': ['A'],
          },
        },
      }
    ]);
    final controller = InteractionController(
        transport: bridge.conversationTransport,
        sessionId: 'task',
        state: state);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: Stack(children: [
          InteractionRequestCard(controller: controller),
        ]),
      ),
    ));
    await tester.pump();

    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .toList();
    expect(texts, contains('Second header'));
    await tester.tap(find.byType(OutlinedButton).at(0));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(OutlinedButton).at(2));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .toList(),
      contains('First header'),
    );
    await tester.tap(find.byType(OutlinedButton).at(1));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();
    expect(
      tester
          .widgetList<Text>(find.byType(Text))
          .map((widget) => widget.data)
          .toList(),
      contains('Second header'),
    );
    await tester.enterText(find.byType(TextField), 'custom answer');
    await tester.tap(find.byType(FilledButton));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();

    expect(bridge.conversationTransport.commands.single.payload, {
      'interactionId': 'questions-1',
      'answer': {
        'action': 'accept',
        'content': {
          'answers': {
            'First question': 'A, B',
            'Second question': 'X, custom answer',
          },
          'answer_0': ['A', 'B'],
          'answer_1': 'X',
        },
      },
    });
  });
}
