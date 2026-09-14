import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/skills_catalog.dart';

import '../ui/fake_features.dart';

void main() {
  test('review: compatibility skills constructor keeps its transport workspace',
      () async {
    final bridge = FeatureBridge();
    Map<String, dynamic>? readScope;
    bridge.channels.handler = (_, method, args) {
      if (method == 'list') {
        readScope = Map<String, dynamic>.from(args.single as Map);
      }
      return {'skills': []};
    };
    final transport = ConversationTransport(
      session: bridge,
      scope: const {
        'workspacePath': 'D:/Synthetic/skills',
        'workspaceIdentity': 'skills-workspace',
      },
    );
    final catalog = SkillsCatalog(
        transport: transport, scopeKey: 'device|skills-workspace');
    addTearDown(catalog.dispose);
    await catalog.refresh();
    expect(readScope?['workspacePath'], 'D:/Synthetic/skills');
    expect(readScope?['workspaceIdentity'], 'skills-workspace');
    expect(readScope?['provider'], 'glm');
  });

  test('review: a pending skill write remains visibly pending until readback',
      () async {
    final bridge = FeatureBridge();
    final gate = Completer<void>();
    var writes = 0;
    bridge.channels.handler = (_, method, __) async {
      if (method == 'setEnabled') {
        writes++;
        await gate.future;
      }
      return {
        'skills': [
          {
            'id': 'review-skill',
            'name': 'review',
            'scope': 'user',
            'path': 'C:/Synthetic/review/SKILL.md',
            'enabled': writes == 0,
          }
        ],
        'capability': {'userScopeAvailable': true},
      };
    };
    final catalog = SkillsCatalog(
        transport: bridge.conversationTransport,
        scopeKey: 'device|workspace',
        workspacePath: 'D:/Synthetic',
        workspaceIdentity: 'workspace');
    await catalog.refresh();
    final entry = catalog.items.single;
    final operation = catalog.setEnabled(entry, false);
    try {
      await Future<void>.delayed(Duration.zero);
      expect(catalog.isWriting(entry), isTrue,
          reason: 'UI pending state must use the active operation token.');
      expect(await catalog.setEnabled(entry, false), isFalse);
      expect(writes, 1);
      gate.complete();
      expect(await operation, isTrue);
      expect(catalog.isWriting(entry), isFalse);
      expect(catalog.items.single.enabled, isFalse);
    } finally {
      if (!gate.isCompleted) gate.complete();
      await operation;
      catalog.dispose();
    }
  });

  test('review: skill write confirmation does not reuse a read started before the write',
      () async {
    final bridge = FeatureBridge();
    final staleRead = Completer<Object?>();
    var reads = 0;
    var enabled = true;
    Map<String, dynamic> snapshot(bool value) => {
          'skills': [
            {'id': 'review', 'name': 'review', 'scope': 'user', 'enabled': value}
          ],
        };
    bridge.channels.handler = (_, method, __) async {
      if (method == 'setEnabled') {
        enabled = false;
        return {'success': true};
      }
      if (method == 'list' && ++reads == 2) return staleRead.future;
      return snapshot(enabled);
    };
    final catalog = SkillsCatalog(transport: bridge.conversationTransport,
        scopeKey: 'device|workspace', workspacePath: 'D:/Synthetic');
    addTearDown(catalog.dispose);
    await catalog.refresh();
    final refresh = catalog.refresh();
    final write = catalog.setEnabled(catalog.items.single, false);
    await Future<void>.delayed(Duration.zero);
    staleRead.complete(snapshot(true));
    await refresh;
    expect(await write, isTrue);
    expect(catalog.items.single.enabled, isFalse,
        reason: 'Only a read begun after the successful write can confirm its result.');
  });
}
