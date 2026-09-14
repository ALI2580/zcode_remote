import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/skills_catalog.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/skills_settings.dart';
import 'package:zcode_remote/ui/theme.dart';

import 'fake_features.dart';
import 'review_capture.dart';

Map<String, dynamic> _snapshot() => {
      'capability': {'supported': true, 'userScopeAvailable': true},
      'skills': [
        {
          'id': 'creator-id',
          'name': 'skill-creator',
          'scope': 'user',
          'path': 'C:/Synthetic/skills/skill-creator/SKILL.md',
          'description': 'Create a useful skill from a concrete task.',
          'enabled': true,
          'metadata': {
            'version': '1.2.3',
            'slug': 'skill-creator',
            'ownerId': 'synthetic-owner',
            'publishedAt': '2026-09-12T08:00:00Z',
          },
        }
      ],
      'diagnostics': [
        {
          'severity': 'warning',
          'code': 'synthetic-warning',
          'message': 'Review warning'
        }
      ],
    };

Map<String, dynamic> _visualSnapshot() => {
      'capability': {
        'supported': true,
        'userScopeAvailable': true,
      },
      'skills': [
        for (final name in ['control-browser', 'web-gui-tester'])
          {
            'id': name,
            'name': name,
            'scope': 'plugin',
            'pluginId': 'browser-use@zcode-plugins-official',
            'pluginName': 'browser-use',
            'pluginMarketplace': 'zcode-plugins-official',
            'description': 'Use browser automation tooling in the session.',
          },
        for (final name in ['docx', 'pdf', 'slides', 'sheets'])
          {
            'id': name,
            'name': name,
            'scope': 'plugin',
            'pluginId': 'doc-skills@zcode-plugins-official',
            'pluginName': 'doc-skills',
            'pluginMarketplace': 'zcode-plugins-official',
            'description': 'Create and inspect documents with the skill.',
          },
      ],
    };

void main() {
  testWidgets('review: skills settings component top at the official viewport',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1158, 722);
    addTearDown(tester.view.reset);
    final bridge = FeatureBridge();
    final snapshot = _visualSnapshot();
    bridge.channels.handler = (_, __, ___) => snapshot;
    final catalog = SkillsCatalog(
      transport: bridge.conversationTransport,
      scopeKey: 'review',
      workspacePath: 'D:/Synthetic',
      workspaceIdentity: 'review',
    );
    final plugins = PluginCatalog(bridge: bridge, scope: const {});
    plugins.items = [
      CatalogPlugin(
        id: 'browser-use@zcode-plugins-official',
        name: 'browser-use',
        marketplace: 'zcode-plugins-official',
        installed: true,
        info: const {
          'enabled': true,
          'scope': 'user',
          'listing': {
            'displayName': 'Browser use',
            'displayNameI18n': {'en-US': 'Browser use'},
          },
        },
      ),
      CatalogPlugin(
        id: 'doc-skills@zcode-plugins-official',
        name: 'doc-skills',
        marketplace: 'zcode-plugins-official',
        installed: true,
        info: const {
          'enabled': true,
          'scope': 'user',
          'listing': {
            'displayName': 'Document skills',
            'displayNameI18n': {'en-US': 'Document skills'},
          },
        },
      ),
    ];
    SharedPreferences.setMockInitialValues({});
    final preferences = ClientPreferences();
    await preferences.setLanguage('en');
    await preferences.setTheme(ThemeMode.dark);
    final boundary = GlobalKey();
    try {
      final capture = Platform.environment['ZCODE_UI_CAPTURE_DIR'] != null;
      await tester.runAsync(() async {
        await loadReviewCaptureFonts();
        if (capture) {
          final data = await File('C:/Windows/Fonts/msyh.ttc').readAsBytes();
          await (FontLoader('ReviewUi')
                ..addFont(Future.value(ByteData.sublistView(data))))
              .load();
        }
      });
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: preferences,
        home: Builder(builder: (context) {
          final base = Theme.of(context);
          final family = capture ? 'ReviewUi' : null;
          return Theme(
            data: base.copyWith(
              textTheme: base.textTheme.apply(fontFamily: family),
              filledButtonTheme: FilledButtonThemeData(
                  style: FilledButton.styleFrom(
                      textStyle: TextStyle(fontFamily: family))),
              outlinedButtonTheme: OutlinedButtonThemeData(
                  style: OutlinedButton.styleFrom(
                      textStyle: TextStyle(fontFamily: family))),
            ),
            child: DefaultTextStyle.merge(
              style: TextStyle(fontFamily: family),
              child: Scaffold(
                body: RepaintBoundary(
                  key: boundary,
                  child: SkillsSettingsPage(
                    catalog: catalog,
                    pluginCatalog: plugins,
                    onCreateTask: (_) {},
                  ),
                ),
              ),
            ),
          );
        }),
      ));
      await tester.pumpAndSettle();
      await captureReviewBoundary(tester, boundary, 'skills-top-1158-dark');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
      plugins.dispose();
      preferences.dispose();
    }
  });

  testWidgets(
      'review: new skill request preserves the official mention payload',
      (tester) async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, __, ___) => _snapshot();
    final catalog = SkillsCatalog(
        transport: bridge.conversationTransport,
        scopeKey: 'review',
        workspacePath: 'D:/Synthetic',
        workspaceIdentity: 'review');
    SkillCreatorDraft? received;
    try {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SkillsSettingsPage(
                  catalog: catalog,
                  onCreateTask: (draft) {
                    received = draft;
                  }))));
      await tester.pumpAndSettle();
      final create = find.byKey(const ValueKey('skills-new'));
      await tester.ensureVisible(create);
      await tester.tap(create);
      await tester.pumpAndSettle();
      expect(received, isNotNull);
      expect(received!.initialPromptMention['id'], 'skill:creator-id');
      expect(received!.initialPromptMention['value'], 'skill-creator');
      expect(received!.initialPromptMention['data'], {
        'path': 'C:/Synthetic/skills/skill-creator/SKILL.md',
        'scope': 'user'
      });
      expect(received!.reference.markdown,
          r'[$skill-creator](C:/Synthetic/skills/skill-creator/SKILL.md)');
      expect(received!.initialPrompt, '${received!.reference.markdown} ');
      expect(bridge.conversationTransport.sent, isEmpty);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    }
  });

  testWidgets(
      'review: skill metadata detail stays readable at 344px and 140 percent',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(344, 760);
    addTearDown(tester.view.reset);
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, __, ___) => _snapshot();
    final catalog = SkillsCatalog(
        transport: bridge.conversationTransport,
        scopeKey: 'review',
        workspacePath: 'D:/Synthetic',
        workspaceIdentity: 'review');
    final boundary = GlobalKey();
    try {
      await tester.runAsync(loadReviewCaptureFonts);
      await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: MaterialApp(
              theme: ZInkTheme.light(),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(textScaler: TextScaler.linear(1.4)),
                  child: child!),
              home: Scaffold(body: SkillsSettingsPage(catalog: catalog)))));
      await tester.pumpAndSettle();
      final item = find.byKey(const ValueKey('skill-item-creator-id-user'));
      await tester.ensureVisible(item);
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('skill-detail')), findsOneWidget);
      expect(find.text('1.2.3'), findsOneWidget);
      expect(find.text('synthetic-owner'), findsOneWidget);
      await captureReviewBoundary(tester, boundary, 'skill-detail-344-en-140');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      catalog.dispose();
    }
  });
}
