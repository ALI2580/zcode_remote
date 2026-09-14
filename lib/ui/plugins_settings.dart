import 'dart:async';

import 'package:flutter/material.dart';

import '../state/client_preferences.dart';
import '../state/composer_input.dart';
import '../state/plugin_catalog.dart';
import 'official_icons.dart';
import 'plugin_display_name.dart';
import 'settings_scope.dart';
import 'theme.dart';

/// A prepared plugin mention for the parent Composer. The callback receives
/// this draft without sending a task or replacing any existing input.
class PluginUseDraft {
  const PluginUseDraft({
    required this.plugin,
    required this.reference,
    required this.initialPrompt,
    required this.initialPromptMention,
  });

  final CatalogPlugin plugin;
  final ComposerReference reference;
  final String initialPrompt;
  final Map<String, dynamic> initialPromptMention;

  Map<String, dynamic> get request => {
        'pluginId': plugin.id,
        'initialPrompt': initialPrompt,
        'initialPromptMention': initialPromptMention,
      };
}

/// Builds the official plugin mention payload without touching a Composer.
/// Parents may decide whether the target draft is empty before applying it.
PluginUseDraft buildPluginUseDraft(CatalogPlugin item,
    {required Locale locale, String scope = 'user', String prompt = ''}) {
  final label = pluginDisplayName(item, locale);
  final reference = ComposerReference(
    id: 'plugin:${item.id}',
    category: 'plugins',
    label: label,
    value: item.id,
    description: item.description,
    scope: scope,
  );
  final mention = <String, dynamic>{
    'id': reference.id,
    'category': 'plugins',
    'label': label,
    'value': item.id,
    'markdown': reference.markdown,
    'data': {
      'pluginId': item.id,
      if (item.icon != null) 'icon': item.icon,
    },
  };
  return PluginUseDraft(
    plugin: item,
    reference: reference,
    initialPrompt: prompt.trim().isEmpty
        ? reference.markdown
        : '${reference.markdown} ${prompt.trim()}',
    initialPromptMention: mention,
  );
}

/// The installed-plugin settings surface. The parent supplies the catalog and
/// owns its bridge; this page only borrows the catalog and never disposes it.
class PluginsSettingsPage extends StatefulWidget {
  const PluginsSettingsPage({
    super.key,
    required this.catalog,
    this.scope = 'user',
    this.onScopeChanged,
    this.workspaceScopeOptions = const [],
    this.selectedWorkspaceScope,
    this.onWorkspaceScopeChanged,
    this.onOpenMarketplace,
    this.onUse,
    this.onUsePrompt,
    this.title,
    this.embedded = false,
  });

  final PluginCatalog catalog;
  final String scope;
  final ValueChanged<String>? onScopeChanged;
  final List<SettingsScopeOption> workspaceScopeOptions;
  final SettingsScopeOption? selectedWorkspaceScope;
  final FutureOr<void> Function(SettingsScopeOption option)?
      onWorkspaceScopeChanged;
  final VoidCallback? onOpenMarketplace;
  final ValueChanged<CatalogPlugin>? onUse;
  final FutureOr<void> Function(PluginUseDraft draft)? onUsePrompt;
  final String? title;
  final bool embedded;

  @override
  State<PluginsSettingsPage> createState() => _PluginsSettingsPageState();
}

class _PluginsSettingsPageState extends State<PluginsSettingsPage> {
  late String _scope;
  String _query = '';
  CatalogPlugin? _detailItem;
  Future<_PluginDetailsResult>? _detailFuture;

  @override
  void initState() {
    super.initState();
    _scope = _validScope(widget.scope);
    widget.catalog.addListener(_changed);
    if (!widget.catalog.loading && widget.catalog.items.isEmpty) {
      unawaited(widget.catalog.refresh());
    }
  }

  @override
  void didUpdateWidget(covariant PluginsSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog) {
      oldWidget.catalog.removeListener(_changed);
      widget.catalog.addListener(_changed);
      _scope = _validScope(widget.scope);
      _query = '';
      _detailItem = null;
      _detailFuture = null;
      if (!widget.catalog.loading && widget.catalog.items.isEmpty) {
        unawaited(widget.catalog.refresh());
      }
    } else if (oldWidget.scope != widget.scope) {
      _scope = _validScope(widget.scope);
    }
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_detailItem != null &&
        !widget.catalog.items.any((item) => item.id == _detailItem!.id)) {
      _detailItem = null;
      _detailFuture = null;
    }
    setState(() {});
  }

  String _validScope(String value) =>
      value == 'workspace' && widget.catalog.hasWorkspace
          ? 'workspace'
          : 'user';

  String _scopeLabel(BuildContext context, String value) => value == 'workspace'
      ? uiText(context, '工作区', 'Workspace')
      : uiText(context, '用户', 'User');

  String _displayName(CatalogPlugin item) =>
      pluginDisplayName(item, Localizations.localeOf(context));

  String _enabledSourceLabel(CatalogPlugin item) {
    if (_scope == 'workspace' && item.enabledSource == 'user') {
      return uiText(context, '继承用户设置', 'Inherited from user');
    }
    if (item.enabledSource == 'workspace') {
      return uiText(context, '工作区覆盖', 'Workspace override');
    }
    if (item.enabledSource == 'user') {
      return uiText(context, '用户默认', 'User default');
    }
    return uiText(context, '默认', 'Default');
  }

  bool _visible(CatalogPlugin item) {
    // listPlugins is already the authoritative effective configScope
    // projection. Installation location must not hide inherited capabilities.
    if ((!item.installed && !item.restorable) || item.packageMissing) {
      return false;
    }
    final query = _query.trim().toLowerCase();
    if (query.isEmpty) return true;
    return '${_displayName(item)} ${item.description} ${item.marketplace} ${item.id}'
        .toLowerCase()
        .contains(query);
  }

  List<CatalogPlugin> get _builtIns => widget.catalog.items
      .where((item) => item.builtIn && !item.packageMissing)
      .where(_visible)
      .toList(growable: false)
    ..sort((a, b) => _displayName(a).compareTo(_displayName(b)));

  List<CatalogPlugin> get _marketplaceInstalled => widget.catalog.items
      .where((item) => !item.builtIn && item.installed && !item.packageMissing)
      .where(_visible)
      .toList(growable: false)
    ..sort((a, b) => _displayName(a).compareTo(_displayName(b)));

  Future<void> _toggle(CatalogPlugin item, bool value) async {
    final ok = await widget.catalog.enable(item, value);
    if (!mounted || ok) return;
    _showError(uiText(context, '插件状态未确认，请刷新重试。',
        'Plugin state could not be confirmed. Refresh to retry.'));
  }

  Future<void> _resetUserDefault(CatalogPlugin item) async {
    final ok = await widget.catalog.resetPluginConfig(item);
    if (!mounted || ok) return;
    _showError(uiText(context, '恢复用户默认值未确认，请刷新重试。',
        'Could not restore the user default. Refresh to retry.'));
  }

  Future<void> _uninstall(CatalogPlugin item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiText(context, '卸载插件', 'Uninstall plugin')),
        content: Text(_displayName(item)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(uiText(context, '取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(uiText(context, '卸载', 'Uninstall')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await widget.catalog.uninstall(item);
    if (!mounted || ok) return;
    _showError(uiText(context, '卸载未确认，请刷新重试。',
        'Uninstall was not confirmed. Refresh to retry.'));
  }

  Future<void> _configure(CatalogPlugin item) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _PluginConfigurationDialog(
        catalog: widget.catalog,
        item: item,
      ),
    );
  }

  PluginUseDraft _draftFor(CatalogPlugin item) {
    return buildPluginUseDraft(item,
        locale: Localizations.localeOf(context), scope: _scope);
  }

  void _use(CatalogPlugin item) {
    final callback = widget.onUsePrompt;
    if (callback != null) {
      unawaited(Future<void>.sync(() => callback(_draftFor(item))));
    } else {
      widget.onUse?.call(item);
    }
  }

  Future<_PluginDetailsResult> _loadDetails(CatalogPlugin item) async {
    try {
      // Await here, before the future reaches FutureBuilder, so an already
      // failed describe call is converted into the page's visible error state
      // without becoming an unhandled error between frames.
      return _PluginDetailsResult.data(await widget.catalog.describe(item));
    } catch (error, stackTrace) {
      return _PluginDetailsResult.failure(error, stackTrace);
    }
  }

  Future<void> _showDetails(CatalogPlugin item) async {
    setState(() {
      _detailItem = item;
      _detailFuture = _loadDetails(item);
    });
  }

  void _closeDetails() {
    if (!mounted) return;
    setState(() {
      _detailItem = null;
      _detailFuture = null;
    });
  }

  Widget _detailsView(InkTokens ink) {
    final item = _detailItem;
    final future = _detailFuture;
    if (item == null || future == null) return const SizedBox.shrink();
    return Column(
      key: const ValueKey('plugin-details'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextButton.icon(
          key: const ValueKey('plugin-details-back'),
          onPressed: _closeDetails,
          icon: const LucideIcon('arrow-left', size: 16),
          label: Text(uiText(context, '插件', 'Plugins')),
        ),
        const SizedBox(height: 4),
        Text(_displayName(item),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${item.marketplace} · ${_scopeLabel(context, _scope)}',
            style: TextStyle(fontSize: 12, color: ink.subtlest)),
        if (item.enabled)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              key: const ValueKey('plugin-details-use'),
              onPressed: () => _use(item),
              icon: const LucideIcon('at-sign', size: 16),
              label: Text(uiText(context, '在新任务中使用', 'Use in new task')),
            ),
          ),
        const SizedBox(height: 16),
        FutureBuilder<_PluginDetailsResult>(
          future: future,
          builder: (context, snapshot) {
            final result = snapshot.data;
            if (result?.hasError == true) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                      uiText(context, '插件详情读取失败。',
                          'Could not load plugin details.'),
                      style: TextStyle(color: ink.diffRemoved)),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    key: const ValueKey('plugin-details-retry'),
                    onPressed: () {
                      final future = _loadDetails(item);
                      setState(() {
                        _detailFuture = future;
                      });
                    },
                    child: Text(uiText(context, '重试', 'Retry')),
                  ),
                ],
              );
            }
            if (result == null) {
              return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()));
            }
            final details = result.details!;
            final warnings = details['warnings'] is List
                ? details['warnings']
                : item.warnings;
            final components = details['components'] is List
                ? details['components']
                : item.components;
            final readme =
                details['readme'] is String ? details['readme'] : item.readme;
            final rootPath =
                details['rootPath'] ?? details['path'] ?? item.rootPath;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _detailField(context, uiText(context, '说明', 'Description'),
                    item.description),
                _detailField(
                    context, uiText(context, '版本', 'Version'), item.version),
                _detailField(
                    context, uiText(context, '作者', 'Author'), item.author),
                if (item.enabledSource != 'default')
                  _detailField(
                      context,
                      uiText(context, '启用来源', 'Enabled source'),
                      _enabledSourceLabel(item)),
                if (rootPath is String && rootPath.trim().isNotEmpty)
                  _detailField(context, uiText(context, '安装路径', 'Root path'),
                      rootPath.trim()),
                if (item.mcpServerNames.isNotEmpty)
                  _detailField(
                      context,
                      uiText(context, 'MCP 服务器', 'MCP servers'),
                      item.mcpServerNames.join(', ')),
                if (item.hookDetails.isNotEmpty)
                  _detailField(context, uiText(context, '钩子', 'Hooks'),
                      '${item.hookDetails.length}'),
                if (warnings is List && warnings.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(uiText(context, '警告', 'Warnings'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  for (final warning in warnings)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text('$warning'),
                    ),
                ],
                if (components is List && components.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(uiText(context, '组件', 'Components'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  for (final component in components.whereType<Map>())
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                          '${component['name'] ?? component['title'] ?? component['type'] ?? ''}'),
                      subtitle: Text(
                          '${component['description'] ?? component['kind'] ?? ''}'),
                    ),
                ],
                if (readme is String && readme.trim().isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(uiText(context, 'README', 'README'),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  SelectableText(readme),
                ],
                const SizedBox(height: 16),
                if (item.userConfig.isNotEmpty)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      key: const ValueKey('plugin-details-configure'),
                      onPressed: () => unawaited(_configure(item)),
                      icon: const LucideIcon('settings-2', size: 16),
                      label: Text(uiText(context, '配置', 'Configure')),
                    ),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _detailField(BuildContext context, String label, String value) {
    if (value.trim().isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(value, softWrap: true),
        ],
      ),
    );
  }

  Future<void> _manageSources() async {
    final controller = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiText(context, '插件市场来源', 'Marketplace sources')),
        content: SizedBox(
          width: 440,
          child: ListenableBuilder(
            listenable: widget.catalog,
            builder: (context, _) => SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final source in widget.catalog.marketplaces)
                    ListTile(
                      dense: true,
                      title: Text('${source['name'] ?? source['id'] ?? ''}'),
                      trailing: Wrap(
                        spacing: 2,
                        children: [
                          IconButton(
                            tooltip: uiText(context, '刷新', 'Refresh'),
                            onPressed: widget.catalog.operation == null
                                ? () => unawaited(widget.catalog
                                    .updateMarketplace('${source['id'] ?? ''}'))
                                : null,
                            icon: const LucideIcon('refresh-cw', size: 16),
                          ),
                          IconButton(
                            tooltip: uiText(context, '移除', 'Remove'),
                            onPressed: widget.catalog.operation == null
                                ? () => unawaited(widget.catalog
                                    .removeMarketplace('${source['id'] ?? ''}'))
                                : null,
                            icon: const LucideIcon('trash-2', size: 16),
                          ),
                        ],
                      ),
                    ),
                  TextField(
                    key: const ValueKey('plugin-source-input'),
                    controller: controller,
                    decoration: InputDecoration(
                      labelText: uiText(context, '市场来源', 'Marketplace source'),
                      hintText: uiText(
                          context, '来源路径或仓库', 'Source path or repository'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        OutlinedButton(
                          key: const ValueKey('plugin-source-validate'),
                          onPressed: widget.catalog.operation != null
                              ? null
                              : () async {
                                  final source = controller.text.trim();
                                  if (source.isEmpty) return;
                                  final successText = uiText(context, '来源校验通过。',
                                      'Source validation passed.');
                                  final failureText = uiText(
                                      context,
                                      '来源校验失败，请检查后重试。',
                                      'Source validation failed.');
                                  final valid = await widget.catalog
                                      .validateMarketplace(source);
                                  if (!mounted) return;
                                  _showError(valid ? successText : failureText);
                                },
                          child: Text(uiText(context, '验证', 'Validate')),
                        ),
                        FilledButton(
                          key: const ValueKey('plugin-source-add'),
                          onPressed: widget.catalog.operation != null
                              ? null
                              : () async {
                                  final source = controller.text.trim();
                                  if (source.isEmpty) return;
                                  if (await widget.catalog
                                      .addMarketplace(source)) {
                                    controller.clear();
                                  }
                                },
                          child: Text(uiText(context, '添加来源', 'Add source')),
                        ),
                      ],
                    ),
                  ),
                  if (widget.catalog.failed)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        uiText(context, '来源操作未确认，请刷新重试。',
                            'Source operation was not confirmed. Refresh to retry.'),
                        style: TextStyle(
                            color: ZInk.of(Theme.of(context).colorScheme)
                                .diffRemoved),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(uiText(context, '关闭', 'Close'))),
        ],
      ),
    );
    controller.dispose();
  }

  Widget _scopePicker() {
    final values = <String>[
      'user',
      if (widget.catalog.hasWorkspace) 'workspace',
    ];
    return SegmentedButton<String>(
      key: const ValueKey('plugins-scope'),
      segments: [
        for (final value in values)
          ButtonSegment<String>(
            value: value,
            label: Text(_scopeLabel(context, value)),
          ),
      ],
      selected: {_scope},
      onSelectionChanged: (selected) {
        final value = selected.firstOrNull;
        if (value == null || value == _scope) return;
        setState(() {
          _scope = value;
          _query = '';
          _detailItem = null;
          _detailFuture = null;
        });
        widget.onScopeChanged?.call(value);
      },
    );
  }

  Widget _row(CatalogPlugin item, InkTokens ink) {
    return InkWell(
      key: ValueKey('plugin-settings-item-${item.id}'),
      onTap: () => unawaited(_showDetails(item)),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final busy = widget.catalog.operation != null;
          final label = _displayName(item);
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 3),
              Text(
                item.description.isEmpty
                    ? uiText(context, '暂无描述', 'No description')
                    : item.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: ink.subtlest),
              ),
              const SizedBox(height: 3),
              Text('${item.marketplace} · ${_scopeLabel(context, _scope)}',
                  style: TextStyle(fontSize: 11, color: ink.subtlest)),
              if (item.enabledSource != 'default')
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    key: ValueKey('plugin-enabled-source-${item.id}'),
                    item.enabledSource == 'workspace'
                        ? uiText(context, '工作区覆盖', 'Workspace override')
                        : _enabledSourceLabel(item),
                    style: TextStyle(fontSize: 11, color: ink.subtlest),
                  ),
                ),
            ],
          );
          final icon = Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: ink.surfaceFill,
              borderRadius: BorderRadius.circular(ZRadius.lg),
            ),
            child: const LucideIcon('blocks', size: 18),
          );
          final actions = Wrap(
            spacing: 2,
            runSpacing: 2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              if (item.installed)
                Switch(
                  key: ValueKey('plugin-enabled-${item.id}'),
                  value: item.enabled,
                  onChanged:
                      busy ? null : (value) => unawaited(_toggle(item, value)),
                ),
              PopupMenuButton<String>(
                key: ValueKey('plugin-actions-${item.id}'),
                enabled: !busy,
                onSelected: (action) {
                  switch (action) {
                    case 'use':
                      _use(item);
                    case 'update':
                      unawaited(widget.catalog.update(item));
                    case 'configure':
                      unawaited(_configure(item));
                    case 'reset':
                      unawaited(_resetUserDefault(item));
                    case 'restore':
                      unawaited(widget.catalog.restore(item));
                    case 'uninstall':
                      unawaited(_uninstall(item));
                  }
                },
                itemBuilder: (context) => [
                  if (item.enabled)
                    PopupMenuItem(
                        value: 'use',
                        child: Text(
                            uiText(context, '在新任务中使用', 'Use in new task'))),
                  if (item.canUpdate)
                    PopupMenuItem(
                        value: 'update',
                        child: Text(uiText(context, '更新', 'Update'))),
                  if (item.userConfig.isNotEmpty)
                    PopupMenuItem(
                        value: 'configure',
                        child: Text(uiText(context, '配置', 'Configure'))),
                  if (_scope == 'workspace' &&
                      item.enabledSource == 'workspace')
                    PopupMenuItem(
                        value: 'reset',
                        child: Text(
                            uiText(context, '恢复用户默认', 'Restore user default'))),
                  if (item.restorable && !item.installed)
                    PopupMenuItem(
                        value: 'restore',
                        child: Text(uiText(context, '恢复', 'Restore'))),
                  if (item.installed)
                    PopupMenuItem(
                        value: 'uninstall',
                        child: Text(uiText(context, '卸载', 'Uninstall'))),
                ],
                icon: const LucideIcon('ellipsis', size: 16),
              ),
            ],
          );
          final wide = constraints.maxWidth >= 520;
          final content = wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    icon,
                    const SizedBox(width: 10),
                    Expanded(child: details),
                    const SizedBox(width: 8),
                    actions,
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        icon,
                        const SizedBox(width: 10),
                        Expanded(child: details),
                      ],
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: actions,
                      ),
                    ),
                  ],
                );
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: content,
          );
        },
      ),
    );
  }

  Widget _card(List<CatalogPlugin> items, InkTokens ink) {
    if (items.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
        decoration: BoxDecoration(
          color: ink.card,
          borderRadius: BorderRadius.circular(ZRadius.xl),
          border: Border.all(color: ink.border),
        ),
        child: Text(
          uiText(context, '此范围没有已安装插件。', 'No plugins installed in this scope.'),
          textAlign: TextAlign.center,
          style: TextStyle(color: ink.subtlest),
        ),
      );
    }
    return Container(
      key: const ValueKey('plugins-installed-card'),
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(ZRadius.xl),
        border: Border.all(color: ink.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          for (var index = 0; index < items.length; index++) ...[
            if (index > 0) Divider(height: 1, color: ink.border),
            _row(items[index], ink),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    if (_detailItem != null) {
      return SingleChildScrollView(
        padding: widget.embedded
            ? const EdgeInsets.only(bottom: 20)
            : const EdgeInsets.all(20),
        child: _detailsView(ink),
      );
    }
    final items = _marketplaceInstalled;
    final builtIns = _builtIns;
    final count = items.length + builtIns.length;
    final hasQuery = _query.trim().isNotEmpty;
    return SingleChildScrollView(
      padding: widget.embedded
          ? const EdgeInsets.only(bottom: 20)
          : const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.title != null)
            Text(widget.title!,
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          if (widget.workspaceScopeOptions.length > 1 &&
              widget.onWorkspaceScopeChanged != null) ...[
            SettingsScopePicker(
              options: widget.workspaceScopeOptions,
              selected: widget.selectedWorkspaceScope,
              onSelected: widget.onWorkspaceScopeChanged!,
            ),
            const SizedBox(height: 10),
          ],
          if (_scope == 'workspace')
            Container(
              key: const ValueKey('plugin-settings-workspace-scope-hint'),
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: ink.surfaceFill,
                borderRadius: BorderRadius.circular(ZRadius.lg),
              ),
              child: Text(
                uiText(context, '工作区显示当前有效配置；用户范围安装的插件也会继承显示。',
                    'Workspace shows the effective configuration, including enabled plugins installed for the user.'),
                style: TextStyle(fontSize: 12, color: ink.subtlest),
              ),
            ),
          if (_scope == 'workspace') const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final search = SizedBox(
                width: constraints.maxWidth < 520 ? double.infinity : 256,
                height: 36,
                child: TextField(
                  key: const ValueKey('plugins-search'),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(left: 10, right: 5),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: LucideIcon('search', size: 14),
                      ),
                    ),
                    prefixIconConstraints: const BoxConstraints(
                      minWidth: 28,
                      minHeight: 28,
                    ),
                    hintText: uiText(context, '搜索插件...', 'Search plugins...'),
                    border: const OutlineInputBorder(),
                  ),
                ),
              );
              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: double.infinity, child: _scopePicker()),
                    const SizedBox(height: 8),
                    Text('${uiText(context, '插件', 'Plugins')} $count'),
                    const SizedBox(height: 8),
                    search,
                  ],
                );
              }
              return Row(
                children: [
                  _scopePicker(),
                  const SizedBox(width: 10),
                  Text('${uiText(context, '插件', 'Plugins')} $count'),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: search,
                    ),
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 20),
          LayoutBuilder(
            builder: (context, constraints) {
              final actions = <Widget>[
                IconButton(
                  key: const ValueKey('plugins-refresh'),
                  tooltip: uiText(context, '刷新插件', 'Refresh plugins'),
                  onPressed:
                      widget.catalog.loading || widget.catalog.operation != null
                          ? null
                          : () => unawaited(widget.catalog.refresh()),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 32, height: 32),
                  icon: const LucideIcon('refresh-cw', size: 16),
                ),
                IconButton(
                  key: const ValueKey('plugins-sources'),
                  tooltip: uiText(context, '管理来源', 'Manage sources'),
                  onPressed: widget.catalog.operation != null
                      ? null
                      : () => unawaited(_manageSources()),
                  padding: EdgeInsets.zero,
                  constraints:
                      const BoxConstraints.tightFor(width: 32, height: 32),
                  icon: const LucideIcon('settings', size: 16),
                ),
                if (widget.onOpenMarketplace != null)
                  TextButton(
                    key: const ValueKey('plugins-manage'),
                    onPressed: widget.onOpenMarketplace,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 32),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(uiText(context, '管理插件', 'Manage plugins')),
                  ),
              ];
              final installed = Text(
                '${uiText(context, '已安装', 'Installed')} $count',
                style: const TextStyle(fontWeight: FontWeight.w600),
              );
              if (constraints.maxWidth < 520) {
                return Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [installed, ...actions],
                );
              }
              return Row(
                children: [
                  installed,
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(
                        spacing: 2,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: actions,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          if (widget.catalog.loading && widget.catalog.items.isEmpty)
            const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)))
          else if (widget.catalog.failed && widget.catalog.items.isEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    uiText(context, '插件列表读取失败，请重试。',
                        'Could not load plugins. Retry.'),
                    style: TextStyle(color: ink.diffRemoved)),
                const SizedBox(height: 8),
                OutlinedButton(
                    onPressed: () => unawaited(widget.catalog.refresh()),
                    child: Text(uiText(context, '重试', 'Retry'))),
              ],
            )
          else if (items.isEmpty && hasQuery && builtIns.isEmpty)
            Text(uiText(context, '没有匹配的插件。', 'No matching plugins.'),
                style: TextStyle(color: ink.subtlest))
          else if (items.isNotEmpty)
            _card(items, ink),
          if (builtIns.isNotEmpty) ...[
            const SizedBox(height: 18),
            Text(uiText(context, '内置', 'Built-in'),
                style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            _card(builtIns, ink),
          ],
          if (items.isEmpty && builtIns.isEmpty && !hasQuery)
            _card(const <CatalogPlugin>[], ink),
          if (widget.catalog.failed && widget.catalog.items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Text(
                  uiText(context, '最新插件状态未确认，请刷新。',
                      'The latest plugin state could not be confirmed. Refresh.'),
                  style: TextStyle(color: ink.diffRemoved)),
            ),
        ],
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }
}

class _PluginDetailsResult {
  const _PluginDetailsResult.data(this.details)
      : error = null,
        stackTrace = null;

  const _PluginDetailsResult.failure(this.error, this.stackTrace)
      : details = null;

  final Map<String, dynamic>? details;
  final Object? error;
  final StackTrace? stackTrace;

  bool get hasError => error != null;
}

class _PluginConfigurationDialog extends StatefulWidget {
  const _PluginConfigurationDialog({required this.catalog, required this.item});

  final PluginCatalog catalog;
  final CatalogPlugin item;

  @override
  State<_PluginConfigurationDialog> createState() =>
      _PluginConfigurationDialogState();
}

class _PluginConfigurationDialogState
    extends State<_PluginConfigurationDialog> {
  late final Map<String, dynamic> _initialValues;
  final _editedValues = <String, dynamic>{};
  final _clearPending = <String>{};
  final _secretVisible = <String, bool>{};
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final configured = widget.item.configuredValues;
    _initialValues = {
      for (final entry in widget.item.userConfig.entries)
        entry.key: configured.containsKey(entry.key)
            ? configured[entry.key]
            : _optionDefault(entry.value),
    };
  }

  dynamic _optionDefault(dynamic option) {
    if (option is Map) {
      for (final key in ['value', 'default', 'defaultValue']) {
        if (option.containsKey(key)) return option[key];
      }
      return null;
    }
    return option;
  }

  Map<String, dynamic> _optionMeta(dynamic option) => option is Map
      ? option.cast<String, dynamic>()
      : const <String, dynamic>{};

  String _text(dynamic value) => value is String ? value : '';

  bool _same(dynamic left, dynamic right) {
    if (left is num && right is num) return left == right;
    return left == right;
  }

  dynamic _valueFor(String key) => _clearPending.contains(key)
      ? null
      : (_editedValues[key] ?? _initialValues[key]);

  void _setEdit(String key, dynamic value) {
    _clearPending.remove(key);
    if (_same(value, _initialValues[key])) {
      _editedValues.remove(key);
    } else {
      _editedValues[key] = value;
    }
    setState(() {});
  }

  bool _canClear(String key, Map<String, dynamic> meta) {
    final source = _text(widget.item.optionSources[key]).trim().toLowerCase();
    final scope = widget.catalog.effectiveScope;
    return ((meta['sensitive'] == true) || scope == 'workspace') &&
        (_clearPending.contains(key) || source == scope);
  }

  ({Map<String, dynamic> options, List<String> clearOptionKeys}) _delta() {
    final options = <String, dynamic>{};
    for (final entry in _editedValues.entries) {
      final option = _optionMeta(widget.item.userConfig[entry.key]);
      final type = _text(option['type']).trim().toLowerCase();
      final value = entry.value;
      if (option['sensitive'] == true &&
          value is String &&
          value.trim().isEmpty) {
        continue;
      }
      if (type == 'number') {
        final parsed = value is num ? value : num.tryParse('$value');
        if (parsed == null || !parsed.isFinite) continue;
        if (!_same(parsed, _initialValues[entry.key])) {
          options[entry.key] = parsed;
        }
        continue;
      }
      if (!_same(value, _initialValues[entry.key])) options[entry.key] = value;
    }
    final clear = _clearPending.toList()..sort();
    return (options: options, clearOptionKeys: clear);
  }

  Widget _clearButton(String key, {required bool pending}) => IconButton(
        key: ValueKey('plugin-config-clear-$key'),
        tooltip: pending
            ? uiText(context, '撤销清除', 'Undo clear')
            : uiText(context, '清除', 'Clear'),
        onPressed: _saving
            ? null
            : () => setState(() {
                  if (pending) {
                    _clearPending.remove(key);
                  } else {
                    _clearPending.add(key);
                    _editedValues.remove(key);
                  }
                }),
        icon: LucideIcon(pending ? 'undo-2' : 'x', size: 16),
      );

  Future<void> _save() async {
    if (_saving) return;
    final delta = _delta();
    if (delta.options.isEmpty && delta.clearOptionKeys.isEmpty) {
      if (mounted) Navigator.pop(context);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final ok = await widget.catalog.configure(
      widget.item,
      delta.options,
      scope: widget.catalog.effectiveScope,
      clearOptionKeys: delta.clearOptionKeys,
    );
    if (!mounted) return;
    if (ok) {
      Navigator.pop(context);
    } else {
      setState(() {
        _saving = false;
        _error = uiText(context, '保存失败，已保留当前配置。',
            'Save failed. The current configuration was kept.');
      });
    }
  }

  Widget _field(String key, dynamic option) {
    final meta = _optionMeta(option);
    final label =
        _text(meta['title']).trim().isEmpty ? key : _text(meta['title']).trim();
    final type = _text(meta['type']).trim().toLowerCase();
    final sensitive = meta['sensitive'] == true;
    final current = _valueFor(key);
    if (type == 'boolean' || current is bool) {
      final clear = _canClear(key, meta);
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(label),
              subtitle: _text(widget.item.optionSources[key]).trim().isEmpty
                  ? null
                  : Text(
                      '${uiText(context, '来源', 'Source')}: ${_text(widget.item.optionSources[key])}'),
              value: current == true,
              onChanged: _saving ? null : (value) => _setEdit(key, value),
            ),
          ),
          if (clear) _clearButton(key, pending: _clearPending.contains(key)),
        ],
      );
    }
    final clear = _canClear(key, meta);
    final pending = _clearPending.contains(key);
    final source = _text(widget.item.optionSources[key]).trim().toLowerCase();
    final helper = [
      if (_text(meta['description']).trim().isNotEmpty)
        _text(meta['description']).trim(),
      if (meta['required'] == true) uiText(context, '必填', 'Required'),
      if (source.isNotEmpty)
        '${uiText(context, '来源', 'Source')}: ${source == 'workspace' ? uiText(context, '工作区', 'Workspace') : source == 'user' ? uiText(context, '用户', 'User') : uiText(context, '默认', 'Default')}',
    ].join(' · ');
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextFormField(
            key: ValueKey(
                'plugin-config-field-$key-${pending ? 'clear' : 'value'}'),
            initialValue: current?.toString() ?? '',
            enabled: !_saving,
            obscureText: sensitive && _secretVisible[key] != true,
            keyboardType:
                type == 'number' ? TextInputType.number : TextInputType.text,
            decoration: InputDecoration(
              labelText: label,
              helperText: helper.isEmpty ? null : helper,
            ),
            onChanged: (value) => _setEdit(key, value),
          ),
        ),
        if (sensitive)
          IconButton(
            key: ValueKey(
                'plugin-config-${_secretVisible[key] == true ? 'hide' : 'show'}-$key'),
            tooltip: _secretVisible[key] == true
                ? uiText(context, '隐藏', 'Hide')
                : uiText(context, '显示', 'Show'),
            onPressed: _saving
                ? null
                : () => setState(
                    () => _secretVisible[key] = _secretVisible[key] != true),
            icon: LucideIcon(_secretVisible[key] == true ? 'eye-off' : 'eye',
                size: 16),
          ),
        if (clear) _clearButton(key, pending: pending),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('plugin-configuration-dialog'),
      title:
          Text(pluginDisplayName(widget.item, Localizations.localeOf(context))),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final entry in widget.item.userConfig.entries)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: _field(entry.key, entry.value),
                ),
              if (_error != null)
                Text(_error!,
                    style: TextStyle(
                        color: ZInk.of(Theme.of(context).colorScheme)
                            .diffRemoved)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(uiText(context, '取消', 'Cancel')),
        ),
        FilledButton(
          key: const ValueKey('plugin-configuration-save'),
          onPressed: _saving ? null : _save,
          child: Text(uiText(context, '保存', 'Save')),
        ),
      ],
    );
  }
}
