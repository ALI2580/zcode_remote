import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/conversation_viewport.dart';
import 'package:zcode_remote/ui/theme.dart';

import 'fake_workspace.dart';

Future<void> runSearchSnippetPriorityReview(WidgetTester tester,
    {GlobalKey? captureKey, Future<void> Function()? onVisible}) async {
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
        'logEpoch': 'review-snippet-priority',
        'control': {'phase': 'idle'},
        'rows': {
          'totalCount': 44,
          'firstRowId': 1,
          'window': [
            for (var turn = 1; turn <= 20; turn++) ...[
              {
                'kind': 'userInput',
                'rowId': turn * 2 + 3,
                'text': 'Later prompt $turn',
              },
              {
                'kind': 'assistantText',
                'rowId': turn * 2 + 4,
                'text': 'Flutter maintenance log $turn',
              },
            ],
          ],
        },
      },
    },
  }, onGap: () => fail('Unexpected gap'));
  final transport = bridge.conversationTransport;
  transport.states['task'] = state;
  transport.historyHandler = (_, before, limit) async {
    // This callback also runs during a guarded native widget pump.
    expectSync(before, 5);
    return {
      'atLogEpoch': 'review-snippet-priority',
      'hasMore': false,
      'rows': [
        {
          'kind': 'userInput',
          'rowId': 1,
          'text': List.filled(100, 'Original long prompt.').join(' '),
        },
        {
          'kind': 'assistantText',
          'rowId': 2,
          'text': List.filled(120, 'Earlier detailed explanation.').join(' '),
        },
        {
          'kind': 'assistantText',
          'rowId': 3,
          'text': 'Flutter selected historical acceptance result',
        },
        {
          'kind': 'assistantText',
          'rowId': 4,
          'text': 'Final summary after the selected snippet',
        },
      ],
    };
  };
  await tester.pumpWidget(MaterialApp(
    theme: ZInkTheme.light(),
    builder: (context, child) =>
        RepaintBoundary(key: captureKey, child: child!),
    home: ChatPage(
      session: bridge,
      scope: const {'workspaceIdentity': 'workspace'},
      workspaceKey: 'workspace',
      sessionId: 'task',
      searchQuery: 'Flutter',
      searchSnippet: 'Flutter selected historical acceptance result',
      title: 'Task',
      embedded: true,
    ),
  ));
  await tester.pumpAndSettle();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
  expect(transport.historyRequests, hasLength(1),
      reason: 'Newer generic query matches cannot satisfy a selected snippet.');
  final target = find.text('Flutter selected historical acceptance result');
  if (const bool.fromEnvironment('NATIVE_SEARCH_VISUAL_REVIEW')) {
    final view = tester
        .widget<ConversationViewport>(find.byType(ConversationViewport))
        .view;
    debugPrint(
        'NATIVE_SEARCH_READING anchor=${view.anchor} offset=${view.anchorOffset} pixels=${view.pixels} following=${view.following} viewport=${tester.getSize(find.byType(ConversationViewport))}');
    debugPrint(
        'NATIVE_SEARCH_STATE epoch=${state.logEpoch} viewEpoch=${view.logEpoch} rows=${state.rows.length} oldest=${state.oldestRowId} total=${state.totalCount} early=${state.rows.where((r) => (r["rowId"] as int) < 5).map((r) => r["rowId"]).toList()}');
    debugPrint(
        'NATIVE_SEARCH_NOTICES ${tester.widgetList<Text>(find.byType(Text)).map((w) => w.data ?? w.textSpan?.toPlainText() ?? "").where((s) => s.contains("历史") || s.contains("History") || s.contains("result") || s.contains("Try again"))}');
  }
  expect(target, findsOneWidget);
  final viewport = tester.getRect(find.byType(ConversationViewport));
  final targetRect = tester.getRect(target);
  expect(targetRect.top, greaterThanOrEqualTo(viewport.top));
  expect(targetRect.bottom, lessThanOrEqualTo(viewport.bottom));
  final overlay = tester.widget<CustomPaint>(
      find.byKey(const ValueKey('search-highlight-overlay')));
  final rectangles = (overlay.painter! as SearchHighlightPainter).rects;
  expect(rectangles, isNotEmpty);
  expect(rectangles.every((r) => r.top >= 0 && r.bottom <= viewport.height),
      isTrue);
  final paintBox = tester.renderObject<RenderBox>(
      find.byKey(const ValueKey('search-highlight-overlay')));
  expect(
      rectangles
          .every((r) => targetRect.contains(paintBox.localToGlobal(r.center))),
      isTrue,
      reason: 'The painted highlight must remain on the selected text after '
          'the virtual list finishes laying out later rows.');
  expect(tester.takeException(), isNull);
  await onVisible?.call();
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  testWidgets('review: an old selected snippet wins over newer query matches',
      runSearchSnippetPriorityReview);
  for (final size in const [Size(441, 981), Size(1723, 1220)]) {
    testWidgets('review: selected snippet remains visible at $size',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(tester.view.reset);
      await runSearchSnippetPriorityReview(tester);
    });
  }
}
