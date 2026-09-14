import 'dart:async';

import 'package:flutter/material.dart';

import '../state/settings_import.dart';
import '../state/client_preferences.dart';
import 'theme.dart';

/// Reusable external-agent import dialog for skills, commands and MCP.
/// Discovery and import are injected so the page can use a fake service in
/// tests and the settings center can bind the current remote bridge later.
class SettingsImportDialog extends StatefulWidget {
  const SettingsImportDialog({
    super.key,
    required this.controller,
    this.onImported,
    this.disposeController = false,
  });

  final ExternalAgentImportController controller;
  final Future<void> Function()? onImported;
  final bool disposeController;

  static Future<void> show(
    BuildContext context, {
    required SettingsSyncService service,
    required String category,
    List<String>? categories,
    String? workspacePath,
    String? workspaceIdentity,
    Future<void> Function()? onImported,
  }) async {
    final controller = ExternalAgentImportController(
      service: service,
      category: category,
      categories: categories,
      workspacePath: workspacePath,
      workspaceIdentity: workspaceIdentity,
    );
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => SettingsImportDialog(
          controller: controller,
          onImported: onImported,
        ),
      );
    } finally {
      controller.dispose();
    }
  }

  @override
  State<SettingsImportDialog> createState() => _SettingsImportDialogState();
}

class _SettingsImportDialogState extends State<SettingsImportDialog> {
  ExternalAgentImportController get controller => widget.controller;

  @override
  void initState() {
    super.initState();
    controller.addListener(_changed);
    if (controller.status == ExternalAgentImportStatus.idle) {
      unawaited(controller.scan());
    }
  }

  @override
  void dispose() {
    controller.removeListener(_changed);
    if (widget.disposeController) controller.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  String _label() {
    if (controller.categories.length > 1) {
      // Official onboarding title (settingsSync.dialog.title).
      return uiText(context, '导入设置', 'Import settings');
    }
    return switch (controller.category) {
      'skills' => uiText(context, '导入技能', 'Import skills'),
      'commands' => uiText(context, '导入命令', 'Import commands'),
      'plugins' => uiText(context, '导入插件', 'Import plugins'),
      _ => uiText(context, '导入 MCP 服务器', 'Import MCP servers'),
    };
  }

  String _categoryLabel(String value) => switch (value) {
        'skills' => uiText(context, '技能', 'Skills'),
        'commands' => uiText(context, '命令', 'Commands'),
        'plugins' => uiText(context, '插件', 'Plugins'),
        _ => uiText(context, 'MCP 服务器', 'MCP servers'),
      };

  String _scopeLabel(String value) => value == 'project'
      ? uiText(context, '项目范围', 'Project')
      : uiText(context, '全局范围', 'Global');

  String _statusLabel(String value) => switch (value) {
        'imported' => uiText(context, '已导入', 'Imported'),
        'skipped' => uiText(context, '已跳过', 'Skipped'),
        'failed' => uiText(context, '失败', 'Failed'),
        _ => value,
      };

  Future<void> _import() async {
    final success = await controller.importSelected();
    if (success && widget.onImported != null) await widget.onImported!();
  }

  Widget _discovery() {
    final rows = controller.visibleRoots;
    if (rows.isEmpty) {
      return Center(
        child: Text(uiText(
            context, '此范围没有可导入资源。', 'No importable resources in this scope.')),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        for (final row in rows) _sourceRoot(row),
      ],
    );
  }

  Widget _sourceRoot(ExternalAgentRootRow row) {
    final agent = row.agent;
    final root = row.root;
    final keys = controller.resourceKeysFor(row);
    final selected = keys.where(controller.isSelected).length;
    final all = keys.isNotEmpty && selected == keys.length;
    final mixed = selected > 0 && !all;
    final expanded = controller.isExpanded(row);
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      child: Column(
        children: [
          Row(
            children: [
              Checkbox(
                tristate: true,
                value: all ? true : (mixed ? null : false),
                onChanged: keys.isEmpty
                    ? null
                    : (_) => controller.setResourceSelection(keys, !all),
              ),
              Expanded(
                child: InkWell(
                  onTap: () => controller.toggleExpanded(row),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.categories.length > 1
                              ? '${agent.label} · ${_categoryLabel(row.category)}'
                              : agent.label,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        Text(
                          root.path,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 11,
                              color: ZInk.of(Theme.of(context).colorScheme)
                                  .subtlest),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Text('${root.importableCount}',
                  style: TextStyle(
                      fontSize: 12,
                      color: ZInk.of(Theme.of(context).colorScheme).subtlest)),
              IconButton(
                tooltip: expanded
                    ? uiText(context, '收起来源', 'Collapse source')
                    : uiText(context, '展开来源', 'Expand source'),
                onPressed: () => controller.toggleExpanded(row),
                icon: Icon(expanded ? Icons.expand_less : Icons.expand_more),
              ),
            ],
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.only(left: 50, right: 12, bottom: 8),
              child: Column(
                children: [
                  for (final resource in root.resources)
                    _resource(row, resource),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _resource(
    ExternalAgentRootRow row,
    ExternalAgentResource resource,
  ) {
    final key = importSelectionKey(
      agent: row.agent.id,
      category: row.category,
      sourceScope: row.root.scope,
      resourcePath: resource.path,
    );
    final selected = controller.isSelected(key);
    return CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: selected,
      onChanged:
          resource.importable ? (_) => controller.toggleSelection(key) : null,
      title: Text(resource.name, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(resource.path,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
      secondary: resource.importable
          ? null
          : Tooltip(
              message:
                  uiText(context, '已存在或不可导入', 'Already present or unavailable'),
              child: const Icon(Icons.block, size: 16),
            ),
    );
  }

  Widget _result() {
    final result = controller.result;
    if (result == null) return const SizedBox.shrink();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Wrap(
          spacing: 18,
          runSpacing: 6,
          children: [
            _countText(uiText(context, '已导入', 'Imported'), result.successCount),
            _countText(uiText(context, '已跳过', 'Skipped'), result.skippedCount),
            _countText(uiText(context, '失败', 'Failed'), result.failedCount),
          ],
        ),
        const SizedBox(height: 14),
        Text(uiText(context, '结果明细', 'Result details'),
            style: const TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        if (result.taskResults.isEmpty)
          Text(uiText(context, '没有明细。', 'No details.'),
              style: TextStyle(
                  color: ZInk.of(Theme.of(context).colorScheme).subtlest))
        else
          for (final row in result.taskResults)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                row.status == 'imported'
                    ? Icons.check_circle
                    : row.status == 'skipped'
                        ? Icons.info
                        : Icons.error,
                size: 17,
              ),
              title: Text(row.name.isEmpty ? row.path : row.name),
              subtitle: Text(
                '${row.path.isEmpty ? '' : '${row.path} · '}${_statusLabel(row.status)}${row.skipReason == null ? '' : ': ${row.skipReason}'}',
              ),
            ),
      ],
    );
  }

  Widget _countText(String label, int count) => RichText(
        text: TextSpan(
          style: DefaultTextStyle.of(context).style,
          children: [
            TextSpan(
                text: '$count ',
                style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: label),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final scanning = controller.status == ExternalAgentImportStatus.scanning;
    final importing = controller.status == ExternalAgentImportStatus.importing;
    final complete = controller.status == ExternalAgentImportStatus.complete;
    final error = controller.error;
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = (screen.width - 24).clamp(240.0, 650.0).toDouble();
    final dialogHeight = (screen.height - 180).clamp(300.0, 530.0).toDouble();
    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
      title: Row(
        children: [
          Expanded(child: Text(_label())),
          if (!complete)
            IconButton(
              tooltip: uiText(context, '重新扫描', 'Rescan'),
              onPressed: scanning || importing
                  ? null
                  : () => unawaited(controller.scan()),
              icon: const Icon(Icons.refresh, size: 19),
            ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          children: [
            if (error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(8)),
                child: Text(error.toString()),
              ),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: scanning
                    ? const Center(child: CircularProgressIndicator())
                    : importing
                        ? Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const CircularProgressIndicator(),
                                const SizedBox(height: 12),
                                Text(uiText(context, '正在导入…', 'Importing…')),
                              ],
                            ),
                          )
                        : complete
                            ? _result()
                            : _discovery(),
              ),
            ),
            if (!complete) ...[
              const SizedBox(height: 10),
              LayoutBuilder(builder: (context, constraints) {
                final width = constraints.maxWidth.isFinite
                    ? (constraints.maxWidth - 8).clamp(112.0, 190.0).toDouble()
                    : 180.0;
                Widget choice({
                  required String label,
                  required Key key,
                  required String value,
                  required List<DropdownMenuItem<String>> items,
                  required ValueChanged<String?>? onChanged,
                }) =>
                    SizedBox(
                      width: width,
                      child: InputDecorator(
                        isFocused: false,
                        decoration: InputDecoration(
                          isDense: true,
                          labelText: label,
                          border: const OutlineInputBorder(),
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                        ),
                        child: DropdownButton<String>(
                          key: key,
                          value: value,
                          isDense: true,
                          isExpanded: true,
                          underline: const SizedBox.shrink(),
                          onChanged: onChanged,
                          items: items,
                        ),
                      ),
                    );
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    choice(
                      label: uiText(context, '来源', 'Source'),
                      key: const ValueKey('import-source-scope'),
                      value: controller.activeSourceScope,
                      onChanged: scanning || importing
                          ? null
                          : (value) {
                              if (value != null) {
                                controller.setActiveSourceScope(value);
                              }
                            },
                      items: [
                        for (final scope in importScopes)
                          DropdownMenuItem(
                              value: scope, child: Text(_scopeLabel(scope))),
                      ],
                    ),
                    choice(
                      label: uiText(context, '目标', 'Target'),
                      key: const ValueKey('import-target-scope'),
                      value: controller.importTargetScope,
                      onChanged: scanning || importing
                          ? null
                          : (value) {
                              if (value != null) {
                                controller.setImportTargetScope(value);
                              }
                            },
                      items: [
                        DropdownMenuItem(
                            value: 'global',
                            child: Text(_scopeLabel('global'))),
                        DropdownMenuItem(
                          value: 'project',
                          enabled: controller.canTargetProject,
                          child: Text(_scopeLabel('project')),
                        ),
                      ],
                    ),
                    choice(
                      label: uiText(context, '方式', 'Mode'),
                      key: const ValueKey('import-mode'),
                      value: controller.importMode,
                      onChanged: scanning || importing
                          ? null
                          : (value) {
                              if (value != null) {
                                controller.setImportMode(value);
                              }
                            },
                      items: [
                        DropdownMenuItem(
                            value: 'symlink',
                            child: Text(uiText(context, '符号链接', 'Symlink'))),
                        DropdownMenuItem(
                            value: 'copy',
                            child: Text(uiText(context, '复制', 'Copy'))),
                      ],
                    ),
                  ],
                );
              }),
            ],
          ],
        ),
      ),
      actions: [
        if (complete)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(uiText(context, '完成', 'Done')),
          )
        else ...[
          Text('${controller.selectedCount}/${controller.totalImportableCount}',
              style: TextStyle(
                  color: ZInk.of(Theme.of(context).colorScheme).subtlest)),
          const SizedBox(width: 24),
          TextButton(
            onPressed: importing ? null : () => Navigator.of(context).pop(),
            child: Text(uiText(context, '取消', 'Cancel')),
          ),
          FilledButton(
            key: const ValueKey('import-submit'),
            onPressed: scanning || importing || controller.selectedCount == 0
                ? null
                : () => unawaited(_import()),
            child: Text(uiText(context, '导入', 'Import')),
          ),
        ],
      ],
    );
  }
}
