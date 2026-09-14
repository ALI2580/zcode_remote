import 'dart:async';

import 'package:flutter/material.dart';

import '../state/client_preferences.dart';
import '../state/remote_agent_catalogs.dart';
import '../state/settings_import.dart';
import 'command_form_dialog.dart';
import 'settings_import_dialog.dart';
import 'theme.dart';

/// Commands settings owns only the page projection. The parent supplies real
/// workspace options and resolves a different bridge when one is selected.
class CommandsSettingsPage extends StatefulWidget {
  const CommandsSettingsPage({
    super.key,
    required this.catalog,
    this.scopes = const [],
    this.onScopeSelected,
    this.onFormTargetSelected,
    this.onComposerRefresh,
    this.settingsSyncService,
  });

  final CommandsCatalog catalog;
  final List<CommandScopeOption> scopes;
  final Future<CommandsCatalog?> Function(CommandScopeOption option)?
      onScopeSelected;
  final Future<CommandFormTarget?> Function(CommandScopeOption option)?
      onFormTargetSelected;
  final FutureOr<void> Function()? onComposerRefresh;
  final SettingsSyncService? settingsSyncService;

  @override
  State<CommandsSettingsPage> createState() => _CommandsSettingsPageState();
}

class _CommandsSettingsPageState extends State<CommandsSettingsPage> {
  late CommandsCatalog _catalog;
  String? _scopeKey;
  String _query = '';
  bool _showForm = false;
  RemoteAgentEntry? _editing;
  String? _formScopeKey;
  int? _formSourceRevision;
  CommandFormTarget? _formTarget;
  String? _formTargetKey;
  int _formTargetGeneration = 0;
  bool _formTargetLoading = false;

  @override
  void initState() {
    super.initState();
    _catalog = widget.catalog;
    _scopeKey = _initialScopeKey();
    _catalog.addListener(_changed);
    unawaited(_catalog.refresh());
  }

  @override
  void didUpdateWidget(covariant CommandsSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final formTargetStillAvailable = _formTargetKey == null ||
        widget.scopes.any((option) => option.key == _formTargetKey);
    if (_showForm && !formTargetStillAvailable) {
      final target = _formTarget;
      if (target != null && !identical(target.catalog, _catalog)) {
        target.catalog.removeListener(_formTargetChanged);
      }
      _showForm = false;
      _editing = null;
      _formTargetGeneration++;
      _formTarget = null;
      _formTargetKey = null;
      _formTargetLoading = false;
      _formScopeKey = null;
      _formSourceRevision = null;
    }
    if (oldWidget.catalog != widget.catalog &&
        identical(_catalog, oldWidget.catalog)) {
      _catalog.removeListener(_changed);
      _catalog = widget.catalog;
      _catalog.addListener(_changed);
      _query = '';
      final scopeStillAvailable = widget.scopes.any(
        (option) => option.key == _scopeKey,
      );
      if (_showForm && !scopeStillAvailable) {
        _showForm = false;
        _editing = null;
        _formTarget = null;
        _formTargetKey = null;
        _formTargetLoading = false;
        _formScopeKey = null;
        _formSourceRevision = null;
      } else if (_showForm) {
        if (_formTarget == null) {
          _formScopeKey = _catalog.scopeKey;
          _formSourceRevision = _catalog.sourceRevision;
        }
      }
    }
    if (widget.scopes.isEmpty) {
      _scopeKey = null;
    } else if (!widget.scopes.any((option) => option.key == _scopeKey)) {
      _scopeKey = widget.scopes
          .where((option) => option.scope == 'user')
          .firstOrNull
          ?.key;
      _scopeKey ??= widget.scopes.first.key;
      if (_showForm) {
        _showForm = false;
        _editing = null;
        _formTarget = null;
        _formTargetKey = null;
        _formTargetLoading = false;
        _formScopeKey = null;
        _formSourceRevision = null;
      }
    }
  }

  String? _initialScopeKey() {
    if (widget.scopes.isEmpty) return null;
    for (final option in widget.scopes) {
      if ((option.scope == 'user' && _catalog.scopeKind == 'user') ||
          (option.scope != 'user' && _catalog.scopeKind != 'user')) {
        return option.key;
      }
    }
    return widget.scopes.first.key;
  }

  @override
  void dispose() {
    _catalog.removeListener(_changed);
    _formTarget?.catalog.removeListener(_formTargetChanged);
    super.dispose();
  }

  void _changed() {
    if (!mounted) return;
    if (_showForm &&
        _formTarget == null &&
        (_formScopeKey != _catalog.scopeKey ||
            _formSourceRevision != _catalog.sourceRevision)) {
      setState(() {
        _showForm = false;
        _editing = null;
        _formTarget = null;
        _formTargetKey = null;
        _formTargetLoading = false;
        _formScopeKey = null;
        _formSourceRevision = null;
      });
      return;
    }
    setState(() {});
  }

  void _formTargetChanged() {
    if (mounted) setState(() {});
  }

  CommandScopeOption? get _selectedScope =>
      widget.scopes.where((option) => option.key == _scopeKey).firstOrNull;

  Future<void> _changeScope(String? key) => _switchListScope(key);

  Future<void> _switchListScope(String? key) async {
    if (key == null || key == _scopeKey) return;
    final option = widget.scopes.firstWhere((item) => item.key == key);
    final target = _formTarget;
    if (target != null && !identical(target.catalog, _catalog)) {
      target.catalog.removeListener(_formTargetChanged);
    }
    _formTargetGeneration++;
    setState(() {
      _scopeKey = key;
      _query = '';
      _showForm = false;
      _editing = null;
      _formTarget = null;
      _formTargetKey = null;
      _formTargetLoading = false;
      _formScopeKey = null;
      _formSourceRevision = null;
    });
    var next = option.catalog;
    next ??= await widget.onScopeSelected?.call(option);
    if (!mounted || next == null || key != _scopeKey) return;
    if (!identical(next, _catalog)) {
      _catalog.removeListener(_changed);
      _catalog = next;
      _catalog.updateScope(
        nextScope: option.identity,
        nextScopeKey: option.key,
        nextWorkspacePath: option.workspacePath,
        nextScopeKind: option.scope,
      );
      _catalog.addListener(_changed);
    } else {
      _catalog.updateScope(
        nextScope: option.identity,
        nextScopeKey: option.key,
        nextWorkspacePath: option.workspacePath,
        nextScopeKind: option.scope,
      );
    }
    await _catalog.refresh();
    if (mounted) setState(() {});
  }

  Future<void> _changeFormScope(String? key) async {
    if (key == null || key == _formTargetKey) return;
    final option = widget.scopes.firstWhere((item) => item.key == key);
    final generation = ++_formTargetGeneration;
    final previous = _formTarget;
    if (previous != null && !identical(previous.catalog, _catalog)) {
      previous.catalog.removeListener(_formTargetChanged);
    }
    setState(() {
      _formTargetKey = key;
      _formTargetLoading = true;
      _formTarget = null;
    });
    var target = option.catalog == null
        ? await widget.onFormTargetSelected?.call(option)
        : CommandFormTarget(
            catalog: option.catalog!,
            onComposerRefresh: widget.onComposerRefresh,
          );
    if (!mounted ||
        generation != _formTargetGeneration ||
        key != _formTargetKey) {
      return;
    }
    if (target == null) {
      setState(() => _formTargetLoading = false);
      return;
    }
    _formTarget = target;
    if (!identical(target.catalog, _catalog)) {
      target.catalog.addListener(_formTargetChanged);
    }
    _formTargetLoading = false;
    _formScopeKey = target.catalog.scopeKey;
    _formSourceRevision = target.catalog.sourceRevision;
    setState(() {});
  }

  Future<void> _openForm([RemoteAgentEntry? editing]) async {
    if (editing != null && !_catalog.canEdit(editing)) return;
    if (editing == null && !_canCreate) return;
    if (!mounted) return;
    setState(() {
      _editing = editing;
      _showForm = true;
      _formTargetKey = _scopeKey;
      _formTarget = CommandFormTarget(
        catalog: _catalog,
        onComposerRefresh: widget.onComposerRefresh,
      );
      _formTargetLoading = false;
      _formScopeKey = _catalog.scopeKey;
      _formSourceRevision = _catalog.sourceRevision;
    });
  }

  void _closeForm() {
    if (!mounted) return;
    final target = _formTarget;
    if (target != null && !identical(target.catalog, _catalog)) {
      target.catalog.removeListener(_formTargetChanged);
    }
    setState(() {
      _showForm = false;
      _editing = null;
      _formTargetGeneration++;
      _formTarget = null;
      _formTargetKey = null;
      _formTargetLoading = false;
      _formScopeKey = null;
      _formSourceRevision = null;
    });
  }

  Future<void> _openImport() async {
    final service = widget.settingsSyncService;
    if (service == null) return;
    final identity = _catalog.scope['workspaceIdentity'];
    await SettingsImportDialog.show(
      context,
      service: service,
      category: 'commands',
      workspacePath: _catalog.workspacePath,
      workspaceIdentity: identity is String ? identity : null,
      onImported: () async {
        await _catalog.refresh();
        await widget.onComposerRefresh?.call();
      },
    );
  }

  bool get _canCreate {
    final scope = _selectedScope?.scope;
    // Official IXt always exposes the new-command entry; capability only
    // disables import. A project form still needs a concrete workspace path.
    if (scope == 'project' || scope == 'workspace') {
      return _catalog.workspacePath?.trim().isNotEmpty == true;
    }
    return true;
  }

  List<RemoteAgentEntry> get _filtered {
    final query = _query.trim().toLowerCase();
    return [
      for (final item in _catalog.visibleItems)
        if (query.isEmpty ||
            [
              item.name,
              item.title,
              item.subtitle ?? '',
              item.path ?? '',
              item.scope ?? '',
              item.source ?? '',
              item.raw['prompt'] is String ? item.raw['prompt'] as String : '',
              item.raw['pluginName'] is String
                  ? item.raw['pluginName'] as String
                  : '',
            ].join(' ').toLowerCase().contains(query))
          item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    if (_showForm) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('commands-form-back'),
                tooltip: uiText(context, '返回', 'Back'),
                onPressed: _closeForm,
                icon: const Icon(Icons.arrow_back, size: 18),
              ),
              Text(
                _editing == null
                    ? uiText(context, '新建命令', 'New command')
                    : uiText(context, '编辑命令', 'Edit command'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          CommandFormDialog(
            embedded: true,
            controller: _formTarget?.catalog ?? _catalog,
            editing: _editing,
            scopeOptions: widget.scopes,
            scopeKey: _formTargetKey,
            onScopeChanged: _changeFormScope,
            onComposerRefresh:
                _formTarget?.onComposerRefresh ?? widget.onComposerRefresh,
            pendingTarget: _formTargetLoading || _formTarget == null,
            onCancel: _closeForm,
            onComplete: _closeForm,
          ),
        ],
      );
    }
    final rows = _filtered;
    final userRows = [
      for (final item in rows)
        if (!item.isPlugin) item
    ];
    final pluginRows = [
      for (final item in rows)
        if (item.isPlugin) item
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            if (widget.scopes.isNotEmpty)
              DropdownButton<String>(
                key: const ValueKey('commands-scope'),
                value: widget.scopes.any((option) => option.key == _scopeKey)
                    ? _scopeKey
                    : widget.scopes.first.key,
                onChanged: _changeScope,
                items: [
                  for (final option in widget.scopes)
                    DropdownMenuItem(
                      value: option.key,
                      child: Text(option.label),
                    ),
                ],
              )
            else
              _pill(context, ink, 'User'),
            Text(
              '${uiText(context, '命令', 'Commands')} ${rows.length}',
              style: TextStyle(color: ink.subtlest, fontSize: 13),
            ),
            SizedBox(
              width: 240,
              child: TextField(
                key: const ValueKey('commands-search'),
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: uiText(context, '搜索命令...', 'Search commands...'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ),
            OutlinedButton.icon(
              key: const ValueKey('commands-refresh'),
              onPressed: _catalog.status == RemoteAgentCatalogStatus.loading
                  ? null
                  : () => unawaited(_catalog.refresh()),
              icon: const Icon(Icons.refresh, size: 16),
              label: Text(uiText(context, '刷新', 'Refresh')),
            ),
            if (widget.settingsSyncService != null)
              OutlinedButton.icon(
                key: const ValueKey('commands-import'),
                onPressed: _catalog.userScopeAvailable ? _openImport : null,
                icon: const Icon(Icons.file_download_outlined, size: 16),
                label: Text(uiText(context, '导入', 'Import')),
              ),
            if (_canCreate)
              FilledButton.icon(
                key: const ValueKey('commands-create'),
                onPressed: () => unawaited(_openForm()),
                icon: const Icon(Icons.add, size: 16),
                label: Text(uiText(context, '新建', 'New')),
              ),
          ],
        ),
        const SizedBox(height: 10),
        Text(
          '${uiText(context, '已安装', 'Installed')} ${userRows.length}',
          style: TextStyle(color: ink.subtlest, fontSize: 13),
        ),
        const SizedBox(height: 8),
        if (_catalog.status == RemoteAgentCatalogStatus.loading)
          const Center(child: CircularProgressIndicator(strokeWidth: 2))
        else if (_catalog.status == RemoteAgentCatalogStatus.error)
          _error(context, ink)
        else if (rows.isEmpty)
          _empty(context, ink)
        else ...[
          if (userRows.isNotEmpty)
            _group(context, ink, 'User commands', userRows),
          if (pluginRows.isNotEmpty) ...[
            const SizedBox(height: 18),
            _group(context, ink, 'Plugin commands', pluginRows),
          ],
        ],
      ],
    );
  }

  Widget _group(BuildContext context, InkTokens ink, String title,
      List<RemoteAgentEntry> rows) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$title ${rows.length}',
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            color: ink.card,
            borderRadius: BorderRadius.circular(ZRadius.xl),
            border: Border.all(color: ink.border),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              for (var index = 0; index < rows.length; index++) ...[
                if (index > 0) Divider(height: 1, color: ink.border),
                _row(context, ink, rows[index]),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _row(BuildContext context, InkTokens ink, RemoteAgentEntry item) {
    final editable = _catalog.canEdit(item);
    final toggleable = _catalog.canToggle(item);
    final saving = _catalog.isSaving(item.id);
    return InkWell(
      key: ValueKey('command-row-${item.id}'),
      onTap: editable && !saving ? () => unawaited(_openForm(item)) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('/${item.title} · ${item.group}'),
                  if (item.subtitle?.isNotEmpty == true)
                    Text(item.subtitle!,
                        style: TextStyle(fontSize: 12, color: ink.subtlest)),
                ],
              ),
            ),
            if (editable)
              TextButton.icon(
                key: ValueKey('command-edit-${item.id}'),
                onPressed: saving ? null : () => unawaited(_openForm(item)),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: Text(uiText(context, '编辑', 'Edit')),
              ),
            if (toggleable)
              Switch(
                key: ValueKey('command-toggle-${item.id}'),
                value: item.enabled ?? false,
                onChanged: saving
                    ? null
                    : (value) =>
                        unawaited(_catalog.setEnabled(item, enabled: value)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _empty(BuildContext context, InkTokens ink) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: ink.card,
          borderRadius: BorderRadius.circular(ZRadius.xl),
          border: Border.all(color: ink.border),
        ),
        child: Text(uiText(context, '尚未安装命令', 'No commands installed')),
      );

  Widget _error(BuildContext context, InkTokens ink) => Row(
        children: [
          Expanded(
            child: Text(
              uiText(context, '命令读取失败，请重试。', 'Could not read commands.'),
              style: TextStyle(color: ink.diffRemoved),
            ),
          ),
          TextButton(
            onPressed: () => unawaited(_catalog.refresh()),
            child: Text(uiText(context, '重试', 'Retry')),
          ),
        ],
      );

  Widget _pill(BuildContext context, InkTokens ink, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: ink.surfaceFill,
          borderRadius: BorderRadius.circular(ZRadius.lg),
          border: Border.all(color: ink.border),
        ),
        child: Text(value, style: const TextStyle(fontSize: 13)),
      );
}
