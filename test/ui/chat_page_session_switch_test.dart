import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'fake_workspace.dart';

void main() {
  testWidgets('session id updates resubscribe the conversation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final bridge = FakeBridge();
    final first = ConversationState();
    seedConversation(first, count: 1);
    final second = ConversationState();
    seedConversation(second, count: 2);
    bridge.conversationTransport.states['first'] = first;
    bridge.conversationTransport.states['second'] = second;
    final prefs = ClientPreferences();
    final composerStore = ComposerStore();
    addTearDown(composerStore.dispose);
    addTearDown(prefs.dispose);

    Widget page(String sessionId) => ChatPage(
          session: bridge,
          scope: const {'workspaceIdentity': 'workspace'},
          workspaceKey: 'workspace',
          sessionId: sessionId,
          title: sessionId,
          workspaceName: 'ZcodeRemote',
          deviceId: 'switch-device',
          composerStore: composerStore,
        );

    Widget app(Widget child) => ZcodeRemoteApp(preferences: prefs, home: child);

    await tester.pumpWidget(app(page('first')));
    await tester.pumpAndSettle();
    expect(find.text('检查第 1 项布局和状态恢复'), findsOneWidget);
    expect(bridge.conversationTransport.subscriptions['first'], 1);

    await tester.pumpWidget(app(page('second')));
    await tester.pump(const Duration(milliseconds: 50));
    expect(bridge.conversationTransport.subscriptions['second'], 1);
  });
}
