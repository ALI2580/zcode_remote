import 'dart:async';
import 'package:flutter/material.dart';

import '../state/mcp_catalog.dart';
import '../state/mcp_status.dart';
import '../state/client_preferences.dart';
import '../state/plugin_catalog.dart';
import 'official_icons.dart';
import 'plugin_display_name.dart';
import 'theme.dart';
import 'settings_scope.dart';

/// Standalone MCP settings surface. The settings center can embed this page
/// after choosing the owning workspace; it intentionally has no navigation
/// dependency and never touches a live device by itself.
class McpSettingsPage extends StatefulWidget {
  const McpSettingsPage({
    super.key,
    required this.catalog,
    this.scope = 'user',
    this.onScopeChanged,
    this.onOpenAuthorization,
    this.onImport,
    this.workspaceScopeOptions = const [],
    this.selectedWorkspaceScope,
    this.onWorkspaceScopeChanged,
    this.title,
    this.pluginCatalog,
  });

  final McpCatalog catalog;
  final String scope;
  final ValueChanged<String>? onScopeChanged;
  final Future<void> Function(String url)? onOpenAuthorization;
  final VoidCallback? onImport;
  final List<SettingsScopeOption> workspaceScopeOptions;
  final SettingsScopeOption? selectedWorkspaceScope;
  final FutureOr<void> Function(SettingsScopeOption option)?
      onWorkspaceScopeChanged;
  final String? title;
  final PluginCatalog? pluginCatalog;

  @override
  State<McpSettingsPage> createState() => _McpSettingsPageState();
}

class _McpSettingsPageState extends State<McpSettingsPage>
    with WidgetsBindingObserver {
  String _query = '';
  McpServerEntry? _editingEntry;
  bool _creating = false;
  String? _lastObservedConfigSignature;
  int _editorGeneration = 0;
  Timer? _oauthTimer;
  bool _oauthTickRunning = false;
  String? _oauthPendingSignature;
  DateTime? _oauthDeadline;
  int _oauthFollowups = 0;
  bool _oauthLifecycleStopped = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.catalog.addListener(_changed);
    widget.pluginCatalog?.addListener(_changed);
    unawaited(_ensureConnectedForVisible());
  }

  @override
  void didUpdateWidget(covariant McpSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.catalog != widget.catalog) {
      oldWidget.catalog.removeListener(_changed);
      oldWidget.pluginCatalog?.removeListener(_changed);
      widget.catalog.addListener(_changed);
      widget.pluginCatalog?.addListener(_changed);
      _editorGeneration++;
      _editingEntry = null;
      _creating = false;
      _lastObservedConfigSignature = null;
      _stopOAuthPolling(reset: true);
      unawaited(_ensureConnectedForVisible());
    } else if (oldWidget.pluginCatalog != widget.pluginCatalog) {
      oldWidget.pluginCatalog?.removeListener(_changed);
      widget.pluginCatalog?.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.catalog.removeListener(_changed);
    widget.pluginCatalog?.removeListener(_changed);
    WidgetsBinding.instance.removeObserver(this);
    _stopOAuthPolling(reset: true);
    super.dispose();
  }

  void _changed() {
    if (mounted) {
      setState(() {});
      if (widget.catalog.status == McpCatalogStatus.loaded) {
        final signature = _visibleConnectionSignature;
        if (signature != _lastObservedConfigSignature) {
          _lastObservedConfigSignature = signature;
          unawaited(_ensureConnectedForVisible(signature));
        }
      }
      _syncOAuthPolling();
    }
  }

  String get _visibleConnectionSignature {
    final plugins = (widget.pluginCatalog?.items
            .where((plugin) =>
                plugin.installed && !plugin.packageMissing && plugin.enabled)
            .map((plugin) => plugin.mcpCapabilitySignature)
            .toList() ??
        <String>[]);
    plugins.sort();
    return '${widget.catalog.configSignature}|${plugins.join('|')}';
  }

  Future<void> _ensureConnectedForVisible([String? signature]) {
    final value = signature ?? _visibleConnectionSignature;
    return widget.catalog.ensureConnectedForVisible(
      additionalSignature: value,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _oauthLifecycleStopped = false;
      _syncOAuthPolling();
      if (widget.catalog.oauthPendingSignature != null) {
        unawaited(widget.catalog.refreshOAuthStatus());
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _oauthLifecycleStopped = true;
      _stopOAuthPolling();
    }
  }

  void _syncOAuthPolling() {
    if (!mounted || _oauthLifecycleStopped) return;
    final signature = widget.catalog.oauthPendingSignature;
    if (signature != null) {
      if (signature != _oauthPendingSignature) {
        _oauthPendingSignature = signature;
        _oauthDeadline = DateTime.now().add(const Duration(minutes: 5));
        _oauthFollowups = 0;
      }
      _ensureOAuthTimer();
      return;
    }
    if (_oauthPendingSignature != null && _oauthFollowups < 10) {
      _ensureOAuthTimer();
    } else {
      _stopOAuthPolling(reset: true);
    }
  }

  void _ensureOAuthTimer() {
    if (_oauthTimer != null || _oauthLifecycleStopped) return;
    _oauthTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      unawaited(_oauthTick());
    });
  }

  Future<void> _oauthTick() async {
    if (!mounted || _oauthLifecycleStopped || _oauthTickRunning) return;
    final deadline = _oauthDeadline;
    if (deadline != null && DateTime.now().isAfter(deadline)) {
      _stopOAuthPolling(reset: true);
      return;
    }
    if (_oauthPendingSignature == null) return;
    _oauthTickRunning = true;
    try {
      await widget.catalog.refreshOAuthStatus();
      if (!mounted || _oauthLifecycleStopped) return;
      if (widget.catalog.statusModeUnsupported) {
        _stopOAuthPolling(reset: true);
        return;
      }
      if (widget.catalog.oauthPendingSignature == null) {
        _oauthFollowups++;
        if (_oauthFollowups >= 10) _stopOAuthPolling(reset: true);
      } else {
        _syncOAuthPolling();
      }
    } finally {
      _oauthTickRunning = false;
    }
  }

  void _stopOAuthPolling({bool reset = false}) {
    _oauthTimer?.cancel();
    _oauthTimer = null;
    _oauthTickRunning = false;
    if (reset) {
      _oauthPendingSignature = null;
      _oauthDeadline = null;
      _oauthFollowups = 0;
    }
  }

  List<McpServerEntry> get _visibleItems {
    final query = _query.trim().toLowerCase();
    return widget.catalog.items.where((entry) {
      if (entry.scope != widget.scope &&
          !(widget.scope == 'user' && entry.scope == 'common')) {
        return false;
      }
      if (query.isEmpty) return true;
      final haystack = [
        entry.name,
        entry.type.value,
        entry.config['url'],
        entry.config['command'],
      ].whereType<String>().join(' ').toLowerCase();
      return haystack.contains(query);
    }).toList(growable: false);
  }

  Map<String, List<McpServerEntry>> _pluginGroups(
      List<McpServerEntry> entries) {
    final groups = <String, List<McpServerEntry>>{};
    for (final entry in entries.where((entry) => entry.isReadOnly)) {
      final pluginId = entry.raw['pluginId'] is String
          ? (entry.raw['pluginId'] as String).trim()
          : '';
      final pluginName = entry.raw['pluginName'] is String
          ? (entry.raw['pluginName'] as String).trim()
          : '';
      // Plugin id is the identity boundary. Same display names from two
      // marketplaces must remain separate groups.
      final key = pluginId.isNotEmpty
          ? pluginId
          : pluginName.isNotEmpty
              ? pluginName
              : uiText(context, '插件能力', 'Plugin capability');
      groups.putIfAbsent(key, () => <McpServerEntry>[]).add(entry);
    }
    final sorted = groups.entries.toList()
      ..sort((a, b) {
        int priority(List<McpServerEntry> value) => value.any((entry) =>
                entry.authorizationUrl != null || entry.error != null)
            ? 0
            : 1;
        final byPriority = priority(a.value).compareTo(priority(b.value));
        return byPriority == 0 ? a.key.compareTo(b.key) : byPriority;
      });
    return {for (final entry in sorted) entry.key: entry.value};
  }

  /// Projects plugin-management's declared/runtime/host MCP capabilities into
  /// the read-only groups shown by the official MCP page. A raw
  /// `source: plugin` row from the native config read is intentionally not
  /// enough to create a group; plugin-management must have reported the
  /// installed plugin and at least one verified MCP capability.
  List<McpServerEntry> _pluginCapabilityEntries() {
    final plugins = widget.pluginCatalog?.items ?? const <CatalogPlugin>[];
    final result = <McpServerEntry>[];
    for (final plugin in plugins) {
      // CXt filters disabled plugin projections upstream. The plugin catalog
      // already carries the authoritative effective configScope snapshot, so
      // installation scope is not a visibility gate here.
      if (!plugin.installed || plugin.packageMissing || !plugin.enabled) {
        continue;
      }
      final host = plugin.hostMcpServerNames.toSet();
      final declared = plugin.declaredMcpServerNames;
      final runtime = plugin.mcpServerNames;
      final names = <String>{
        ...host,
        ...declared.map((value) => _pluginDisplayName(plugin, value)),
        ...runtime.map((value) => _pluginDisplayName(plugin, value)),
      };
      for (final displayName in names) {
        final runtimeName = host.contains(displayName)
            ? displayName
            : _pluginRuntimeName(plugin, displayName, runtime);
        final status = widget.catalog.statusForPlugin(
          pluginId: plugin.id,
          runtimeServerName: runtimeName,
          displayName: displayName,
        );
        final raw = <String, dynamic>{
          'id': '${plugin.id}:$displayName',
          'name': displayName,
          'source': 'plugin',
          'scope': 'common',
          'enabled': plugin.enabled,
          'pluginId': plugin.id,
          'pluginName': plugin.name,
          'pluginMarketplace': plugin.marketplace,
          'runtimeServerName': runtimeName,
          'pluginEnabled': plugin.enabled,
          'active': host.contains(displayName) ||
              runtime.contains(displayName) ||
              runtime.any(
                  (value) => _pluginDisplayName(plugin, value) == displayName),
          if (host.contains(displayName)) 'hostProvided': true,
          'location': {'source': 'plugin'},
          'config': const <String, dynamic>{},
          if (status != null) ...{
            if (status.state != null) 'status': status.state,
            if (status.toolCount != null) 'toolCount': status.toolCount,
            if (status.error != null) 'error': status.error,
            if (status.failureKind != null) 'failureKind': status.failureKind,
            if (status.authorizationUrl != null)
              'authorizationUrl': status.authorizationUrl,
            if (status.raw['authorization'] is Map)
              'authorization': status.raw['authorization'],
          },
        };
        result.add(McpServerEntry.fromRaw(raw));
      }
    }
    return result;
  }

  String _pluginDisplayName(CatalogPlugin plugin, String value) {
    final prefix = 'plugin:${plugin.name}:';
    return value.startsWith(prefix) ? value.substring(prefix.length) : value;
  }

  String _pluginRuntimeName(
      CatalogPlugin plugin, String displayName, List<String> runtimeNames) {
    for (final value in runtimeNames) {
      if (value == displayName ||
          _pluginDisplayName(plugin, value) == displayName) {
        return value;
      }
    }
    return 'plugin:${plugin.name}:$displayName';
  }

  String _pluginGroupLabel(String key, List<McpServerEntry> entries) {
    final pluginId = entries
        .map((entry) => entry.raw['pluginId'])
        .whereType<String>()
        .map((value) => value.trim())
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    for (final plugin
        in widget.pluginCatalog?.items ?? const <CatalogPlugin>[]) {
      if (plugin.id != pluginId && plugin.name != key) continue;
      return pluginDisplayName(plugin, Localizations.localeOf(context));
    }
    return key;
  }

  Widget _sectionLabel(BuildContext context, String label, int count,
      {Widget? actions}) {
    final labelRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(label,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: 6),
        Text('$count',
            style: TextStyle(
                fontSize: 12,
                color: ZInk.of(Theme.of(context).colorScheme).subtlest)),
      ],
    );
    return LayoutBuilder(builder: (context, constraints) {
      final compact =
          constraints.maxWidth.isFinite && constraints.maxWidth < 520;
      return Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 10),
        child: actions == null || !compact
            ? Row(children: [
                Expanded(child: labelRow),
                if (actions != null) actions,
              ])
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  labelRow,
                  const SizedBox(height: 6),
                  Align(alignment: Alignment.centerRight, child: actions),
                ],
              ),
      );
    });
  }

  Future<void> _openEditor([McpServerEntry? editing]) async {
    setState(() {
      _editingEntry = editing;
      _creating = editing == null;
    });
  }

  void _closeEditor() {
    if (!mounted) return;
    setState(() {
      _editingEntry = null;
      _creating = false;
    });
  }

  Future<void> _delete(McpServerEntry entry) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(uiText(context, '删除 MCP 服务器', 'Delete MCP server')),
        content: Text(uiText(
            context, '确定删除「${entry.name}」吗？', 'Delete “${entry.name}”?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(uiText(context, '取消', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(uiText(context, '删除', 'Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final success = await widget.catalog.delete(entry);
    if (!success && mounted) {
      _showError(widget.catalog.operationError(entry.identity));
    }
  }

  Future<void> _toggle(McpServerEntry entry, bool enabled) async {
    final success = await widget.catalog.setEnabled(entry, enabled);
    if (!success && mounted) {
      _showError(widget.catalog.operationError(entry.identity));
    }
  }

  void _showError(Object? value) {
    final message = value?.toString() ??
        uiText(context, '操作失败，请重试。', 'Operation failed. Retry.');
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _authorize(McpServerEntry entry) async {
    final value = entry.authorizationUrl?.trim();
    final uri = value == null ? null : Uri.tryParse(value);
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
      _showError(StateError('MCP authorization URL is unavailable'));
      return;
    }
    final callback = widget.onOpenAuthorization;
    if (callback == null) {
      _showError(StateError('No external browser handler is configured'));
      return;
    }
    try {
      await callback(value!);
    } catch (error) {
      // Keep the challenge visible so the user can retry after a platform
      // browser failure; an error must not look like successful authorization.
      if (mounted) _showError(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final items = _visibleItems;
    final pluginItems = _pluginCapabilityEntries();
    final catalog = widget.catalog;
    final hasStatusError = catalog.statusListStatus == McpStatusStatus.error;
    if (_editingEntry != null || _creating) {
      final editorGeneration = _editorGeneration;
      return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: McpServerFormDialog(
          key: ValueKey(
              'mcp-inline-editor-${identityHashCode(catalog)}-${_editingEntry?.identity ?? 'new'}'),
          catalog: catalog,
          scope: widget.scope,
          editing: _editingEntry,
          inline: true,
          onSaved: () {
            if (editorGeneration == _editorGeneration) _closeEditor();
          },
          onCanceled: _closeEditor,
        ),
      );
    }
    return SingleChildScrollView(
      // SettingsCenter already owns the page title and outer 28px gutter.
      // Keeping this surface flush prevents a second title/padding stack when
      // it is embedded, while the bottom inset still gives standalone use air.
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.workspaceScopeOptions.length > 1 &&
              widget.onWorkspaceScopeChanged != null) ...[
            SettingsScopePicker(
              options: widget.workspaceScopeOptions,
              selected: widget.selectedWorkspaceScope,
              onSelected: widget.onWorkspaceScopeChanged!,
            ),
            const SizedBox(height: 8),
          ],
          if (catalog.error != null) _ErrorBanner(error: catalog.error!),
          if (hasStatusError) _ErrorBanner(error: catalog.statusListError!),
          if (catalog.statusModeUnsupported)
            _InfoBanner(
              text: uiText(context, '远端不支持被动状态读取；请使用“连接并刷新”。',
                  'Passive status is unavailable on this attachment; use “Connect & refresh”.'),
            ),
          _McpTopBar(
            scope: widget.scope,
            onScopeChanged: widget.onScopeChanged,
            query: _query,
            onQueryChanged: (value) => setState(() => _query = value),
            count: items.where((entry) => !entry.isReadOnly).length +
                pluginItems.length,
            onRefresh: catalog.statusListStatus == McpStatusStatus.loading
                ? null
                : () => unawaited(catalog.connectAndRefreshStatus()),
            onImport: widget.onImport,
            onCreate: () => unawaited(_openEditor()),
          ),
          const SizedBox(height: 14),
          Builder(builder: (context) {
            final loading = catalog.status == McpCatalogStatus.loading &&
                catalog.items.isEmpty;
            if (loading) {
              return const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final installed =
                items.where((entry) => !entry.isReadOnly).toList();
            final plugins = _pluginGroups(pluginItems);
            return ListView(
              key: const ValueKey('mcp-server-list'),
              shrinkWrap: true,
              primary: false,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _sectionLabel(context, uiText(context, '已安装', 'Installed'),
                    installed.length,
                    actions: _McpInstalledActions(
                      onImport: widget.onImport,
                      onRefresh: catalog.statusListStatus ==
                              McpStatusStatus.loading
                          ? null
                          : () => unawaited(catalog.connectAndRefreshStatus()),
                      onCreate: () => unawaited(_openEditor()),
                    )),
                if (installed.isNotEmpty)
                  _McpRows(
                    entries: installed,
                    catalog: catalog,
                    onEdit: _openEditor,
                    onDelete: _delete,
                    onToggle: _toggle,
                    onAuthorize: _authorize,
                    onRetry: () => _ensureConnectedForVisible(),
                  ),
                if (items.isEmpty && pluginItems.isEmpty)
                  ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 200),
                    child: _EmptyMcp(onCreate: () => unawaited(_openEditor())),
                  ),
                for (final group in plugins.entries) ...[
                  const SizedBox(height: 18),
                  _sectionLabel(
                      context,
                      _pluginGroupLabel(group.key, group.value),
                      group.value.length),
                  _McpRows(
                    entries: group.value,
                    catalog: catalog,
                    onEdit: _openEditor,
                    onDelete: _delete,
                    onToggle: _toggle,
                    onAuthorize: _authorize,
                    onRetry: () => _ensureConnectedForVisible(),
                  ),
                ],
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _McpTopBar extends StatelessWidget {
  const _McpTopBar({
    required this.scope,
    required this.onScopeChanged,
    required this.query,
    required this.onQueryChanged,
    required this.count,
    required this.onRefresh,
    required this.onImport,
    required this.onCreate,
  });

  final String scope;
  final ValueChanged<String>? onScopeChanged;
  final String query;
  final ValueChanged<String> onQueryChanged;
  final int count;
  final VoidCallback? onRefresh;
  final VoidCallback? onImport;
  final VoidCallback onCreate;

  Widget _scope(BuildContext context, InkTokens ink) {
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
                key: const ValueKey('mcp-scope'),
                value: scope,
                isDense: true,
                isExpanded: true,
                underline: const SizedBox.shrink(),
                padding: EdgeInsets.zero,
                icon: const LucideIcon('chevron-down', size: 12),
                style: TextStyle(fontSize: 13, color: ink.text),
                onChanged: (value) {
                  if (value != null) onScopeChanged?.call(value);
                },
                items: [
                  DropdownMenuItem(
                    value: 'user',
                    child: Text(uiText(context, '用户', 'User')),
                  ),
                  DropdownMenuItem(
                    value: 'workspace',
                    child: Text(uiText(context, '工作区', 'Workspace')),
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

  Widget _search(BuildContext context, InkTokens ink) {
    return _McpSearchField(
      query: query,
      onChanged: onQueryChanged,
      hintText: uiText(context, '搜索 MCP 服务器...', 'Search MCP servers...'),
      border: ink.border,
      textColor: ink.text,
      subtlest: ink.subtlest,
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return LayoutBuilder(builder: (context, constraints) {
      final header = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _scope(context, ink),
          const SizedBox(width: 26),
          Text(
            uiText(context, 'MCP $count', 'MCP $count'),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ],
      );
      if (constraints.maxWidth < 520) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            header,
            const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: _search(context, ink)),
          ],
        );
      }
      return Row(
        children: [
          header,
          const Spacer(),
          _search(context, ink),
        ],
      );
    });
  }
}

class _McpSearchField extends StatefulWidget {
  const _McpSearchField({
    required this.query,
    required this.onChanged,
    required this.hintText,
    required this.border,
    required this.textColor,
    required this.subtlest,
  });

  final String query;
  final ValueChanged<String> onChanged;
  final String hintText;
  final Color border;
  final Color textColor;
  final Color subtlest;

  @override
  State<_McpSearchField> createState() => _McpSearchFieldState();
}

class _McpSearchFieldState extends State<_McpSearchField> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.query);
  }

  @override
  void didUpdateWidget(covariant _McpSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query != _controller.text) {
      _controller.value = TextEditingValue(
        text: widget.query,
        selection: TextSelection.collapsed(offset: widget.query.length),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 256,
      height: 32,
      child: TextField(
        key: const ValueKey('mcp-search'),
        controller: _controller,
        onChanged: widget.onChanged,
        style: TextStyle(fontSize: 13, color: widget.textColor),
        decoration: InputDecoration(
          isDense: true,
          prefixIcon: const Padding(
            padding: EdgeInsets.only(left: 10, right: 5),
            child: LucideIcon('search', size: 14),
          ),
          prefixIconConstraints:
              const BoxConstraints(minWidth: 28, minHeight: 28),
          hintText: widget.hintText,
          hintStyle: TextStyle(fontSize: 13, color: widget.subtlest),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ZRadius.lg),
            borderSide: BorderSide(color: widget.border),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(ZRadius.lg),
            borderSide: BorderSide(color: widget.border),
          ),
        ),
      ),
    );
  }
}

class _McpInstalledActions extends StatelessWidget {
  const _McpInstalledActions({
    required this.onImport,
    required this.onRefresh,
    required this.onCreate,
  });

  final VoidCallback? onImport;
  final VoidCallback? onRefresh;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        PopupMenuButton<String>(
          key: const ValueKey('mcp-more'),
          tooltip: uiText(context, '更多', 'More'),
          padding: EdgeInsets.zero,
          icon: const LucideIcon('ellipsis', size: 16),
          itemBuilder: (context) => [
            if (onImport != null)
              PopupMenuItem<String>(
                key: const ValueKey('mcp-import'),
                value: 'import',
                child: Text(uiText(context, '导入', 'Import')),
              ),
          ],
          onSelected: (value) {
            if (value == 'import') onImport?.call();
          },
        ),
        IconButton(
          key: const ValueKey('mcp-refresh'),
          tooltip: uiText(context, '刷新', 'Refresh'),
          onPressed: onRefresh,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 32, height: 32),
          icon: const LucideIcon('refresh-cw', size: 15),
        ),
        const SizedBox(width: 8),
        FilledButton.icon(
          key: const ValueKey('mcp-create'),
          onPressed: onCreate,
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
      ],
    );
  }
}

class _McpServerRow extends StatelessWidget {
  const _McpServerRow({
    required this.entry,
    required this.operating,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onAuthorize,
    required this.onRetry,
  });

  final McpServerEntry entry;
  final bool operating;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final ValueChanged<bool> onToggle;
  final VoidCallback onAuthorize;
  final VoidCallback onRetry;

  Color _statusColor(BuildContext context) => switch (entry.status) {
        'connected' => Colors.green,
        'connecting' => Colors.orange,
        'error' || 'failed' => Theme.of(context).colorScheme.error,
        _ => Theme.of(context).colorScheme.onSurface.withValues(alpha: .42),
      };

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final endpoint = entry.isReadOnly
        ? _pluginDescription(context)
        : entry.type == McpServerType.stdio
            ? [
                entry.config['command'],
                ...(entry.config['args'] is List
                    ? entry.config['args'] as List
                    : const [])
              ].whereType<String>().join(' ')
            : _redactedEndpoint(entry.config['url']);
    final details = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(entry.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 3),
        Text(
          entry.isReadOnly
              ? endpoint
              : endpoint.isEmpty
                  ? entry.type.value
                  : '${entry.type.value} · $endpoint',
          maxLines: entry.isReadOnly ? 2 : 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 12, color: ink.subtlest),
        ),
        if (entry.error != null && !entry.isReadOnly)
          Text(entry.error!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontSize: 12, color: Theme.of(context).colorScheme.error)),
      ],
    );
    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (entry.authorizationUrl != null)
          TextButton.icon(
            key: ValueKey('mcp-authorize-${entry.identity}'),
            onPressed: operating ? null : onAuthorize,
            icon: const Icon(Icons.open_in_new, size: 15),
            label: Text(uiText(context, '授权', 'Authorize')),
          ),
        if (!entry.isReadOnly) ...[
          PopupMenuButton<String>(
            key: ValueKey('mcp-row-menu-${entry.identity}'),
            tooltip: uiText(context, '更多操作', 'More actions'),
            padding: EdgeInsets.zero,
            icon: const LucideIcon('ellipsis', size: 17),
            enabled: entry.canManage && !operating,
            itemBuilder: (context) => [
              PopupMenuItem(
                key: ValueKey('mcp-edit-${entry.identity}'),
                value: 'edit',
                child: Text(uiText(context, '编辑', 'Edit')),
              ),
              PopupMenuItem(
                key: ValueKey('mcp-delete-${entry.identity}'),
                value: 'delete',
                child: Text(uiText(context, '删除', 'Delete')),
              ),
              PopupMenuItem(
                key: ValueKey('mcp-retry-${entry.identity}'),
                value: 'retry',
                child: Text(uiText(context, '重试连接', 'Retry connection')),
              ),
            ],
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
              if (value == 'retry') onRetry();
            },
          ),
          _McpCompactSwitch(
            key: ValueKey('mcp-enabled-${entry.identity}'),
            value: entry.enabled,
            onChanged: entry.canManage && !operating ? onToggle : null,
          ),
        ],
      ],
    );
    final row = LayoutBuilder(builder: (context, constraints) {
      final compact =
          constraints.maxWidth.isFinite && constraints.maxWidth < 520;
      final primary = Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _McpIconBox(entry: entry, color: _statusColor(context)),
          const SizedBox(width: 12),
          Expanded(child: details),
        ],
      );
      if (compact) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            primary,
            const SizedBox(height: 4),
            Align(alignment: Alignment.centerRight, child: actions),
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: primary),
          const SizedBox(width: 8),
          actions,
        ],
      );
    });
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: row,
    );
  }

  String _pluginDescription(BuildContext context) {
    final pluginName = entry.raw['pluginName'] is String
        ? (entry.raw['pluginName'] as String).trim()
        : '';
    if (entry.authorizationUrl?.trim().isNotEmpty == true) {
      return uiText(context, '需要授权后才能使用该 MCP 服务器。',
          'Authorization is required before this MCP server can be used.');
    }
    if (entry.error?.trim().isNotEmpty == true) {
      return uiText(context, 'MCP 服务器连接失败：${entry.error}',
          'MCP server connection failed: ${entry.error}');
    }
    final active = entry.raw['active'] == true &&
        entry.raw['pluginEnabled'] != false &&
        entry.raw['enabled'] != false;
    if (active &&
        (entry.status == 'connecting' ||
            entry.status == 'connected' ||
            entry.status == 'disconnected')) {
      return switch (entry.status) {
        'connecting' => uiText(
            context, '正在连接插件 MCP 服务器。', 'Connecting to the plugin MCP server.'),
        'connected' => uiText(context, '该插件 MCP 服务器已连接并可用。',
            'The plugin MCP server is connected and available.'),
        _ => uiText(context, '该插件 MCP 服务器已断开。',
            'The plugin MCP server is disconnected.'),
      };
    }
    if (entry.raw['hostProvided'] == true) {
      final target = pluginName.isEmpty ? 'installed' : pluginName;
      return uiText(
        context,
        '该 MCP 服务器由 ZCode 宿主为${pluginName.isEmpty ? '' : ' $pluginName'} 插件提供，运行时身份由宿主管理。',
        'This MCP server is provided by the ZCode host for the $target plugin; runtime identity is host-managed.',
      );
    }
    if (active) {
      return uiText(
          context, '该插件 MCP 服务器已启用。', 'The plugin MCP server is enabled.');
    }
    if (entry.raw['unavailable'] == true || entry.status == 'unavailable') {
      return uiText(context, '该插件 MCP 服务器当前不可用。',
          'The plugin MCP server is currently unavailable.');
    }
    if (entry.raw['pluginEnabled'] == false || entry.raw['enabled'] == false) {
      return uiText(context, '该 MCP 服务器内置在插件中，启用插件后会加载。',
          'This MCP server is built into a plugin. Enable the plugin to load it.');
    }
    return uiText(context, '该插件 MCP 服务器由已安装插件提供。',
        'The MCP server is provided by an installed plugin.');
  }

  String _redactedEndpoint(Object? value) {
    if (value is! String) return '';
    final uri = Uri.tryParse(value);
    if (uri == null) return value;
    var redacted = uri;
    if (uri.userInfo.isNotEmpty) {
      redacted = redacted.replace(userInfo: '<redacted>');
    }
    if (uri.queryParameters.isNotEmpty) {
      redacted = redacted.replace(
        queryParameters: {
          for (final entry in uri.queryParameters.entries)
            entry.key:
                _isSecretQueryKey(entry.key) ? '<redacted>' : entry.value,
        },
      );
    }
    return redacted.toString();
  }

  bool _isSecretQueryKey(String key) {
    final normalized = key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return normalized.contains('token') ||
        normalized.contains('secret') ||
        normalized.contains('key') ||
        normalized.contains('password') ||
        normalized == 'auth';
  }
}

class _McpIconBox extends StatelessWidget {
  const _McpIconBox({required this.entry, required this.color});

  final McpServerEntry entry;
  final Color color;

  Widget _icon() {
    if (!entry.isReadOnly) return const LucideIcon('blocks', size: 17);
    final name = entry.name.toLowerCase();
    if (name.contains('browser') || name.contains('node')) {
      return const Icon(Icons.web_asset_outlined, size: 17);
    }
    if (name.contains('computer')) return const Icon(Icons.grid_view, size: 17);
    if (name.contains('image') || name.contains('search')) {
      return const LucideIcon('file-image', size: 17);
    }
    return const LucideIcon('blocks', size: 17);
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Semantics(
      key: ValueKey('mcp-status-${entry.identity}'),
      label: switch (entry.status) {
        'connected' => 'Connected',
        'connecting' => 'Connecting',
        'error' || 'failed' => 'Connection failed',
        _ => 'Disconnected',
      },
      child: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: ink.hover,
                borderRadius: BorderRadius.circular(ZRadius.lg),
              ),
              child: SizedBox.expand(
                child: Center(
                    child: IconTheme(
                        data: IconThemeData(color: ink.text), child: _icon())),
              ),
            ),
            Positioned(
              right: -1,
              bottom: -1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(color: ink.card, width: 2),
                ),
                child: const SizedBox(width: 9, height: 9),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _McpCompactSwitch extends StatelessWidget {
  const _McpCompactSwitch({super.key, required this.value, this.onChanged});

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

class _McpRows extends StatelessWidget {
  const _McpRows({
    required this.entries,
    required this.catalog,
    required this.onEdit,
    required this.onDelete,
    required this.onToggle,
    required this.onAuthorize,
    required this.onRetry,
  });

  final List<McpServerEntry> entries;
  final McpCatalog catalog;
  final Future<void> Function([McpServerEntry?]) onEdit;
  final Future<void> Function(McpServerEntry) onDelete;
  final Future<void> Function(McpServerEntry, bool) onToggle;
  final Future<void> Function(McpServerEntry) onAuthorize;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: ZInk.of(Theme.of(context).colorScheme).card,
          borderRadius: BorderRadius.circular(ZRadius.xl),
          border:
              Border.all(color: ZInk.of(Theme.of(context).colorScheme).border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          children: [
            for (var index = 0; index < entries.length; index++) ...[
              if (index > 0)
                Divider(
                    height: 1,
                    thickness: 1,
                    color:
                        Theme.of(context).dividerColor.withValues(alpha: .45)),
              _McpServerRow(
                entry: entries[index],
                operating: catalog.isOperating(entries[index].identity),
                onEdit: () => unawaited(onEdit(entries[index])),
                onDelete: () => unawaited(onDelete(entries[index])),
                onToggle: (value) => unawaited(onToggle(entries[index], value)),
                onAuthorize: () => unawaited(onAuthorize(entries[index])),
                onRetry: () => unawaited(onRetry()),
              ),
            ],
          ],
        ),
      );
}

class _EmptyMcp extends StatelessWidget {
  const _EmptyMcp({required this.onCreate});
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(uiText(
                context, '当前范围没有 MCP 服务器。', 'No MCP servers in this scope.')),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: onCreate,
              icon: const Icon(Icons.add, size: 16),
              label: Text(uiText(context, '新建服务器', 'New server')),
            ),
          ],
        ),
      );
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(error.toString()),
      );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text),
      );
}

class McpServerFormDialog extends StatefulWidget {
  const McpServerFormDialog({
    super.key,
    required this.catalog,
    required this.scope,
    this.editing,
    this.inline = false,
    this.onSaved,
    this.onCanceled,
  });

  final McpCatalog catalog;
  final String scope;
  final McpServerEntry? editing;
  final bool inline;
  final VoidCallback? onSaved;
  final VoidCallback? onCanceled;

  @override
  State<McpServerFormDialog> createState() => _McpServerFormDialogState();
}

class _McpServerFormDialogState extends State<McpServerFormDialog> {
  late McpFormDraft _draft;
  late TextEditingController _name;
  late TextEditingController _command;
  late TextEditingController _args;
  late TextEditingController _env;
  late TextEditingController _url;
  late TextEditingController _headers;
  late TextEditingController _timeout;
  late TextEditingController _oauth;
  late TextEditingController _protocol;
  late TextEditingController _json;
  String _mode = 'form';
  String? _error;
  String? _jsonError;
  bool _optionalExpanded = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.editing == null
        ? McpFormDraft(storageLevel: widget.scope)
        : McpFormDraft.fromEntry(widget.editing!);
    _name = TextEditingController(text: _draft.name);
    _command = TextEditingController(text: _draft.command);
    _args = TextEditingController(text: _draft.args);
    _env = TextEditingController(text: _draft.env);
    _url = TextEditingController(text: _draft.url);
    _headers = TextEditingController(text: _draft.headers);
    _timeout = TextEditingController(text: _draft.timeoutMs);
    _oauth = TextEditingController(text: _draft.oauth);
    _protocol = TextEditingController(text: _draft.protocolVersion);
    _json = TextEditingController(text: _draft.toJson());
  }

  @override
  void dispose() {
    for (final controller in [
      _name,
      _command,
      _args,
      _env,
      _url,
      _headers,
      _timeout,
      _oauth,
      _protocol,
      _json,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _updateDraft() {
    _draft = _draft.copyWith(
      name: _name.text,
      command: _command.text,
      args: _args.text,
      env: _env.text,
      url: _url.text,
      headers: _headers.text,
      timeoutMs: _timeout.text,
      oauth: _oauth.text,
      protocolVersion: _protocol.text,
    );
  }

  void _setMode(String mode) {
    if (mode == _mode) return;
    if (mode == 'json') {
      _updateDraft();
      _json.text = _draft.toJson();
      _jsonError = null;
    } else {
      try {
        final parsed = McpFormDraft.parseJson(_json.text, fallback: _draft);
        _draft = parsed;
        _writeDraftControllers();
        _jsonError = null;
      } on Object catch (value) {
        setState(() => _jsonError = value.toString());
        return;
      }
    }
    setState(() => _mode = mode);
  }

  void _writeDraftControllers() {
    _name.text = _draft.name;
    _command.text = _draft.command;
    _args.text = _draft.args;
    _env.text = _draft.env;
    _url.text = _draft.url;
    _headers.text = _draft.headers;
    _timeout.text = _draft.timeoutMs;
    _oauth.text = _draft.oauth;
    _protocol.text = _draft.protocolVersion;
  }

  Future<void> _save() async {
    McpFormDraft draft;
    if (_mode == 'json') {
      try {
        draft = McpFormDraft.parseJson(_json.text, fallback: _draft);
        _jsonError = null;
      } on Object catch (value) {
        setState(() => _jsonError = value.toString());
        return;
      }
    } else {
      _updateDraft();
      draft = _draft;
    }
    final validation = draft.validationError;
    if (validation != null) {
      setState(() => _error = validation);
      return;
    }
    setState(() => _error = null);
    final success = await widget.catalog.upsert(draft, editing: widget.editing);
    if (!mounted) return;
    if (success) {
      if (widget.inline) {
        widget.onSaved?.call();
      } else {
        Navigator.of(context).pop();
      }
    } else {
      final identity = widget.editing?.identity ??
          'zcodeagentmcp:${draft.name.trim()}:${widget.scope == 'workspace' ? widget.catalog.workspacePath ?? '' : ''}';
      setState(() => _error =
          widget.catalog.operationError(identity)?.toString() ??
              uiText(context, '保存失败，请重试。', 'Save failed. Retry.'));
    }
  }

  InputDecoration _decoration(String label, {String? hint}) => InputDecoration(
        isDense: true,
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      );

  Widget _field(TextEditingController controller, String label,
          {String? hint,
          int minLines = 1,
          int maxLines = 1,
          TextInputType? keyboard}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextField(
          controller: controller,
          enabled: widget.editing == null ||
              widget.catalog.operationError(widget.editing!.identity) == null,
          minLines: minLines,
          maxLines: maxLines,
          keyboardType: keyboard,
          decoration: _decoration(label, hint: hint),
          onChanged: (_) => setState(() {}),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final type = _draft.type;
    final title = Row(
      children: [
        Expanded(
          child: Text(widget.editing == null
              ? uiText(context, '新建 MCP 服务器', 'New MCP server')
              : uiText(context, '编辑 MCP 服务器', 'Edit MCP server')),
        ),
        ToggleButtons(
          isSelected: [_mode == 'form', _mode == 'json'],
          onPressed: (index) => _setMode(index == 0 ? 'form' : 'json'),
          constraints: const BoxConstraints(minHeight: 34, minWidth: 56),
          children: const [Text('Form'), Text('JSON')],
        ),
      ],
    );
    final content = SizedBox(
      width: widget.inline ? double.infinity : 540,
      child: SingleChildScrollView(
        child: _mode == 'json'
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    key: const ValueKey('mcp-json-editor'),
                    controller: _json,
                    minLines: 16,
                    maxLines: 24,
                    style:
                        const TextStyle(fontFamily: 'monospace', fontSize: 12),
                    decoration: _decoration(
                      uiText(context, '完整配置', 'Full config'),
                      hint:
                          '{"my-server":{"type":"http","url":"https://example.com/mcp"}}',
                    ),
                    onChanged: (_) {
                      if (_jsonError != null) setState(() => _jsonError = null);
                    },
                  ),
                  const SizedBox(height: 6),
                  Text(
                    uiText(context, '支持直接配置、单名称包装或 mcpServers 包装；一次只能保存一个服务器。',
                        'Supports a direct config, one-name wrapper, or mcpServers wrapper; one server per save.'),
                    style: TextStyle(
                        fontSize: 12,
                        color: ZInk.of(Theme.of(context).colorScheme).subtlest),
                  ),
                  if (_jsonError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_jsonError!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    ),
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _field(_name, uiText(context, '名称', 'Name'),
                      hint: 'my-mcp-server'),
                  DropdownButtonFormField<McpServerType>(
                    key: const ValueKey('mcp-type'),
                    initialValue: type,
                    decoration: _decoration(uiText(context, '类型', 'Type')),
                    items: [
                      for (final value in McpServerType.values)
                        DropdownMenuItem(
                            value: value, child: Text(value.value)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _draft = _draft.copyWith(type: value);
                        _json.text = _draft.toJson();
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  _field(_timeout,
                      uiText(context, '超时毫秒（可选）', 'Timeout ms (optional)'),
                      hint: '30000', keyboard: TextInputType.number),
                  if (type != McpServerType.sse)
                    _field(
                        _protocol,
                        uiText(
                            context, '协议版本（可选）', 'Protocol version (optional)'),
                        hint: 'legacy / 2026-07-28'),
                  if (type == McpServerType.stdio) ...[
                    _field(_command, uiText(context, '命令', 'Command'),
                        hint: 'npx'),
                    _field(_args, uiText(context, '参数', 'Arguments'),
                        hint: '-y @modelcontextprotocol/server-memory'),
                  ] else
                    _field(_url, 'URL', hint: 'https://mcp.example.com/mcp'),
                  TextButton.icon(
                    onPressed: () =>
                        setState(() => _optionalExpanded = !_optionalExpanded),
                    icon: Icon(
                        _optionalExpanded
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 17),
                    label: Text(type == McpServerType.stdio
                        ? uiText(
                            context, '环境变量（可选）', 'Environment JSON (optional)')
                        : uiText(context, '请求头 / OAuth（可选）',
                            'Headers / OAuth JSON (optional)')),
                  ),
                  if (_optionalExpanded && type == McpServerType.stdio)
                    _field(_env, 'env JSON',
                        hint: '{"API_KEY":"..."}', minLines: 3, maxLines: 6),
                  if (_optionalExpanded && type != McpServerType.stdio) ...[
                    _field(_headers, 'headers JSON',
                        hint: '{"Authorization":"Bearer ..."}',
                        minLines: 3,
                        maxLines: 6),
                    _field(_oauth, 'oauth JSON', minLines: 3, maxLines: 6),
                  ],
                  if (_error != null)
                    Text(_error!,
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.error)),
                ],
              ),
      ),
    );
    final actions = [
      TextButton(
        onPressed: () {
          if (widget.inline) {
            widget.onCanceled?.call();
          } else {
            Navigator.of(context).pop();
          }
        },
        child: Text(uiText(context, '取消', 'Cancel')),
      ),
      FilledButton(
        key: const ValueKey('mcp-save'),
        onPressed: _save,
        child: Text(uiText(context, '保存', 'Save')),
      ),
    ];
    if (widget.inline) {
      return Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              title,
              const SizedBox(height: 14),
              content,
              Row(mainAxisAlignment: MainAxisAlignment.end, children: actions),
            ],
          ),
        ),
      );
    }
    return AlertDialog(title: title, content: content, actions: actions);
  }
}
