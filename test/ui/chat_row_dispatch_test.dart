import 'package:flutter/material.dart';
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

  testWidgets('用户气泡原位编辑提交 editUserQuery 并显示重发态（U-E1）',
      (tester) async {
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
                  'entityId': 'user-entity-1',
                  'text': '原始问题',
                },
                {
                  'kind': 'turnHeader',
                  'rowId': 2,
                  'state': 'complete',
                },
              ],
            },
          },
        },
      },
      onGap: () {},
    );
    bridge.conversationTransport.states['dispatch-edit'] = state;
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    final composerStore = ComposerStore();
    addTearDown(composerStore.dispose);
    addTearDown(prefs.dispose);

    await tester.pumpWidget(ZcodeRemoteApp(
      preferences: prefs,
      home: ChatPage(
        session: bridge,
        scope: const {'workspaceIdentity': 'workspace'},
        workspaceKey: 'workspace',
        sessionId: 'dispatch-edit',
        title: 'dispatch-edit',
        workspaceName: 'ZcodeRemote',
        deviceId: 'dispatch-device',
        composerStore: composerStore,
      ),
    ));
    await tester.pumpAndSettle();

    // Edit opens the in-place field inside the bubble (composer excluded).
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    final field = find.byType(TextField).first;
    expect(find.text('重新发送'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    await tester.enterText(field, ' 修改后的问题 ');
    await tester.tap(find.text('重新发送'));
    await tester.pumpAndSettle();

    // The edit went out as the official editUserQuery command with the row
    // target and trimmed text; the in-place editor closed afterwards.
    final edit = bridge.conversationTransport.commands
        .lastWhere((c) => c.type == 'editUserQuery');
    expect(edit.sessionId, 'dispatch-edit');
    expect(edit.payload['newText'], '修改后的问题');
    expect(edit.payload['target']['rowId'], 1);
    expect(edit.payload['target']['entityId'], 'user-entity-1');
    // The in-place editor closed; only the composer field remains.
    expect(find.text('重新发送'), findsNothing);
    expect(find.text('取消'), findsNothing);
    expect(find.text('原始问题'), findsOneWidget);
  });

  testWidgets('editUserQuery 拒绝时原位编辑保留并显示失败反馈（U-E1）',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final bridge = FakeBridge();
    bridge.conversationTransport.response = {'status': 'rejected'};
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
                  'entityId': 'user-entity-1',
                  'text': '原始问题',
                },
                {
                  'kind': 'turnHeader',
                  'rowId': 2,
                  'state': 'complete',
                },
              ],
            },
          },
        },
      },
      onGap: () {},
    );
    bridge.conversationTransport.states['dispatch-edit-fail'] = state;
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    final composerStore = ComposerStore();
    addTearDown(composerStore.dispose);
    addTearDown(prefs.dispose);

    await tester.pumpWidget(ZcodeRemoteApp(
      preferences: prefs,
      home: ChatPage(
        session: bridge,
        scope: const {'workspaceIdentity': 'workspace'},
        workspaceKey: 'workspace',
        sessionId: 'dispatch-edit-fail',
        title: 'dispatch-edit-fail',
        workspaceName: 'ZcodeRemote',
        deviceId: 'dispatch-device',
        composerStore: composerStore,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '新文本');
    await tester.tap(find.text('重新发送'));
    await tester.pumpAndSettle();

    expect(find.text('编辑重发失败，请重试'), findsOneWidget);
    // The editor stays open so the user's text is not lost.
    expect(find.text('重新发送'), findsOneWidget);
  });
}
