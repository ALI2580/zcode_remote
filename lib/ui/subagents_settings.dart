import 'dart:async';

import 'package:flutter/material.dart';

import '../state/client_preferences.dart';
import '../state/remote_agent_catalogs.dart';
import 'theme.dart';

/// A model projection supplied by the already loaded official model catalog.
/// Keeping this as a small value object lets the settings page share the
/// Composer's provider projection without creating a second model request.
class SubagentModelOption {
  const SubagentModelOption({
    required this.value,
    required this.label,
    this.thoughtLevels = const [],
  });

  final String value;
  final String label;
  final List<String> thoughtLevels;
}

/// A scope entry supplied by SettingsCenterPage. [identity] must contain the
/// same workspace identity used by the current bridge.
class SubagentScopeOption {
  const SubagentScopeOption({
    required this.key,
    required this.label,
    required this.scope,
    required this.identity,
    this.workspacePath,
    this.catalog,
  });

  final String key;
  final String label;
  final String scope;
  final Map<String, dynamic> identity;
  final String? workspacePath;

  /// Optional catalog owned by the parent for this device/bridge/workspace.
  /// If absent, the page retargets its initial catalog for compatibility.
  final SubagentsCatalog? catalog;
}

/// U16 subagent catalog page. The parent owns the bridge/catalog lifetime and
/// may provide [onComposerRefresh] to invalidate Composer agent candidates
/// after a confirmed mutation.
class SubagentsSettingsPage extends StatefulWidget {
  const SubagentsSettingsPage({
    super.key,
    required this.catalog,
    this.scopes = const [],
    this.modelOptions = const [],
    this.onScopeSelected,
    this.onComposerRefresh,
  });

  final SubagentsCatalog catalog;
  final List<SubagentScopeOption> scopes;
  final List<SubagentModelOption> modelOptions;
  final Future<SubagentsCatalog?> Function(SubagentScopeOption option)?
      onScopeSelected;
  final FutureOr<void> Function()? onComposerRefresh;

  @override
  State<SubagentsSettingsPage> createState() => _SubagentsSettingsPageState();
}

class _SubagentsSettingsPageState extends State<SubagentsSettingsPage> {
  late SubagentsCatalog _catalog;
  String _query = '';
  String? _scopeKey;
  RemoteAgentEntry? _editing;
  bool _showForm = false;
  String? _formScopeKey;
  int? _formSourceRevision;

  @override
  void initState() {
    super.initState();
    _catalog = widget.catalog;
    _scopeKey = _initialScopeKey();
    _catalog.addListener(_catalogChanged);
    unawaited(_catalog.refresh());
  }

  @override
  void didUpdateWidget(covariant SubagentsSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog &&
        identical(_catalog, oldWidget.catalog)) {
      _query = '';
      oldWidget.catalog.removeListener(_catalogChanged);
      _catalog = widget.catalog;
      _catalog.addListener(_catalogChanged);
      if (_showForm) {
        _showForm = false;
        _editing = null;
        _formScopeKey = null;
        _formSourceRevision = null;
      }
    }
    if (widget.scopes.isEmpty) {
      _scopeKey = null;
    } else if (!widget.scopes.any((scope) => scope.key == _scopeKey)) {
      _scopeKey = widget.scopes
          .where((scope) => scope.scope == 'user')
          .firstOrNull
          ?.key;
      _scopeKey ??= widget.scopes.first.key;
      if (_showForm) {
        _showForm = false;
        _editing = null;
        _formScopeKey = null;
        _formSourceRevision = null;
      }
    }
  }

  String? _initialScopeKey() {
    if (widget.scopes.isEmpty) return null;
    for (final scope in widget.scopes) {
      if (scope.scope == _catalog.scopeKind) return scope.key;
    }
    return widget.scopes.first.key;
  }

  @override
  void dispose() {
    _catalog.removeListener(_catalogChanged);
    super.dispose();
  }

  void _catalogChanged() {
    if (!mounted ||
        !_showForm ||
        (_formScopeKey == _catalog.scopeKey &&
            _formSourceRevision == _catalog.sourceRevision)) {
      return;
    }
    setState(() {
      _showForm = false;
      _editing = null;
      _formScopeKey = null;
      _formSourceRevision = null;
    });
  }

  SubagentScopeOption? get _selectedScope {
    if (_scopeKey == null) return null;
    for (final scope in widget.scopes) {
      if (scope.key == _scopeKey) return scope;
    }
    return null;
  }

  bool get _canCreate {
    final scope = _selectedScope;
    final targetScope = scope?.scope ?? 'user';
    return _catalog.canCreate(targetScope);
  }

  Future<void> _changeScope(String? key) async {
    if (key == null || key == _scopeKey) return;
    final next = widget.scopes.firstWhere((scope) => scope.key == key);
    setState(() {
      _scopeKey = key;
      _query = '';
      _showForm = false;
      _editing = null;
      _formScopeKey = null;
      _formSourceRevision = null;
    });
    var nextCatalog = next.catalog;
    final scopeResolver = widget.onScopeSelected;
    if (nextCatalog == null && scopeResolver != null) {
      nextCatalog = await scopeResolver(next);
    }
    if (!mounted || key != _scopeKey) return;
    // Standalone consumers can provide scope identity/path options without a
    // parent resolver. Retarget the supplied catalog directly in that mode;
    // parent-owned pages still use the resolver's source-specific catalog.
    if (nextCatalog == null && scopeResolver != null) return;
    nextCatalog ??= _catalog;
    if (!identical(nextCatalog, _catalog)) {
      _catalog.removeListener(_catalogChanged);
      _catalog = nextCatalog;
      _catalog.addListener(_catalogChanged);
    }
    _catalog.updateScope(
      nextScope: next.identity,
      nextWorkspacePath: next.workspacePath,
      nextScopeKey: next.key,
      nextScopeKind: next.scope,
    );
    await _catalog.refresh();
  }

  Future<void> _openForm({RemoteAgentEntry? editing}) async {
    if (!_canCreate && editing == null) return;
    if (editing != null && !_catalog.canEdit(editing)) return;
    setState(() {
      _editing = editing;
      _showForm = true;
      _formScopeKey = _catalog.scopeKey;
      _formSourceRevision = _catalog.sourceRevision;
    });
  }

  void _closeForm() {
    if (!mounted) return;
    setState(() {
      _showForm = false;
      _editing = null;
      _formScopeKey = null;
      _formSourceRevision = null;
    });
  }

  List<RemoteAgentEntry> _filtered(String query) {
    final normalized = query.trim().toLowerCase();
    return [
      for (final item in _catalog.visibleItems)
        if (normalized.isEmpty ||
            [
              item.name,
              item.title,
              item.subtitle ?? '',
              item.path ?? '',
              item.scope ?? '',
              item.source ?? '',
              ...?item.tools,
            ].join(' ').toLowerCase().contains(normalized))
          item,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    if (_showForm) {
      final selected = _selectedScope;
      final targetScope = selected?.scope ??
          (_editing?.scope == 'workspace' ? 'workspace' : 'user');
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconButton(
                key: const ValueKey('subagents-form-back'),
                tooltip: uiText(context, '返回', 'Back'),
                onPressed: _closeForm,
                icon: const Icon(Icons.arrow_back, size: 18),
              ),
              Text(
                _editing == null
                    ? uiText(context, '新建子智能体', 'New subagent')
                    : uiText(context, '编辑子智能体', 'Edit subagent'),
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SubagentFormDialog(
            embedded: true,
            catalog: _catalog,
            editing: _editing,
            targetScope: targetScope,
            modelOptions: widget.modelOptions,
            onComposerRefresh: widget.onComposerRefresh,
            onCancel: _closeForm,
            onComplete: _closeForm,
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: _catalog,
      builder: (context, _) {
        final filtered = _filtered(_query);
        final userRows = [
          for (final item in filtered)
            if (_catalog.canEdit(item)) item,
        ];
        final pluginRows = [
          for (final item in filtered)
            if (item.isPlugin) item
        ];
        final builtInRows = [
          for (final item in filtered)
            if (!item.isPlugin && !_catalog.canEdit(item)) item,
        ];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _toolbar(context, ink),
            if (_catalog.status == RemoteAgentCatalogStatus.error)
              _errorBanner(context, ink),
            if (_catalog.status == RemoteAgentCatalogStatus.loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else if (_catalog.status == RemoteAgentCatalogStatus.idle)
              const SizedBox.shrink()
            else
              _groups(
                context,
                ink,
                userRows: userRows,
                pluginRows: pluginRows,
                builtInRows: builtInRows,
              ),
          ],
        );
      },
    );
  }

  Widget _toolbar(BuildContext context, InkTokens ink) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (widget.scopes.isNotEmpty)
            SizedBox(
              width: 160,
              child: DropdownButton<String>(
                key: const ValueKey('subagents-scope'),
                value: _scopeKey,
                isExpanded: true,
                onChanged: _changeScope,
                items: [
                  for (final scope in widget.scopes)
                    DropdownMenuItem<String>(
                      value: scope.key,
                      child: Text(
                        scope.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            )
          else
            _pill(context, ink, uiText(context, '用户', 'User')),
          Text(
            '${uiText(context, '子智能体', 'Subagents')} ${_catalog.visibleItems.length}',
            style: TextStyle(color: ink.subtlest, fontSize: 13),
          ),
          Text(
            '${uiText(context, '已安装', 'Installed')} ${_catalog.visibleItems.where(_catalog.canEdit).length}',
            style: TextStyle(color: ink.subtlest, fontSize: 13),
          ),
          SizedBox(
            width: 240,
            child: TextField(
              key: const ValueKey('subagents-search'),
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: uiText(context, '搜索子智能体...', 'Search subagents...'),
                border: const OutlineInputBorder(),
              ),
            ),
          ),
          OutlinedButton.icon(
            key: const ValueKey('subagents-refresh'),
            onPressed: _catalog.status == RemoteAgentCatalogStatus.loading
                ? null
                : () => unawaited(_catalog.refresh()),
            icon: const Icon(Icons.refresh, size: 16),
            label: Text(uiText(context, '刷新', 'Refresh')),
          ),
          if (_canCreate)
            FilledButton.icon(
              key: const ValueKey('subagents-create'),
              onPressed: () => unawaited(_openForm()),
              icon: const Icon(Icons.add, size: 16),
              label: Text(uiText(context, '新建', 'New')),
            ),
        ],
      ),
    );
  }

  Widget _pill(BuildContext context, InkTokens ink, String value) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: ink.surfaceFill,
          borderRadius: BorderRadius.circular(ZRadius.lg),
          border: Border.all(color: ink.border),
        ),
        child: Text(value, style: const TextStyle(fontSize: 13)),
      );

  Widget _errorBanner(BuildContext context, InkTokens ink) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: ink.diffRemoved.withValues(alpha: .08),
          border: Border.all(color: ink.diffRemoved.withValues(alpha: .3)),
          borderRadius: BorderRadius.circular(ZRadius.lg),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                uiText(context, '子智能体读取失败，请重试。',
                    'Could not read subagents. Retry.'),
                style: TextStyle(color: ink.diffRemoved),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(_catalog.refresh()),
              child: Text(uiText(context, '重试', 'Retry')),
            ),
          ],
        ),
      );

  Widget _groups(
    BuildContext context,
    InkTokens ink, {
    required List<RemoteAgentEntry> userRows,
    required List<RemoteAgentEntry> pluginRows,
    required List<RemoteAgentEntry> builtInRows,
  }) {
    final children = <Widget>[];
    if (userRows.isEmpty) {
      children.add(_emptyCard(context, ink, canCreate: _canCreate));
    } else {
      children.add(_group(context, ink,
          title: uiText(context, '已安装', 'Installed'), rows: userRows));
    }
    if (pluginRows.isNotEmpty) {
      children.add(const SizedBox(height: 20));
      children.add(_group(context, ink,
          title: uiText(context, '插件子智能体', 'Plugin subagents'),
          rows: pluginRows));
    }
    if (builtInRows.isNotEmpty) {
      children.add(const SizedBox(height: 20));
      children.add(_group(context, ink,
          title: uiText(context, '内置子智能体', 'Built-in subagents'),
          rows: builtInRows));
    }
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
  }

  Widget _group(
    BuildContext context,
    InkTokens ink, {
    required String title,
    required List<RemoteAgentEntry> rows,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
            Text('${rows.length}', style: TextStyle(color: ink.subtlest)),
          ],
        ),
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
    final overrideName = _catalog.builtInOverrideName(item);
    final operating = _catalog.isOperating(item.id) ||
        (overrideName != null && _catalog.isOperating('model:$overrideName'));
    final info = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(item.name),
            if (item.isBuiltIn || item.isPlugin)
              _badge(
                context,
                ink,
                item.inheritsAllTools
                    ? uiText(context, '全部工具', 'All tools')
                    : '${item.tools!.length} ${uiText(context, '个工具', 'tools')}',
              ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          item.subtitle?.isNotEmpty == true
              ? item.subtitle!
              : uiText(context, '暂无描述', 'No description'),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: ink.subtlest),
        ),
      ],
    );
    final leading = Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: ink.surfaceFill,
        borderRadius: BorderRadius.circular(ZRadius.lg),
      ),
      child: Icon(Icons.smart_toy_outlined, size: 17, color: ink.subtlest),
    );
    final actions = <Widget>[
      if (overrideName != null)
        _builtInOverride(context, ink, item, operating)
      else if (toggleable)
        Switch(
          key: ValueKey('subagent-enabled-${item.id}'),
          value: item.enabled ?? true,
          onChanged:
              operating ? null : (value) => unawaited(_toggle(item, value)),
        ),
      if (editable)
        IconButton(
          key: ValueKey('subagent-delete-${item.id}'),
          tooltip: uiText(context, '删除', 'Delete'),
          onPressed: operating ? null : () => unawaited(_delete(item)),
          icon: const Icon(Icons.delete_outline, size: 18),
        ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final primary = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            leading,
            const SizedBox(width: 10),
            Expanded(child: info),
          ],
        );
        final actionRow = Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 4,
          children: actions,
        );
        return InkWell(
          key: ValueKey('subagent-row-${item.id}'),
          onTap: editable && !operating
              ? () => unawaited(_openForm(editing: item))
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: compact
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      primary,
                      if (actions.isNotEmpty) ...[
                        const SizedBox(height: 8),
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
                        const SizedBox(width: 10),
                        actionRow,
                      ],
                    ],
                  ),
          ),
        );
      },
    );
  }

  Widget _badge(BuildContext context, InkTokens ink, String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: ink.surfaceFill,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: ink.border),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: ink.subtlest)),
      );

  Widget _builtInOverride(
    BuildContext context,
    InkTokens ink,
    RemoteAgentEntry item,
    bool operating,
  ) {
    final options = <SubagentModelOption>[
      const SubagentModelOption(value: 'inherit', label: 'Main model'),
      ...widget.modelOptions.where((option) => option.value != 'inherit'),
    ];
    final current = item.modelOverride ?? 'inherit';
    final values = {for (final option in options) option.value};
    final value = values.contains(current) ? current : 'inherit';
    final selected = options.cast<SubagentModelOption?>().firstWhere(
          (option) => option?.value == value,
          orElse: () => null,
        );
    final thoughtLevels = selected?.thoughtLevels ?? const <String>[];
    final thought = thoughtLevels.contains(item.thoughtLevelOverride)
        ? item.thoughtLevelOverride
        : null;
    final modelControl = SizedBox(
      width: 180,
      child: DropdownButton<String>(
        key: ValueKey('subagent-model-${item.name}'),
        isExpanded: true,
        value: value,
        onChanged: operating
            ? null
            : (next) {
                if (next == null || next == current) return;
                // Official pYt clears the old thought level whenever
                // the model changes; levels belong to one model.
                unawaited(_setBuiltInModel(item, next, null));
              },
        items: [
          for (final option in options)
            DropdownMenuItem(
              value: option.value,
              child: Text(option.label, overflow: TextOverflow.ellipsis),
            ),
        ],
      ),
    );
    final thoughtControl = SizedBox(
      width: 92,
      child: DropdownButton<String?>(
        key: ValueKey('subagent-thought-${item.name}'),
        isExpanded: true,
        value: thought,
        hint: Text(uiText(context, '默认', 'Default')),
        onChanged: operating
            ? null
            : (next) => unawaited(_setBuiltInModel(item, value, next)),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('Default')),
          for (final level in thoughtLevels)
            DropdownMenuItem<String?>(value: level, child: Text(level)),
        ],
      ),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth.isFinite && constraints.maxWidth < 290;
        if (value == 'inherit' || thoughtLevels.isEmpty) return modelControl;
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              modelControl,
              const SizedBox(height: 4),
              thoughtControl,
            ],
          );
        }
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [modelControl, const SizedBox(width: 8), thoughtControl],
        );
      },
    );
  }

  Future<void> _toggle(RemoteAgentEntry item, bool value) async {
    final ok = await _catalog.setEnabled(item, enabled: value);
    if (ok) await widget.onComposerRefresh?.call();
  }

  Future<void> _setBuiltInModel(
      RemoteAgentEntry item, String model, String? thoughtLevel) async {
    final ok = await _catalog.setBuiltInModelOverride(
      entry: item,
      model: model == 'inherit' ? null : model,
      thoughtLevel: model == 'inherit' ? null : thoughtLevel,
    );
    if (ok) await widget.onComposerRefresh?.call();
  }

  Future<void> _delete(RemoteAgentEntry item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(uiText(context, '删除子智能体', 'Delete subagent')),
        content: Text(
            uiText(context, '确定删除「${item.name}」吗？', 'Delete "${item.name}"?')),
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
    final ok = await _catalog.deleteAgent(item);
    if (ok) await widget.onComposerRefresh?.call();
  }

  Widget _emptyCard(BuildContext context, InkTokens ink,
      {required bool canCreate}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(ZRadius.xl),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(uiText(context, '没有找到子智能体', 'No subagents found')),
          const SizedBox(height: 6),
          Text(
            uiText(context, '填写名称、描述和系统提示词，保存后返回列表。',
                'Create one with a name, description and system prompt.'),
            style: TextStyle(fontSize: 12, color: ink.subtlest),
          ),
          if (canCreate) ...[
            const SizedBox(height: 12),
            FilledButton.icon(
              key: const ValueKey('subagents-create-empty'),
              onPressed: () => unawaited(_openForm()),
              icon: const Icon(Icons.add, size: 16),
              label: Text(uiText(context, '新建', 'New')),
            ),
          ],
        ],
      ),
    );
  }
}

/// Official subagent form. Save sends only after all required fields and the
/// selected model/thought level have validated; a failed save leaves the
/// current draft in the dialog for retry.
class SubagentFormDialog extends StatefulWidget {
  const SubagentFormDialog({
    super.key,
    required this.catalog,
    required this.targetScope,
    this.editing,
    this.modelOptions = const [],
    this.onComposerRefresh,
    this.embedded = false,
    this.onCancel,
    this.onComplete,
  });

  final SubagentsCatalog catalog;
  final RemoteAgentEntry? editing;
  final String targetScope;
  final List<SubagentModelOption> modelOptions;
  final FutureOr<void> Function()? onComposerRefresh;
  final bool embedded;
  final VoidCallback? onCancel;
  final VoidCallback? onComplete;

  @override
  State<SubagentFormDialog> createState() => _SubagentFormDialogState();
}

class _SubagentFormDialogState extends State<SubagentFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _systemPrompt;
  late String _color;
  late bool _injectAgentsMd;
  late bool _inheritAllTools;
  late Set<String> _selectedTools;
  late String _model;
  String? _thoughtLevel;
  String? _validation;
  bool _confirmDelete = false;

  bool get _saving {
    final id = widget.editing == null
        ? 'create-agent'
        : 'update:${widget.editing!.id}';
    return widget.catalog.isOperating(id);
  }

  Object? get _error {
    final id = widget.editing == null
        ? 'create-agent'
        : 'update:${widget.editing!.id}';
    return widget.catalog.operationError(id);
  }

  @override
  void initState() {
    super.initState();
    final raw = widget.editing?.raw ?? const <String, dynamic>{};
    _name = TextEditingController(text: _string(raw['name'] ?? raw['title']));
    _description = TextEditingController(text: _string(raw['description']));
    _systemPrompt = TextEditingController(
        text: _string(raw['systemPrompt'] ?? raw['prompt']));
    _color = _string(raw['color']).isEmpty ? 'yellow' : _string(raw['color']);
    _injectAgentsMd =
        raw['injectAgentsMd'] is bool ? raw['injectAgentsMd'] as bool : true;
    final rawTools = raw['tools'];
    _inheritAllTools = rawTools is! List ||
        rawTools.isEmpty ||
        rawTools.any((tool) => tool is String && tool.trim() == '*');
    _selectedTools = {
      if (rawTools is List)
        for (final tool in rawTools)
          if (tool is String && SubagentsCatalog.defaultTools.contains(tool))
            tool,
    };
    _model = _string(raw['model']).isEmpty ? 'inherit' : _string(raw['model']);
    _thoughtLevel = _string(raw['thoughtLevel']).isEmpty
        ? null
        : _string(raw['thoughtLevel']);
    _name.addListener(_clearValidation);
    _description.addListener(_clearValidation);
    _systemPrompt.addListener(_clearValidation);
    widget.catalog.addListener(_catalogChanged);
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_catalogChanged);
    _name.dispose();
    _description.dispose();
    _systemPrompt.dispose();
    super.dispose();
  }

  static String _string(Object? value) => value is String ? value : '';

  void _clearValidation() {
    if (_validation != null && mounted) setState(() => _validation = null);
  }

  void _catalogChanged() {
    if (mounted) setState(() {});
  }

  List<SubagentModelOption> get _modelChoices => [
        const SubagentModelOption(value: 'inherit', label: 'Main model'),
        ...widget.modelOptions.where((item) => item.value != 'inherit'),
      ];

  List<String> get _unknownTools => [
        for (final tool in widget.editing?.tools ?? const <String>[])
          if (!SubagentsCatalog.defaultTools.contains(tool) &&
              tool.trim() != '*')
            tool,
      ];

  SubagentModelOption? get _currentModelOption {
    for (final option in _modelChoices) {
      if (option.value == _model) return option;
    }
    return null;
  }

  bool _valid() {
    final name = _name.text.trim();
    if (name.length < 3 || name.length > 50) {
      _validation = uiText(context, '名称长度必须为 3–50 个字符。',
          'Name must be between 3 and 50 characters.');
      return false;
    }
    if (!RegExp(r'^[a-zA-Z0-9-]+$').hasMatch(name)) {
      _validation = uiText(context, '名称只能包含字母、数字和连字符。',
          'Name may contain only letters, digits and hyphens.');
      return false;
    }
    if (_description.text.trim().isEmpty) {
      _validation = uiText(context, '描述不能为空。', 'Description is required.');
      return false;
    }
    if (_systemPrompt.text.trim().isEmpty) {
      _validation = uiText(context, '系统提示词不能为空。', 'System prompt is required.');
      return false;
    }
    if (_model != 'inherit' && _currentModelOption == null) {
      _validation =
          uiText(context, '所选模型不可用。', 'Selected model is unavailable.');
      return false;
    }
    if (_thoughtLevel != null &&
        (_currentModelOption == null ||
            !_currentModelOption!.thoughtLevels.contains(_thoughtLevel))) {
      _validation = uiText(
          context, '所选思考档位不可用。', 'Selected thought level is unavailable.');
      return false;
    }
    _validation = null;
    return true;
  }

  Map<String, dynamic> _config() {
    final raw = widget.editing?.raw ?? const <String, dynamic>{};
    final config = <String, dynamic>{...raw};
    for (final key in const [
      'id',
      'agentId',
      'path',
      'filePath',
      'projectPath',
      'scope',
      'source',
      'readOnly',
      'enabled',
      'pluginId',
      'pluginName',
      'title',
      'modelOverride',
      'thoughtLevelOverride',
    ]) {
      config.remove(key);
    }
    config['name'] = _name.text.trim();
    config['description'] = _description.text.trim();
    config['systemPrompt'] = _systemPrompt.text.trim();
    config['color'] = _color;
    config['injectAgentsMd'] = _injectAgentsMd;
    if (_model == 'inherit') {
      config.remove('model');
      config.remove('thoughtLevel');
    } else {
      config['model'] = _model;
      if (_thoughtLevel?.trim().isNotEmpty == true) {
        config['thoughtLevel'] = _thoughtLevel!.trim();
      } else {
        config.remove('thoughtLevel');
      }
    }
    if (_inheritAllTools) {
      config.remove('tools');
    } else {
      final preserved = widget.editing?.tools?.where(
              (tool) => !SubagentsCatalog.defaultTools.contains(tool)) ??
          const Iterable<String>.empty();
      config['tools'] = {
        ..._selectedTools,
        ...preserved,
      }.toList();
    }
    return config;
  }

  Future<void> _save() async {
    if (_saving || !_valid()) {
      if (mounted) setState(() {});
      return;
    }
    final ok = widget.editing == null
        ? await widget.catalog
            .createAgent(config: _config(), targetScope: widget.targetScope)
        : await widget.catalog.updateAgent(widget.editing!, config: _config());
    if (!mounted) return;
    if (ok) {
      await widget.onComposerRefresh?.call();
      if (widget.onComplete != null) {
        widget.onComplete!();
      } else if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      setState(() {});
    }
  }

  Future<void> _delete() async {
    final editing = widget.editing;
    if (editing == null || _saving) return;
    if (!_confirmDelete) {
      setState(() => _confirmDelete = true);
      return;
    }
    final ok = await widget.catalog.deleteAgent(editing);
    if (!mounted) return;
    if (ok) {
      await widget.onComposerRefresh?.call();
      if (widget.onComplete != null) {
        widget.onComplete!();
      } else if (mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final operationError = _error;
    final body = ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: widget.embedded
              ? MediaQuery.sizeOf(context).height * .62
              : double.infinity,
        ),
        child: SizedBox(
          width: widget.embedded ? double.infinity : 620,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  uiText(context, '保存前填写必填字段；取消不会发送请求。',
                      'Fill the required fields before saving. Cancel sends no request.'),
                  style: TextStyle(fontSize: 12, color: ink.subtlest),
                ),
                const SizedBox(height: 14),
                _field(context, _name,
                    label: uiText(context, '名称', 'Name'), hint: 'review-agent'),
                const SizedBox(height: 12),
                _field(context, _description,
                    label: uiText(context, '描述', 'Description')),
                const SizedBox(height: 12),
                _field(context, _systemPrompt,
                    label: uiText(context, '系统提示词', 'System prompt'),
                    minLines: 4,
                    maxLines: 8),
                const SizedBox(height: 12),
                _modelAndThought(context),
                const SizedBox(height: 12),
                _colorAndTools(context, ink),
                const SizedBox(height: 12),
                Material(
                  color: Colors.transparent,
                  child: SwitchListTile.adaptive(
                    key: const ValueKey('subagent-inject-agents-md'),
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                        uiText(context, '注入 AGENTS.md', 'Inject AGENTS.md')),
                    value: _injectAgentsMd,
                    onChanged: _saving
                        ? null
                        : (value) => setState(() => _injectAgentsMd = value),
                  ),
                ),
                if (_validation != null || operationError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _validation ??
                        uiText(context, '保存失败，请检查连接后重试。',
                            'Save failed. Check the connection and retry.'),
                    style: TextStyle(color: ink.diffRemoved, fontSize: 12),
                  ),
                ],
                if (_confirmDelete && widget.editing != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    uiText(context, '再次点击删除以确认。',
                        'Click delete again to confirm.'),
                    style: TextStyle(color: ink.diffRemoved, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ));
    final actions = <Widget>[
      if (widget.editing != null)
        TextButton.icon(
          key: const ValueKey('subagent-delete-confirm'),
          onPressed: _saving ? null : _delete,
          icon: const Icon(Icons.delete_outline, size: 16),
          label: Text(uiText(context, '删除', 'Delete')),
        ),
      const SizedBox(width: 8),
      TextButton(
        onPressed: _saving
            ? null
            : (widget.onCancel ?? () => Navigator.of(context).pop(false)),
        child: Text(uiText(context, '取消', 'Cancel')),
      ),
      FilledButton(
        key: const ValueKey('subagent-save'),
        onPressed: _saving ? null : _save,
        child: Text(_saving
            ? uiText(context, '保存中', 'Saving')
            : uiText(context, '保存', 'Save')),
      ),
    ];
    if (widget.embedded) {
      return Material(
        type: MaterialType.transparency,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: ink.card,
            border: Border.all(color: ink.border),
            borderRadius: BorderRadius.circular(ZRadius.xl),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              body,
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(spacing: 8, children: actions),
              ),
            ],
          ),
        ),
      );
    }
    return AlertDialog(
      title: Text(widget.editing == null
          ? uiText(context, '新建子智能体', 'New subagent')
          : uiText(context, '编辑子智能体', 'Edit subagent')),
      content: body,
      actions: actions,
    );
  }

  Widget _field(
    BuildContext context,
    TextEditingController controller, {
    required String label,
    String? hint,
    int minLines = 1,
    int maxLines = 1,
  }) =>
      TextField(
        controller: controller,
        enabled: !_saving,
        minLines: minLines,
        maxLines: maxLines,
        decoration: InputDecoration(
          isDense: true,
          labelText: label,
          hintText: hint,
          alignLabelWithHint: minLines > 1,
          border: const OutlineInputBorder(),
        ),
      );

  Widget _modelAndThought(BuildContext context) {
    final options = _modelChoices;
    final selected =
        options.any((option) => option.value == _model) ? _model : 'inherit';
    final thoughtLevels =
        _currentModelOption?.thoughtLevels ?? const <String>[];
    final modelField = DropdownButtonFormField<String>(
      key: const ValueKey('subagent-model-field'),
      isExpanded: true,
      initialValue: selected,
      decoration: InputDecoration(
        isDense: true,
        labelText: uiText(context, '模型', 'Model'),
        border: const OutlineInputBorder(),
      ),
      items: [
        for (final option in options)
          DropdownMenuItem(value: option.value, child: Text(option.label)),
      ],
      onChanged: _saving
          ? null
          : (value) {
              if (value == null) return;
              setState(() {
                _model = value;
                _thoughtLevel = null;
              });
            },
    );
    final thoughtField = DropdownButtonFormField<String?>(
      key: const ValueKey('subagent-thought-level-field'),
      isExpanded: true,
      initialValue:
          thoughtLevels.contains(_thoughtLevel) ? _thoughtLevel : null,
      decoration: InputDecoration(
        isDense: true,
        labelText: uiText(context, '思考档位（可选）', 'Thought level (optional)'),
        border: const OutlineInputBorder(),
      ),
      items: [
        DropdownMenuItem<String?>(
            value: null, child: Text(uiText(context, '默认', 'Default'))),
        for (final level in thoughtLevels)
          DropdownMenuItem<String?>(value: level, child: Text(level)),
      ],
      onChanged: _saving || _model == 'inherit'
          ? null
          : (value) => setState(() => _thoughtLevel = value),
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.maxWidth.isFinite && constraints.maxWidth < 520;
        if (compact) {
          return Column(
            children: [
              modelField,
              const SizedBox(height: 12),
              thoughtField,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: modelField),
            const SizedBox(width: 12),
            Expanded(child: thoughtField),
          ],
        );
      },
    );
  }

  Widget _colorAndTools(BuildContext context, InkTokens ink) {
    const colors = [
      'yellow',
      'blue',
      'green',
      'red',
      'purple',
      'orange',
      'pink',
      'cyan'
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(uiText(context, '颜色', 'Color'),
            style: TextStyle(fontSize: 12, color: ink.subtlest)),
        const SizedBox(height: 7),
        Wrap(
          spacing: 8,
          children: [
            for (final color in colors)
              ChoiceChip(
                key: ValueKey('subagent-color-$color'),
                label: Text(color),
                selected: _color == color,
                onSelected:
                    _saving ? null : (_) => setState(() => _color = color),
              ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          key: const ValueKey('subagent-tools-mode'),
          initialValue: _inheritAllTools ? 'all' : 'custom',
          decoration: InputDecoration(
            isDense: true,
            labelText: uiText(context, '工具', 'Tools'),
            border: const OutlineInputBorder(),
          ),
          items: [
            DropdownMenuItem(
                value: 'all',
                child: Text(uiText(context, '全部工具', 'All tools'))),
            DropdownMenuItem(
                value: 'custom',
                child: Text(uiText(context, '自定义工具', 'Custom tools'))),
          ],
          onChanged: _saving
              ? null
              : (value) => setState(() {
                    _inheritAllTools = value == 'all';
                    if (!_inheritAllTools && _selectedTools.isEmpty) {
                      _selectedTools = {...SubagentsCatalog.defaultTools};
                    }
                  }),
        ),
        if (!_inheritAllTools) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: ink.surfaceFill,
              borderRadius: BorderRadius.circular(ZRadius.lg),
              border: Border.all(color: ink.border),
            ),
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final tool in SubagentsCatalog.defaultTools)
                  FilterChip(
                    label: Text(tool, style: const TextStyle(fontSize: 11)),
                    selected: _selectedTools.contains(tool),
                    onSelected: _saving
                        ? null
                        : (selected) => setState(() {
                              if (selected) {
                                _selectedTools.add(tool);
                              } else {
                                _selectedTools.remove(tool);
                              }
                            }),
                  ),
                for (final tool in _unknownTools)
                  FilterChip(
                    key: ValueKey('subagent-unknown-tool-$tool'),
                    label: Text(tool, style: const TextStyle(fontSize: 11)),
                    selected: true,
                    onSelected: _saving ? null : (_) {},
                  ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
