import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/code_renderer.dart';

import 'fake_workspace.dart';
import 'review_capture.dart';

void main() {
  setUpAll(loadReviewCaptureFonts);
  testWidgets(
      'review: real ChatPage tool dispatch renders colored inline edits',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final preferences = ClientPreferences();
    final composers = ComposerStore();
    final bridge = FakeBridge();
    final state = ConversationState();
    state.applyFrame({
      'toSeq': 1,
      'payload': {
        'kind': 'snapshot',
        'snapshot': {
          ...composerSnapshotFixture,
          'rows': {
            'totalCount': 3,
            'firstRowId': 1,
            'window': [
              {'kind': 'userInput', 'rowId': 1, 'text': 'Review the edit.'},
              {
                'kind': 'toolCall',
                'rowId': 2,
                'toolName': 'Edit',
                'status': 'success',
                'input': {
                  'file_path': 'lib/counter.dart',
                  'old_string': 'const count = 1;\nkeep();\n',
                  'new_string': 'const count = 2;\nkeep();\n'
                }
              },
              {
                'kind': 'assistantText',
                'rowId': 3,
                'state': 'complete',
                'text': 'The edit is ready.'
              },
            ]
          },
        }
      },
    }, onGap: () => fail('unexpected gap'));
    bridge.conversationTransport.states['tool-review'] = state;
    final boundary = GlobalKey();
    try {
      for (final scenario in [(390.0, 'zh', 1.0), (1180.0, 'en', 1.4)]) {
        tester.view.physicalSize = Size(scenario.$1, 820);
        await preferences.setLanguage(scenario.$2);
        await preferences.setTextScale(scenario.$3);
        await preferences
            .setTheme(scenario.$2 == 'zh' ? ThemeMode.light : ThemeMode.dark);
        await tester.pumpWidget(RepaintBoundary(
            key: boundary,
            child: ZcodeRemoteApp(
              preferences: preferences,
              home: ChatPage(
                  session: bridge,
                  scope: const {'workspaceIdentity': 'workspace'},
                  workspaceKey: 'workspace',
                  sessionId: 'tool-review',
                  title: 'Inline diff review',
                  deviceId: 'tool-device',
                  composerStore: composers),
            )));
        await tester.pumpAndSettle();
        if (find.byType(CodeDiffViewer).evaluate().isEmpty) {
          if (find.byKey(const ValueKey('tool-row-2')).evaluate().isEmpty) {
            await tester.tap(find.text(turnWorkLabel(state: 'completed')));
            await tester.pumpAndSettle();
          }
          await tester.tap(find.byKey(const ValueKey('tool-row-2')));
          await tester.pumpAndSettle();
        }
        final diff = find.byType(CodeDiffViewer);
        expect(diff, findsOneWidget);
        final selected = tester.widget<SelectableText>(
            find.descendant(of: diff, matching: find.byType(SelectableText)));
        final source = selected.textSpan!.toPlainText();
        expect(source, contains('-const count = 1;\n+const count = 2;'));
        expect(source, contains(' keep();'));
        expect(source, isNot(contains('@@ -')));
        final theme = tester.widget<CodeDiffViewer>(diff).theme;
        final spans = <TextSpan>[];
        selected.textSpan!.visitChildren((span) {
          if (span is TextSpan) spans.add(span);
          return true;
        });
        final removed = spans.singleWhere(
            (span) => span.text?.startsWith('-const count = 1;') == true);
        final added = spans.singleWhere(
            (span) => span.text?.startsWith('+const count = 2;') == true);
        expect(removed.style?.color, theme.colorFor('markup.deleted'));
        expect(removed.style?.backgroundColor, theme.removedBackground);
        expect(added.style?.color, theme.colorFor('markup.inserted'));
        expect(added.style?.backgroundColor, theme.insertedBackground);
        await tester.ensureVisible(diff);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await captureReviewBoundary(tester, boundary,
            'tool-inline-${scenario.$1.toInt()}-${scenario.$2}');
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      composers.dispose();
      preferences.dispose();
    }
  });
}
