import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/conversation_viewport.dart';

import '../test/ui/fake_workspace.dart';

/// Device frame-rate sampling for the optimization device gate
/// (references/optimization/final-report.md §5). Streams a fixed delta
/// sequence into a real ChatPage over an N-row history, then performs a
/// user-scroll fling, collecting FrameTiming for both windows.
///
/// Run (profile, on-device):
///   ZCODE_ANDROID_QA=true flutter test integration_test/streaming_frame_metrics_test.dart \
///     -d `<device>` --profile
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final frames = <FrameTiming>[];
  void timings(List<FrameTiming> values) => frames.addAll(values);

  Future<void> measure(String phase, Future<void> Function() body) async {
    final before = frames.length;
    final sw = Stopwatch()..start();
    await body();
    sw.stop();
    final sample = frames.sublist(before);
    if (sample.isEmpty) {
      // ignore: avoid_print
      print('PDEVICE $phase frames=0 (no timing callbacks)');
      return;
    }
    int p(List<FrameTiming> list, int Function(FrameTiming) pick) {
      final v = list.map(pick).toList()..sort();
      return v[(v.length * 0.95).floor().clamp(0, v.length - 1)];
    }

    final refresh = SchedulerBinding
        .instance.platformDispatcher.views.first.display.refreshRate;
    // ignore: avoid_print
    print('PDEVICE ${{
      'phase': phase,
      'frames': sample.length,
      'wallMs': sw.elapsedMilliseconds,
      'refreshRate': refresh.toStringAsFixed(1),
      'buildP50us': p(sample, (f) => f.buildDuration.inMicroseconds),
      'buildP95us': p(sample, (f) => f.buildDuration.inMicroseconds),
      'rasterP95us': p(sample, (f) => f.rasterDuration.inMicroseconds),
      'totalP50us': p(sample, (f) => f.totalSpan.inMicroseconds),
      'totalP95us': p(sample, (f) => f.totalSpan.inMicroseconds),
      'over16ms': sample.where((f) => f.totalSpan.inMicroseconds > 16666).length,
      'over8ms': sample.where((f) => f.totalSpan.inMicroseconds > 8333).length,
    }}');
  }

  testWidgets('device sampling: streaming + scroll over 1000-row history',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final bridge = FakeBridge();
    final state = ConversationState();
    const n = 1000;
    final window = [
      for (var i = 1; i <= n; i++)
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
          'logEpoch': 'device-epoch',
          'control': {'phase': 'streaming'},
          'rows': {'totalCount': n, 'firstRowId': 1, 'window': window},
        },
      },
    }, onGap: () {});
    bridge.conversationTransport.states['device-metrics'] = state;
    final prefs = ClientPreferences();
    addTearDown(prefs.dispose);

    await tester.pumpWidget(ZcodeRemoteApp(
      preferences: prefs,
      home: ChatPage(
        session: bridge,
        scope: const {'workspaceIdentity': 'workspace'},
        workspaceKey: 'workspace',
        sessionId: 'device-metrics',
        title: 'device-metrics',
        workspaceName: 'ZcodeRemote',
        deviceId: 'device',
        composerStore: ComposerStore(),
      ),
    ));
    await tester.pumpAndSettle();

    WidgetsBinding.instance.addTimingsCallback(timings);

    await measure('streaming', () async {
      for (var f = 0; f < 60; f++) {
        state.applyFrame({
          'toSeq': 2 + f,
          'payload': {
            'kind': 'deltas',
            'deltas': [
              {
                'op': 'row.appended',
                'row': {
                  'rowId': n + 1,
                  'kind': 'assistantText',
                  'text': 'streaming',
                  'state': 'streaming',
                },
              },
              {
                'op': 'row.delta',
                'rowId': n + 1,
                'path': 'text',
                'append': ' chunk $f ${'y' * 16}',
              },
            ],
          },
          'fromSeq': 1 + f,
        }, onGap: () {});
        await tester.pump(const Duration(milliseconds: 16));
      }
    });

    await measure('scroll', () async {
      final viewportFinder = find.byType(ConversationViewport);
      for (var f = 0; f < 6; f++) {
        await tester.fling(
            find
                .descendant(
                    of: viewportFinder, matching: find.byType(Scrollable))
                .first,
            const Offset(0, -800),
            3000);
        await tester.pumpAndSettle(const Duration(milliseconds: 100));
      }
    });

    WidgetsBinding.instance.removeTimingsCallback(timings);
    expect(tester.takeException(), isNull);
  });
}
