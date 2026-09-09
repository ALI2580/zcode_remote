import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'fake_features.dart';
import 'fake_workspace.dart';

void main() {
  testWidgets(
      'Markdown selection copies linked text and the complete second paragraph',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.conversationTransport.states['task'] = ConversationState()
      ..applyFrame({
        'toSeq': 1,
        'payload': {
          'kind': 'snapshot',
          'snapshot': {
            ...composerSnapshotFixture,
            'rows': {
              'totalCount': 1,
              'firstRowId': 1,
              'window': [
                {
                  'kind': 'assistantText',
                  'rowId': 1,
                  'text':
                      'This is selectable [reference text](file.md).\n\nThe complete second paragraph.'
                }
              ]
            }
          }
        }
      }, onGap: () {});
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      if (call.method == 'Clipboard.getData') return {'text': copied};
      return null;
    });
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      bridge.channels.dispose();
    });
    await tester.pumpWidget(ZcodeRemoteApp(
        home: ChatPage(
            session: bridge,
            scope: const {},
            workspaceKey: 'synthetic',
            sessionId: 'task',
            title: 'Synthetic')));
    await tester.pumpAndSettle();
    final text = find.textContaining('This is selectable');
    await tester.longPressAt(tester.getTopLeft(text) + const Offset(20, 10));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Copy'));
    await tester.pumpAndSettle();
    expect(copied, contains('This is selectable reference text.'));
    expect(copied, contains('The complete second paragraph.'));
    expect(copied, isNot(contains('[reference text]')));
    expect(bridge.conversationTransport.sent, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });
}
