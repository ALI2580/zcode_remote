import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/ui/conversation_viewport.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/shell/shell_layout.dart';
import 'fake_workspace.dart';

void main() {
  testWidgets('cold restoration finds an unbuilt variable-height message by ID',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.reset);
    final view = ConversationViewState()
      ..following = false
      ..pixels = 0
      ..anchor = 'row-765'
      ..anchorOffset = -27;
    final built = <int>{};
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
      body: ConversationViewport(
        view: view,
        ids: [for (var i = 0; i < 1000; i++) 'row-$i'],
        itemBuilder: (context, i) {
          built.add(i);
          return SizedBox(
              key: ValueKey('row-$i'),
              height: i.isEven ? 47 : 213,
              child: Text('Message $i'));
        },
      ),
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('row-765')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const ValueKey('row-765'))).dy,
        closeTo(-27, 1));
    expect(built.length, lessThan(100),
        reason: 'Do not render the entire history');
    expect(view.following, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'streaming, pagination and folding keep the reading anchor until Latest is tapped',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(720, 800);
    addTearDown(tester.view.reset);
    final view = ConversationViewState();
    var ids = [for (var i = 0; i < 45; i++) 'row-$i'];
    late StateSetter change;
    await tester.pumpWidget(
        MaterialApp(home: StatefulBuilder(builder: (context, setState) {
      change = setState;
      return Scaffold(
          body: ConversationViewport(
              view: view,
              ids: ids,
              itemBuilder: (context, i) => Padding(
                  key: ValueKey(ids[i]),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(
                      '${ids[i]} ${List.filled(12, 'A message that wraps when the device folds.').join(' ')}'))));
    })));
    await tester.pumpAndSettle();
    final scrollable = tester.state<ScrollableState>(find.byType(Scrollable));
    expect(scrollable.position.extentAfter, lessThan(1));
    await tester.drag(find.byType(Scrollable), const Offset(0, 470));
    await tester.pumpAndSettle();
    expect(view.following, isFalse);
    final anchor = view.anchor!;
    final offset = tester.getTopLeft(find.byKey(ValueKey(anchor))).dy;
    change(() => ids = [...ids, 'row-new']);
    await tester.pumpAndSettle();
    expect(
        tester.getTopLeft(find.byKey(ValueKey(anchor))).dy, closeTo(offset, 1));
    tester.view.physicalSize = const Size(344, 800);
    await tester.pumpAndSettle();
    expect(
        tester.getTopLeft(find.byKey(ValueKey(anchor))).dy, closeTo(offset, 1));
    change(() => ids = ['row-older', ...ids]);
    await tester.pumpAndSettle();
    expect(
        tester.getTopLeft(find.byKey(ValueKey(anchor))).dy, closeTo(offset, 1));
    expect(view.following, isFalse);
    await tester.tap(find.text('Latest'));
    await tester.pumpAndSettle();
    expect(view.following, isTrue);
    expect(scrollable.position.extentAfter, lessThan(1));
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'cold restoration survives a different width and 140 percent text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 800);
    addTearDown(tester.view.reset);
    var large = false;
    Widget render(ConversationViewState view) => MaterialApp(
          builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(textScaler: TextScaler.linear(large ? 1.4 : 1)),
              child: child!),
          home: Scaffold(
              body: ConversationViewport(
            view: view,
            ids: [for (var i = 0; i < 500; i++) 'item-$i'],
            itemBuilder: (context, i) => Padding(
                key: ValueKey('item-$i'),
                padding: const EdgeInsets.all(8),
                child: Text(
                    List.filled(i % 7 + 1,
                            'A paragraph whose height changes with both width and font size.')
                        .join(' '),
                    style: const TextStyle(fontSize: 14, height: 1.4))),
          )),
        );
    final first = ConversationViewState()
      ..following = false
      ..anchor = 'item-325'
      ..anchorOffset = -30;
    await tester.pumpWidget(render(first));
    await tester.pumpAndSettle();
    final saved = first.toJson();
    final height =
        tester.getSize(find.byKey(const ValueKey('item-325'))).height;
    expect(tester.getTopLeft(find.byKey(const ValueKey('item-325'))).dy,
        closeTo(-30, 1));
    await tester.pumpWidget(const SizedBox.shrink());
    large = true;
    tester.view.physicalSize = const Size(720, 900);
    final restored = ConversationViewState.fromJson(saved);
    await tester.pumpWidget(render(restored));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byKey(const ValueKey('item-325'))).height,
        isNot(closeTo(height, 1)));
    expect(tester.getTopLeft(find.byKey(const ValueKey('item-325'))).dy,
        closeTo(-30, 1));
    expect(restored.following, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('embedded composer applies keyboard inset once', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge();
    await tester.pumpWidget(MaterialApp(
        home: WorkspaceShellLayout(
            title: 'Task',
            project: 'Project',
            sidebar: const Text('Sidebar'),
            sidebarCollapsed: false,
            onSidebarCollapsed: (_) {},
            conversation: ChatPage(
                session: bridge,
                scope: const {},
                workspaceKey: 'workspace',
                sessionId: 'task',
                title: 'Task',
                embedded: true))));
    await tester.pumpAndSettle();
    final original = tester.getBottomLeft(find.byType(TextField)).dy;
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getBottomLeft(find.byType(TextField)).dy,
        closeTo(original - 300, 1));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
