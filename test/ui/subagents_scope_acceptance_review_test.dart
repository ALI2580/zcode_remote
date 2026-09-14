import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/remote_agent_catalogs.dart';
import 'package:zcode_remote/ui/subagents_settings.dart';

import 'fake_features.dart';
import 'review_capture.dart';

void main() {
  testWidgets('review: built-in controls fit a narrow large-text settings pane',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(344, 760);
    addTearDown(tester.view.reset);
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) => {
          'agents': [
            {
              'id': 'general-purpose',
              'name': 'general-purpose',
              'scope': 'built-in',
              'source': 'built-in',
              'modelOverride': 'provider/model',
              'thoughtLevelOverride': 'high'
            }
          ],
          'pluginAgents': [],
          'capability': {'supported': true, 'userScopeAvailable': true},
        };
    final catalog =
        SubagentsCatalog(session: bridge, scope: const {}, scopeKey: 'narrow');
    final boundary = GlobalKey();
    try {
      await tester.runAsync(loadReviewCaptureFonts);
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
        data: const MediaQueryData(
            size: Size(344, 760), textScaler: TextScaler.linear(1.4)),
        child: RepaintBoundary(
            key: boundary,
            child: Scaffold(
                body: Padding(
              padding: const EdgeInsets.all(20),
              child: SingleChildScrollView(
                child: SubagentsSettingsPage(
                    catalog: catalog,
                    modelOptions: const [
                      SubagentModelOption(
                          value: 'provider/model',
                          label: 'Review model',
                          thoughtLevels: ['high']),
                    ]),
              ),
            ))),
      )));
      await tester.pumpAndSettle();
      await captureReviewBoundary(tester, boundary, 'u16-subagents-narrow-140');
      expect(tester.takeException(), isNull,
          reason:
              'Both built-in model and thought controls must fit within the settings pane.');
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    }
  });

  testWidgets('review: subagent scope selector changes the visible source set',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) => {
          'capability': {'supported': true, 'userScopeAvailable': true},
          'agents': [
            {
              'id': 'personal-review',
              'name': 'personal-review',
              'scope': 'user',
              'source': 'user'
            },
            {
              'id': 'workspace-review',
              'name': 'workspace-review',
              'scope': 'workspace',
              'source': 'user',
              'projectPath': 'D:/Synthetic'
            },
            {
              'id': 'other-workspace',
              'name': 'other-workspace',
              'scope': 'workspace',
              'source': 'user',
              'projectPath': 'D:/Another'
            },
            {
              'id': 'general-purpose',
              'name': 'general-purpose',
              'scope': 'built-in',
              'source': 'built-in'
            },
          ],
          'pluginAgents': <Map<String, dynamic>>[],
        };
    final catalog = SubagentsCatalog(
        session: bridge,
        scope: const {'workspaceIdentity': 'review'},
        scopeKey: 'device|review',
        workspacePath: 'D:/Synthetic');
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
        child: SubagentsSettingsPage(catalog: catalog, scopes: const [
          SubagentScopeOption(
              key: 'user',
              label: 'User',
              scope: 'user',
              identity: {'workspaceIdentity': 'review'},
              workspacePath: 'D:/Synthetic'),
          SubagentScopeOption(
              key: 'workspace',
              label: 'Workspace',
              scope: 'workspace',
              identity: {'workspaceIdentity': 'review'},
              workspacePath: 'D:/Synthetic'),
        ]),
      ))));
      await tester.pumpAndSettle();
      expect(find.text('personal-review'), findsOneWidget);
      expect(find.text('general-purpose'), findsOneWidget);
      expect(find.text('workspace-review'), findsNothing,
          reason: 'Official hYt excludes workspace rows in User scope.');
      await tester.tap(find.text('User').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Workspace').last);
      await tester.pumpAndSettle();
      expect(find.text('workspace-review'), findsOneWidget);
      expect(find.text('personal-review'), findsNothing);
      expect(find.text('general-purpose'), findsNothing);
      expect(find.text('other-workspace'), findsNothing,
          reason:
              'Workspace scope excludes profiles for another project path.');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    }
  });
}
