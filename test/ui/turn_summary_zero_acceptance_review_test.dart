import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';

import 'fake_workspace.dart';

void main() {
  testWidgets('review: zero-change header suppresses every summary in the turn',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final rows = <Map<String, dynamic>>[
      {'rowId': 1, 'kind': 'userInput', 'text': 'No changes'},
      {'rowId': 2, 'kind': 'changeSummary', 'count': 4},
      {
        'rowId': 3,
        'kind': 'turnHeader',
        'state': 'complete',
        'fileChanges': {'files': 0, 'additions': 0, 'deletions': 0},
      },
      {'rowId': 4, 'kind': 'assistantText', 'state': 'complete', 'text': 'Done'},
    ];
    final bridge = FakeBridge();
    bridge.conversationTransport.states['zero-review'] = ConversationState()
      ..applyFrame({
        'toSeq': 1,
        'payload': {
          'kind': 'snapshot',
          'snapshot': {
            ...composerSnapshotFixture,
            'rows': {'totalCount': rows.length, 'firstRowId': 1, 'window': rows},
          },
        },
      }, onGap: () => fail('unexpected gap'));
    final preferences = ClientPreferences();
    await preferences.setLanguage('zh');
    final composers = ComposerStore();
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: ChatPage(
          session: bridge,
          scope: const {'workspaceIdentity': 'zero-review'},
          workspaceKey: 'zero-review',
          sessionId: 'zero-review',
          title: 'No changes',
          composerStore: composers,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationChangeSummary), findsNothing,
          reason: 'A zero-change turn must not create a +0/-0 bar or revive legacy stats.');
      expect(conversationFileChangeSummaryRows(rows), isEmpty,
          reason: 'The side panel must use the same no-changes gate.');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      composers.dispose();
      preferences.dispose();
    }
  });
}
