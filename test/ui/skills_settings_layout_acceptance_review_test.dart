import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/skills_catalog.dart';
import 'package:zcode_remote/ui/skills_settings.dart';

import 'fake_features.dart';

class _LayoutSkillsService implements SkillsService {
  @override
  Future<Object?> list({
    required String? workspacePath,
    required String? workspaceIdentity,
    required String provider,
  }) async =>
      {
        'skills': [
          {
            'id': 'review',
            'name': 'review',
            'scope': 'user',
            'description': 'Review code',
          },
        ],
        'capability': {'userScopeAvailable': true},
      };

  @override
  Future<Object?> setEnabled({
    required String? workspacePath,
    required String? workspaceIdentity,
    required String provider,
    required String scope,
    required String skillId,
    required bool enabled,
  }) async =>
      null;

  @override
  Future<Object?> deleteSkill({
    required String? workspacePath,
    required String? workspaceIdentity,
    required String skillId,
  }) async =>
      null;
}

void main() {
  testWidgets('skills chrome remains usable at compact and desktop widths',
      (tester) async {
    final bridge = FeatureBridge();
    final catalog = SkillsCatalog(
      transport: bridge.conversationTransport,
      scopeKey: 'device|workspace',
      service: _LayoutSkillsService(),
      scope: const {'workspacePath': 'D:/Project'},
    );
    addTearDown(catalog.dispose);
    await tester.binding.setSurfaceSize(const Size(344, 140));
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SkillsSettingsPage(
          catalog: catalog,
          onCreateTask: (draft) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(const Size(1180, 720));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.binding.setSurfaceSize(null);
  });
}
