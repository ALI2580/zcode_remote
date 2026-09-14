import 'dart:async';

import 'package:flutter/material.dart';

import '../state/composer_input.dart';
import '../state/client_preferences.dart';
import '../state/plugin_catalog.dart';
import '../state/settings_import.dart';
import '../state/skills_catalog.dart';
import 'settings_import_dialog.dart';
import 'settings_scope.dart';
import 'official_icons.dart';
import 'plugin_display_name.dart';
import 'theme.dart';

/// Data passed to the parent when the user asks to start a skill-creator task.
/// The callback only prepares a draft; it never sends a task or calls a
/// createSkill RPC. The parent owns the existing @draft conflict decision.
class SkillCreatorDraft {
  const SkillCreatorDraft({
    required this.provider,
    required this.initialPrompt,
    required this.initialPromptMention,
    required this.reference,
    this.source,
  });

  final String provider;
  final String initialPrompt;
  final Map<String, dynamic> initialPromptMention;
  final ComposerReference reference;
  final SkillEntry? source;

  Map<String, dynamic> get request => {
        'provider': provider,
        'initialPrompt': initialPrompt,
        'initialPromptMention': initialPromptMention,
      };
}

/// Complete skills settings surface. It is deliberately standalone so the
/// settings center can connect its current bridge and Composer policy later.
class SkillsSettingsPage extends StatefulWidget {
  const SkillsSettingsPage({
    super.key,
    required this.catalog,
    this.pluginCatalog,
    this.scope = 'user',
    this.onScopeChanged,
    this.workspaceScopeOptions = const [],
    this.selectedWorkspaceScope,
    this.onWorkspaceScopeChanged,
    this.settingsSyncService,
    this.onImport,
    this.onCreateTask,
    this.onCreateTaskPayload,
    this.onComposerRefresh,
    this.canOpenPath = false,
    this.onOpenPath,
    this.title,
  });

  final SkillsCatalog catalog;
  final PluginCatalog? pluginCatalog;
  final String scope;
  final ValueChanged<String>? onScopeChanged;
  final List<SettingsScopeOption> workspaceScopeOptions;
  final SettingsScopeOption? selectedWorkspaceScope;
  final FutureOr<void> Function(SettingsScopeOption option)?
      onWorkspaceScopeChanged;
  final SettingsSyncService? settingsSyncService;
  final FutureOr<void> Function()? onImport;
  final FutureOr<void> Function(SkillCreatorDraft draft)? onCreateTask;
  final FutureOr<void> Function(Map<String, dynamic> request)?
      onCreateTaskPayload;
  final FutureOr<void> Function()? onComposerRefresh;

  /// Parent must explicitly authorize opening a path through its remote-file
  /// viewer. This page never treats a remote path as a phone-local file.
  final bool canOpenPath;
  final FutureOr<void> Function(String path)? onOpenPath;
  final String? title;

  @override
  State<SkillsSettingsPage> createState() => _SkillsSettingsPageState();
}

class _SkillsSettingsPageState extends State<SkillsSettingsPage> {
  late String _scope;
  String _query = '';
  bool _diagnosticsExpanded = false;
  int _lastPluginConfigurationRevision = 0;
  int _pluginRefreshGeneration = 0;

  @override
  void initState() {
    super.initState();
    _scope = _validScope(widget.scope);
    widget.catalog.addListener(_changed);
    widget.pluginCatalog?.addListener(_changed);
    _lastPluginConfigurationRevision =
        widget.pluginCatalog?.configurationRevision ?? 0;
    unawaited(widget.catalog.refresh());
  }

  @override
  void didUpdateWidget(covariant SkillsSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog) {
      oldWidget.catalog.removeListener(_changed);
      widget.catalog.addListener(_changed);
      unawaited(widget.catalog.refresh());
    }
    if (oldWidget.pluginCatalog != widget.pluginCatalog) {
      oldWidget.pluginCatalog?.removeListener(_changed);
      widget.pluginCatalog?.addListener(_changed);
      _lastPluginConfigurationRevision =
          widget.pluginCatalog?.configurationRevision ?? 0;
    }
    if (oldWidget.scope != widget.scope ||
        !['user', 'workspace'].contains(_scope)) {
      _scope = _validScope(widget.scope);
    }
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_changed);
    widget.pluginCatalog?.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final plugin = widget.pluginCatalog;
    final revision = plugin?.configurationRevision ?? 0;
    if (plugin == null || revision == _lastPluginConfigurationRevision) {
      return;
    }
    _lastPluginConfigurationRevision = revision;
    final generation = ++_pluginRefreshGeneration;
    // A plugin write changes the remote skill projection. Refresh the full
    // skills snapshot after PluginCatalog has completed its authoritative
    // plugin readback; only this scope's page is affected.
    unawaited(() async {
      await widget.catalog.refresh(force: true);
      if (!mounted || generation != _pluginRefreshGeneration) return;
      setState(() {});
    }());
  }

  String _validScope(String value) => value == 'workspace' &&
          widget.catalog.workspacePath?.trim().isNotEmpty == true
      ? 'workspace'
      : 'user';

  String _scopeLabel(BuildContext context, String value) => value == 'workspace'
      ? uiText(context, '工作区', 'Workspace')
      : uiText(context, '用户', 'User');

  String _scopeReason(BuildContext context) {
    if (!widget.catalog.hasWorkspace) {
      return uiText(context, '需要已选择的工作区。', 'Select a workspace first.');
    }
    if (!widget.catalog.userScopeAvailable) {
      return widget.catalog.userScopeReason ??
          uiText(context, '当前连接不支持用户范围。',
              'The current connection does not support user scope.');
    }
    if (widget.settingsSyncService == null && widget.onImport == null) {
      return uiText(context, '导入服务不可用。', 'Import service is unavailable.');
    }
    return '';
  }

  bool get _canImport => _scopeReason(context).isEmpty;
  bool get _canCreate =>
      widget.catalog.hasWorkspace &&
      (widget.onCreateTask != null || widget.onCreateTaskPayload != null);

  List<SkillEntry> _localItems() {
    final normalized = _query.trim().toLowerCase();
    return [
      for (final item in widget.catalog.items)
        if (!item.isPlugin &&
            (item.scope == _scope ||
                (_scope == 'user' && item.scope == 'common')) &&
            _matches(item, normalized))
          item,
    ];
  }

  List<SkillEntry> _pluginItems() {
    final plugins = widget.pluginCatalog?.items ?? const <CatalogPlugin>[];
    final normalized = _query.trim().toLowerCase();
    return [
      for (final item in widget.catalog.items)
        if (item.isPlugin &&
            _pluginEnabledForScope(item, plugins) &&
            _matches(item, normalized))
          item,
    ];
  }

  bool _matches(SkillEntry item, String query) =>
      query.isEmpty ||
      '${item.name} ${item.description ?? ''}'.toLowerCase().contains(query);

  bool _pluginEnabledForScope(SkillEntry skill, List<CatalogPlugin> plugins) {
    final pluginId = skill.pluginId?.trim() ?? '';
    if (pluginId.isNotEmpty) {
      // An explicit id is authoritative. A same-name plugin from another
      // marketplace must never make this skill visible.
      final plugin = plugins.cast<CatalogPlugin?>().firstWhere(
            (item) => item?.id == pluginId,
            orElse: () => null,
          );
      return plugin != null && plugin.installed && plugin.enabled;
    }

    final name = skill.pluginName?.trim().toLowerCase() ?? '';
    final marketplace = skill.pluginMarketplace?.trim().toLowerCase() ?? '';
    if (name.isEmpty || marketplace.isEmpty) return false;
    final candidates = plugins
        .where((plugin) =>
            plugin.name.trim().toLowerCase() == name &&
            plugin.marketplace.trim().toLowerCase() == marketplace)
        .toList(growable: false);
    // The fallback is safe only for one confirmed marketplace/name identity.
    if (candidates.length != 1) return false;
    final plugin = candidates.single;
    return plugin.installed && plugin.enabled;
  }

  Map<String, List<SkillEntry>> _pluginGroups(List<SkillEntry> items) {
    final groups = <String, List<SkillEntry>>{};
    for (final item in items) {
      final key = item.pluginId?.trim().isNotEmpty == true
          ? item.pluginId!.trim()
          : (item.pluginName?.trim().isNotEmpty == true
              ? item.pluginName!.trim()
              : 'plugin');
      groups.putIfAbsent(key, () => <SkillEntry>[]).add(item);
    }
    return groups;
  }

  String _pluginLabel(String key, List<CatalogPlugin> plugins) {
    for (final plugin in plugins) {
      if (plugin.id == key) return _pluginGroupLabel(plugin.name);
    }
    return _pluginGroupLabel(key);
  }

  String _pluginGroupLabel(String value) {
    final plugin = (widget.pluginCatalog?.items ?? const <CatalogPlugin>[])
        .where((item) => item.name == value || item.id == value)
        .firstOrNull;
    return plugin == null
        ? formatPluginName(value)
        : pluginDisplayName(plugin, Localizations.localeOf(context));
  }

  Future<void> _toggle(SkillEntry item, bool enabled) async {
    final catalog = widget.catalog;
    final composerRefresh = widget.onComposerRefresh;
    final ok = await catalog.setEnabled(item, enabled);
    if (!mounted) return;
    if (!ok) {
      final value = catalog.operationError(item) ?? catalog.error;
      _showError(value?.toString() ??
          uiText(context, '启停技能失败，请重试。', 'Could not update the skill.'));
    } else {
      await composerRefresh?.call();
    }
  }

  Future<void> _delete(SkillEntry item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiText(context, '删除技能', 'Delete skill')),
        content: Text(
            uiText(context, '确定删除「${item.name}」吗？', 'Delete “${item.name}”?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(uiText(context, '取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(uiText(context, '删除', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final catalog = widget.catalog;
    final composerRefresh = widget.onComposerRefresh;
    final ok = await catalog.deleteSkill(item);
    if (!mounted || ok) {
      if (ok) await composerRefresh?.call();
      return;
    }
    final value = catalog.operationError(item) ?? catalog.error;
    _showError(value?.toString() ??
        uiText(context, '删除技能失败，请重试。', 'Could not delete the skill.'));
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openImport() async {
    if (!_canImport) return;
    final service = widget.settingsSyncService;
    final catalog = widget.catalog;
    final composerRefresh = widget.onComposerRefresh;
    final importCallback = widget.onImport;
    if (service != null) {
      await SettingsImportDialog.show(
        context,
        service: service,
        category: 'skills',
        workspacePath: widget.catalog.workspacePath,
        workspaceIdentity: widget.catalog.workspaceIdentity,
        onImported: () async {
          await catalog.refresh();
          await composerRefresh?.call();
        },
      );
    } else {
      await importCallback?.call();
    }
  }

  void _createSkill() {
    if (!_canCreate) return;
    final entries = widget.catalog.items.where((item) =>
        !item.isPlugin && item.name.trim().toLowerCase() == 'skill-creator');
    final source = entries.isEmpty ? null : entries.first;
    final reference = ComposerReference(
      id: 'skill:${source?.id ?? 'skill-creator'}',
      category: 'skills',
      label: 'skill-creator',
      value: source?.path ?? '',
      description: source?.description ?? '',
      scope: source?.scope ?? '',
    );
    final mention = <String, dynamic>{
      'id': reference.id,
      'category': 'skills',
      'label': 'skill-creator',
      // The mention token is the skill name; ComposerReference.value stays
      // path-backed so its markdown retains the real skill link.
      'value': 'skill-creator',
      'markdown': reference.markdown,
      if (source?.description?.isNotEmpty == true)
        'description': source!.description,
      if (source != null) 'data': {'path': source.path, 'scope': source.scope},
    };
    final draft = SkillCreatorDraft(
      provider: widget.catalog.provider,
      initialPrompt: '${reference.markdown} ',
      initialPromptMention: mention,
      reference: reference,
      source: source,
    );
    final callback = widget.onCreateTask;
    if (callback != null) {
      unawaited(() async {
        await callback(draft);
      }());
    } else {
      unawaited(() async {
        await widget.onCreateTaskPayload!(draft.request);
      }());
    }
  }

  Future<void> _openPath(SkillEntry item) async {
    if (!widget.canOpenPath || widget.onOpenPath == null || item.path.isEmpty) {
      return;
    }
    try {
      await widget.onOpenPath!(item.path);
    } catch (error) {
      if (mounted) _showError(error.toString());
    }
  }

  String _diagnosticCode(SkillDiagnostic item) => item.code;

  Future<void> _showDetail(SkillEntry item) async {
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => _SkillDetailDialog(
        item: item,
        canOpenPath: widget.canOpenPath && widget.onOpenPath != null,
        onOpenPath: () => _openPath(item),
      ),
    );
  }

  Widget _scopePicker(InkTokens ink) {
    final values = <String>[
      'user',
      if (widget.catalog.hasWorkspace) 'workspace'
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ink.hover,
        borderRadius: BorderRadius.circular(ZRadius.xl),
      ),
      child: SizedBox(
        width: 88,
        height: 32,
        child: Row(
          children: [
            const SizedBox(width: 8),
            Icon(Icons.desktop_windows_outlined, size: 14, color: ink.text),
            const SizedBox(width: 3),
            Expanded(
              child: DropdownButton<String>(
                key: const ValueKey('skills-scope'),
                value: values.contains(_scope) ? _scope : values.first,
                isDense: true,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                padding: EdgeInsets.zero,
                icon: const LucideIcon('chevron-down', size: 12),
                style: TextStyle(fontSize: 13, color: ink.text),
                onChanged: (value) {
                  if (value == null || value == _scope) return;
                  setState(() {
                    _scope = value;
                    _query = '';
                  });
                  widget.onScopeChanged?.call(value);
                },
                items: [
                  for (final value in values)
                    DropdownMenuItem(
                      value: value,
                      child: Text(_scopeLabel(context, value)),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 5),
          ],
        ),
      ),
    );
  }

  int _scopeCount() {
    return _localItems().length + _pluginItems().length;
  }

  Widget _topBar(InkTokens ink) => LayoutBuilder(
        builder: (context, constraints) {
          final search = SizedBox(
            width: 256,
            height: 32,
            child: TextField(
              key: const ValueKey('skills-search'),
              onChanged: (value) => setState(() => _query = value),
              style: const TextStyle(fontSize: 13),
              decoration: InputDecoration(
                isDense: true,
                hintText: uiText(context, '搜索技能...', 'Search skills...'),
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(left: 10, right: 5),
                  child: LucideIcon('search', size: 14),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ZRadius.lg),
                  borderSide: BorderSide(color: ink.border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ZRadius.lg),
                  borderSide: BorderSide(color: ink.border),
                ),
              ),
            ),
          );
          final header = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _scopePicker(ink),
              const SizedBox(width: 26),
              Text(
                uiText(
                    context, '技能 ${_scopeCount()}', 'Skills ${_scopeCount()}'),
                style:
                    const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ],
          );
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                header,
                const SizedBox(height: 8),
                SizedBox(width: double.infinity, child: search),
              ],
            );
          }
          return Row(children: [header, const Spacer(), search]);
        },
      );

  Widget _actions(InkTokens ink) {
    final reason = _scopeReason(context);
    final import = PopupMenuButton<String>(
      key: const ValueKey('skills-more'),
      tooltip: _canImport ? uiText(context, '更多', 'More') : reason,
      padding: EdgeInsets.zero,
      icon: const LucideIcon('ellipsis', size: 16),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          key: const ValueKey('skills-import'),
          value: 'import',
          enabled: _canImport,
          child: Text(uiText(context, '导入', 'Import')),
        ),
      ],
      onSelected: (value) {
        if (value == 'import') unawaited(_openImport());
      },
    );
    final createReason = !widget.catalog.hasWorkspace
        ? uiText(context, '需要已选择的工作区。', 'Select a workspace first.')
        : widget.onCreateTask == null && widget.onCreateTaskPayload == null
            ? uiText(context, '新建任务回调不可用。', 'Create task is unavailable.')
            : '';
    final create = Tooltip(
      message: _canCreate
          ? uiText(
              context, '准备 skill-creator 草稿', 'Prepare skill-creator draft')
          : createReason,
      child: FilledButton.icon(
        key: const ValueKey('skills-new'),
        onPressed: _canCreate ? _createSkill : null,
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          textStyle: const TextStyle(fontSize: 13),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ZRadius.lg)),
        ),
        icon: const LucideIcon('plus', size: 14),
        label: Text(uiText(context, '新建', 'New')),
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        import,
        IconButton(
          key: const ValueKey('skills-refresh'),
          onPressed: widget.catalog.status == SkillsStatus.loading
              ? null
              : () => unawaited(widget.catalog.refresh()),
          tooltip: uiText(context, '刷新', 'Refresh'),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          icon: const LucideIcon('refresh-cw', size: 15),
        ),
        const SizedBox(width: 8),
        create,
      ],
    );
  }

  Widget _diagnostics(InkTokens ink) {
    final list = widget.catalog.diagnostics;
    if (list.isEmpty) return const SizedBox.shrink();
    final errors = widget.catalog.errorCount;
    final warnings = widget.catalog.warningCount;
    final summary = uiText(context, '诊断：$errors 个错误，$warnings 个警告',
        'Diagnostics: $errors errors, $warnings warnings');
    return Container(
      key: const ValueKey('skills-diagnostics'),
      decoration: BoxDecoration(
        color: ink.warning.withValues(alpha: .10),
        border: Border.all(color: ink.warning.withValues(alpha: .45)),
        borderRadius: BorderRadius.circular(ZRadius.lg),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () =>
                setState(() => _diagnosticsExpanded = !_diagnosticsExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(
                children: [
                  Icon(
                    _diagnosticsExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 17,
                  ),
                  const SizedBox(width: 6),
                  Icon(Icons.warning_amber_rounded,
                      size: 17, color: ink.warning),
                  const SizedBox(width: 7),
                  Expanded(child: Text(summary)),
                ],
              ),
            ),
          ),
          if (_diagnosticsExpanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: Column(
                children: [
                  const Divider(height: 1),
                  for (final item in list)
                    ListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Wrap(
                        spacing: 7,
                        children: [
                          Text(item.severity.toUpperCase(),
                              style: TextStyle(
                                  color: item.isError
                                      ? ink.diffRemoved
                                      : ink.warning,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700)),
                          Text(_diagnosticCode(item),
                              style: const TextStyle(fontSize: 12)),
                          if (item.skillName != null) Text(item.skillName!),
                        ],
                      ),
                      subtitle: Text(
                        [item.message, if (item.path != null) item.path!]
                            .where((value) => value.isNotEmpty)
                            .join('\n'),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _skillIcon(SkillEntry item, InkTokens ink) {
    final name = item.name.toLowerCase();
    if (name.contains('browser') || name.contains('web')) {
      return const Icon(Icons.web_asset_outlined, size: 17);
    }
    if (name.contains('doc') || name.contains('pdf')) {
      return const LucideIcon('file-text', size: 17);
    }
    if (name.contains('computer') || name.contains('terminal')) {
      return const LucideIcon('square-terminal', size: 17);
    }
    return Icon(Icons.auto_awesome_outlined, size: 17, color: ink.subtlest);
  }

  Widget _row(SkillEntry item, InkTokens ink) {
    final writing = widget.catalog.isWriting(item);
    final writable = item.isWritable;
    final actions = <Widget>[
      if (writable)
        _SkillCompactSwitch(
          key: ValueKey('skill-enabled-${item.id}-${item.scope}'),
          value: item.enabled,
          onChanged:
              writing ? null : (value) => unawaited(_toggle(item, value)),
        ),
      if (writable)
        IconButton(
          key: ValueKey('skill-delete-${item.id}-${item.scope}'),
          tooltip: uiText(context, '删除', 'Delete'),
          onPressed: writing ? null : () => unawaited(_delete(item)),
          icon: const Icon(Icons.delete_outline, size: 18),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth.isFinite && constraints.maxWidth < 520;
        final primary = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: ink.surfaceFill,
                borderRadius: BorderRadius.circular(ZRadius.lg),
              ),
              child: Center(child: _skillIcon(item, ink)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.name,
                      key: ValueKey('skill-row-${item.id}-${item.scope}'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    item.description?.isNotEmpty == true
                        ? item.description!
                        : uiText(context, '暂无描述', 'No description'),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 12, color: ink.subtlest),
                  ),
                ],
              ),
            ),
          ],
        );
        final actionRow = Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 2,
          children: actions,
        );
        return InkWell(
          key: ValueKey('skill-item-${item.id}-${item.scope}'),
          onTap: () => unawaited(_showDetail(item)),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      primary,
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Align(
                            alignment: Alignment.centerRight, child: actionRow),
                      ],
                    ],
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: primary),
                      if (actions.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        actionRow,
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _emptyCard(InkTokens ink) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 168),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      decoration: BoxDecoration(
        color: ink.background,
        borderRadius: BorderRadius.circular(ZRadius.xl),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(uiText(context, '尚未安装技能', 'No skills installed'),
              style: const TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(
            uiText(context, '新建技能，或从外部 Agent 导入已有技能。',
                'Create a skill, or import an existing skill from an external Agent.'),
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: ink.subtlest),
          ),
          const SizedBox(height: 14),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                key: const ValueKey('skills-empty-new'),
                onPressed: _canCreate ? _createSkill : null,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(fontSize: 13),
                ),
                icon: const LucideIcon('plus', size: 14),
                label: Text(uiText(context, '新建技能', 'New skill')),
              ),
              OutlinedButton.icon(
                key: const ValueKey('skills-empty-import'),
                onPressed: _canImport ? () => unawaited(_openImport()) : null,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  textStyle: const TextStyle(fontSize: 13),
                ),
                icon: const LucideIcon('arrow-down', size: 14),
                label: Text(uiText(context, '导入', 'Import')),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _card(List<SkillEntry> items, InkTokens ink) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Text(
            uiText(
                context, '此范围没有已安装技能。', 'No skills installed in this scope.'),
            style: TextStyle(color: ink.subtlest)),
      );
    }
    return Container(
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

  Widget _content(InkTokens ink) {
    final state = widget.catalog.status;
    if (state == SkillsStatus.loading && widget.catalog.items.isEmpty) {
      return const Padding(
          padding: EdgeInsets.symmetric(vertical: 24),
          child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (state == SkillsStatus.error && widget.catalog.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              uiText(context, '技能列表读取失败，请重试。', 'Could not read skills. Retry.'),
              style: TextStyle(color: ink.diffRemoved)),
          const SizedBox(height: 10),
          OutlinedButton(
              onPressed: () => unawaited(widget.catalog.refresh()),
              child: Text(uiText(context, '重试', 'Retry'))),
        ],
      );
    }
    final local = _localItems();
    final plugins = widget.pluginCatalog?.items ?? const <CatalogPlugin>[];
    final pluginGroups = _pluginGroups(_pluginItems());
    final visibleCount = local.length +
        pluginGroups.values.fold<int>(0, (sum, rows) => sum + rows.length);
    if (_query.trim().isNotEmpty && visibleCount == 0) {
      return Text(uiText(context, '没有匹配的技能。', 'No matching skills.'),
          style: TextStyle(color: ink.subtlest));
    }
    final count = local.length;
    final installedActions = _actions(ink);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(builder: (context, constraints) {
          final compact =
              constraints.maxWidth.isFinite && constraints.maxWidth < 520;
          final label = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(uiText(context, '已安装', 'Installed'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 6),
              Text('$count', style: TextStyle(color: ink.subtlest)),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                label,
                const SizedBox(height: 6),
                Align(
                    alignment: Alignment.centerRight, child: installedActions),
              ],
            );
          }
          return Row(children: [label, const Spacer(), installedActions]);
        }),
        const SizedBox(height: 8),
        if (local.isEmpty) _emptyCard(ink) else _card(local, ink),
        for (final entry in pluginGroups.entries) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text(
                  _pluginLabel(entry.key, plugins),
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              Text('${entry.value.length}',
                  style: TextStyle(color: ink.subtlest)),
            ],
          ),
          const SizedBox(height: 8),
          _card(entry.value, ink),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return ListenableBuilder(
      listenable: widget.catalog,
      builder: (context, _) => SingleChildScrollView(
        // SettingsCenter owns the shared title and 28px content gutter.
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.title != null)
              Text(widget.title!,
                  style: const TextStyle(
                      fontSize: 18, fontWeight: FontWeight.w600)),
            if (widget.workspaceScopeOptions.length > 1 &&
                widget.onWorkspaceScopeChanged != null) ...[
              SettingsScopePicker(
                options: widget.workspaceScopeOptions,
                selected: widget.selectedWorkspaceScope,
                onSelected: widget.onWorkspaceScopeChanged!,
              ),
              const SizedBox(height: 10),
            ],
            _topBar(ink),
            const SizedBox(height: 14),
            if (!widget.catalog.userScopeAvailable)
              Container(
                key: const ValueKey('skills-scope-reason'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: ink.surfaceFill,
                  borderRadius: BorderRadius.circular(ZRadius.lg),
                ),
                child: Text(_scopeReason(context),
                    style: TextStyle(color: ink.subtlest)),
              ),
            if (widget.catalog.diagnostics.isNotEmpty) ...[
              _diagnostics(ink),
              const SizedBox(height: 12),
            ],
            _content(ink),
          ],
        ),
      ),
    );
  }
}

class _SkillCompactSwitch extends StatelessWidget {
  const _SkillCompactSwitch({
    super.key,
    required this.value,
    this.onChanged,
  });

  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 48,
      height: 36,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: onChanged == null ? null : () => onChanged!(!value),
            ),
          ),
          Transform.scale(
            scale: .62,
            child: Switch(
              value: value,
              onChanged: onChanged,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillDetailDialog extends StatelessWidget {
  const _SkillDetailDialog({
    required this.item,
    required this.canOpenPath,
    required this.onOpenPath,
  });

  final SkillEntry item;
  final bool canOpenPath;
  final VoidCallback onOpenPath;

  Widget _field(BuildContext context, String label, String? value,
      {bool mono = false}) {
    if (value == null || value.trim().isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(value,
            style: TextStyle(
                color: ZInk.of(Theme.of(context).colorScheme).subtlest,
                fontFamily: mono ? 'monospace' : null),
            softWrap: true),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      key: const ValueKey('skill-detail'),
      title: Text(item.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
        child: SingleChildScrollView(
          child: Builder(
            builder: (context) {
              final compact = MediaQuery.sizeOf(context).width < 560;
              final fields = [
                _field(context, uiText(context, '范围', 'Scope'), item.scope),
                _field(
                    context,
                    uiText(context, '状态', 'Status'),
                    item.enabled
                        ? uiText(context, '已启用', 'Enabled')
                        : uiText(context, '已停用', 'Disabled')),
                _field(context, uiText(context, '版本', 'Version'), item.version,
                    mono: true),
                _field(context, uiText(context, 'Slug', 'Slug'), item.slug,
                    mono: true),
                _field(context, uiText(context, '发布时间', 'Published at'),
                    item.publishedAt,
                    mono: true),
                _field(context, uiText(context, 'Owner ID', 'Owner ID'),
                    item.ownerId,
                    mono: true),
              ];
              final detail = Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(
                      context,
                      uiText(context, '描述', 'Description'),
                      item.description ??
                          uiText(context, '暂无描述', 'No description')),
                  const SizedBox(height: 16),
                  if (compact)
                    ...fields
                        .expand((field) => [field, const SizedBox(height: 12)])
                  else
                    Wrap(
                      spacing: 24,
                      runSpacing: 14,
                      children: [
                        for (final field in fields)
                          SizedBox(width: 230, child: field)
                      ],
                    ),
                  if (item.path.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _field(context, uiText(context, '路径', 'Path'), item.path,
                        mono: true),
                    if (canOpenPath) ...[
                      const SizedBox(height: 8),
                      OutlinedButton.icon(
                        key: const ValueKey('skill-open-path'),
                        onPressed: onOpenPath,
                        icon: const Icon(Icons.open_in_new, size: 16),
                        label: Text(uiText(context, '打开路径', 'Open path')),
                      ),
                    ],
                  ],
                ],
              );
              return detail;
            },
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(uiText(context, '关闭', 'Close')),
        ),
      ],
    );
  }
}
