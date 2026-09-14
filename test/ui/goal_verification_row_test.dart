import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/theme.dart';
import 'package:zcode_remote/ui/conversation_work_rows.dart';

import 'fake_workspace.dart';

Map<String, dynamic> syntheticRow({
  String status = 'started',
  bool? passed,
  String reason = '',
  String nextAction = '',
  int? iteration,
}) =>
    {
      'version': 1,
      'kind': 'synthetic',
      'type': 'goal_verification',
      'display': 'separator',
      'targetId': 'target-1',
      'verificationId': 'verify-1',
      'status': status,
      if (passed != null || reason.isNotEmpty || nextAction.isNotEmpty)
        'verification': {
          if (passed != null) 'passed': passed,
          if (reason.isNotEmpty) 'reason': reason,
          if (nextAction.isNotEmpty) 'nextAction': nextAction,
        },
      if (iteration != null) 'goalIteration': iteration,
    };

Future<void> _pump(WidgetTester tester, Map<String, dynamic> row) async {
  await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.dark(),
      home: Scaffold(
          body: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [GoalVerificationRow(row: row)]))));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('GoalVerificationRow.isGoalVerification (规则 24 合成行)', () {
    test('接受合成 schema 双字段形态', () {
      expect(GoalVerificationRow.isGoalVerification(syntheticRow()), isTrue);
    });

    test('接受展平 kind 形态', () {
      expect(GoalVerificationRow.isGoalVerification(
          {'kind': 'goal_verification'}), isTrue);
    });

    test('拒绝普通行', () {
      expect(GoalVerificationRow.isGoalVerification(
          {'kind': 'assistantText'}), isFalse);
      expect(GoalVerificationRow.isGoalVerification(
          {'kind': 'synthetic', 'type': 'other'}), isFalse);
    });
  });

  testWidgets('started 行显示验证中标题与迭代号', (tester) async {
    await _pump(tester, syntheticRow(status: 'started', iteration: 2));
    expect(find.text('#2 Goal verification running'), findsOneWidget);
    expect(find.text('Goal verification passed'), findsNothing);
  });

  testWidgets('completed+passed 显示通过与 reason/nextAction', (tester) async {
    await _pump(tester,
        syntheticRow(status: 'completed', passed: true, reason: '所有断言均已满足', nextAction: '无需进一步操作'));
    expect(find.text('Goal verification passed'), findsOneWidget);
    expect(find.text('所有断言均已满足'), findsOneWidget);
    expect(find.text('Next: 无需进一步操作'), findsOneWidget);
  });

  testWidgets('completed 未通过显示警示文案与 reason', (tester) async {
    await _pump(tester,
        syntheticRow(status: 'completed', passed: false, reason: '第 3 步超时'));
    expect(find.text('Goal verification not passed'), findsOneWidget);
    expect(find.text('第 3 步超时'), findsOneWidget);
  });

  testWidgets('failed_closed 行显示失败关闭', (tester) async {
    await _pump(tester, syntheticRow(status: 'failed_closed'));
    expect(find.text('Goal verification failed closed'), findsOneWidget);
  });

  testWidgets('cancelled 行中性显示', (tester) async {
    await _pump(tester, syntheticRow(status: 'cancelled'));
    expect(find.text('Goal verification cancelled'), findsOneWidget);
  });

  testWidgets('ChatPage 快照行路由贯通：raw synthetic 与展平 kind 双形态',
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
              'totalCount': 3,
              'firstRowId': 1,
              'window': [
                {
                  'kind': 'userInput',
                  'rowId': 1,
                  'text': '验证目标校验行路由',
                },
                syntheticRow(
                    status: 'completed',
                    passed: true,
                    reason: '原始 schema 贯通',
                    iteration: 2),
                {
                  'kind': 'goal_verification',
                  'rowId': 3,
                  'status': 'started',
                  'goalIteration': 7,
                },
              ],
            },
          },
        },
      },
      onGap: () {},
    );
    bridge.conversationTransport.states['route'] = state;
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
        sessionId: 'route',
        title: 'route',
        workspaceName: 'ZcodeRemote',
        deviceId: 'route-device',
        composerStore: composerStore,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(GoalVerificationRow), findsNWidgets(2));
    expect(find.textContaining('#2'), findsOneWidget);
    expect(find.textContaining('#7'), findsOneWidget);
    expect(find.textContaining('原始 schema 贯通'), findsOneWidget);
  });
}
