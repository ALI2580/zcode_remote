import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/ui/conversation_viewport.dart';

/// P2-viewport measurement harness (references/optimization/
/// performance-todolist.md). Deterministic scenarios over
/// ConversationViewport:
///   A: long-history streaming — itemCount grows by 1 per frame (append),
///      each frame reconciles children and runs findChildIndexCallback.
///   B: deep scroll — 20 small drag steps, each triggering post-frame
///      anchor capture.
/// Counters print as P2VIEW lines; wall clock is the secondary metric.
void main() {
  Widget host(ConversationViewState view, List<String> ids) =>
      MaterialApp(
          home: Scaffold(
              body: ConversationViewport(
        view: view,
        ids: ids,
        itemBuilder: (_, i) =>
            SizedBox(height: 40, child: Text('item ${ids[i]}')),
      )));

  Future<void> resetAndPump(
      WidgetTester tester, ConversationViewState view, List<String> ids) async {
    viewportChildIndexProbeCalls = 0;
    viewportChildIndexProbeEntries = 0;
    viewportCaptureScans = 0;
    await tester.pumpWidget(Container());
    await tester.pumpWidget(host(view, ids));
    await tester.pumpAndSettle();
  }

  testWidgets('metric A: streaming appends reconcile children',
      (tester) async {
    for (final n in [1000, 5000, 20000]) {
      final view = ConversationViewState();
      final ids = List<String>.generate(n, (i) => 'r$i');
      await resetAndPump(tester, view, ids);
      final calls0 = viewportChildIndexProbeCalls;
      final entries0 = viewportChildIndexProbeEntries;
      final sw = Stopwatch()..start();
      for (var f = 0; f < 40; f++) {
        ids.add('new$f');
        await tester.pumpWidget(host(view, ids));
        await tester.pump();
      }
      sw.stop();
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('P2VIEW A rows=$n frames=40 '
          'wallUs=${sw.elapsedMicroseconds} '
          'probeCalls=${viewportChildIndexProbeCalls - calls0} '
          'probeEntries=${viewportChildIndexProbeEntries - entries0}');
    }
  });

  testWidgets('metric B: deep-scroll anchor captures', (tester) async {
    for (final n in [1000, 5000, 20000]) {
      final view = ConversationViewState();
      final ids = List<String>.generate(n, (i) => 'r$i');
      await resetAndPump(tester, view, ids);
      // scroll deep: fling repeatedly towards the end of a 40px-per-item list
      for (var i = 0; i < 6; i++) {
        await tester.fling(find.byType(ConversationViewport),
            const Offset(0, -12000), 12000);
        await tester.pumpAndSettle();
      }
      final scans0 = viewportCaptureScans;
      final sw = Stopwatch()..start();
      for (var f = 0; f < 20; f++) {
        await tester.drag(
            find.byType(ConversationViewport), const Offset(0, 60));
        await tester.pump();
        await tester.pumpAndSettle();
      }
      sw.stop();
      // ignore: avoid_print
      print('P2VIEW B rows=$n drags=20 '
          'wallUs=${sw.elapsedMicroseconds} '
          'captureScans=${viewportCaptureScans - scans0}');
    }
  });

  testWidgets('metric C: reconcile while deep-scrolled (following=false)',
      (tester) async {
    for (final n in [1000, 5000, 20000]) {
      final view = ConversationViewState();
      final ids = List<String>.generate(n, (i) => 'r$i');
      await resetAndPump(tester, view, ids);
      for (var i = 0; i < 6; i++) {
        await tester.fling(find.byType(ConversationViewport),
            const Offset(0, -12000), 12000);
        await tester.pumpAndSettle();
      }
      final calls0 = viewportChildIndexProbeCalls;
      final entries0 = viewportChildIndexProbeEntries;
      final idx0 = viewportIndexOfScans;
      final sw = Stopwatch()..start();
      for (var f = 0; f < 40; f++) {
        ids.add('deep$f');
        await tester.pumpWidget(host(view, ids));
        await tester.pump();
      }
      sw.stop();
      await tester.pumpAndSettle();
      // ignore: avoid_print
      print('P2VIEW C rows=$n frames=40 '
          'wallUs=${sw.elapsedMicroseconds} '
          'probeCalls=${viewportChildIndexProbeCalls - calls0} '
          'probeEntries=${viewportChildIndexProbeEntries - entries0} '
          'indexOfScans=${viewportIndexOfScans - idx0}');
    }
  });
}
