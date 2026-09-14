import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';

import '../fake_workspace.dart';

Future<void> _pumpChat(WidgetTester tester, double width) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 844);
  addTearDown(tester.view.reset);
  SharedPreferences.setMockInitialValues({});
  final bridge = FakeBridge();
  final state = ConversationState();
  state.applyFrame(
    {
      'toSeq': 1,
      'payload': {
        'kind': 'snapshot',
        'snapshot': {
          ...composerSnapshotFixture,
          'revision': 1,
          'logEpoch': 'test',
          'control': {'phase': 'idle'},
          'rows': {
            'totalCount': 2,
            'firstRowId': 1,
            'window': [
              {'rowId': 1, 'kind': 'userInput', 'text': 'read the log'},
              {
                'rowId': 2,
                'kind': 'assistant',
                'text': 'Done, see the summary.',
                'state': 'complete',
              },
            ],
          },
        },
      },
    },
    onGap: () {},
  );
  bridge.conversationTransport.states['actions'] = state;
  final prefs = ClientPreferences();
  final composerStore = ComposerStore();
  addTearDown(composerStore.dispose);
  addTearDown(prefs.dispose);
  await tester.pumpWidget(ZcodeRemoteApp(
    preferences: prefs,
    home: ChatPage(
      session: bridge,
      scope: const {'workspaceIdentity': 'workspace'},
      workspaceKey: 'workspace',
      sessionId: 'actions',
      title: 'actions',
      workspaceName: 'ZcodeRemote',
      deviceId: 'actions-device',
      composerStore: composerStore,
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('compact message actions copy button is a 48px target',
      (tester) async {
    await _pumpChat(tester, 390);

    final copyButtons = find.byTooltip('Copy');
    expect(copyButtons, findsWidgets);
    for (final rect in [
      tester.getRect(find.byTooltip('Copy').first),
      tester.getRect(find.byTooltip('Copy').last),
    ]) {
      expect(rect.width, greaterThanOrEqualTo(48),
          reason: 'copy hit box must meet the compact touch target');
      expect(rect.height, greaterThanOrEqualTo(48));
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide message actions keep the desktop 28px row',
      (tester) async {
    await _pumpChat(tester, 1180);

    final rect = tester.getRect(find.byTooltip('Copy').first);
    expect(rect.width, closeTo(28, 0.1));
    expect(rect.height, closeTo(28, 0.1));
    expect(tester.takeException(), isNull);
  });
}
