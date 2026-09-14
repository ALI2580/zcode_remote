import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/plugin_catalog.dart';
import 'package:zcode_remote/ui/plugins_settings.dart';

void main() {
  test('review: plugin use draft uses the official reference identity', () {
    final item = CatalogPlugin(
      id: 'writer@official',
      name: 'writer',
      marketplace: 'official',
      installed: true,
      summary: const {
        'listing': {'displayName': 'Writer Tools', 'icon': 'writer-icon'},
      },
    );
    final draft = buildPluginUseDraft(item, locale: const Locale('en'));

    expect(draft.reference.id, 'plugin:writer@official');
    expect(draft.reference.category, 'plugins');
    expect(draft.reference.label, 'Writer Tools');
    expect(draft.reference.value, 'writer@official');
    expect(
        draft.reference.markdown, '[@Writer Tools](plugin://writer@official)');
    expect(draft.initialPrompt, draft.reference.markdown);
    expect(draft.initialPromptMention, {
      'id': 'plugin:writer@official',
      'category': 'plugins',
      'label': 'Writer Tools',
      'value': 'writer@official',
      'markdown': '[@Writer Tools](plugin://writer@official)',
      'data': {'pluginId': 'writer@official', 'icon': 'writer-icon'},
    });
    expect(
        buildPluginUseDraft(item,
                locale: const Locale('en'), prompt: '  summarize this  ')
            .initialPrompt,
        '[@Writer Tools](plugin://writer@official) summarize this');
  });
}
