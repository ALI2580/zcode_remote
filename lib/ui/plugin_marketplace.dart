import 'package:flutter/material.dart';
import '../state/client_preferences.dart';
import '../state/plugin_catalog.dart';
import 'official_icons.dart';
import 'theme.dart';

class PluginMarketplace extends StatefulWidget {
  const PluginMarketplace(
      {super.key, required this.catalog, required this.onUse});
  final PluginCatalog catalog;
  final ValueChanged<CatalogPlugin> onUse;
  @override
  State<PluginMarketplace> createState() => _PluginMarketplaceState();
}

class _PluginMarketplaceState extends State<PluginMarketplace> {
  final _search = TextEditingController();
  bool _installedOnly = false;
  @override
  void initState() {
    super.initState();
    _search.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _confirmUninstall(CatalogPlugin item) async {
    final yes = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(uiText(context, '卸载插件', 'Uninstall plugin')),
                content: Text(item.name),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(uiText(context, '取消', 'Cancel'))),
                  TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(uiText(context, '卸载', 'Uninstall')))
                ]));
    if (yes == true) await widget.catalog.uninstall(item);
  }

  Future<void> _sources() async {
    final input = TextEditingController();
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(uiText(context, '插件市场来源', 'Marketplace sources')),
                content: SizedBox(
                    width: 440,
                    child: ListenableBuilder(
                        listenable: widget.catalog,
                        builder: (context, _) => SingleChildScrollView(
                                child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                  for (final source
                                      in widget.catalog.marketplaces)
                                    ListTile(
                                        dense: true,
                                        title: Text(
                                            '${source['name'] ?? source['id'] ?? ''}'),
                                        trailing: IconButton(
                                            tooltip: uiText(
                                                context, '刷新', 'Refresh'),
                                            onPressed: widget
                                                        .catalog.operation !=
                                                    null
                                                ? null
                                                : () => widget.catalog.mutate(
                                                        'updatePluginMarketplace',
                                                        {
                                                          'marketplace':
                                                              source['id']
                                                        }),
                                            icon: const LucideIcon('refresh-cw',
                                                size: 16))),
                                  TextField(
                                      controller: input,
                                      decoration: InputDecoration(
                                          labelText: uiText(context, '市场来源',
                                              'Marketplace source'),
                                          hintText: 'owner/repository')),
                                  const SizedBox(height: 8),
                                  TextButton(
                                      onPressed: widget.catalog.operation !=
                                              null
                                          ? null
                                          : () async {
                                              if (input.text.trim().isEmpty) {
                                                return;
                                              }
                                              if (await widget.catalog.mutate(
                                                  'addPluginMarketplace', {
                                                'source': input.text.trim()
                                              })) {
                                                input.clear();
                                              }
                                            },
                                      child: Text(uiText(
                                          context, '添加来源', 'Add source'))),
                                  if (widget.catalog.failed)
                                    Text(uiText(context, '操作失败，请检查来源并重试',
                                        'Could not update the source. Try again.')),
                                ])))),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(uiText(context, '关闭', 'Close')))
                ]));
    input.dispose();
  }

  Future<void> _detail(CatalogPlugin item) async {
    final details = widget.catalog.describe(item);
    await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(item.name),
                content: SizedBox(
                    width: 560,
                    child: FutureBuilder<Map<String, dynamic>>(
                        future: details,
                        builder: (context, snapshot) {
                          if (snapshot.hasError) {
                            return Text(uiText(context, '插件详情读取失败',
                                'Could not load plugin details'));
                          }
                          if (!snapshot.hasData) {
                            return const SizedBox(
                                height: 80,
                                child:
                                    Center(child: CircularProgressIndicator()));
                          }
                          final data = snapshot.data!;
                          final components = data['components'] is List
                              ? data['components'] as List
                              : const [];
                          return SingleChildScrollView(
                              child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                if (item.description.isNotEmpty)
                                  Text(item.description),
                                const SizedBox(height: 12),
                                Text(
                                    '${uiText(context, '来源', 'Source')}: ${item.marketplace}'),
                                if (data['readme'] is String)
                                  Padding(
                                      padding: const EdgeInsets.only(top: 12),
                                      child: SelectableText(
                                          data['readme'] as String)),
                                for (final component
                                    in components.whereType<Map>())
                                  ListTile(
                                      dense: true,
                                      title: Text(
                                          '${component['name'] ?? component['title'] ?? component['type'] ?? ''}'),
                                      subtitle: Text(
                                          '${component['description'] ?? component['kind'] ?? ''}')),
                              ]));
                        })),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(uiText(context, '关闭', 'Close')))
                ]));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.catalog,
      builder: (context, _) {
        final catalog = widget.catalog;
        final ink = ZInk.of(Theme.of(context).colorScheme);
        final query = _search.text.trim().toLowerCase();
        final items = catalog.items
            .where((e) =>
                (!_installedOnly || e.installed) &&
                '${e.name} ${e.description} ${e.marketplace}'
                    .toLowerCase()
                    .contains(query))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
        final categories = <String>[
          'productivity',
          'developer-tools',
          'utilities',
          'finance',
          'guides',
          'template',
          'other'
        ];
        String categoryName(String value) => switch (value) {
              'productivity' => uiText(context, '效率工具', 'Productivity'),
              'developer-tools' => uiText(context, '开发工具', 'Developer tools'),
              'utilities' => uiText(context, '实用工具', 'Utilities'),
              'finance' => uiText(context, '金融', 'Finance'),
              'guides' => uiText(context, '指南', 'Guides'),
              'template' => uiText(context, '模板', 'Templates'),
              'other' => uiText(context, '其他', 'Other'),
              _ => value,
            };
        return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        ChoiceChip(
                            label: Text(uiText(context, '全部插件', 'All plugins')),
                            selected: !_installedOnly,
                            onSelected: (_) =>
                                setState(() => _installedOnly = false)),
                        ChoiceChip(
                            label: Text(uiText(context, '已安装', 'Installed')),
                            selected: _installedOnly,
                            onSelected: (_) =>
                                setState(() => _installedOnly = true)),
                        TextButton(
                            onPressed: _sources,
                            child: Text(
                                uiText(context, '管理来源', 'Manage sources'))),
                        IconButton(
                            tooltip: uiText(context, '刷新插件', 'Refresh plugins'),
                            onPressed:
                                catalog.loading || catalog.operation != null
                                    ? null
                                    : catalog.refresh,
                            icon: LucideIcon('refresh-cw',
                                size: 16, color: ink.subtlest)),
                      ]),
                  const SizedBox(height: 12),
                  TextField(
                      key: const ValueKey('plugin-market-search'),
                      controller: _search,
                      decoration: InputDecoration(
                          isDense: true,
                          prefixIcon: const Padding(
                              padding: EdgeInsets.all(10),
                              child: LucideIcon('search', size: 16)),
                          hintText: uiText(context, '搜索插件…', 'Search plugins…'),
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12)))),
                  if (catalog.loading)
                    const LinearProgressIndicator(minHeight: 2),
                  if (catalog.failed)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                            uiText(context, '插件信息或操作未确认，请刷新重试',
                                'Plugin data or operation could not be confirmed. Refresh to retry.'),
                            style: TextStyle(color: ink.diffRemoved))),
                  if (catalog.operation != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Text(
                            uiText(context, '正在更新插件…', 'Updating plugin…'))),
                  Expanded(
                      child: ListView(children: [
                    if (!catalog.loading && items.isEmpty)
                      Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(uiText(
                              context, '没有匹配的插件', 'No matching plugins'))),
                    for (final category in {
                      ...categories,
                      ...items.map((e) => e.category)
                    })
                      if (items.any((e) => e.category == category)) ...[
                        Padding(
                            padding: const EdgeInsets.only(top: 24, bottom: 8),
                            child: Text(categoryName(category),
                                style: TextStyle(
                                    fontSize: 16,
                                    color: ink.text,
                                    fontWeight: FontWeight.w600))),
                        for (final item
                            in items.where((e) => e.category == category))
                          InkWell(
                              key: ValueKey('plugin-card-${item.id}'),
                              onTap: () => _detail(item),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 10),
                                  child: Row(children: [
                                    LucideIcon('blocks',
                                        size: 32, color: ink.subtlest),
                                    const SizedBox(width: 12),
                                    Expanded(
                                        child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                          Text(item.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  color: ink.text,
                                                  fontWeight: FontWeight.w600)),
                                          if (item.description.isNotEmpty)
                                            Text(item.description,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                    fontSize: 12,
                                                    color: ink.subtlest)),
                                        ])),
                                    const SizedBox(width: 8),
                                    if (!item.installed)
                                      TextButton(
                                          onPressed: catalog.operation != null
                                              ? null
                                              : () => catalog.install(item),
                                          child: Text(item.restorable
                                              ? uiText(context, '恢复', 'Restore')
                                              : uiText(
                                                  context, '安装', 'Install')))
                                    else
                                      PopupMenuButton<String>(
                                          tooltip: uiText(context, '插件操作',
                                              'Plugin actions'),
                                          onSelected: (action) {
                                            if (action == 'use') {
                                              widget.onUse(item);
                                            }
                                            if (action == 'toggle') {
                                              catalog.enable(
                                                  item, !item.enabled);
                                            }
                                            if (action == 'uninstall') {
                                              _confirmUninstall(item);
                                            }
                                            if (action == 'update') {
                                              catalog.mutate('updatePlugin',
                                                  {'pluginId': item.id});
                                            }
                                          },
                                          enabled: catalog.operation == null,
                                          itemBuilder: (context) => [
                                                if (item.enabled)
                                                  PopupMenuItem(
                                                      value: 'use',
                                                      child: Text(uiText(
                                                          context,
                                                          '在新任务中使用',
                                                          'Use in new task'))),
                                                PopupMenuItem(
                                                    value: 'toggle',
                                                    child: Text(item.enabled
                                                        ? uiText(context, '禁用',
                                                            'Disable')
                                                        : uiText(context, '启用',
                                                            'Enable'))),
                                                if (item.canUpdate)
                                                  PopupMenuItem(
                                                      value: 'update',
                                                      child: Text(uiText(
                                                          context,
                                                          '更新',
                                                          'Update'))),
                                                PopupMenuItem(
                                                    value: 'uninstall',
                                                    child: Text(uiText(context,
                                                        '卸载', 'Uninstall'))),
                                              ],
                                          icon: LucideIcon('ellipsis',
                                              size: 16, color: ink.subtlest)),
                                  ]))),
                      ],
                  ])),
                ]));
      });
}
