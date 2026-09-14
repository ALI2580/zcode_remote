import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/workspace_file_viewer.dart';
import 'fake_features.dart';
import 'review_capture.dart';

void main() {
  for (final systemScale in [1.0, 1.4]) {
    testWidgets('review: real file wrapped code with system scale $systemScale',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(344, 800);
      addTearDown(tester.view.reset);
      tester.platformDispatcher.textScaleFactorTestValue = systemScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      final prefs = ClientPreferences();
      await prefs.setLanguage('en');
      await prefs.setUiFontSizePx(20);
      await prefs.setCodeFontSize(18);
      await prefs.setWrapLongLines(true);
      await prefs.setShowLineNumbers(true);
      const first =
          'final thisIsOneVeryLongSourceLineWithManyWords = "a long value that wraps multiple times";';
      const source = '$first\nreturn secondLine;';
      final bridge = FeatureBridge();
      final boundary = GlobalKey();
      bridge.channels.handler = (_, method, __) =>
          method == 'readTextFile' ? {'text': source} : <String, dynamic>{};
      try {
        await tester.runAsync(loadReviewCaptureFonts);
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: ZcodeRemoteApp(
                preferences: prefs,
                home: Scaffold(
                    body: WorkspaceFileViewer(
                        transport: bridge.conversation(
                            const {'workspaceIdentity': 'wrap-review'}),
                        path: 'D:/Synthetic/wrap.dart',
                        title: 'wrap.dart')))));
        await tester.pumpAndSettle();
        final editable = find.byWidgetPredicate((widget) =>
            widget is EditableText && widget.controller.text == source);
        expect(editable, findsOneWidget,
            reason:
                'Keep a selectable complete source so copying multiple lines preserves the file.');
        final renderCode =
            tester.state<EditableTextState>(editable).renderEditable;
        final codeY = renderCode
            .localToGlobal(renderCode
                .getLocalRectForCaret(
                    const TextPosition(offset: first.length + 1))
                .topLeft)
            .dy;
        final firstY = renderCode
            .localToGlobal(renderCode
                .getLocalRectForCaret(const TextPosition(offset: 0))
                .topLeft)
            .dy;
        expect(codeY - firstY, greaterThan(54),
            reason: 'The long first source line must actually wrap.');
        expect(renderCode.textScaler.scale(18), closeTo(18 * systemScale, .01),
            reason: 'The saved interface size must not multiply code size.');
        await captureReviewBoundary(tester, boundary,
            'real-file-wrap-344-ui20-code18-system$systemScale');
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        prefs.dispose();
      }
    });
  }
}
