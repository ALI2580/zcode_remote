import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/background_works.dart';
import 'package:zcode_remote/ui/background_works_banner.dart';
import 'package:zcode_remote/ui/theme.dart';

import 'fake_workspace.dart';

ConversationState _state() {
  final state = ConversationState();
  state.applyFrame({
    'toSeq': 1,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {
        'sessionId': 'task',
        'revision': 1,
        'logEpoch': 'epoch',
        'backgroundWorks': [
          {
            'workId': 'bash-1',
            'kind': 'bash',
            'title': 'Run checks',
            'status': 'running',
            'startedAt': 1,
            'cancellable': true,
          },
          {
            'workId': 'agent-1',
            'kind': 'subagent',
            'title': 'Explore repo',
            'status': 'running',
            'startedAt': 2,
            'cancellable': false,
          },
          {
            'workId': 'old-1',
            'kind': 'bash',
            'title': 'Finished',
            'status': 'resultPending',
          },
        ],
      },
    },
  }, onGap: () {});
  return state;
}

void main() {
  testWidgets('running background works show official stop action',
      (tester) async {
    final bridge = FakeBridge();
    final state = _state();
    final controller = BackgroundWorksController(
      transport: bridge.conversationTransport,
      sessionId: 'task',
      state: state,
    );
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: BackgroundWorksBanner(controller: controller),
      ),
    ));
    await tester.pumpAndSettle();

    expect(controller.running, hasLength(2));
    expect(find.text('2 running background task(s)'), findsOneWidget);
    expect(find.text('Run checks'), findsOneWidget);
    expect(find.text('Explore repo'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Stop'), findsOneWidget);
    expect(controller.isCancellable(controller.running.first), isTrue);

    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    final command = bridge.conversationTransport.commands.single;
    expect(command.sessionId, 'task');
    expect(command.type, 'cancelBackgroundWork');
    expect(command.payload, {'workId': 'bash-1'});
  });

  testWidgets('cancel failure stays scoped and clears on authoritative update',
      (tester) async {
    final bridge = FakeBridge();
    final state = _state();
    bridge.conversationTransport.commandHandler =
        (sessionId, type, payload) async => {
              'status':
                  type == 'cancelBackgroundWork' ? 'rejected' : 'accepted',
              if (type == 'cancelBackgroundWork')
                'reasonCode': 'not_cancellable',
            };
    final controller = BackgroundWorksController(
      transport: bridge.conversationTransport,
      sessionId: 'task',
      state: state,
    );
    addTearDown(controller.dispose);

    expect(await controller.cancel('bash-1'), isFalse);
    expect(controller.failureFor('bash-1'), isNotNull);

    state.applyFrame({
      'toSeq': 2,
      'payload': {
        'kind': 'deltas',
        'fromSeq': 1,
        'deltas': [
          {
            'op': 'state.updated',
            'patch': {
              'backgroundWorks': [
                {
                  'workId': 'bash-1',
                  'kind': 'bash',
                  'title': 'Run checks',
                  'status': 'cancelled',
                  'startedAt': 1,
                },
              ],
            },
          },
        ],
      },
    }, onGap: () {});

    expect(controller.failureFor('bash-1'), isNull);
    expect(controller.running, isEmpty);
  });
}
