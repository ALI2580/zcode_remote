import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/workspace_file_viewer.dart';

import 'fake_features.dart';

void main() {
  testWidgets('review: a real file preview follows the saved code font size',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final preferences = ClientPreferences();
    await preferences.setCodeFontSize(18);
    final bridge = FeatureBridge();
    const code = 'const reviewFontSize = 18;';
    bridge.channels.handler = (channel, method, args) {
      if (method == 'readTextFile') return {'text': code};
      return <String, dynamic>{};
    };
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: Scaffold(
            body: WorkspaceFileViewer(
          transport:
              bridge.conversation(const {'workspaceIdentity': 'font-review'}),
          path: 'D:/Synthetic/review.dart',
          title: 'review.dart',
        )),
      ));
      await tester.pumpAndSettle();
      final codeStyles = <TextStyle>[
        for (final text
            in tester.widgetList<EditableText>(find.byType(EditableText)))
          if (text.controller.text.contains(code)) text.style,
        for (final text in tester.widgetList<RichText>(find.byType(RichText)))
          if (text.text.toPlainText().contains(code) && text.text.style != null)
            text.text.style!,
      ];
      expect(codeStyles, isNotEmpty,
          reason: 'The actual file must be rendered.');
      expect(codeStyles.any((style) => style.fontSize == 18), isTrue,
          reason:
              'The saved 18px code preference must affect file content, not just settings preview.');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      preferences.dispose();
    }
  });
}
