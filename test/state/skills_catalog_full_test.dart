import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/skills_catalog.dart';

import '../ui/fake_features.dart';

class _SkillsService implements SkillsService {
  Object? response = {
    'skills': [
      {
        'id': 'review',
        'name': 'review',
        'path': 'skills/review.md',
        'scope': 'workspace',
        'description': 'Review code',
        'enabled': true,
        'metadata': {
          'version': '1.2.0',
          'slug': 'review-code',
          'publishedAt': '2026-09-01T00:00:00Z',
          'ownerId': 'owner-1',
        },
      },
      {
        'id': 'plugin-skill',
        'name': 'plugin-skill',
        'path': 'plugin/skill.md',
        'scope': 'plugin',
        'pluginId': 'acme@official',
      },
    ],
    'capability': {'userScopeAvailable': true},
    'diagnostics': [
      {
        'severity': 'error',
        'code': 'invalid-frontmatter',
        'message': 'Missing name',
        'path': 'skills/bad.md',
      },
      {
        'severity': 'warning',
        'code': 'deprecated-field',
        'message': 'Old field',
      },
    ],
    'metadata': {
      'review': {'version': '1.2.0'},
    },
  };
  final calls = <(String, Map<String, dynamic>)>[];
  Completer<Object?>? writeCompleter;
  bool failWrite = false;

  @override
  Future<Object?> list({
    required String? workspacePath,
    required String? workspaceIdentity,
    required String provider,
  }) async {
    calls.add((
      'list',
      {
        'workspacePath': workspacePath,
        'workspaceIdentity': workspaceIdentity,
        'provider': provider,
      }
    ));
    return response;
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
    calls.add((
      'setEnabled',
      {
        'workspacePath': workspacePath,
        'workspaceIdentity': workspaceIdentity,
        'provider': provider,
        'scope': scope,
        'skillId': skillId,
        'enabled': enabled,
      }
    ));
    if (failWrite) throw StateError('rejected');
    final pending = writeCompleter;
    if (pending != null) return pending.future;
    return null;
  }

  @override
  Future<Object?> deleteSkill({
    required String? workspacePath,
    required String? workspaceIdentity,
    required String skillId,
  }) async {
    calls.add((
      'deleteSkill',
      {
        'workspacePath': workspacePath,
        'workspaceIdentity': workspaceIdentity,
        'skillId': skillId,
      }
    ));
    if (failWrite) throw StateError('rejected');
    return null;
  }
}

void main() {
  test('full list keeps capability diagnostics and metadata', () async {
    final bridge = FeatureBridge();
    final service = _SkillsService();
    final catalog = SkillsCatalog(
      transport: bridge.conversationTransport,
      scopeKey: 'device|workspace',
      service: service,
      scope: const {
        'workspacePath': 'D:/Project',
        'workspaceIdentity': 'workspace-1',
      },
    );
    addTearDown(catalog.dispose);

    await catalog.refresh();
    expect(service.calls.first.$2, {
      'workspacePath': 'D:/Project',
      'workspaceIdentity': 'workspace-1',
      'provider': 'glm',
    });
    expect(catalog.items.first.version, '1.2.0');
    expect(catalog.items.first.slug, 'review-code');
    expect(catalog.items.first.ownerId, 'owner-1');
    expect(catalog.userScopeAvailable, isTrue);
    expect(catalog.errorCount, 1);
    expect(catalog.warningCount, 1);
    expect(catalog.items.last.isPlugin, isTrue);
    expect(catalog.items.last.isWritable, isFalse);
  });

  test('writes stay pending, use scope identity, and refresh after readback',
      () async {
    final bridge = FeatureBridge();
    final service = _SkillsService()..writeCompleter = Completer<Object?>();
    final catalog = SkillsCatalog(
      transport: bridge.conversationTransport,
      scopeKey: 'device|workspace',
      service: service,
      scope: const {
        'workspacePath': 'D:/Project',
        'workspaceIdentity': 'workspace-1',
      },
    );
    addTearDown(catalog.dispose);
    await catalog.refresh();
    final entry = catalog.items.first;
    final write = catalog.setEnabled(entry, false);
    await pumpEventQueue();
    expect(catalog.isWriting(entry), isTrue);
    expect(await catalog.setEnabled(entry, false), isFalse);
    service.writeCompleter!.complete(null);
    service.writeCompleter = null;
    expect(await write, isTrue);
    final payload =
        service.calls.firstWhere((call) => call.$1 == 'setEnabled').$2;
    expect(payload['scope'], 'workspace');
    expect(payload['skillId'], 'review');
    expect(payload['enabled'], isFalse);
  });

  test(
      'failed writes preserve the confirmed row and plugin rows stay read-only',
      () async {
    final bridge = FeatureBridge();
    final service = _SkillsService()..failWrite = true;
    final catalog = SkillsCatalog(
      transport: bridge.conversationTransport,
      scopeKey: 'device|workspace',
      service: service,
      scope: const {'workspacePath': 'D:/Project'},
    );
    addTearDown(catalog.dispose);
    await catalog.refresh();
    final entry = catalog.items.first;
    expect(await catalog.setEnabled(entry, false), isFalse);
    expect(catalog.items.first.enabled, isTrue);
    expect(catalog.operationError(entry), isA<StateError>());
    expect(await catalog.deleteSkill(catalog.items.last), isFalse);
    expect(service.calls.where((call) => call.$1 == 'deleteSkill'), isEmpty);
  });

  test('old source response cannot replace a newer scope', () async {
    final bridge = FeatureBridge();
    final service = _SkillsService();
    final first = Completer<Object?>();
    service.response = first.future;
    final catalog = SkillsCatalog(
      transport: bridge.conversationTransport,
      scopeKey: 'device|first',
      service: service,
      scope: const {'workspacePath': 'D:/First'},
    );
    addTearDown(catalog.dispose);
    final oldRefresh = catalog.refresh();
    await pumpEventQueue();
    final newer = _SkillsService();
    catalog.updateScope(
      nextScope: const {'workspacePath': 'D:/Second'},
      nextScopeKey: 'device|second',
      nextService: newer,
    );
    await catalog.refresh();
    first.complete({
      'skills': [
        {'id': 'old', 'name': 'old', 'scope': 'workspace'},
      ],
    });
    await oldRefresh;
    expect(catalog.scopeKey, 'device|second');
    expect(catalog.items, isNotEmpty);
    expect(catalog.items.first.id, 'review');
  });

  test('write forces a new readback instead of reusing an older pending read',
      () async {
    final bridge = FeatureBridge();
    final service = _SkillsService();
    final oldRead = Completer<Object?>();
    service.response = oldRead.future;
    final catalog = SkillsCatalog(
      transport: bridge.conversationTransport,
      scopeKey: 'device|workspace',
      service: service,
      scope: const {'workspacePath': 'D:/Project'},
    );
    addTearDown(catalog.dispose);
    final pendingRead = catalog.refresh();
    await pumpEventQueue();
    service.response = {
      'skills': [
        {
          'id': 'review',
          'name': 'review',
          'path': 'skills/review.md',
          'scope': 'workspace',
          'enabled': false,
        },
      ],
      'capability': {'userScopeAvailable': true},
    };
    final entry = SkillEntry.fromRaw(const {
      'id': 'review',
      'name': 'review',
      'path': 'skills/review.md',
      'scope': 'workspace',
      'enabled': true,
    });
    final write = catalog.setEnabled(entry, false);
    await pumpEventQueue();
    expect(await write, isTrue);
    expect(catalog.items.first.enabled, isFalse);
    oldRead.complete({
      'skills': [
        {
          'id': 'review',
          'name': 'review',
          'path': 'skills/review.md',
          'scope': 'workspace',
          'enabled': true,
        },
      ],
    });
    await pendingRead;
    expect(catalog.items.first.enabled, isFalse);
  });
}
