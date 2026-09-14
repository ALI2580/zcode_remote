import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/ui/conversation_work_rows.dart';
import 'package:zcode_remote/ui/theme.dart';

void main() {
  testWidgets(
      'expanded edit row renders path, range diff and foldable raw args',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: const Scaffold(
        body: ToolCallRow(row: {
          'rowId': 501,
          'toolName': 'Edit',
          'status': 'success',
          'input': {
            'file_path': 'lib/example.dart',
            'oldText': 'before\nkeep\n',
            'newText': 'after\nkeep\n',
          },
        }),
      ),
    ));
    await tester.tap(find.byKey(const ValueKey('tool-row-501')));
    await tester.pumpAndSettle();

    expect(find.text('lib/example.dart'), findsNWidgets(2));
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText().contains('-before') == true),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText().contains('+after') == true),
        findsOneWidget);
    expect(find.text('Text range'), findsOneWidget);
    expect(find.textContaining('@@'), findsNothing);
    expect(find.text('Hide raw arguments'), findsOneWidget);
    expect(find.textContaining('"oldText"'), findsOneWidget);

    await tester.tap(find.text('Hide raw arguments'));
    await tester.pumpAndSettle();
    expect(find.text('Show raw arguments'), findsOneWidget);
    expect(find.textContaining('"oldText"'), findsNothing);
    // The visible edit body remains after the raw argument fold.
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText().contains('-before') == true),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
