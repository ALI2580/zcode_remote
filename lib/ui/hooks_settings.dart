import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../state/client_preferences.dart';
import '../state/plugin_catalog.dart';
import '../state/remote_agent_catalogs.dart';
import 'official_icons.dart';
import 'settings_scope.dart';
import 'theme.dart';

/// The exact identity and digests required by the existing workspace-hook
/// review flow. The page does not invent a trust RPC; the owner wires this to
/// WorkspaceHookReviewController/ConversationTransport.
class WorkspaceHookTrustRequest {
  const WorkspaceHookTrustRequest({
    required this.hook,
    required this.workspacePath,
    required this.workspaceIdentity,
    required this.bundleDigest,
    required this.hookDeclarationDigest,
    required this.reviewItemId,
  });

  final WorkspaceHook hook;
  final String? workspacePath;
  final String? workspaceIdentity;
  final String? bundleDigest;
  final String? hookDeclarationDigest;
  final String? reviewItemId;
}

class WorkspaceHookTrustResult {
  const WorkspaceHookTrustResult({
    required this.accepted,
    this.reasonCode,
  });

  final bool accepted;
  final String? reasonCode;
}

typedef WorkspaceHookTrustHandler = Future<WorkspaceHookTrustResult> Function(
    WorkspaceHookTrustRequest request);

/// Settings-center hooks page. It owns the list/form presentation while the
/// parent owns monitor selection and catalog lifecycle.
class HooksSettingsPage extends StatefulWidget {
  const HooksSettingsPage({
    super.key,
    required this.catalog,
    this.pluginCatalog,
    this.scopeOptions = const <SettingsScopeOption>[],
    this.selectedScopeKey = 'user',
    this.onScopeChanged,
    this.onTrustHook,
    this.onAfterMutation,
  });

  final HooksCatalog catalog;
  final PluginCatalog? pluginCatalog;
  final List<SettingsScopeOption> scopeOptions;
  final String selectedScopeKey;
  final FutureOr<bool> Function(String scopeKey)? onScopeChanged;
  final WorkspaceHookTrustHandler? onTrustHook;
  final FutureOr<void> Function()? onAfterMutation;

  @override
  State<HooksSettingsPage> createState() => _HooksSettingsPageState();
}

/// Alias kept for settings-center integrations that call the section by its
/// shorter name.
typedef HooksSettingsSection = HooksSettingsPage;

class _HooksSettingsPageState extends State<HooksSettingsPage> {
  String _scopeKey = 'user';
  String _query = '';
  WorkspaceHook? _editing;
  bool _showForm = false;
  bool _scopeChanging = false;
  String? _trustingId;
  int _operationGeneration = 0;
  final Map<String, String> _trustErrors = <String, String>{};
  final Map<String, bool> _toggleIntents = <String, bool>{};

  @override
  void initState() {
    super.initState();
    _scopeKey = widget.selectedScopeKey;
  }

  @override
  void didUpdateWidget(covariant HooksSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedScopeKey != widget.selectedScopeKey) {
      _scopeKey = widget.selectedScopeKey;
    }
    if (!identical(oldWidget.catalog, widget.catalog)) {
      _operationGeneration++;
      _trustingId = null;
      if (_showForm) {
        _showForm = false;
        _editing = null;
      }
    }
  }

  bool get _projectScope => _scopeKey != 'user';

  SettingsScopeOption? get _selectedWorkspace => widget.scopeOptions
      .where((option) => option.identity == _scopeKey)
      .cast<SettingsScopeOption?>()
      .firstOrNull;

  String _scopeLabel(BuildContext context) {
    if (!_projectScope) return uiText(context, '用户', 'User');
    final option = _selectedWorkspace;
    return option?.workspaceName ?? uiText(context, '工作区', 'Workspace');
  }

  void _openForm(WorkspaceHook? hook) {
    setState(() {
      _editing = hook;
      _showForm = true;
    });
  }

  Future<void> _selectScope(String? value) async {
    if (value == null || (value == _scopeKey && !_scopeChanging)) return;
    final generation = ++_operationGeneration;
    setState(() => _scopeChanging = true);
    final callback = widget.onScopeChanged;
    var accepted = true;
    if (callback != null) {
      try {
        accepted = await callback(value);
      } catch (_) {
        accepted = false;
      }
    }
    if (!mounted || generation != _operationGeneration) return;
    if (!accepted) {
      setState(() => _scopeChanging = false);
      return;
    }
    setState(() {
      _scopeKey = value;
      _query = '';
      _showForm = false;
      _editing = null;
      _trustingId = null;
      _trustErrors.clear();
      _scopeChanging = false;
    });
  }

  Future<void> _afterMutation() async {
    final callback = widget.onAfterMutation;
    if (callback != null) await callback();
  }

  Future<void> _toggle(WorkspaceHook hook, bool enabled) async {
    final generation = _operationGeneration;
    final catalog = widget.catalog;
    _toggleIntents[hook.id] = enabled;
    await catalog.setEnabled(hook, enabled);
    if (!mounted ||
        generation != _operationGeneration ||
        !identical(widget.catalog, catalog)) {
      return;
    }
    if (catalog.saveError('toggle-${hook.id}') == null) {
      _toggleIntents.remove(hook.id);
      await _afterMutation();
    }
  }

  Future<void> _trust(WorkspaceHook hook) async {
    final callback = widget.onTrustHook;
    if (callback == null || _trustingId != null) return;
    final generation = ++_operationGeneration;
    final catalog = widget.catalog;
    final scope = widget.catalog.scope;
    setState(() {
      _trustingId = hook.id;
      _trustErrors.remove(hook.id);
    });
    try {
      final result = await callback(WorkspaceHookTrustRequest(
        hook: hook,
        workspacePath: widget.catalog.workspacePath,
        workspaceIdentity: hook.workspaceIdentity ??
            (scope['workspaceIdentity'] is String
                ? scope['workspaceIdentity'] as String
                : null),
        bundleDigest: hook.bundleDigest,
        hookDeclarationDigest: hook.hookDeclarationDigest,
        reviewItemId: hook.reviewItemId,
      ));
      if (!mounted ||
          generation != _operationGeneration ||
          !identical(widget.catalog, catalog)) {
        return;
      }
      if (!result.accepted) {
        setState(() {
          _trustErrors[hook.id] = result.reasonCode?.trim().isNotEmpty == true
              ? result.reasonCode!
              : uiText(context, '信任未受理。', 'Trust was not accepted.');
        });
      } else {
        await catalog.refresh(force: true);
        if (!mounted ||
            generation != _operationGeneration ||
            !identical(widget.catalog, catalog)) {
          return;
        }
        if (catalog.status == RemoteAgentCatalogStatus.loaded) {
          await _afterMutation();
        }
      }
    } catch (value) {
      if (mounted) {
        setState(() {
          _trustErrors[hook.id] = '$value';
        });
      }
    } finally {
      if (mounted &&
          generation == _operationGeneration &&
          identical(widget.catalog, catalog)) {
        setState(() => _trustingId = null);
      }
    }
  }

  List<WorkspaceHook> _hooksForScope(List<WorkspaceHook> hooks) => [
        for (final hook in hooks)
          if ((hook.storageLevel == 'project') == _projectScope) hook,
      ];

  bool _matches(WorkspaceHook hook, String query) {
    if (query.isEmpty) return true;
    final values = <String>[
      hook.event,
      hook.matcher,
      hook.type,
      hook.command,
      ...hook.args,
      hook.statusMessage,
      hook.locationSource ?? '',
    ];
    return values.any((value) => value.toLowerCase().contains(query));
  }

  bool _matchesPlugin(Map<String, dynamic> detail, String query) {
    if (query.isEmpty) return true;
    final values = <String>[
      '${detail['event'] ?? ''}',
      '${detail['matcher'] ?? ''}',
      '${detail['type'] ?? ''}',
      '${detail['command'] ?? ''}',
      '${detail['sourcePath'] ?? ''}',
      if (detail['args'] is List)
        for (final arg in detail['args'] as List) '$arg',
    ];
    return values.any((value) => value.toLowerCase().contains(query));
  }

  bool _pluginMatchesScope(CatalogPlugin plugin) {
    final scope = plugin.installedScope?.toLowerCase();
    if (scope == null || scope.isEmpty) return true;
    if (!_projectScope) return scope == 'user';
    return scope == 'workspace' || scope == 'project';
  }

  List<_PluginHook> _pluginHooks(String query) {
    final plugins = widget.pluginCatalog?.items ?? const <CatalogPlugin>[];
    final result = <_PluginHook>[];
    for (final plugin in plugins) {
      if (!plugin.installed || !_pluginMatchesScope(plugin)) continue;
      for (final detail in plugin.hookDetails) {
        if (_matchesPlugin(detail, query)) {
          result.add(_PluginHook(plugin: plugin, detail: detail));
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final plugin = widget.pluginCatalog;
    return ListenableBuilder(
      listenable: widget.catalog,
      builder: (context, _) => plugin == null
          ? _body(context)
          : ListenableBuilder(
              listenable: plugin,
              builder: (context, _) => _body(context),
            ),
    );
  }

  Widget _body(BuildContext context) {
    if (_showForm) {
      return _HookFormPage(
        key: ValueKey<String>('hooks-form-${_editing?.id ?? 'new'}'),
        catalog: widget.catalog,
        existing: _editing,
        projectScope: _projectScope,
        scopeLabel: _scopeLabel(context),
        onCancel: () => setState(() {
          _showForm = false;
          _editing = null;
        }),
        onSaved: () async {
          setState(() {
            _showForm = false;
            _editing = null;
          });
          await _afterMutation();
        },
      );
    }

    final ink = ZInk.of(Theme.of(context).colorScheme);
    final query = _query.trim().toLowerCase();
    final scoped = _hooksForScope(widget.catalog.items);
    // Older hosts may expose plugin rows only through loadHooks. Keep those
    // rows visible in the installed read-only projection until the verified
    // plugin-management hookDetails source is available.
    final pluginProjectionAvailable = widget.pluginCatalog?.items
            .any((plugin) => plugin.hookDetails.isNotEmpty) ==
        true;
    final pluginFallback = !pluginProjectionAvailable;
    final configured = [
      for (final hook in scoped)
        if (hook.isEditable ||
            (hook.editable == false && hook.locationSource == 'zcode') ||
            (pluginFallback && hook.locationSource == 'plugin'))
          if (_matches(hook, query)) hook,
    ];
    final compatibility = [
      for (final hook in scoped)
        if (!hook.isEditable &&
            hook.locationSource != 'zcode' &&
            !(pluginFallback && hook.locationSource == 'plugin'))
          if (_matches(hook, query)) hook,
    ];
    final pluginHooks = _pluginHooks(query);
    final total = configured.length + compatibility.length + pluginHooks.length;

    return Column(
      key: const ValueKey('hooks-settings-section'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(context, ink, total, configured.length),
        if (widget.catalog.status == RemoteAgentCatalogStatus.error)
          _errorBanner(context, ink),
        if (widget.catalog.status == RemoteAgentCatalogStatus.loading &&
            widget.catalog.items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        if (widget.catalog.status != RemoteAgentCatalogStatus.loading ||
            widget.catalog.items.isNotEmpty)
          ..._groups(
            context,
            ink,
            configured,
            compatibility,
            pluginHooks,
          ),
      ],
    );
  }

  Widget _header(
      BuildContext context, InkTokens ink, int total, int installedCount) {
    final scopeItems = <DropdownMenuItem<String>>[
      DropdownMenuItem(
        value: 'user',
        child: Text(uiText(context, '用户', 'User')),
      ),
      for (final option in widget.scopeOptions)
        DropdownMenuItem(
          value: option.identity,
          child: Text(option.label, overflow: TextOverflow.ellipsis),
        ),
    ];
    final selected =
        scopeItems.any((item) => item.value == _scopeKey) ? _scopeKey : 'user';
    final scopePicker = DropdownButton<String>(
      key: const ValueKey('hooks-scope-picker'),
      value: selected,
      isExpanded: true,
      isDense: true,
      // Keep the scope picker active while a slow workspace opens;
      // selecting User again cancels that pending source.
      onChanged: _selectScope,
      items: scopeItems,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final mediaWidth = MediaQuery.sizeOf(context).width - 40;
            final availableWidth =
                constraints.maxWidth.isFinite && constraints.maxWidth > 0
                    ? constraints.maxWidth
                    : mediaWidth;
            final narrow = availableWidth < 520;
            final scopeWidth = narrow
                ? (availableWidth < 120 ? availableWidth : 120.0)
                : 120.0;
            final scope = SizedBox(
              width: scopeWidth,
              child: scopePicker,
            );
            final header = Row(
              children: [
                scope,
                const SizedBox(width: 12),
                Text(
                  '${uiText(context, '钩子', 'Hooks')} $total',
                  style: TextStyle(fontSize: 14, color: ink.text),
                ),
              ],
            );
            final search = SizedBox(
              width: narrow ? availableWidth : 256,
              height: 36,
              child: TextField(
                key: const ValueKey('hooks-search'),
                enabled: !_scopeChanging,
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
                  hintText: uiText(context, '搜索钩子...', 'Search hooks...'),
                  border: const OutlineInputBorder(),
                ),
              ),
            );
            if (narrow) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  header,
                  const SizedBox(height: 8),
                  search,
                ],
              );
            }
            return Row(
              children: [
                header,
                const Spacer(),
                search,
              ],
            );
          },
        ),
        const SizedBox(height: 20),
        LayoutBuilder(
          builder: (context, constraints) {
            final actions = <Widget>[
              IconButton(
                key: const ValueKey('hooks-refresh'),
                tooltip: uiText(context, '刷新', 'Refresh'),
                onPressed: _scopeChanging ? null : () => unawaited(_refresh()),
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints.tightFor(width: 32, height: 32),
                icon: const LucideIcon('refresh-cw', size: 15),
              ),
              FilledButton.icon(
                key: const ValueKey('hooks-new'),
                onPressed: _scopeChanging ? null : () => _openForm(null),
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(ZRadius.lg)),
                ),
                icon: const LucideIcon('plus', size: 14),
                label: Text(uiText(context, '新建钩子', 'New hook')),
              ),
            ];
            final installed = Text(
              '${uiText(context, '已安装', 'Installed')} $installedCount',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: ink.subtlest),
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
                const Spacer(),
                ...actions,
              ],
            );
          },
        ),
        // Determinate progress keeps the testable layout stable while the
        // parent may wait on a real workspace open.
        if (_scopeChanging) ...[
          const SizedBox(height: 8),
          const LinearProgressIndicator(value: .4, minHeight: 2),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _errorBanner(BuildContext context, InkTokens ink) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ink.diffRemoved.withValues(alpha: .08),
          border: Border.all(color: ink.diffRemoved.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                uiText(context, '钩子读取失败，已保留已确认列表。',
                    'Could not read hooks. The confirmed list is kept.'),
                style: TextStyle(color: ink.diffRemoved),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(_refresh()),
              child: Text(uiText(context, '重试', 'Retry')),
            ),
          ],
        ),
      );

  Future<void> _refresh() async {
    await widget.catalog.refresh();
    final plugin = widget.pluginCatalog;
    if (plugin != null) await plugin.refresh();
  }

  List<Widget> _groups(
    BuildContext context,
    InkTokens ink,
    List<WorkspaceHook> configured,
    List<WorkspaceHook> compatibility,
    List<_PluginHook> pluginHooks,
  ) {
    final groups = <Widget>[];
    if (configured.isNotEmpty) {
      groups.add(_configuredCard(context, ink, configured));
    }
    final byPlugin = <String, List<_PluginHook>>{};
    for (final hook in pluginHooks) {
      byPlugin.putIfAbsent(hook.plugin.id, () => []).add(hook);
    }
    final pluginIds = byPlugin.keys.toList()..sort();
    for (final pluginId in pluginIds) {
      final hooks = byPlugin[pluginId]!;
      final plugin = hooks.first.plugin;
      groups.add(_group(
        context,
        ink,
        '${plugin.name} · ${uiText(context, '插件', 'Plugin')}',
        hooks.length,
        [_pluginCard(context, ink, hooks)],
      ));
    }
    if (compatibility.isNotEmpty) {
      groups.add(_group(
        context,
        ink,
        uiText(context, '兼容来源', 'Legacy'),
        compatibility.length,
        [_compatibilityCard(context, ink, compatibility)],
      ));
    }
    if (groups.isEmpty) {
      groups.add(_empty(context, ink));
    }
    return groups;
  }

  Widget _group(BuildContext context, InkTokens ink, String title, int count,
          List<Widget> children) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                '$title $count',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: ink.subtlest),
              ),
            ),
            ...children,
          ],
        ),
      );

  Widget _configuredCard(
      BuildContext context, InkTokens ink, List<WorkspaceHook> hooks) {
    return _card(
      ink,
      [
        for (var index = 0; index < hooks.length; index++) ...[
          if (index > 0) Divider(height: 1, color: ink.border),
          _configuredRow(context, ink, hooks[index]),
        ],
      ],
    );
  }

  Widget _configuredRow(
      BuildContext context, InkTokens ink, WorkspaceHook hook) {
    final trustRequired = hook.requiresTrust;
    final busy = _trustingId == hook.id ||
        widget.catalog.isSaving('toggle-${hook.id}') ||
        widget.catalog.isSaving('delete-${hook.id}');
    final summary = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hook.event.isEmpty ? hook.id : hook.event,
          style: TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: ink.text),
        ),
        const SizedBox(height: 4),
        Text(
          '${hook.matcher.isEmpty ? uiText(context, '匹配全部', 'Match all') : hook.matcher} · ${hook.type}: ${hook.command}',
          style: TextStyle(fontSize: 12, color: ink.subtlest),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
    final actions = <Widget>[
      if (hook.isEditable && !trustRequired)
        IconButton(
          key: ValueKey<String>('hook-edit-${hook.id}'),
          tooltip: uiText(context, '编辑', 'Edit'),
          onPressed: busy ? null : () => _openForm(hook),
          icon: const LucideIcon('pencil', size: 15),
        ),
      if (trustRequired)
        Tooltip(
          message: widget.onTrustHook == null
              ? uiText(context, '当前工作区暂不支持信任操作。',
                  'Trust is unavailable for this workspace.')
              : uiText(context, '信任此工作区 Hook', 'Trust this workspace hook'),
          child: OutlinedButton(
            key: ValueKey<String>('hook-trust-${hook.id}'),
            onPressed: widget.onTrustHook == null || busy
                ? null
                : () => unawaited(_trust(hook)),
            child: Text(uiText(context, '信任', 'Trust')),
          ),
        )
      else
        Switch(
          key: ValueKey<String>('hook-toggle-${hook.id}'),
          value: hook.enabled,
          onChanged: hook.isEditable && !busy
              ? (value) => unawaited(_toggle(hook, value))
              : null,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final main = constraints.maxWidth < 520
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    summary,
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Wrap(
                          spacing: 2,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: actions,
                        ),
                      ),
                    ),
                  ],
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: summary),
                    Wrap(
                      spacing: 2,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: actions,
                    ),
                  ],
                );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              main,
              if (_trustErrors[hook.id] != null)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    uiText(context, '信任未受理：${_trustErrors[hook.id]}',
                        'Trust was not accepted: ${_trustErrors[hook.id]}'),
                    style: TextStyle(fontSize: 12, color: ink.diffRemoved),
                  ),
                ),
              if (widget.catalog.saveError('toggle-${hook.id}') != null)
                _saveFailure(context, ink, 'toggle-${hook.id}', hook),
            ],
          );
        },
      ),
    );
  }

  Widget _compatibilityCard(
      BuildContext context, InkTokens ink, List<WorkspaceHook> hooks) {
    return _card(
      ink,
      [
        for (var index = 0; index < hooks.length; index++) ...[
          if (index > 0) Divider(height: 1, color: ink.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final action = OutlinedButton.icon(
                  key: ValueKey<String>('hook-import-${hooks[index].id}'),
                  onPressed:
                      widget.catalog.isSaving('import-${hooks[index].id}')
                          ? null
                          : () => unawaited(_import(hooks[index])),
                  icon: const LucideIcon('download', size: 14),
                  label: Text(uiText(context, '导入', 'Import')),
                );
                final summary = _hookSummary(context, ink, hooks[index]);
                if (constraints.maxWidth < 520) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      summary,
                      Align(
                        alignment: Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: action,
                        ),
                      ),
                    ],
                  );
                }
                return Row(
                  children: [Expanded(child: summary), action],
                );
              },
            ),
          ),
          if (widget.catalog.saveError('import-${hooks[index].id}') != null)
            _saveFailure(context, ink, 'import-${hooks[index].id}', null),
        ],
      ],
    );
  }

  Future<void> _import(WorkspaceHook hook) async {
    final generation = _operationGeneration;
    final catalog = widget.catalog;
    await catalog.importHook(hook);
    if (!mounted ||
        generation != _operationGeneration ||
        !identical(widget.catalog, catalog)) {
      return;
    }
    if (catalog.saveError('import-${hook.id}') == null) {
      await _afterMutation();
    }
  }

  Widget _pluginCard(
      BuildContext context, InkTokens ink, List<_PluginHook> hooks) {
    return _card(
      ink,
      [
        for (var index = 0; index < hooks.length; index++) ...[
          if (index > 0) Divider(height: 1, color: ink.border),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
            child: Row(
              children: [
                const Padding(
                  padding: EdgeInsets.only(right: 12),
                  child: LucideIcon('plug', size: 16),
                ),
                Expanded(child: _pluginSummary(context, ink, hooks[index])),
                if (hooks[index].plugin.enabled == false)
                  Text(uiText(context, '已禁用', 'Disabled'),
                      style: TextStyle(fontSize: 12, color: ink.subtlest)),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _hookSummary(BuildContext context, InkTokens ink, WorkspaceHook hook) {
    final command =
        [hook.command, ...hook.args].where((e) => e.isNotEmpty).join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(hook.event.isEmpty ? hook.id : hook.event,
            style: TextStyle(fontSize: 14, color: ink.text)),
        const SizedBox(height: 4),
        Text(command,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 12, color: ink.subtlest)),
      ],
    );
  }

  Widget _pluginSummary(BuildContext context, InkTokens ink, _PluginHook hook) {
    final detail = hook.detail;
    final args = detail['args'] is List
        ? [for (final value in detail['args'] as List) '$value']
        : const <String>[];
    final command = ['${detail['command'] ?? ''}', ...args]
        .where((e) => e.isNotEmpty)
        .join(' ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('${detail['event'] ?? '--'}',
            style: TextStyle(fontSize: 14, color: ink.text)),
        const SizedBox(height: 4),
        Text(command,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontFamily: 'monospace', fontSize: 12, color: ink.subtlest)),
        if ('${detail['sourcePath'] ?? ''}'.isNotEmpty)
          Text('${detail['sourcePath']}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 11, color: ink.subtlest)),
      ],
    );
  }

  Widget _saveFailure(BuildContext context, InkTokens ink, String errorId,
      WorkspaceHook? hook) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              uiText(context, '保存失败，已保留原设置。',
                  'Save failed. The previous value is kept.'),
              style: TextStyle(fontSize: 12, color: ink.diffRemoved),
            ),
          ),
          TextButton(
            onPressed: widget.catalog.isSaving(errorId)
                ? null
                : () => unawaited(
                      hook == null
                          ? widget.catalog.importHook(widget.catalog.items
                              .firstWhere(
                                  (item) => 'import-${item.id}' == errorId))
                          : _toggle(
                              hook, _toggleIntents[hook.id] ?? hook.enabled),
                    ),
            child: Text(uiText(context, '重试', 'Retry')),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context, InkTokens ink) => SizedBox(
        width: double.infinity,
        child: CustomPaint(
          painter: _HooksDashedRoundedBorderPainter(color: ink.border),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: [
                Text(uiText(context, '尚未安装钩子', 'No hooks installed yet'),
                    style: TextStyle(fontSize: 15, color: ink.text)),
                const SizedBox(height: 6),
                Text(
                  uiText(context, '新建钩子，以在任务生命周期事件中运行命令。',
                      'Create a hook to run a command on task lifecycle events.'),
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: ink.subtlest),
                ),
                const SizedBox(height: 14),
                FilledButton.icon(
                  key: const ValueKey('hooks-new-empty'),
                  onPressed: () => _openForm(null),
                  icon: const LucideIcon('plus', size: 14),
                  label: Text(uiText(context, '新建钩子', 'New hook')),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _card(InkTokens ink, List<Widget> children) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: ink.surfaceFill,
          border: Border.all(color: ink.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Column(children: children),
        ),
      );
}

class _HooksDashedRoundedBorderPainter extends CustomPainter {
  _HooksDashedRoundedBorderPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    final path = Path()
      ..addRRect(RRect.fromRectAndRadius(
        Offset.zero & size,
        const Radius.circular(12),
      ));
    for (final metric in path.computeMetrics()) {
      var drawn = 0.0;
      while (drawn < metric.length) {
        final end = drawn + 5 > metric.length ? metric.length : drawn + 5;
        canvas.drawPath(metric.extractPath(drawn, end), paint);
        drawn += 9;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _HooksDashedRoundedBorderPainter oldDelegate) =>
      oldDelegate.color != color;
}

class _PluginHook {
  const _PluginHook({required this.plugin, required this.detail});

  final CatalogPlugin plugin;
  final Map<String, dynamic> detail;
}

class _HookFormPage extends StatefulWidget {
  const _HookFormPage({
    super.key,
    required this.catalog,
    required this.existing,
    required this.projectScope,
    required this.scopeLabel,
    required this.onCancel,
    required this.onSaved,
  });

  final HooksCatalog catalog;
  final WorkspaceHook? existing;
  final bool projectScope;
  final String scopeLabel;
  final VoidCallback onCancel;
  final Future<void> Function() onSaved;

  @override
  State<_HookFormPage> createState() => _HookFormPageState();
}

class _HookFormPageState extends State<_HookFormPage> {
  static const events = <String>[
    'SessionStart',
    'UserPromptSubmit',
    'PreToolUse',
    'PermissionRequest',
    'PostToolUse',
    'PostToolUseFailure',
    'Stop',
  ];

  late String _event;
  late String _type;
  late String _storageLevel;
  late bool _async;
  late bool _enabled;
  late final TextEditingController _matcher;
  late final TextEditingController _command;
  late final TextEditingController _args;
  late final TextEditingController _shell;
  late final TextEditingController _statusMessage;
  late final TextEditingController _timeout;
  late final TextEditingController _customJson;
  String? _error;
  bool _saving = false;
  bool _deleteArmed = false;

  @override
  void initState() {
    super.initState();
    final hook = widget.existing;
    _event = hook?.event.isNotEmpty == true ? hook!.event : 'PreToolUse';
    _type = hook?.type == 'command' ? 'command' : 'process';
    _storageLevel = widget.projectScope
        ? 'project'
        : (hook?.storageLevel == 'project' ? 'project' : 'user');
    if (_storageLevel == 'project' &&
        widget.catalog.workspacePath?.trim().isNotEmpty != true) {
      _storageLevel = 'user';
    }
    _async = hook?.isAsync ?? false;
    _enabled = hook?.enabled ?? true;
    _matcher = TextEditingController(text: hook?.matcher ?? '');
    _command = TextEditingController(text: hook?.command ?? '');
    _args = TextEditingController(text: hook?.args.join('\n') ?? '');
    _shell = TextEditingController(
        text: hook?.shell is String ? hook!.shell as String : '');
    _statusMessage = TextEditingController(text: hook?.statusMessage ?? '');
    _timeout = TextEditingController(text: '${hook?.timeout ?? 60}');
    _customJson = TextEditingController(
        text: hook?.custom == null || hook!.custom!.isEmpty
            ? ''
            : const JsonEncoder.withIndent('  ').convert(hook.custom));
  }

  @override
  void dispose() {
    _matcher.dispose();
    _command.dispose();
    _args.dispose();
    _shell.dispose();
    _statusMessage.dispose();
    _timeout.dispose();
    _customJson.dispose();
    super.dispose();
  }

  bool get _canSave =>
      _command.text.trim().isNotEmpty &&
      int.tryParse(_timeout.text.trim()) != null &&
      int.parse(_timeout.text.trim()) > 0 &&
      (_customJson.text.trim().isEmpty || _customValue != null);

  Map<String, dynamic>? get _customValue {
    if (_customJson.text.trim().isEmpty) return null;
    try {
      final value = jsonDecode(_customJson.text);
      return value is Map ? value.cast<String, dynamic>() : null;
    } catch (_) {
      return null;
    }
  }

  String? get _customError {
    if (_customJson.text.trim().isEmpty || _customValue != null) return null;
    try {
      final value = jsonDecode(_customJson.text);
      if (value is Map) return null;
      return uiText(context, '自定义 JSON 必须是对象。', 'Must be a JSON object.');
    } catch (_) {
      return uiText(context, '自定义 JSON 解析失败。', 'Invalid JSON.');
    }
  }

  Future<void> _save() async {
    if (!_canSave || _saving) return;
    final hook = widget.existing;
    final errorId = 'form-${hook?.id ?? 'new'}';
    setState(() {
      _saving = true;
      _error = null;
    });
    final timeout = int.parse(_timeout.text.trim());
    final args = _type == 'process'
        ? [
            for (final line in _args.text.split('\n'))
              if (line.trim().isNotEmpty) line.trim(),
          ]
        : null;
    if (hook == null) {
      await widget.catalog.createHook(
        event: _event,
        type: _type,
        command: _command.text,
        matcher: _matcher.text,
        args: args,
        async: _async,
        shell: _shell.text,
        statusMessage: _statusMessage.text,
        timeout: timeout,
        enabled: _enabled,
        custom: _customValue,
        storageLevel: _storageLevel,
        directoryPath: widget.catalog.workspacePath,
        errorId: errorId,
      );
    } else {
      await widget.catalog.updateHook(
        hook,
        event: _event,
        type: _type,
        command: _command.text,
        matcher: _matcher.text,
        args: args,
        async: _async,
        shell: _shell.text,
        statusMessage: _statusMessage.text,
        timeout: timeout,
        custom: _customValue,
        storageLevel: _storageLevel,
        directoryPath: widget.catalog.workspacePath,
        errorId: errorId,
      );
    }
    if (!mounted) return;
    if (widget.catalog.saveError(errorId) != null) {
      setState(() {
        _saving = false;
        _error = uiText(context, '保存失败，已保留当前输入。请重试。',
            'Save failed. Your input is kept for retry.');
      });
      return;
    }
    await widget.onSaved();
  }

  Future<void> _delete() async {
    final hook = widget.existing;
    if (hook == null || _saving) return;
    if (!_deleteArmed) {
      setState(() => _deleteArmed = true);
      return;
    }
    // The second click is the destructive confirmation. Keeping the form
    // mounted preserves all entered fields when the operation fails.
    if (!mounted) return;
    final errorId = 'delete-${hook.id}';
    setState(() {
      _saving = true;
      _error = null;
    });
    await widget.catalog.deleteHook(hook, errorId: errorId);
    if (!mounted) return;
    if (widget.catalog.saveError(errorId) != null) {
      setState(() {
        _saving = false;
        _error = uiText(context, '删除失败，已保留当前输入。请重试。',
            'Delete failed. Your input is kept for retry.');
      });
    } else {
      await widget.onSaved();
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Column(
      key: const ValueKey('hooks-form'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            TextButton.icon(
              onPressed: _saving ? null : widget.onCancel,
              icon: const LucideIcon('chevron-left', size: 15),
              label: Text(uiText(context, '钩子', 'Hooks')),
            ),
            const Text(' / '),
            Text(
              widget.existing == null
                  ? uiText(context, '新建', 'New')
                  : uiText(context, '编辑', 'Edit'),
              style: TextStyle(fontSize: 13, color: ink.subtlest),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          widget.existing == null
              ? uiText(context, '新建钩子', 'New hook')
              : uiText(context, '编辑钩子', 'Edit hook'),
          style: TextStyle(
              fontSize: 20, fontWeight: FontWeight.w600, color: ink.text),
        ),
        const SizedBox(height: 6),
        Text(
          uiText(context, '在匹配的工作区事件发生时运行命令。',
              'Run a command when a matching workspace event occurs.'),
          style: TextStyle(fontSize: 12, color: ink.subtlest),
        ),
        const SizedBox(height: 18),
        _formCard(context, ink),
      ],
    );
  }

  Widget _formCard(BuildContext context, InkTokens ink) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: ink.border),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 520
                  ? Column(children: [_eventField(), _typeField()])
                  : Row(children: [
                      Expanded(child: _eventField()),
                      const SizedBox(width: 12),
                      Expanded(child: _typeField()),
                    ]),
            ),
            const SizedBox(height: 12),
            _storageField(context),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, constraints) => constraints.maxWidth < 520
                  ? Column(children: [_matcherField(), _commandField()])
                  : Row(
                      children: [
                        Expanded(child: _matcherField()),
                        const SizedBox(width: 12),
                        Expanded(child: _commandField()),
                      ],
                    ),
            ),
            const SizedBox(height: 12),
            if (_type == 'process') _argsField() else _commandOptions(context),
            const SizedBox(height: 12),
            ExpansionTile(
              key: const ValueKey('hook-form-advanced'),
              tilePadding: EdgeInsets.zero,
              title: Text(uiText(context, '高级', 'Advanced')),
              children: [
                _statusField(),
                const SizedBox(height: 12),
                _timeoutField(),
                const SizedBox(height: 12),
                _customField(),
              ],
            ),
            SwitchListTile(
              key: const ValueKey('hook-form-enabled'),
              contentPadding: EdgeInsets.zero,
              value: _enabled,
              onChanged:
                  _saving ? null : (value) => setState(() => _enabled = value),
              title: Text(uiText(context, '启用', 'Enabled')),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(_error!,
                    style: TextStyle(fontSize: 12, color: ink.diffRemoved)),
              ),
            const SizedBox(height: 14),
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 8,
              children: [
                if (widget.existing != null)
                  TextButton(
                    key: const ValueKey('hook-form-delete'),
                    onPressed: _saving ? null : _delete,
                    style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.error),
                    child: Text(_deleteArmed
                        ? uiText(context, '确认删除', 'Confirm delete')
                        : uiText(context, '删除', 'Delete')),
                  ),
                TextButton(
                  key: const ValueKey('hook-form-cancel'),
                  onPressed: _saving ? null : widget.onCancel,
                  child: Text(uiText(context, '取消', 'Cancel')),
                ),
                FilledButton(
                  key: const ValueKey('hook-form-save'),
                  onPressed: _saving || !_canSave ? null : _save,
                  child: Text(widget.existing == null
                      ? uiText(context, '新建', 'Create')
                      : uiText(context, '保存', 'Save')),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _eventField() => DropdownButtonFormField<String>(
        key: const ValueKey('hook-form-event'),
        initialValue: events.contains(_event) ? _event : null,
        decoration: InputDecoration(
            labelText: uiText(context, '事件', 'Event'),
            border: const OutlineInputBorder()),
        items: [
          for (final event in events)
            DropdownMenuItem(value: event, child: Text(event)),
          if (!events.contains(_event))
            DropdownMenuItem(value: _event, child: Text(_event)),
        ],
        onChanged: _saving
            ? null
            : (value) => setState(() => _event = value ?? _event),
      );

  Widget _typeField() => DropdownButtonFormField<String>(
        key: const ValueKey('hook-form-type'),
        initialValue: _type,
        decoration: InputDecoration(
            labelText: uiText(context, '类型', 'Type'),
            border: const OutlineInputBorder()),
        items: [
          DropdownMenuItem(
              value: 'process', child: Text(uiText(context, '进程', 'Process'))),
          DropdownMenuItem(
              value: 'command', child: Text(uiText(context, '命令', 'Command'))),
        ],
        onChanged: _saving
            ? null
            : (value) => setState(
                () => _type = value == 'command' ? 'command' : 'process'),
      );

  Widget _storageField(BuildContext context) => DropdownButtonFormField<String>(
        key: const ValueKey('hook-form-storageLevel'),
        initialValue: _storageLevel,
        decoration: InputDecoration(
            labelText: uiText(context, '存储范围', 'Storage level'),
            helperText: widget.catalog.workspacePath?.isNotEmpty == true
                ? '${uiText(context, '当前工作区', 'Current workspace')}: ${widget.scopeLabel}'
                : uiText(context, '没有工作区路径时仅支持用户范围。',
                    'Only user scope is available without a workspace path.'),
            border: const OutlineInputBorder()),
        items: [
          DropdownMenuItem(
              value: 'user', child: Text(uiText(context, '用户', 'User'))),
          if (widget.catalog.workspacePath?.trim().isNotEmpty == true)
            DropdownMenuItem(
                value: 'project',
                child: Text(uiText(context, '项目', 'Project'))),
        ],
        onChanged: _saving
            ? null
            : (value) => setState(() => _storageLevel = value ?? 'user'),
      );

  Widget _matcherField() => TextField(
        key: const ValueKey('hook-form-matcher'),
        controller: _matcher,
        enabled: !_saving,
        decoration: InputDecoration(
            labelText: uiText(context, 'Matcher', 'Matcher'),
            hintText:
                uiText(context, '工具名，留空匹配全部', 'Tool name; empty matches all'),
            border: const OutlineInputBorder()),
      );

  Widget _commandField() => TextField(
        key: const ValueKey('hook-form-command'),
        controller: _command,
        enabled: !_saving,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
            labelText: uiText(context, '命令', 'Command'),
            hintText: uiText(context, '要执行的命令', 'Command to run'),
            border: const OutlineInputBorder()),
      );

  Widget _argsField() => TextField(
        key: const ValueKey('hook-form-args'),
        controller: _args,
        enabled: !_saving,
        minLines: 3,
        maxLines: 6,
        decoration: InputDecoration(
            labelText: uiText(context, '参数', 'Arguments'),
            hintText: uiText(context, '每行一个参数', 'One argument per line'),
            helperText: uiText(context, '每行一个参数，空行忽略。',
                'One argument per line; blank lines are ignored.'),
            border: const OutlineInputBorder()),
      );

  Widget _commandOptions(BuildContext context) => Column(
        children: [
          TextField(
            key: const ValueKey('hook-form-shell'),
            controller: _shell,
            enabled: !_saving,
            decoration: InputDecoration(
                labelText: uiText(context, 'Shell', 'Shell'),
                hintText: uiText(
                    context, '留空使用默认 shell', 'Empty uses the default shell'),
                border: const OutlineInputBorder()),
          ),
          CheckboxListTile(
            key: const ValueKey('hook-form-async'),
            contentPadding: EdgeInsets.zero,
            value: _async,
            onChanged: _saving
                ? null
                : (value) => setState(() => _async = value ?? false),
            title: Text(uiText(context, '异步执行', 'Run asynchronously')),
          ),
        ],
      );

  Widget _statusField() => TextField(
        key: const ValueKey('hook-form-statusMessage'),
        controller: _statusMessage,
        enabled: !_saving,
        decoration: InputDecoration(
            labelText: uiText(context, '状态信息', 'Status message'),
            border: const OutlineInputBorder()),
      );

  Widget _timeoutField() => TextField(
        key: const ValueKey('hook-form-timeout'),
        controller: _timeout,
        enabled: !_saving,
        keyboardType: TextInputType.number,
        onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
            labelText: uiText(context, '超时（秒）', 'Timeout (s)'),
            errorText: _timeout.text.trim().isEmpty ||
                    int.tryParse(_timeout.text.trim()) == null ||
                    int.tryParse(_timeout.text.trim())! <= 0
                ? uiText(context, '请输入正整数。', 'Enter a positive integer.')
                : null,
            border: const OutlineInputBorder()),
      );

  Widget _customField() => TextField(
        key: const ValueKey('hook-form-customJson'),
        controller: _customJson,
        enabled: !_saving,
        minLines: 3,
        maxLines: 8,
        onChanged: (_) => setState(() {}),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
        decoration: InputDecoration(
            labelText: uiText(context, '自定义 JSON', 'Custom JSON'),
            errorText: _customError,
            border: const OutlineInputBorder()),
      );
}
