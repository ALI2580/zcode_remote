import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';

import 'fake_workspace.dart';
import 'review_capture.dart';

void main() {
  setUpAll(loadReviewCaptureFonts);
  testWidgets('review: official turnHeader fileChanges reaches the summary bar',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge();
    final state = ConversationState();
    state.applyFrame({
      'toSeq': 1,
      'payload': {
        'kind': 'snapshot',
        'snapshot': {
          ...composerSnapshotFixture,
          'revision': 1,
          'logEpoch': 'summary-review',
          'control': {'phase': 'idle'},
          'rows': {
            'totalCount': 3,
            'firstRowId': 1,
            'window': [
              {'kind': 'userInput', 'rowId': 1, 'turnId': 'turn-a', 'text': 'Review change'},
              {
                'kind': 'turnHeader', 'rowId': 2, 'turnId': 'turn-a',
                'entityId': 'turn-a-header', 'state': 'complete',
                'fileChanges': {'files': 1, 'additions': 10, 'deletions': 10, 'state': 'active'},
                'actions': {'canRewindFiles': true},
              },
              {'kind': 'assistantText', 'rowId': 3, 'turnId': 'turn-a',
                'state': 'complete', 'text': 'Finished review.'},
            ],
          },
        },
      },
    }, onGap: () => fail('unexpected gap'));
    bridge.conversationTransport.states['summary-review'] = state;
    final preferences = ClientPreferences();
    await preferences.setLanguage('zh');
    final composers = ComposerStore();
    final boundary = GlobalKey();
    try {
      await tester.pumpWidget(RepaintBoundary(key: boundary, child: ZcodeRemoteApp(
        preferences: preferences,
        home: ChatPage(session: bridge, scope: const {'workspaceIdentity': 'workspace'},
          workspaceKey: 'workspace', sessionId: 'summary-review', title: 'Summary review',
          deviceId: 'summary-device', composerStore: composers),
      )));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationChangeSummary), findsOneWidget,
          reason: 'Official summary is attached to the turn header, not a fabricated row kind.');
      expect(find.text('1 个文件已更改'), findsOneWidget);
      expect(find.text('+10'), findsOneWidget);
      expect(find.text('-10'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureReviewBoundary(tester, boundary, 'u06-summary-390-zh');
      tester.view.physicalSize = const Size(1180, 820);
      await preferences.setLanguage('en');
      await preferences.setTextScale(1.4);
      await preferences.setTheme(ThemeMode.dark);
      await tester.pumpAndSettle();
      expect(find.text('1 files changed'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await captureReviewBoundary(tester, boundary, 'u06-summary-1180-en-140');
      final summaryRect =
          tester.getRect(find.byType(ConversationChangeSummary));
      final undoRect = tester.getRect(find.text('Undo'));
      expect(summaryRect.right - undoRect.right, lessThanOrEqualTo(24),
          reason: 'Undo belongs at the right edge of the summary bar.');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      composers.dispose();
      preferences.dispose();
    }
  });
}
