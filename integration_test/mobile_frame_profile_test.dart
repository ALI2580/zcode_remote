import 'dart:async';

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
import 'package:zcode_remote/ui/mobile/option_sheet.dart';

import '../test/ui/fake_workspace.dart';

/// Mobile layout frame-rate sampling (M7 measurement: layout switch,
/// scroll, keyboard/panel frame profile). Mirrors
/// streaming_frame_metrics_test.dart (performance-side device gate):
/// scroll flings over an N-row history, then samples the mobile-specific
/// phases — bottom-sheet open/close, single keyboard-inset application
/// (simulated inset: measures the layout relayout pipeline, not the IME
/// animation) and a full-width panel route push/pop.
///
/// Simulator-口径 evidence only; physical-device profile stays 待验.
/// Run (profile, on-device):
///   ZCODE_ANDROID_QA=true flutter test integration_test/mobile_frame_profile_test.dart \
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
      print('MOBILEP $phase frames=0 (no timing callbacks)');
      return;
    }
    int p(List<FrameTiming> list, int Function(FrameTiming) pick) {
      final v = list.map(pick).toList()..sort();
      return v[(v.length * 0.95).floor().clamp(0, v.length - 1)];
    }

    final refresh = SchedulerBinding
        .instance.platformDispatcher.views.first.display.refreshRate;
    // ignore: avoid_print
    print('MOBILEP ${{
      'phase': phase,
      'frames': sample.length,
      'wallMs': sw.elapsedMilliseconds,
      'refreshRate': refresh.toStringAsFixed(1),
      'totalP50us': p(sample, (f) => f.totalSpan.inMicroseconds),
      'totalP95us': p(sample, (f) => f.totalSpan.inMicroseconds),
      'over16ms': sample.where((f) => f.totalSpan.inMicroseconds > 16666).length,
      'over8ms': sample.where((f) => f.totalSpan.inMicroseconds > 8333).length,
    }}');
  }

  testWidgets('device sampling: mobile scroll/sheet/inset/panel phases',
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
    bridge.conversationTransport.states['mobile-frame-profile'] = state;
    final prefs = ClientPreferences();
    addTearDown(prefs.dispose);

    // Simulated keyboard inset toggle: single MediaQuery rebuild, the same
    // one-shot inset application rule the mobile composer follows.
    bool keyboard = false;
    void Function(void Function())? hostSetState;
    final host = StatefulBuilder(builder: (context, setState) {
      hostSetState = setState;
      return MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(viewInsets: EdgeInsets.only(bottom: keyboard ? 280 : 0)),
          child: ChatPage(
            session: bridge,
            scope: const {'workspaceIdentity': 'workspace'},
            workspaceKey: 'workspace',
            sessionId: 'mobile-frame-profile',
            title: 'mobile-frame-profile',
            workspaceName: 'ZcodeRemote',
            deviceId: 'device',
            composerStore: ComposerStore(),
          ));
    });
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs, home: Scaffold(body: host)));
    await tester.pumpAndSettle();

    WidgetsBinding.instance.addTimingsCallback(timings);

    await measure('mobile-scroll', () async {
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

    await measure('keyboard-inset', () async {
      for (var i = 0; i < 4; i++) {
        hostSetState!(() => keyboard = keyboard == false);
        await tester.pumpAndSettle(const Duration(milliseconds: 120));
      }
    });

    await measure('mobile-sheet', () async {
      final context = tester.state(find.byType(Navigator)).context;
      for (var i = 0; i < 3; i++) {
        unawaited(showMobileOptionSheet<String>(
            context: context,
            title: '选择模型',
            options: const [
              MobileSheetOption(value: 'a', label: 'Model A'),
              MobileSheetOption(value: 'b', label: 'Model B'),
            ]));
        await tester.pumpAndSettle(const Duration(milliseconds: 120));
        await tester.tap(find.text('Model A').last);
        await tester.pumpAndSettle(const Duration(milliseconds: 120));
      }
    });

    await measure('panel-route', () async {
      final navigator = Navigator.of(tester.state(find.byType(Navigator)).context);
      for (var i = 0; i < 3; i++) {
        navigator.push(MaterialPageRoute(
            builder: (_) => Scaffold(
                appBar: AppBar(title: const Text('panel')),
                body: const Center(child: Text('full-width panel')))));
        await tester.pumpAndSettle(const Duration(milliseconds: 120));
        navigator.pop();
        await tester.pumpAndSettle(const Duration(milliseconds: 120));
      }
    });

    WidgetsBinding.instance.removeTimingsCallback(timings);
    expect(tester.takeException(), isNull);
  });
}
