import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/mobile/option_sheet.dart';
import 'package:zcode_remote/ui/mobile/touch_target.dart';
import 'package:zcode_remote/ui/theme.dart';

/// Semantics-tree harness for the mobile components. The human TalkBack
/// pass needs a real device with a screen reader (currently unavailable on
/// both reachable devices); these checks pin down what a screen reader will
/// consume — labels/tooltips, button/selected flags, tap actions and tree
/// traversal order — so the human pass only has to judge focus feel.
///
/// Note: in widget tests SemanticsNode.rect carries no ancestor transform
/// (every node reports its local rect from 0,0), so traversal-order checks
/// must use tree order, not screen coordinates.
List<SemanticsNode> _walk(WidgetTester tester) {
  // ignore: deprecated_member_use
  final owner = tester.binding.pipelineOwner.semanticsOwner;
  final root = owner?.rootSemanticsNode;
  final nodes = <SemanticsNode>[];
  bool visit(SemanticsNode node) {
    nodes.add(node);
    node.visitChildren(visit);
    return true;
  }

    expect(root, isNotNull, reason: 'semantics tree must be enabled');
  visit(root!);
  return nodes;
}

String _text(SemanticsNode n) {
  final data = n.getSemanticsData();
  return '${data.label}\n${data.tooltip}';
}

SemanticsNode _nodeByText(List<SemanticsNode> nodes, String text) {
  final matches = nodes.where((n) => _text(n).contains(text)).toList();
  expect(matches, isNotEmpty, reason: 'no semantics node carrying "$text"');
  // The innermost merged node carries the interactive actions; outer
  // containers (Tooltip wrappers) duplicate the text without actions.
  final interactive = matches
      .where((n) => n.getSemanticsData().actions != 0)
      .toList();
  return interactive.isEmpty ? matches.last : interactive.last;
}

void main() {
  testWidgets('MobileIconButton exposes tooltip, button flag, tap and box',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: Scaffold(
            body: Center(
                child: MobileIconButton(
                    icon: 'terminal', label: '终端', onPressed: () {})))));
    await tester.pumpAndSettle();

    final node = _nodeByText(_walk(tester), '终端');
    final data = node.getSemanticsData();
    expect(data.tooltip, contains('终端'));
    expect(data.actions & SemanticsAction.tap.index, isNonZero);
    expect(data.flagsCollection.isButton, isTrue);
    final rect = node.rect;
    expect(rect.width, greaterThanOrEqualTo(48));
    expect(rect.height, greaterThanOrEqualTo(48));
    handle.dispose();
  });

  testWidgets('option sheet rows carry button/selected semantics in order',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final handle = tester.ensureSemantics();
    const options = [
      MobileSheetOption(value: 'glm', label: 'GLM-5.3', subtitle: 'default'),
      MobileSheetOption(value: 'air', label: 'GLM-Air', selected: true),
      MobileSheetOption(value: 'off', label: '离线语音', enabled: false),
    ];
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        home: Scaffold(
            body: Builder(
                builder: (context) => Center(
                    child: TextButton(
                        onPressed: () => showMobileOptionSheet<String>(
                            context: context,
                            title: '选择模型',
                            options: options),
                        child: const Text('open')))))));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final nodes = _walk(tester);
    final title = _nodeByText(nodes, '选择模型');
    final glm = _nodeByText(nodes, 'GLM-5.3');
    final air = _nodeByText(nodes, 'GLM-Air');
    final off = _nodeByText(nodes, '离线语音');

    // TalkBack walks the tree depth-first: title precedes the rows and the
    // rows keep their list order.
    expect(nodes.indexOf(title), lessThan(nodes.indexOf(glm)));
    expect(nodes.indexOf(glm), lessThan(nodes.indexOf(air)));

    // Enabled rows announce as tappable buttons; the selected row carries
    // the selection flag.
    for (final node in [glm, air]) {
      final data = node.getSemanticsData();
      expect(data.actions & SemanticsAction.tap.index, isNonZero);
      expect(data.flagsCollection.isButton, isTrue);
    }
    expect(air.getSemanticsData().flagsCollection.isSelected,
        Tristate.isTrue);
    expect(off.getSemanticsData().actions & SemanticsAction.tap.index, 0,
        reason: 'disabled option must not advertise a tap action');
    handle.dispose();
  });
}
