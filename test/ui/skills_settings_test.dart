import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/state/skills_catalog.dart';
import 'package:zcode_remote/ui/skills_settings.dart';

import 'fake_features.dart';

class _UiSkillsService implements SkillsService {
  final calls = <String>[];

  @override
  Future<Object?> list({
    required String? workspacePath,
    required String? workspaceIdentity,
    required String provider,
  }) async {
    calls.add('list');
    return {
      'skills': [
        {
          'id': 'review',
          'name': 'review',
          'path': 'skills/review.md',
          'scope': 'user',
          'description': 'Review code',
          'enabled': true,
          'metadata': {
            'version': '1.0.0',
            'slug': 'review',
            'publishedAt': '2026-09-01',
            'ownerId': 'owner',
          },
        },
        {
          'id': 'plugin-review',
          'name': 'plugin-review',
          'path': 'plugin/review.md',
          'scope': 'plugin',
          'source': 'plugin',
          'pluginId': 'acme@official',
          'pluginName': 'Acme',
        },
      ],
      'capability': {'userScopeAvailable': true},
    };
  }

  @override
  Future<Object?> setEnabled({
    required String? workspacePath,
    required String? workspaceIdentity,
    required String provider,
    required String scope,
    required String skillId,
    required bool enabled,
  }) async {
    calls.add('setEnabled');
    return null;
  }

  @override
  Future<Object?> deleteSkill({
    required String? workspacePath,
    required String? workspaceIdentity,
    required String skillId,
  }) async {
    calls.add('deleteSkill');
    return null;
  }
}

void main() {
  testWidgets(
      'skills settings shows detail, metadata, and verified plugin group',
      (tester) async {
    final bridge = FeatureBridge();
    final service = _UiSkillsService();
    final catalog = SkillsCatalog(
      transport: bridge.conversationTransport,
      scopeKey: 'device|workspace',
      service: service,
      scope: const {'workspacePath': 'D:/Project'},
    );
    final plugins = PluginCatalog(bridge: bridge, scope: const {});
    plugins.items = [
      CatalogPlugin(
        id: 'acme@official',
        name: 'Acme',
        marketplace: 'official',
        installed: true,
        info: const {'enabled': true, 'scope': 'user'},
        installedMeta: const {'scope': 'user'},
      ),
    ];
    addTearDown(catalog.dispose);
    addTearDown(plugins.dispose);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SkillsSettingsPage(
          catalog: catalog,
          pluginCatalog: plugins,
          onCreateTask: (draft) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('skills-search')), findsOneWidget);
    expect(
        find.byKey(const ValueKey('skill-item-review-user')), findsOneWidget);
    expect(find.text('Acme'), findsOneWidget);
    expect(find.text('plugin-review'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('skill-item-review-user')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('skill-detail')), findsOneWidget);
    expect(find.text('1.0.0'), findsOneWidget);
    expect(find.text('skills/review.md'), findsOneWidget);
    expect(find.byKey(const ValueKey('skill-open-path')), findsNothing);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('new skill prepares a ComposerReference without sending a task',
      (tester) async {
    final bridge = FeatureBridge();
    final service = _UiSkillsService();
    final catalog = SkillsCatalog(
      transport: bridge.conversationTransport,
      scopeKey: 'device|workspace',
      service: service,
      scope: const {'workspacePath': 'D:/Project'},
    );
    SkillCreatorDraft? draft;
    addTearDown(catalog.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SkillsSettingsPage(
          catalog: catalog,
          onCreateTask: (value) => draft = value,
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('skills-new')));
    await tester.pump();
    expect(draft, isNotNull);
    expect(draft!.provider, 'glm');
    expect(draft!.initialPrompt, r'$skill-creator ');
    expect(draft!.reference.category, 'skills');
    expect(draft!.initialPromptMention['category'], 'skills');
    expect(service.calls, ['list']);
  });
}
