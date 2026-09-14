import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';

import 'fake_workspace.dart';

/// chat_page `_rowWidget` 分派贯通守护：快照行经 ChatPage 渲染为对应行组件
/// （与 goal_verification_row_test 的贯通测试同一 harness 模式）。
void main() {
  testWidgets('快照 changeSummary 行渲染变更摘要卡并可展开文件行', (tester) async {
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
                {
                  'kind': 'userInput',
                  'rowId': 1,
                  'text': '检查变更摘要行路由',
                },
                {
                  'kind': 'changeSummary',
                  'rowId': 2,
                  'state': 'complete',
                  'count': 2,
                  'files': [
                    {
                      'path': 'lib/a.dart',
                      'addedLines': 10,
                      'removedLines': 2,
                    },
                    {
                      'path': 'lib/b.dart',
                      'addedLines': 3,
                      'removedLines': 1,
                    },
                  ],
                },
              ],
            },
          },
        },
      },
      onGap: () {},
    );
    bridge.conversationTransport.states['dispatch'] = state;
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
        sessionId: 'dispatch',
        title: 'dispatch',
        workspaceName: 'ZcodeRemote',
        deviceId: 'dispatch-device',
        composerStore: composerStore,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('2 个文件已更改'), findsOneWidget);
    expect(find.text('+13'), findsOneWidget);
    expect(find.text('-3'), findsOneWidget);
    expect(find.text('lib/a.dart'), findsNothing);

    await tester.tap(find.text('2 个文件已更改'));
    await tester.pumpAndSettle();

    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('lib/'), findsWidgets);
    expect(find.text('b.dart'), findsOneWidget);
    expect(find.text('+10 -2'), findsOneWidget);
    expect(find.text('+3 -1'), findsOneWidget);
  });

  testWidgets('快照 subagent 行渲染类型·状态—摘要文本', (tester) async {
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
                {
                  'kind': 'userInput',
                  'rowId': 1,
                  'text': '检查子智能体行路由',
                },
                {
                  'kind': 'subagent',
                  'rowId': 2,
                  'subagentType': 'Explore',
                  'status': 'completed',
                  'summaryText': '仓库结构已扫描',
                },
              ],
            },
          },
        },
      },
      onGap: () {},
    );
    bridge.conversationTransport.states['dispatch-sub'] = state;
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
        sessionId: 'dispatch-sub',
        title: 'dispatch-sub',
        workspaceName: 'ZcodeRemote',
        deviceId: 'dispatch-device',
        composerStore: composerStore,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Explore · completed — 仓库结构已扫描'), findsOneWidget);
  });
}
