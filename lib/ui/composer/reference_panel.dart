import 'package:flutter/material.dart';
import '../../state/client_preferences.dart';
import '../../state/composer_references.dart';
import '../official_icons.dart';
import '../theme.dart';

class ReferencePanel extends StatelessWidget {
  const ReferencePanel(
      {super.key, required this.references, required this.onPicked});
  final ComposerReferences references;
  final VoidCallback onPicked;
  String _label(BuildContext context, String category) => switch (category) {
        'files' => uiText(context, '文件', 'Files'),
        'skills' => uiText(context, '技能', 'Skills'),
        'plugins' => uiText(context, '插件', 'Plugins'),
        'sessions' => uiText(context, '任务', 'Tasks'),
        _ => uiText(context, '能力', 'Commands'),
      };
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final entries = references.entries;
    return Container(
        key: const ValueKey('composer-reference-panel'),
        margin: const EdgeInsets.only(bottom: 8),
        constraints:
            BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .3),
        decoration: BoxDecoration(
            color: ink.card,
            border: Border.all(color: ink.border),
            borderRadius: BorderRadius.circular(12)),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
              child: Row(children: [
                Expanded(
                    child: Text(uiText(context, '添加到对话', 'Add to conversation'),
                        style: TextStyle(fontSize: 12, color: ink.subtlest))),
                InkWell(
                    onTap: references.dismiss,
                    child: SizedBox(
                        width: 28,
                        height: 24,
                        child: Center(
                            child: LucideIcon('x',
                                size: 14, color: ink.subtlest)))),
              ])),
          if (references.loading && entries.isEmpty)
            const LinearProgressIndicator(minHeight: 2),
          if (references.failed.isNotEmpty)
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  Expanded(
                      child: Text(
                          uiText(context, '部分引用加载失败',
                              'Some references could not be loaded'),
                          style:
                              TextStyle(fontSize: 12, color: ink.diffRemoved))),
                  TextButton(
                      onPressed: references.retry,
                      child: Text(uiText(context, '重试', 'Retry')))
                ])),
          if (!references.loading && entries.isEmpty)
            Padding(
                padding: const EdgeInsets.all(12),
                child: Text(uiText(context, '没有匹配的内容', 'No matches'),
                    style: TextStyle(fontSize: 13, color: ink.subtlest))),
          Flexible(
              child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(4, 0, 4, 4),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final scopeLabel = switch (entry.scope) {
                      'workspace' => uiText(context, '工作区', 'Workspace'),
                      'plugin' => uiText(context, '插件', 'Plugin'),
                      'user' => uiText(context, '用户', 'User'),
                      _ => '',
                    };
                    final description = [
                      if (entry.category == 'skills' && scopeLabel.isNotEmpty)
                        scopeLabel,
                      if (entry.description.isNotEmpty) entry.description,
                    ].join(' · ');
                    return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (index == 0 ||
                              entries[index - 1].category != entry.category)
                            Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                                child: Text(_label(context, entry.category),
                                    style: TextStyle(
                                        fontSize: 12, color: ink.subtlest))),
                          Material(
                              color: references.selected == index
                                  ? ink.hover
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(8),
                              child: InkWell(
                                  key: ValueKey('reference-${entry.id}'),
                                  onTap: entry.disabled
                                      ? null
                                      : () {
                                          if (references.pick(entry)) {
                                            onPicked();
                                          }
                                        },
                                  borderRadius: BorderRadius.circular(8),
                                  child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 7),
                                      child: Row(children: [
                                        LucideIcon(
                                            switch (entry.category) {
                                              'files' => entry.directory
                                                  ? 'folder'
                                                  : 'file-diff',
                                              'skills' => 'dollar-sign',
                                              'plugins' => 'blocks',
                                              'sessions' =>
                                                'message-circle-plus',
                                              _ => 'square-slash'
                                            },
                                            size: 16,
                                            color: ink.subtlest),
                                        const SizedBox(width: 8),
                                        Expanded(
                                            child: Column(
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                              Text(entry.label,
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                  style: TextStyle(
                                                      fontSize: 14,
                                                      color: entry.disabled
                                                          ? ink.subtlest
                                                          : ink.text)),
                                              if (entry.disabled ||
                                                  description.isNotEmpty)
                                                Text(
                                                    entry.disabled
                                                        ? uiText(
                                                            context,
                                                            '插件名称冲突，无法引用',
                                                            'Plugin name conflict')
                                                        : description,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        fontSize: 12,
                                                        color: ink.subtlest)),
                                            ])),
                                      ])))),
                        ]);
                  })),
        ]));
  }
}
