import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/conversation_work_rows.dart';

void main() {
  testWidgets('review: the visible inline diff copies all source rows in order',
      (tester) async {
    String? copied;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map)['text'] as String;
      }
      if (call.method == 'Clipboard.getData') return {'text': copied};
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    try {
      await tester.pumpWidget(const ZcodeRemoteApp(
          home: Scaffold(
              body: ToolCallRow(row: {
        'rowId': 501,
        'toolName': 'Edit',
        'status': 'success',
        'input': {
          'file_path': 'lib/review.dart',
          'oldText': 'before\nkeep\n',
          'newText': 'after\nkeep\n'
        }
      }))));
      await tester.tap(find.byKey(const ValueKey('tool-row-501')));
      await tester.pumpAndSettle();
      final visibleDiff = find.byWidgetPredicate((widget) =>
          widget is EditableText &&
          widget.controller.text.contains('-before') &&
          widget.controller.text.contains('+after'));
      expect(visibleDiff, findsOneWidget,
          reason:
              'Observe the actual selectable diff, not hidden per-line finder compatibility text.');
      await tester
          .longPressAt(tester.getTopLeft(visibleDiff) + const Offset(12, 30));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Select all'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(copied, contains('-before\n+after\n keep'));
      expect(copied, isNot(contains('1\n2\n3')));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
