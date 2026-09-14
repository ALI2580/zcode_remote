import 'review_capture.dart';
import 'dart:ui' show DisplayFeature, DisplayFeatureState, DisplayFeatureType;
import 'package:flutter/material.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/shell/shell_layout.dart';
import 'package:zcode_remote/ui/theme.dart';

class _Editor extends StatefulWidget {
  const _Editor({required this.name, required this.onMount});
  final String name;
  final VoidCallback onMount;
  @override
  State<_Editor> createState() => _EditorState();
}

class _EditorState extends State<_Editor> {
  final controller = TextEditingController();
  @override
  void initState() {
    super.initState();
    widget.onMount();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(children: [
        Text(widget.name),
        TextField(key: ValueKey(widget.name), controller: controller)
      ]);
}

class _ScrollableConversation extends StatefulWidget {
  const _ScrollableConversation();

  @override
  State<_ScrollableConversation> createState() =>
      _ScrollableConversationState();
}

class _ScrollableConversationState extends State<_ScrollableConversation> {
  final controller = ScrollController();

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListView.builder(
      controller: controller,
      itemCount: 80,
      itemBuilder: (context, index) =>
          SizedBox(height: 48, child: Text('消息 $index')));
}

Widget _shellLayout({
  required String title,
  required String project,
  required bool sidebarCollapsed,
  required ValueChanged<bool> onSidebarCollapsed,
  required Widget sidebar,
  required Widget conversation,
  Widget? panel,
  bool panelOpen = false,
  VoidCallback? onClosePanel,
  List<Widget> actions = const [],
  TextScaler textScaler = TextScaler.noScaling,
}) =>
    MediaQuery(
        data: MediaQueryData(textScaler: textScaler),
        child: MaterialApp(
            theme: ZInkTheme.light(),
            home: WorkspaceShellLayout(
                title: title,
                project: project,
                sidebarCollapsed: sidebarCollapsed,
                onSidebarCollapsed: onSidebarCollapsed,
                sidebar: sidebar,
                conversation: conversation,
                panel: panel,
                panelOpen: panelOpen,
                onClosePanel: onClosePanel,
                actions: actions)));

void main() {
  setUpAll(loadReviewCaptureFonts);
  testWidgets(
      'five form factors preserve both editors and restore sidebar preference',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var panel = false, collapsed = false;
    var mainMounts = 0, sideMounts = 0;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return WorkspaceShellLayout(
              title: '任务标题',
              project: 'ZcodeRemote',
              sidebarCollapsed: collapsed,
              onSidebarCollapsed: (v) => setState(() => collapsed = v),
              sidebar: const Text('sidebar-content'),
              conversation: _Editor(name: 'main', onMount: () => mainMounts++),
              panel: _Editor(name: 'side', onMount: () => sideMounts++),
              panelOpen: panel,
              onClosePanel: () => setState(() => panel = false));
        })));
    for (final width in [390.0, 344.0, 720.0, 834.0, 1180.0]) {
      tester.view.physicalSize = Size(width, 820);
      update(() => panel = false);
      await tester.pumpAndSettle();
      expect(find.text('sidebar-content'),
          width >= 640 ? findsOneWidget : findsNothing);
      await tester.enterText(find.byKey(const ValueKey('main')), '主草稿 $width');
      update(() => panel = true);
      await tester.pumpAndSettle();
      expect(find.text('sidebar-content'),
          width >= 1000 ? findsOneWidget : findsNothing);
      await tester.enterText(find.byKey(const ValueKey('side')), '辅助草稿 $width');
      expect(find.text('主草稿 $width'), findsOneWidget);
      update(() => panel = false);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(mainMounts, 1);
    expect(sideMounts, 1);
    update(() => collapsed = true);
    await tester.pumpAndSettle();
    update(() => panel = true);
    await tester.pumpAndSettle();
    update(() => panel = false);
    await tester.pumpAndSettle();
    expect(find.text('sidebar-content'), findsNothing);
  });

  testWidgets(
      'overlay removes main composer from accessibility and keyboard focus',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(344, 740);
    addTearDown(tester.view.reset);
    final mainFocus = FocusNode();
    addTearDown(mainFocus.dispose);
    await tester.pumpWidget(MaterialApp(
        home: WorkspaceShellLayout(
            title: '标题',
            project: '项目',
            sidebar: const Text('导航'),
            sidebarCollapsed: false,
            onSidebarCollapsed: (_) {},
            conversation: TextField(focusNode: mainFocus),
            panel: const Text('工作面板'))));
    await tester.pumpAndSettle();
    mainFocus.requestFocus();
    await tester.pump();
    expect(mainFocus.hasFocus, isFalse);
    final exclusion = tester.widget<ExcludeSemantics>(find
        .ancestor(
            of: find.byType(TextField), matching: find.byType(ExcludeSemantics))
        .first);
    expect(exclusion.excluding, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('fold hinge is avoided with sidebar expanded and collapsed',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(740, 820);
    addTearDown(tester.view.reset);
    for (final collapsed in [false, true]) {
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data:
                  const MediaQueryData(size: Size(740, 820), displayFeatures: [
                DisplayFeature(
                    bounds: Rect.fromLTWH(354, 0, 20, 820),
                    type: DisplayFeatureType.hinge,
                    state: DisplayFeatureState.postureFlat)
              ]),
              child: WorkspaceShellLayout(
                  title: 'Fold',
                  project: 'Project',
                  sidebar: const Text('sidebar'),
                  sidebarCollapsed: collapsed,
                  onSidebarCollapsed: (_) {},
                  conversation:
                      const SizedBox.expand(key: ValueKey('chat'))))));
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(const ValueKey('chat'))).dx, 374);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'Git chip and panel button visible across widths and 140 percent scale',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final scaleValue in [1.0, 1.4]) {
      for (final width in [344.0, 390.0, 720.0, 834.0, 1180.0]) {
        tester.view.physicalSize = Size(width, 820);
        await tester.pumpWidget(_shellLayout(
            title: 'T',
            project: 'P',
            sidebarCollapsed: false,
            onSidebarCollapsed: (_) {},
            sidebar: const SizedBox.shrink(),
            conversation: const SizedBox.expand(),
            textScaler: TextScaler.linear(scaleValue),
            actions: const [
              SizedBox(key: ValueKey('git-chip'), width: 8, height: 8),
            ]));
        await tester.pumpAndSettle();
        expect(
            find.byKey(const ValueKey('official-task-header')), findsOneWidget,
            reason: 'scale=$scaleValue width=$width header exists');
        expect(find.byKey(const ValueKey('git-chip')), findsOneWidget,
            reason: 'scale=$scaleValue width=$width git chip visible');
      }
    }
  });

  testWidgets('fold hinge keeps the conversation edge clear during reversal',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(820, 820);
    addTearDown(tester.view.reset);
    var collapsed = false;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
            data: const MediaQueryData(size: Size(820, 820), displayFeatures: [
              DisplayFeature(
                  bounds: Rect.fromLTWH(420, 0, 24, 820),
                  type: DisplayFeatureType.hinge,
                  state: DisplayFeatureState.postureFlat)
            ]),
            child: StatefulBuilder(builder: (context, setState) {
              update = setState;
              return WorkspaceShellLayout(
                  title: 'Fold',
                  project: 'Project',
                  sidebar: const SizedBox(width: 420),
                  sidebarCollapsed: collapsed,
                  onSidebarCollapsed: (value) =>
                      setState(() => collapsed = value),
                  conversation:
                      const SizedBox.expand(key: ValueKey('fold-chat')));
            }))));
    await tester.pumpAndSettle();
    final expandedLeft =
        tester.getTopLeft(find.byKey(const ValueKey('fold-chat'))).dx;
    expect(expandedLeft, closeTo(444, 0.1));
    update(() => collapsed = true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final collapsedMidLeft =
        tester.getTopLeft(find.byKey(const ValueKey('fold-chat'))).dx;
    final collapsedMidWidth = tester
        .getRect(find.byKey(const ValueKey('workspace-sidebar-clip')))
        .width;
    expect(collapsedMidWidth, greaterThan(0));
    expect(collapsedMidWidth, lessThan(420));
    expect(collapsedMidLeft, closeTo(expandedLeft, 0.1));
    update(() => collapsed = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 90));
    final expandedMidLeft =
        tester.getTopLeft(find.byKey(const ValueKey('fold-chat'))).dx;
    expect(expandedMidLeft, closeTo(expandedLeft, 0.1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('keyboard insets keep main and panel composers visible',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const cases = [
      (344.0, false),
      (720.0, false),
      (834.0, true),
      (1180.0, true),
    ];
    for (final (width, panelOpen) in cases) {
      tester.view.physicalSize = Size(width, 820);
      await tester.pumpWidget(_shellLayout(
          title: '键盘矩阵',
          project: 'B1.4',
          sidebarCollapsed: false,
          onSidebarCollapsed: (_) {},
          sidebar: const SizedBox.shrink(),
          conversation: const Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                  key: ValueKey('composer-keyboard'), width: 160, height: 48)),
          panel: const Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                  key: ValueKey('panel-composer-keyboard'),
                  width: 160,
                  height: 48)),
          panelOpen: panelOpen,
          textScaler: const TextScaler.linear(1.4)));
      // Wrap once with the keyboard inset after the shell exists.
      await tester.pumpWidget(MediaQuery(
          data: const MediaQueryData(
              textScaler: TextScaler.linear(1.4),
              viewInsets: EdgeInsets.only(bottom: 220)),
          child: MaterialApp(
              theme: ZInkTheme.light(),
              home: WorkspaceShellLayout(
                  title: '键盘矩阵',
                  project: 'B1.4',
                  sidebarCollapsed: false,
                  onSidebarCollapsed: (_) {},
                  sidebar: const SizedBox.shrink(),
                  conversation: const Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                          key: ValueKey('composer-keyboard'),
                          width: 160,
                          height: 48)),
                  panel: const Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                          key: ValueKey('panel-composer-keyboard'),
                          width: 160,
                          height: 48)),
                  panelOpen: panelOpen,
                  onClosePanel: () {}))));
      await tester.pumpAndSettle();
      final composer =
          tester.getRect(find.byKey(const ValueKey('composer-keyboard')));
      expect(composer.bottom, lessThanOrEqualTo(820 - 220),
          reason: 'width=$width panelOpen=$panelOpen main composer hidden');
      if (panelOpen) {
        final panel = tester
            .getRect(find.byKey(const ValueKey('panel-composer-keyboard')));
        expect(panel.bottom, lessThanOrEqualTo(820 - 220),
            reason: 'width=$width side composer hidden');
      }
      expect(tester.takeException(), isNull,
          reason: 'width=$width panelOpen=$panelOpen');
    }
  });

  testWidgets('persistent sidebar survives panel open at 1180, drawer at 500',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(1180, 820);
    await tester.pumpWidget(_shellLayout(
        title: 'T',
        project: 'P',
        sidebarCollapsed: false,
        onSidebarCollapsed: (_) {},
        sidebar: const Text('sidebar-content'),
        conversation: const SizedBox.expand(),
        panel: const Text('panel'),
        panelOpen: true));
    await tester.pumpAndSettle();
    expect(find.text('sidebar-content'), findsOneWidget,
        reason: '1180px panel open: sidebar persists');
    expect(find.text('panel'), findsOneWidget);
    tester.view.physicalSize = const Size(500, 820);
    await tester.pumpWidget(_shellLayout(
        title: 'T',
        project: 'P',
        sidebarCollapsed: false,
        onSidebarCollapsed: (_) {},
        sidebar: const Text('sidebar-content'),
        conversation: const SizedBox.expand()));
    await tester.pumpAndSettle();
    expect(find.text('sidebar-content'), findsNothing,
        reason: '500px: sidebar not shown persistently (drawer closed)');
  });

  testWidgets(
      'panel is overlay at 344 (main loses focus) and persistent at 1180',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    tester.view.physicalSize = const Size(344, 820);
    final narrowFocus = FocusNode();
    addTearDown(narrowFocus.dispose);
    await tester.pumpWidget(_shellLayout(
        title: 'T',
        project: 'P',
        sidebarCollapsed: false,
        onSidebarCollapsed: (_) {},
        sidebar: const SizedBox.shrink(),
        conversation: TextField(focusNode: narrowFocus),
        panel: const Text('panel'),
        panelOpen: true));
    await tester.pumpAndSettle();
    narrowFocus.requestFocus();
    await tester.pump();
    expect(narrowFocus.hasFocus, isFalse,
        reason: '344px: overlay panel blocks main focus');
    tester.view.physicalSize = const Size(1180, 820);
    final wideFocus = FocusNode();
    addTearDown(wideFocus.dispose);
    await tester.pumpWidget(_shellLayout(
        title: 'T',
        project: 'P',
        sidebarCollapsed: false,
        onSidebarCollapsed: (_) {},
        sidebar: const Text('side'),
        conversation: TextField(focusNode: wideFocus),
        panel: const Text('panel'),
        panelOpen: true));
    await tester.pumpAndSettle();
    wideFocus.requestFocus();
    await tester.pump();
    expect(wideFocus.hasFocus, isTrue,
        reason: '1180px: persistent panel allows main focus');
  });

  testWidgets(
      'panel open/close preserves main and side editor text across cycles',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var panel = false;
    var mainMounts = 0, sideMounts = 0;
    late StateSetter update;
    tester.view.physicalSize = const Size(834, 820);
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return WorkspaceShellLayout(
              title: 'T',
              project: 'P',
              sidebarCollapsed: false,
              onSidebarCollapsed: (_) {},
              sidebar: const SizedBox.shrink(),
              conversation: _Editor(name: 'main', onMount: () => mainMounts++),
              panel: _Editor(name: 'side', onMount: () => sideMounts++),
              panelOpen: panel,
              onClosePanel: () => setState(() => panel = false));
        })));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('main')), '主草稿');
    update(() => panel = true);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('side')), '辅草稿');
    expect(find.text('主草稿'), findsOneWidget,
        reason: 'main draft preserved when panel opens');
    update(() => panel = false);
    await tester.pumpAndSettle();
    expect(find.text('主草稿'), findsOneWidget,
        reason: 'main draft preserved after panel closes');
    update(() => panel = true);
    await tester.pumpAndSettle();
    expect(find.text('辅草稿'), findsOneWidget,
        reason: 'side draft preserved after reopen');
    expect(find.text('主草稿'), findsOneWidget);
    expect(mainMounts, 1, reason: 'main editor not remounted');
    expect(sideMounts, 1, reason: 'side editor not remounted');
  });

  testWidgets(
      'sidebar collapse and expand survives panel open/close cycle at 1180',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var collapsed = false, panel = false;
    late StateSetter update;
    tester.view.physicalSize = const Size(1180, 820);
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return WorkspaceShellLayout(
              title: 'T',
              project: 'P',
              sidebar: const Text('sidebar-content'),
              sidebarCollapsed: collapsed,
              onSidebarCollapsed: (v) => setState(() => collapsed = v),
              conversation: const SizedBox.expand(),
              panel: const Text('panel'),
              panelOpen: panel,
              onClosePanel: () => setState(() => panel = false));
        })));
    await tester.pumpAndSettle();
    expect(find.text('sidebar-content'), findsOneWidget);
    update(() => collapsed = true);
    await tester.pumpAndSettle();
    expect(find.text('sidebar-content'), findsNothing);
    update(() => panel = true);
    await tester.pumpAndSettle();
    expect(find.text('sidebar-content'), findsNothing);
    update(() {
      panel = false;
      collapsed = false;
    });
    await tester.pumpAndSettle();
    expect(find.text('sidebar-content'), findsOneWidget,
        reason: 'sidebar restored after panel cycle');
  });

  testWidgets(
      'sidebar width and main conversation move continuously and reverse quickly',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    var collapsed = false;
    late StateSetter update;
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: MaterialApp(
            theme: ZInkTheme.light(),
            home: StatefulBuilder(builder: (context, setState) {
              update = setState;
              return WorkspaceShellLayout(
                  title: '动画',
                  project: 'P',
                  sidebar: const SizedBox(
                      key: ValueKey('sidebar-content'),
                      width: 264,
                      child: Text('侧栏')),
                  sidebarCollapsed: collapsed,
                  onSidebarCollapsed: (value) =>
                      setState(() => collapsed = value),
                  conversation: const SizedBox.expand());
            }))));
    await tester.pumpAndSettle();
    final full =
        tester.getRect(find.byKey(const ValueKey('workspace-sidebar-clip')));
    expect(full.width, closeTo(264, 0.1));
    expect(tester.getRect(find.byKey(const ValueKey('workspace-main'))).left,
        closeTo(full.width, 0.1));

    update(() => collapsed = true);
    await tester.pump();
    for (var frame = 0; frame < 5; frame++) {
      await tester.pump(const Duration(milliseconds: 30));
      await captureReviewBoundary(tester, boundary, 'u03-sidebar-frame-$frame');
    }
    final midpoint =
        tester.getRect(find.byKey(const ValueKey('workspace-sidebar-clip')));
    expect(midpoint.width, greaterThan(0));
    expect(midpoint.width, lessThan(full.width));
    expect(tester.getRect(find.byKey(const ValueKey('workspace-main'))).left,
        closeTo(midpoint.width, 0.1));

    // A reverse before the first transition completes starts from the current
    // frame instead of jumping through a second full-width layout.
    update(() => collapsed = false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final reverseMidpoint =
        tester.getRect(find.byKey(const ValueKey('workspace-sidebar-clip')));
    expect(reverseMidpoint.width, greaterThan(midpoint.width));
    expect(reverseMidpoint.width, lessThan(full.width));
    await tester.pumpAndSettle();
    expect(
        tester
            .getRect(find.byKey(const ValueKey('workspace-sidebar-clip')))
            .width,
        closeTo(full.width, 0.1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar collapse honors disableAnimations and keeps subtree',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    var collapsed = false;
    var disableAnimations = true;
    late StateSetter update;
    final conversation = _Editor(name: 'conversation', onMount: () {});
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return MediaQuery(
              data: MediaQuery.of(context)
                  .copyWith(disableAnimations: disableAnimations),
              child: WorkspaceShellLayout(
                  title: '动画',
                  project: 'P',
                  sidebar: const SizedBox(width: 264, child: Text('侧栏')),
                  sidebarCollapsed: collapsed,
                  onSidebarCollapsed: (value) =>
                      setState(() => collapsed = value),
                  conversation: conversation));
        })));
    await tester.pumpAndSettle();
    final before = tester.state(find.byType(_Editor));
    update(() => collapsed = true);
    await tester.pump();
    expect(
        tester
            .getRect(find.byKey(const ValueKey('workspace-sidebar-clip')))
            .width,
        0);
    expect(tester.state(find.byType(_Editor)), same(before),
        reason: 'conversation state survives reduced-motion collapse');
    expect(tester.takeException(), isNull);
  });

  testWidgets('sidebar animation preserves conversation identity and scroll',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    var collapsed = false;
    late StateSetter update;
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return WorkspaceShellLayout(
              title: '阅读位置',
              project: 'P',
              sidebar: const SizedBox(width: 264),
              sidebarCollapsed: collapsed,
              onSidebarCollapsed: (value) => setState(() => collapsed = value),
              conversation: const _ScrollableConversation());
        })));
    await tester.pumpAndSettle();
    final state = tester.state<_ScrollableConversationState>(
        find.byType(_ScrollableConversation));
    state.controller.jumpTo(420);
    await tester.pump();
    update(() => collapsed = true);
    await tester.pump(const Duration(milliseconds: 90));
    expect(
        tester.state<_ScrollableConversationState>(
            find.byType(_ScrollableConversation)),
        same(state));
    expect(state.controller.offset, closeTo(420, 0.1));
    await tester.pumpAndSettle();
    expect(state.controller.offset, closeTo(420, 0.1));
    expect(tester.takeException(), isNull);
  });

testWidgets('header actions anchor to the right edge of the task header',
    (tester) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1180, 820);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_shellLayout(
      title: '任务标题',
      project: 'ZcodeRemote',
      sidebarCollapsed: false,
      onSidebarCollapsed: (_) {},
      sidebar: const SizedBox.shrink(),
      conversation: const _ScrollableConversation(),
      actions: const [
        SizedBox(key: ValueKey('header-action-a'), width: 24, height: 24),
        SizedBox(key: ValueKey('header-action-b'), width: 24, height: 24),
      ]));
  await tester.pumpAndSettle();
  final header = tester.getRect(find.byKey(const ValueKey('official-task-header')));
  final last = tester.getRect(find.byKey(const ValueKey('header-action-b')));
  // Header horizontal padding is 4; the trailing action must sit against it.
  expect(header.right - 4 - last.right, lessThan(2.0));
  // The title region still fills the space between the toggle and actions.
  final title = tester.getRect(find.text('任务标题'));
  expect(title.left, greaterThan(header.left));
  expect(last.left - title.right,
      greaterThan(0)); // no overlap between title and actions
});
}
