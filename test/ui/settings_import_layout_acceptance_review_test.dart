import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/settings_import.dart';
import 'package:zcode_remote/ui/settings_import_dialog.dart';

import 'review_capture.dart';

class _Sync implements SettingsSyncService {
  @override
  Future<Object?> detect(
          {String? workspacePath,
          String? workspaceIdentity,
          required List<String> categories,
          required String intent}) async =>
      {
        'agents': [
          {
            'agent': 'codexCli',
            'name': 'Codex CLI',
            'categories': [
              {
                'category': 'skills',
                'sourceRoots': [
                  {
                    'scope': 'global',
                    'path': 'C:/Synthetic/skills',
                    'importableCount': 1,
                    'skills': [
                      {
                        'name': 'review-long-skill',
                        'path': 'C:/Synthetic/skills/review',
                        'importable': true
                      }
                    ]
                  }
                ]
              }
            ]
          }
        ]
      };
  @override
  Future<Object?> importSelected(
          {String? workspacePath,
          String? workspaceIdentity,
          required List<Map<String, dynamic>> selections}) async =>
      throw StateError(
          'Synthetic import failed; keep the selected resource for retry.');
}

void main() {
  testWidgets(
      'review: import failure and scope controls fit 344px at 140 percent',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(344, 760);
    addTearDown(tester.view.reset);
    final controller = ExternalAgentImportController(
        service: _Sync(),
        category: 'skills',
        workspacePath: 'D:/Synthetic',
        workspaceIdentity: 'review');
    final boundary = GlobalKey();
    try {
      await tester.runAsync(loadReviewCaptureFonts);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
              data: const MediaQueryData(
                  size: Size(344, 760), textScaler: TextScaler.linear(1.4)),
              child: RepaintBoundary(
                  key: boundary,
                  child: SettingsImportDialog(controller: controller)))));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Codex CLI'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('review-long-skill'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('import-submit')));
      await tester.pumpAndSettle();
      await captureReviewBoundary(
          tester, boundary, 'u16-import-error-344-en-140');
      expect(controller.selectedCount, 1);
      expect(controller.error, isNotNull);
      expect(find.textContaining('Synthetic import failed'), findsOneWidget);
      expect(find.byKey(const ValueKey('import-submit')), findsOneWidget);
      expect(tester.takeException(), isNull,
          reason: 'Source, target, import mode and retry must fit the phone.');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      controller.dispose();
    }
  });
}
