import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';

import 'fake_workspace.dart';

/// P2-conv measurement harness (references/optimization/
/// performance-todolist.md): the streaming chain is
/// ConversationState notification → setState → ChatPage build →
/// conversationTurnGroups over ALL rows. This harness counts each stage
/// deterministically for a fixed delta sequence over an N-row history.
///
/// Run: flutter test test/ui/chat_stream_metrics_test.dart --plain-name 'metric'
/// (counters print to stdout; assertions only check chain integrity).
void main() {
  test('conversationTurnGroups algorithmic cost (baseline data)', () {
    const sizes = [1000, 5000, 20000];
    for (final n in sizes) {
      final rows = [
        for (var i = 1; i <= n; i++)
          {
            'rowId': i,
            'kind': i.isOdd ? 'userInput' : 'assistantText',
            'text': 'row $i ${'x' * 80}',
          }
      ];
      // warm-up
      for (var i = 0; i < 50; i++) {
        conversationTurnGroups(rows);
      }
      final sw = Stopwatch()..start();
      const rounds = 200;
      for (var i = 0; i < rounds; i++) {
        conversationTurnGroups(rows);
      }
      sw.stop();
      // ignore: avoid_print
      print('P2CONV group rows=$n '
          'total_us=${sw.elapsedMicroseconds} '
          'per_call_us=${(sw.elapsedMicroseconds / rounds).toStringAsFixed(1)}');
    }
  });

  Future<(int, int)> runStreamHarness({
    required WidgetTester tester,
    required int historyRows,
    required int deltaFrames,
  }) async {
    SharedPreferences.setMockInitialValues({});
    final bridge = FakeBridge();
    final state = ConversationState();
    var notifications = 0;
    state.addListener(() => notifications++);
    final window = [
      for (var i = 1; i <= historyRows; i++)
        {
          'rowId': i,
          'kind': i.isOdd ? 'userInput' : 'assistantText',
          'text': 'row $i ${'x' * 80}',
          'state': 'complete',
        }
    ];
    state.applyFrame({
      'toSeq': 1,
      'payload': {
        'kind': 'snapshot',
        'snapshot': {
          ...composerSnapshotFixture,
          'revision': 1,
          'logEpoch': 'test',
          'control': {'phase': 'streaming'},
          'rows': {'totalCount': historyRows, 'firstRowId': 1, 'window': window},
        },
      },
    }, onGap: () {});
    bridge.conversationTransport.states['stream-metrics'] = state;
    final prefs = ClientPreferences();
    final composerStore = ComposerStore();
    addTearDown(composerStore.dispose);
    addTearDown(prefs.dispose);

    chatPageBuildCount = 0;
    chatTurnGroupComputations = 0;
    chatTurnGroupComputeMicros = 0;
    chatTurnGroupProfiling = true;

    await tester.pumpWidget(ZcodeRemoteApp(
      preferences: prefs,
      home: ChatPage(
        session: bridge,
        scope: const {'workspaceIdentity': 'workspace'},
        workspaceKey: 'workspace',
        sessionId: 'stream-metrics',
        title: 'stream-metrics',
        workspaceName: 'ZcodeRemote',
        deviceId: 'stream-device',
        composerStore: composerStore,
      ),
    ));
    await tester.pumpAndSettle();

    final baselineBuilds = chatPageBuildCount;
    final baselineGroups = chatTurnGroupComputations;
    final sw = Stopwatch()..start();
    for (var f = 0; f < deltaFrames; f++) {
      state.applyFrame({
        'toSeq': 2 + f,
        'payload': {
          'kind': 'deltas',
          'deltas': [
            {
              'op': 'row.appended',
              'row': {
                'rowId': historyRows + 1,
                'kind': 'assistantText',
                'text': 'streaming',
                'state': 'streaming',
              },
            },
            {
              'op': 'row.delta',
              'rowId': historyRows + 1,
              'path': 'text',
              'append': ' chunk $f ${'y' * 16}',
            },
          ],
        },
        'fromSeq': 1 + f,
      }, onGap: () {});
      await tester.pump();
    }
    sw.stop();
    await tester.pumpAndSettle();
    chatTurnGroupProfiling = false;

    // chain integrity: every notification reached a build, every build
    // grouped the full row list.
    // ignore: avoid_print
    print('P2CONV stream historyRows=$historyRows deltaFrames=$deltaFrames '
        'notifications=$notifications '
        'builds=${chatPageBuildCount - baselineBuilds} '
        'groupCalls=${chatTurnGroupComputations - baselineGroups} '
        'groupMicros=$chatTurnGroupComputeMicros '
        'wallUs=${sw.elapsedMicroseconds}');
    return (notifications, chatPageBuildCount - baselineBuilds);
  }

  testWidgets('metric: streaming chain counters at 200-row history',
      (tester) async {
    final (notifications, builds) = await runStreamHarness(
        tester: tester, historyRows: 200, deltaFrames: 60);
    expect(notifications, greaterThanOrEqualTo(60));
    expect(builds, greaterThanOrEqualTo(1));
  });

  testWidgets('metric: streaming chain counters at 5000-row history',
      (tester) async {
    final (notifications, builds) = await runStreamHarness(
        tester: tester, historyRows: 5000, deltaFrames: 60);
    expect(notifications, greaterThanOrEqualTo(60));
    expect(builds, greaterThanOrEqualTo(1));
  });
}
