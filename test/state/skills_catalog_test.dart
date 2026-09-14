import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/skills_catalog.dart';

import '../ui/fake_features.dart';

void main() {
  test('skills catalog reads enabled workspace skills', () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (channel, method, args) {
      expect(channel, 'skills');
      expect(method, 'list');
      final scope = args.single as Map;
      expect(scope['provider'], 'glm');
      return {
        'skills': [
          {
            'id': 'review-code',
            'name': 'review-code',
            'path': '/user/review.md',
            'scope': 'user',
            'description': 'Review the patch',
            'enabled': true
          }
        ]
      };
    };
    final controller = SkillsCatalog(
        transport: bridge.conversationTransport, scopeKey: 'device|workspace');
    addTearDown(controller.dispose);

    await controller.refresh();
    expect(controller.status, SkillsStatus.loaded);
    expect(controller.error, isNull);
    expect(controller.items.single.name, 'review-code');
    expect(controller.items.single.scope, 'user');
    expect(bridge.channels.calls.map((call) => call.channel), ['skills']);
  });

  test('a failed skills refresh keeps prior items and supports retry',
      () async {
    final bridge = FeatureBridge();
    bridge.channels.handler = (_, __, ___) => {
          'skills': [
            {'id': 'review-code', 'name': 'review-code'}
          ]
        };
    final controller = SkillsCatalog(
        transport: bridge.conversationTransport, scopeKey: 'device|workspace');
    addTearDown(controller.dispose);
    await controller.refresh();

    bridge.channels.handler = (_, __, ___) => throw StateError('offline');
    await controller.refresh();
    expect(controller.status, SkillsStatus.error);
    expect(controller.items.single.name, 'review-code');

    bridge.channels.handler = (_, __, ___) => {'skills': []};
    await controller.refresh();
    expect(controller.status, SkillsStatus.loaded);
    expect(controller.items, isEmpty);
  });
}
