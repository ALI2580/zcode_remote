import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:super_sliver_list/super_sliver_list.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/conversation_viewport.dart';
import 'fake_history.dart';
import 'fake_workspace.dart';

void main() {
  testWidgets(
      'a touch drag over selectable message text scrolls the conversation',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge(),
        view = ConversationViewState()
          ..following = false
          ..anchor = '20';
    bridge.conversationTransport.states['task'] = readingState(1, 100);
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
      session: bridge,
      scope: const {},
      workspaceKey: 'work',
      deviceId: 'A',
      sessionId: 'task',
      title: 'Reading',
      embedded: true,
      viewStates: {composerKey('A', 'work', 'task'): view},
    )));
    await tester.pumpAndSettle();
    final list = tester.widget<SuperListView>(find.byType(SuperListView));
    final previous = list.controller!.offset;
    final target = find.text(readingRows(21, 21).single['text']);
    await tester.drag(target, const Offset(0, -120));
    await tester.pumpAndSettle();
    expect(list.controller!.offset, greaterThan(previous + 50));
    expect(view.anchor != '20' || view.anchorOffset.abs() > 10, isTrue);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'chat restores a paged-out reading row at its saved screen offset',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge(),
        view = ConversationViewState()
          ..following = false
          ..anchor = '450'
          ..anchorOffset = -19
          ..logEpoch = 'reading-fixture';
    bridge.conversationTransport.states['task'] = readingState(801, 860);
    bridge.conversationTransport.historyHandler =
        (_, before, __) async => readingPage(before!);
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
      session: bridge,
      scope: const {},
      workspaceKey: 'work',
      deviceId: 'A',
      sessionId: 'task',
      title: 'Reading',
      embedded: true,
      viewStates: {composerKey('A', 'work', 'task'): view},
    )));
    await tester.pumpAndSettle();
    expect(
        bridge.conversationTransport.historyRequests.map((r) => r.beforeRowId),
        [801, 601]);
    expect(view.anchor, '450');
    final list = tester.widget<SuperListView>(find.byType(SuperListView));
    expect(list.listController!.visibleRange!.$1,
        50); // row 450 in 401..860 plus load header
    expect(
        list.listController!.getOffsetToReveal(50, 0) - list.controller!.offset,
        closeTo(-19, 1));
    expect(find.byType(ConversationViewport), findsOneWidget);
    expect(view.following, isFalse);
    expect(bridge.conversationTransport.commands, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'failed reading recovery offers retry and Latest while preserving the editor',
      (tester) async {
    final bridge = FakeBridge(),
        view = ConversationViewState()
          ..following = false
          ..anchor = '450';
    bridge.conversationTransport.states['task'] = readingState(801, 860);
    final gate = Completer<dynamic>();
    bridge.conversationTransport.historyHandler = (_, __, ___) => gate.future;
    final composers = ComposerStore();
    final editor = composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work',
        sessionId: 'task');
    editor.input.text = 'Preserve this draft';
    await tester.pumpWidget(MaterialApp(
        home: ChatPage(
      session: bridge,
      scope: const {},
      workspaceKey: 'work',
      deviceId: 'A',
      sessionId: 'task',
      title: 'Reading',
      embedded: true,
      composerStore: composers,
      viewStates: {composerKey('A', 'work', 'task'): view},
    )));
    await tester.pump();
    await tester.pump();
    expect(find.text('Restoring reading position…'), findsOneWidget);
    gate.completeError(StateError('offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Could not restore'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    await tester.tap(find.text('Latest'));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationViewport), findsOneWidget);
    expect(editor.input.text, 'Preserve this draft');
    expect(view.following, isTrue);
    expect(bridge.conversationTransport.commands, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    composers.dispose();
  });
}
