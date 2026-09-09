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

void main() {
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
}
