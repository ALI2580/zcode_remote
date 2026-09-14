import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/conversation_viewport.dart';
import 'package:zcode_remote/ui/theme.dart';

import 'fake_workspace.dart';

Map<String, dynamic> _searchSnapshot(
    String epoch, int firstRowId, List<Map<String, dynamic>> window,
    {required int totalCount}) {
  return {
    ...composerSnapshotFixture,
    'sessionId': 'task',
    'revision': 1,
    'logEpoch': epoch,
    'control': {'phase': 'idle'},
    'rows': {
      'totalCount': totalCount,
      'firstRowId': firstRowId,
      'window': window,
    },
  };
}

void _applySearchSnapshot(ConversationState state, String epoch, int firstRowId,
    List<Map<String, dynamic>> window,
    {required int totalCount}) {
  state.applyFrame({
    'toSeq': state.seq + 1,
    'payload': {
      'kind': 'snapshot',
      'snapshot':
          _searchSnapshot(epoch, firstRowId, window, totalCount: totalCount),
    },
  }, onGap: () => fail('Unexpected gap'));
}

void main() {
  testWidgets('search locates an old ellipsis snippet and removes real boxes',
      (tester) async {
    final bridge = FakeBridge();
    final transport = bridge.conversationTransport;
    final state = ConversationState();
    state.applyFrame({
      'toSeq': 1,
      'payload': {
        'kind': 'snapshot',
        'snapshot': {
          ...composerSnapshotFixture,
          'sessionId': 'task',
          'revision': 1,
          'logEpoch': 'highlight-epoch',
          'control': {'phase': 'idle'},
          'rows': {
            'totalCount': 3,
            'firstRowId': 1,
            'window': [
              {'kind': 'userInput', 'rowId': 3, 'text': '当前可见内容'},
            ],
          },
        },
      },
    }, onGap: () {});
    transport.states['task'] = state;
    transport.historyHandler = (_, before, __) async {
      expect(before, 3);
      return {
        'atLogEpoch': 'highlight-epoch',
        'hasMore': false,
        'rows': [
          {
            'kind': 'assistantText',
            'rowId': 1,
            'text': '... needle   target ...',
          }
        ],
      };
    };
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: ChatPage(
            session: bridge,
            scope: const {'workspaceIdentity': 'workspace'},
            workspaceKey: 'workspace',
            sessionId: 'task',
            searchQuery: 'needle target',
            searchSnippet: '... needle   target ...',
            title: 'Task',
            embedded: true)));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 500));
    expect(state.rows.any((row) => row['rowId'] == 1), isTrue,
        reason: 'match came from the older history page');
    expect(tester.takeException(), isNull);
  });

  testWidgets('visible search match paints real boxes for three seconds',
      (tester) async {
    final bridge = FakeBridge();
    final state = ConversationState();
    state.applyFrame({
      'toSeq': 1,
      'payload': {
        'kind': 'snapshot',
        'snapshot': {
          ...composerSnapshotFixture,
          'sessionId': 'task',
          'revision': 1,
          'logEpoch': 'visible-epoch',
          'control': {'phase': 'idle'},
          'rows': {
            'totalCount': 1,
            'firstRowId': 1,
            'window': [
              {'kind': 'assistantText', 'rowId': 1, 'text': 'needle target'},
            ],
          },
        },
      },
    }, onGap: () {});
    bridge.conversationTransport.states['task'] = state;
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: ChatPage(
            session: bridge,
            scope: const {'workspaceIdentity': 'workspace'},
            workspaceKey: 'workspace',
            sessionId: 'task',
            searchQuery: 'needle target',
            searchSnippet: 'needle target',
            title: 'Task',
            embedded: true)));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('search-highlight-overlay')));
    final painter = paint.painter! as SearchHighlightPainter;
    expect(painter.rects, isNotEmpty);
    expect(painter.rects.every((rect) => rect.width > 0 && rect.height > 0),
        isTrue);
    await tester.pump(const Duration(seconds: 3));
    expect(
        find.byKey(const ValueKey('search-highlight-overlay')), findsNothing);
  });

  testWidgets('search continues past six history pages', (tester) async {
    final bridge = FakeBridge();
    final state = ConversationState();
    _applySearchSnapshot(
      state,
      'long-epoch',
      1,
      [
        for (var id = 1381; id <= 1440; id++)
          {'kind': 'userInput', 'rowId': id, 'text': 'recent deep $id'},
      ],
      totalCount: 1440,
    );
    bridge.conversationTransport.states['task'] = state;
    bridge.conversationTransport.historyHandler = (_, before, limit) async {
      expectSync(limit, 200);
      final end = before!;
      final start = (end - 200).clamp(1, end - 1).toInt();
      return {
        'atLogEpoch': 'long-epoch',
        'hasMore': start > 1,
        'rows': [
          for (var id = start; id < end; id++)
            {
              'kind': id == 100 ? 'assistantText' : 'userInput',
              'rowId': id,
              'text': id == 100 ? 'deep target' : 'older $id',
            },
        ],
      };
    };
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: ChatPage(
            session: bridge,
            scope: const {'workspaceIdentity': 'workspace'},
            workspaceKey: 'workspace',
            sessionId: 'task',
            searchQuery: 'deep',
            searchSnippet: 'deep target',
            title: 'Task',
            embedded: true)));
    await tester.pumpAndSettle();
    expect(bridge.conversationTransport.historyRequests.length, 7,
        reason: 'the result is on the seventh 200-row page');
    expect(state.rows.any((row) => row['rowId'] == 100), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('assistant search match anchors its containing turn',
      (tester) async {
    final bridge = FakeBridge();
    final state = ConversationState();
    final window = <Map<String, dynamic>>[
      {
        'kind': 'userInput',
        'rowId': 10,
        'text': List.filled(80, 'long user prompt').join(' '),
      },
      {
        'kind': 'assistantText',
        'rowId': 11,
        'text': 'assistant preface',
      },
      {
        'kind': 'assistantText',
        'rowId': 12,
        'text': 'assistant needle target',
      },
      {'kind': 'reasoning', 'rowId': 13, 'text': 'follow-up'},
      {'kind': 'assistantText', 'rowId': 14, 'text': 'final summary'},
      for (var turn = 0; turn < 30; turn++) ...[
        {
          'kind': 'userInput',
          'rowId': 20 + turn * 2,
          'text': 'later user prompt $turn',
        },
        {
          'kind': 'assistantText',
          'rowId': 21 + turn * 2,
          'text': 'later answer $turn',
        },
      ],
    ];
    _applySearchSnapshot(
      state,
      'assistant-epoch',
      10,
      window,
      totalCount: window.length,
    );
    bridge.conversationTransport.states['task'] = state;
    final views = <String, ConversationViewState>{};
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: ChatPage(
            session: bridge,
            scope: const {'workspaceIdentity': 'workspace'},
            workspaceKey: 'workspace',
            sessionId: 'task',
            searchQuery: 'needle',
            searchSnippet: 'needle target',
            title: 'Task',
            viewStates: views,
            embedded: true)));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 100));
    final view = views[composerKey(null, 'workspace', 'task')];
    expect(view?.anchor, '11',
        reason: 'the viewport scrolls to the group row, not assistant row 12');
    expect(view?.following, isFalse);
    final target = find.text('assistant needle target');
    expect(target, findsOneWidget);
    final viewport = tester.getTopLeft(find.byType(ConversationViewport)).dy;
    final viewportBottom =
        tester.getBottomRight(find.byType(ConversationViewport)).dy;
    final targetTop = tester.getTopLeft(target).dy;
    final targetBottom = tester.getBottomRight(target).dy;
    expect(targetTop, greaterThanOrEqualTo(viewport));
    expect(targetBottom, lessThanOrEqualTo(viewportBottom));
    await tester.pump(const Duration(milliseconds: 100));
    final paint = tester.widget<CustomPaint>(
        find.byKey(const ValueKey('search-highlight-overlay')));
    expect((paint.painter! as SearchHighlightPainter).rects, isNotEmpty);
    final trigger = find.byKey(const ValueKey('search-target-turn-trigger'));
    expect(trigger, findsOneWidget);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.text('assistant needle target'), findsNothing,
        reason: 'search expansion can still be manually collapsed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('search waits for the first snapshot and retries an epoch change',
      (tester) async {
    final bridge = FakeBridge();
    final state = ConversationState();
    final firstPage = Completer<dynamic>();
    bridge.conversationTransport.subscribeHandler =
        (_) async => FakeConversationSubscription(state, () {});
    bridge.conversationTransport.historyHandler = (_, before, limit) async {
      expectSync(limit, 200);
      if (bridge.conversationTransport.historyRequests.length == 1) {
        expectSync(before, 801);
        return firstPage.future;
      }
      expectSync(before, 801);
      return {
        'atLogEpoch': 'new-epoch',
        'hasMore': false,
        'rows': [
          {'kind': 'assistantText', 'rowId': 500, 'text': 'epoch target'},
        ],
      };
    };
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: ChatPage(
            session: bridge,
            scope: const {'workspaceIdentity': 'workspace'},
            workspaceKey: 'workspace',
            sessionId: 'task',
            searchQuery: 'epoch',
            searchSnippet: 'epoch target',
            title: 'Task',
            embedded: true)));
    await tester.pump();
    expect(bridge.conversationTransport.historyRequests, isEmpty,
        reason: 'search must wait for a ready initial snapshot');

    _applySearchSnapshot(
      state,
      'old-epoch',
      1,
      [
        for (var id = 801; id <= 860; id++)
          {'kind': 'userInput', 'rowId': id, 'text': 'old $id'},
      ],
      totalCount: 860,
    );
    await tester.pump();
    expect(bridge.conversationTransport.historyRequests.length, 1);

    _applySearchSnapshot(
      state,
      'new-epoch',
      1,
      [
        for (var id = 801; id <= 860; id++)
          {'kind': 'userInput', 'rowId': id, 'text': 'new $id'},
      ],
      totalCount: 860,
    );
    firstPage.complete({
      'atLogEpoch': 'old-epoch',
      'hasMore': true,
      'rows': [
        {'kind': 'assistantText', 'rowId': 500, 'text': 'stale target'},
      ],
    });
    await tester.pump(const Duration(milliseconds: 20));
    await tester.pumpAndSettle();
    expect(bridge.conversationTransport.historyRequests.length, 2,
        reason: 'stale page should restart from the new epoch cursor');
    expect(state.rows.any((row) => row['rowId'] == 500), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('same epoch stale history stops without retrying forever',
      (tester) async {
    final bridge = FakeBridge();
    final state = ConversationState();
    _applySearchSnapshot(
      state,
      'stable-epoch',
      1,
      [
        for (var id = 801; id <= 860; id++)
          {'kind': 'userInput', 'rowId': id, 'text': 'recent $id'},
      ],
      totalCount: 860,
    );
    bridge.conversationTransport.states['task'] = state;
    bridge.conversationTransport.historyHandler = (_, before, limit) async {
      // A third invocation would prove that same-epoch stale pages bypassed
      // the search page budget and restarted the locator.
      if (bridge.conversationTransport.historyRequests.length >= 3) {
        throw StateError('unexpected retry');
      }
      return {
        'atLogEpoch': 'wrong-epoch',
        'hasMore': true,
        'rows': [
          {'kind': 'assistantText', 'rowId': 500, 'text': 'epoch target'},
        ],
      };
    };
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: ChatPage(
            session: bridge,
            scope: const {'workspaceIdentity': 'workspace'},
            workspaceKey: 'workspace',
            sessionId: 'task',
            searchQuery: 'epoch',
            searchSnippet: 'epoch target',
            title: 'Task',
            embedded: true)));
    await tester.pumpAndSettle();
    expect(bridge.conversationTransport.historyRequests, hasLength(1));
    expect(state.rows.any((row) => row['rowId'] == 500), isFalse);
    expect(tester.takeException(), isNull);
  });
}
