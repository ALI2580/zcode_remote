import 'dart:async';

import 'package:flutter/material.dart';

import '../state/client_preferences.dart';
import '../state/remote_agent_catalogs.dart';
import 'official_icons.dart';
import 'theme.dart';

class CommandScopeOption {
  const CommandScopeOption({
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
  final CommandsCatalog? catalog;
}

/// A form target is independent from the list target. The parent owns its
/// catalog and may attach a Composer refresh callback for that exact bridge.
class CommandFormTarget {
  const CommandFormTarget({
    required this.catalog,
    this.onComposerRefresh,
  });

  final CommandsCatalog catalog;
  final FutureOr<void> Function()? onComposerRefresh;
}

/// Official remote-control command form (jXt in js-1): name / description /
/// argument hint / prompt; prompt is required, new names must be 1..50 chars
/// of [a-zA-Z0-9_-] (editing keeps the official looser rule), empty optional
/// fields are omitted from the config payload, and the visible list only
/// changes through the controller's list read-back. Delete is the editor's
/// destructive action with a two-step confirm.
class CommandFormDialog extends StatefulWidget {
  const CommandFormDialog({
    super.key,
    required this.controller,
    this.editing,
    this.scopeOptions = const [],
    this.scopeKey,
    this.onScopeChanged,
    this.onComposerRefresh,
    this.pendingTarget = false,
    this.embedded = false,
    this.onCancel,
    this.onComplete,
  });

  final CommandsCatalog controller;
  final RemoteAgentEntry? editing;
  final List<CommandScopeOption> scopeOptions;
  final String? scopeKey;
  final ValueChanged<String>? onScopeChanged;
  final FutureOr<void> Function()? onComposerRefresh;
  final bool pendingTarget;
  final bool embedded;
  final VoidCallback? onCancel;
  final VoidCallback? onComplete;

  @override
  State<CommandFormDialog> createState() => _CommandFormDialogState();
}

class _CommandFormDialogState extends State<CommandFormDialog> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _argumentHint;
  late final TextEditingController _prompt;
  String? _validation;
  bool _confirmingDelete = false;

  static final RegExp _namePattern = RegExp(r'^[a-zA-Z0-9_-]+$');

  bool get _saving => widget.controller.isSaving('command-form');
  Object? get _error => widget.controller.saveError('command-form');

  @override
  void initState() {
    super.initState();
    _name = TextEditingController(
        text: widget.editing?.title.replaceFirst(RegExp(r'^/+'), '') ?? '');
    _description = TextEditingController(
        text: widget.editing?.raw['description'] is String
            ? widget.editing!.raw['description'] as String
            : '');
    _argumentHint = TextEditingController(
        text: widget.editing?.raw['argumentHint'] is String
            ? widget.editing!.raw['argumentHint'] as String
            : '');
    _prompt = TextEditingController(
        text: widget.editing?.raw['prompt'] is String
            ? widget.editing!.raw['prompt'] as String
            : '');
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant CommandFormDialog oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
      _validation = null;
      _confirmingDelete = false;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _name.dispose();
    _description.dispose();
    _argumentHint.dispose();
    _prompt.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Map<String, dynamic> _config() {
    final config = <String, dynamic>{
      if (widget.editing != null) ...widget.editing!.raw,
    };
    for (final key in const [
      'id',
      'commandId',
      'path',
      'filePath',
      'agentSource',
      'source',
      'readOnly',
      'enabled',
      'scope',
      'location',
      'pluginId',
      'pluginName',
      'title',
    ]) {
      config.remove(key);
    }
    config['name'] = _name.text.trim();
    config['prompt'] = _prompt.text.trim();
    if (_description.text.trim().isNotEmpty) {
      config['description'] = _description.text.trim();
    } else {
      config.remove('description');
    }
    if (_argumentHint.text.trim().isNotEmpty) {
      config['argumentHint'] = _argumentHint.text.trim();
    } else {
      config.remove('argumentHint');
    }
    return config;
  }

  bool _valid() {
    if (_prompt.text.trim().isEmpty) {
      _validation = uiText(context, '提示词不能为空', 'Prompt is required');
      return false;
    }
    final name = _name.text.trim();
    if (widget.editing == null) {
      if (name.isEmpty || name.length > 50) {
        _validation = uiText(context, '长度必须在 1 到 50 个字符之间',
            'Length must be between 1 and 50 characters');
        return false;
      }
      if (!_namePattern.hasMatch(name)) {
        _validation = uiText(context, '仅允许使用字母、数字、连字符和下划线',
            'Only letters, digits, hyphens and underscores are allowed');
        return false;
      }
    }
    _validation = null;
    return true;
  }

  Future<void> _save() async {
    if (_saving || widget.pendingTarget) return;
    if (!_valid()) {
      setState(() {});
      return;
    }
    final controller = widget.controller;
    final editing = widget.editing;
    final config = _config();
    final storageLevel = _storageLevel;
    final composerRefresh = widget.onComposerRefresh;
    final confirmed = editing == null
        ? await controller.createCommand(config,
            errorId: 'command-form', storageLevel: storageLevel)
        : await controller.updateCommand(editing, config,
            errorId: 'command-form', storageLevel: storageLevel);
    if (confirmed) {
      await composerRefresh?.call();
      if (!mounted) return;
      if (controller.saveError('command-form') == null) {
        if (widget.onComplete != null) {
          widget.onComplete!();
        } else {
          Navigator.of(context).pop();
        }
      }
    }
  }

  Future<void> _delete() async {
    final controller = widget.controller;
    final editing = widget.editing;
    if (editing == null || widget.pendingTarget) return;
    if (!_confirmingDelete) {
      setState(() => _confirmingDelete = true);
      return;
    }
    final composerRefresh = widget.onComposerRefresh;
    final confirmed =
        await controller.deleteCommand(editing, errorId: 'command-form');
    if (confirmed) {
      await composerRefresh?.call();
      if (!mounted) return;
      if (controller.saveError('command-form') == null) {
        if (widget.onComplete != null) {
          widget.onComplete!();
        } else {
          Navigator.of(context).pop();
        }
      }
    }
  }

  String? get _storageLevel {
    final selected = widget.scopeOptions
        .where((option) => option.key == widget.scopeKey)
        .firstOrNull;
    if (selected != null) {
      return selected.scope == 'workspace' || selected.scope == 'project'
          ? 'project'
          : 'user';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final errorText = _validation ??
        switch (_error) {
          null => null,
          Object value => () {
              final message = value.toString();
              if (message.contains('exists') || message.contains('already')) {
                return uiText(context, '${_name.text.trim()}.md 已存在',
                    '${_name.text.trim()}.md already exists');
              }
              return uiText(context, '保存失败，请重试。', 'Save failed. Retry.');
            }(),
        };
    final body = SizedBox(
      width: widget.embedded ? double.infinity : 420,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
                widget.editing == null
                    ? uiText(context, '填写命令名称和提示词，保存后返回列表。',
                        'Fill in the command name and prompt, then save.')
                    : uiText(context, '修改命令内容，保存后返回列表。',
                        'Edit the command content, then save.'),
                style: TextStyle(fontSize: 12.5, color: ink.subtlest)),
            const SizedBox(height: 14),
            TextField(
                controller: _name,
                enabled: widget.editing == null && !_saving,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                    isDense: true,
                    labelText: uiText(context, '名称', 'Name'),
                    hintText: 'my-command',
                    border: const OutlineInputBorder())),
            const SizedBox(height: 12),
            if (widget.scopeOptions.isNotEmpty) ...[
              DropdownButtonFormField<String>(
                key: const ValueKey('command-form-scope'),
                initialValue: widget.scopeOptions
                        .any((option) => option.key == widget.scopeKey)
                    ? widget.scopeKey
                    : widget.scopeOptions.first.key,
                decoration: InputDecoration(
                    isDense: true,
                    labelText: uiText(context, '范围', 'Scope'),
                    border: const OutlineInputBorder()),
                items: [
                  for (final option in widget.scopeOptions)
                    DropdownMenuItem(
                        value: option.key, child: Text(option.label)),
                ],
                onChanged: widget.editing != null || _saving
                    ? null
                    : (value) {
                        if (value != null) widget.onScopeChanged?.call(value);
                      },
              ),
              const SizedBox(height: 12),
            ],
            TextField(
                controller: _description,
                enabled: !_saving,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                    isDense: true,
                    labelText:
                        uiText(context, '描述（可选）', 'Description (optional)'),
                    hintText: uiText(context, '在命令选择器中显示的简短描述',
                        'Shown in the command picker'),
                    border: const OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _argumentHint,
                enabled: !_saving,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                    isDense: true,
                    labelText:
                        uiText(context, '参数提示（可选）', 'Argument hint (optional)'),
                    hintText:
                        uiText(context, '例如 <file-path>', 'e.g. <file-path>'),
                    border: const OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(
                controller: _prompt,
                enabled: !_saving,
                minLines: 5,
                maxLines: 8,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                    isDense: true,
                    alignLabelWithHint: true,
                    labelText: uiText(context, '提示词', 'Prompt'),
                    hintText: uiText(context, '填写调用该命令时发送的提示词...',
                        'Prompt sent when the command is invoked...'),
                    border: const OutlineInputBorder())),
            if (errorText != null) ...[
              const SizedBox(height: 8),
              Text(errorText,
                  style: TextStyle(fontSize: 12, color: ink.diffRemoved)),
            ],
            if (_confirmingDelete && widget.editing != null) ...[
              const SizedBox(height: 12),
              Text(uiText(context, '删除命令', 'Delete command'),
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ink.diffRemoved)),
              const SizedBox(height: 4),
              Text(
                  uiText(
                      context,
                      '确定要删除命令「${widget.editing!.title.replaceFirst(RegExp(r'^/+'), '')}」吗？此操作无法撤销。',
                      'Delete command "${widget.editing!.title.replaceFirst(RegExp(r'^/+'), '')}"? This cannot be undone.'),
                  style: TextStyle(fontSize: 12, color: ink.subtlest)),
            ],
          ],
        ),
      ),
    );
    final actions = <Widget>[
      if (widget.editing != null)
        TextButton.icon(
            onPressed: _saving || widget.pendingTarget ? null : _delete,
            icon: const LucideIcon('trash-2', size: 13),
            label: Text(uiText(context, '删除', 'Delete'),
                style: TextStyle(fontSize: 12, color: ink.diffRemoved))),
      const Spacer(),
      TextButton(
          onPressed: _saving || widget.pendingTarget
              ? null
              : (widget.onCancel ?? () => Navigator.of(context).pop()),
          child: Text(uiText(context, '取消', 'Cancel'))),
      const SizedBox(width: 8),
      FilledButton(
          onPressed: _saving || widget.pendingTarget ? null : _save,
          child: Text(_saving
              ? uiText(context, '保存中', 'Saving')
              : uiText(context, '保存', 'Save'))),
    ];
    if (widget.embedded) {
      return Material(
        color: Colors.transparent,
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
              Text(
                  widget.editing == null
                      ? uiText(context, '新建命令', 'New command')
                      : uiText(context, '编辑命令', 'Edit command'),
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              body,
              const SizedBox(height: 12),
              Row(children: actions),
            ],
          ),
        ),
      );
    }
    return AlertDialog(
      title: Text(widget.editing == null
          ? uiText(context, '新建命令', 'New command')
          : uiText(context, '编辑命令', 'Edit command')),
      content: body,
      actions: actions,
    );
  }
}
