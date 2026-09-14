import 'dart:convert';
import 'package:flutter/material.dart';
import 'dart:io';
import '../protocol/file_changes.dart';
import '../state/client_preferences.dart';
import '../state/remote_settings.dart';
import 'code_renderer.dart';
import 'official_icons.dart';
import 'file_changes_review_panel.dart';
import 'theme.dart';

String _text(dynamic value) => value is String ? value.trim() : '';
String _pretty(String name) {
  final text = name
      .trim()
      .replaceAll(RegExp(r'[-_]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
  return text.isEmpty ? '' : '${text[0].toUpperCase()}${text.substring(1)}';
}

/// V4 display.mcp_tool takes precedence over the encoded name (NJ/Knt).
/// Unknown tools keep their identity in the title and raw details.
class ToolRowInfo {
  const ToolRowInfo(
      {required this.name,
      required this.family,
      required this.title,
      this.server,
      this.description});
  final String name, family, title;
  final String? server, description;
  String get icon => switch (family) {
        'read' || 'search' => 'search',
        'write' || 'edit' || 'delete' => 'file-diff',
        'command' => 'terminal',
        'webSearch' => 'earth',
        'webFetch' => 'globe',
        'plan' => 'list-todo',
        'skill' => 'sparkles',
        'taskControl' => 'terminal',
        'message' => 'message-circle-plus',
        'agent' => 'bot',
        _ => 'globe',
      };

  static ToolRowInfo fromRow(Map<String, dynamic> row) {
    final name = _text(row['toolName']);
    final display = row['display'];
    String? server, tool, description;
    if (display is Map &&
        display['kind'] == 'mcp_tool' &&
        _text(display['serverName']).isNotEmpty &&
        _text(display['toolName']).isNotEmpty) {
      server = _text(display['serverName']);
      tool = _text(display['toolName']);
      description = _text(display['description']);
    } else {
      final parts = name.split('__');
      if (parts.length == 3 &&
          parts[0].toLowerCase() == 'mcp' &&
          parts[1].isNotEmpty &&
          parts[2].isNotEmpty) {
        server = parts[1];
        tool = parts[2];
        final a = server.split('_').where((e) => e.isNotEmpty).toList();
        final b = tool.split('_').where((e) => e.isNotEmpty).toList();
        var overlap = 0;
        for (var n = a.length < b.length ? a.length : b.length; n > 0; n--) {
          if (a.sublist(a.length - n).join('_').toLowerCase() ==
              b.take(n).join('_').toLowerCase()) {
            overlap = n;
            break;
          }
        }
        if (overlap > 0) {
          server = a.sublist(a.length - overlap).join('_');
          if (overlap < b.length) tool = b.skip(overlap).join('_');
        } else if (a.isNotEmpty && a.first.toLowerCase() == 'plugin') {
          server = a.last;
        }
      }
    }
    if (server != null && tool != null) {
      final parts = server
          .split(':')
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList();
      server = _pretty(parts.length > 1 && parts.first.toLowerCase() == 'plugin'
          ? parts.last
          : server);
      tool = _pretty(tool);
      if (tool.toLowerCase().startsWith('${server.toLowerCase()} ')) {
        tool = _pretty(tool.substring(server.length + 1));
      }
      return ToolRowInfo(
          name: name,
          family: 'mcp',
          title: tool,
          server: server,
          description: description);
    }
    final normalized = name.toLowerCase().replaceAll(RegExp(r'[-_]'), '');
    final family = switch (normalized) {
      'read' || 'readfile' || 'fileread' => 'read',
      'grep' || 'glob' || 'search' || 'searchfiles' => 'search',
      'write' || 'writefile' || 'filewrite' => 'write',
      'edit' || 'multiedit' || 'applypatch' || 'fileedit' => 'edit',
      'delete' || 'deletefile' => 'delete',
      'bash' || 'shell' || 'terminal' || 'execcommand' => 'command',
      'websearch' => 'webSearch',
      'webfetch' => 'webFetch',
      'todowrite' || 'updatetodo' || 'updateplan' => 'plan',
      'skill' => 'skill',
      'taskoutput' ||
      'bashoutput' ||
      'taskstop' ||
      'killshell' =>
        'taskControl',
      'respondtocoordinator' => 'message',
      'task' || 'subagent' || 'agent' => 'agent',
      _ => 'unknown',
    };
    final input = toolInput(row);
    String summary = '';
    if (input is Map) {
      final fields = switch (family) {
        'command' => ['command', 'cmd'],
        'search' || 'webSearch' => ['pattern', 'query'],
        'webFetch' => ['url'],
        // Official Skill card renders input.skill.name (prt()).
        'skill' => ['skill.name'],
        // Official task-control reads task_id/shell_id (Trt/xrt);
        'taskControl' => ['task_id', 'shell_id'],
        // Official message card renders input.summary (drt).
        'message' => ['summary', 'message'],
        'agent' => ['description'],
        _ => ['file_path', 'path'],
      };
      for (final field in fields) {
        if (field.contains('.')) {
          dynamic cursor = input;
          for (final part in field.split('.')) {
            if (cursor is Map && cursor[part] != null) {
              cursor = cursor[part];
            } else {
              cursor = null;
              break;
            }
          }
          summary = cursor is String ? _text(cursor) : '';
        } else {
          summary = _text(input[field]);
        }
        if (summary.isNotEmpty) break;
      }
    }
    if (summary.isEmpty) {
      // Official XJ fallback chain includes step.skillMetadata.qualifiedName.
      final meta = row['skillMetadata'];
      if (meta is Map && _text(meta['qualifiedName']).isNotEmpty) {
        summary = _text(meta['qualifiedName']);
      }
    }
    return ToolRowInfo(
        name: name,
        family: family,
        title: summary.isNotEmpty ? summary : _pretty(name));
  }
}

/// Returns true for todo tool cards that are hidden by the official
/// `messageStreamShowTodos` gate. The underlying conversation rows remain in
/// the state and are therefore still available to the task/status views.
bool isTodoConversationRow(Map<String, dynamic> row) {
  if (row['kind'] == 'todo' || row['type'] == 'todo') return true;
  final name = _text(row['toolName']).toLowerCase().replaceAll(RegExp(r'[-_]'), '');
  return name == 'todo' ||
      name == 'todowrite' ||
      name == 'updatetodo' ||
      name == 'updateplan';
}

String? _runtimeShellText(Map<String, dynamic> row) {
  final input = toolInput(row);
  if (input is String && input.trim().isNotEmpty) return input.trim();
  if (input is List && input.every((value) => value is String)) {
    final value = input.whereType<String>().join(' ').trim();
    if (value.isNotEmpty) return value;
  }
  if (input is Map) {
    for (final key in ['command', 'cmd', 'script', 'parsed_cmd']) {
      final value = input[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
      if (value is List && value.every((item) => item is String)) {
        final joined = value.whereType<String>().join(' ').trim();
        if (joined.isNotEmpty) return joined;
      }
    }
  }
  for (final key in ['command', 'cmd', 'script', 'parsed_cmd']) {
    final value = row[key];
    if (value is String && value.trim().isNotEmpty) return value.trim();
  }
  return null;
}

/// Mirrors the official shell classification used by `zY`/`BY`/`Pit`:
/// read-only inspection commands are Explore, while an actual shell command
/// with no read-only inspection signal stays Terminal. A tool name such as
/// Bash alone is never sufficient to classify a row as Explore.
bool isExploreConversationTool(Map<String, dynamic> row) {
  final family = ToolRowInfo.fromRow(row).family;
  if (family == 'read' || family == 'search') return true;
  if (family != 'command') return false;
  final source = _runtimeShellText(row);
  if (source == null || source.isEmpty) return false;
  final commands = source
      .replaceFirst(RegExp(r'^(?:/bin/)?(?:zsh|bash|sh)\s+-lc\s+',
          caseSensitive: false), '')
      .split(RegExp(r'&&|\|\||;|\r?\n'))
      .map((value) {
        final trimmed = value.trim();
        if (trimmed.length >= 2 &&
            ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
                (trimmed.startsWith("'") && trimmed.endsWith("'")))) {
          return trimmed.substring(1, trimmed.length - 1).trim();
        }
        return trimmed;
      })
      .where((value) => value.isNotEmpty)
      .toList();
  if (commands.isEmpty) return false;
  final mutating = RegExp(
      r'\b(sed\s+-i|perl\s+-pi|tee|mv|cp|rm|mkdir|rmdir|touch|truncate|chmod|chown|remove-item|del|erase|set-content|add-content|clear-content|out-file|new-item|move-item|copy-item|rename-item|set-item)\b|^git\s+(add|commit|rm|mv|checkout|switch|restore|reset|clean|revert|cherry-pick|merge|rebase)\b',
      caseSensitive: false);
  final redirect = RegExp(r'(^|[^\d<])>>?\s*\S|&>\s*\S');
  if (commands.any((value) => mutating.hasMatch(value) || redirect.hasMatch(value))) {
    return false;
  }
  final inspect = RegExp(
      r'\b(rg|grep|find|ls|cat|head|tail|wc|stat|pwd|which|readlink|tree|sed\s+-n|get-childitem|gci|dir|get-content|gc|type|select-string|sls|get-location|test-path|resolve-path)\b|^git\s+(status|log|show|diff)\b',
      caseSensitive: false);
  return commands.any(inspect.hasMatch);
}

/// Classification consumed by the conversation renderer. `null` means the
/// row must remain an individual card.
String? runtimeToolGroupingFamily(
  Map<String, dynamic> row, {
  bool groupExplore = true,
  bool groupTerminal = true,
  bool groupChanges = false,
}) {
  if (row['kind'] != 'toolCall' || isTodoConversationRow(row)) return null;
  final family = ToolRowInfo.fromRow(row).family;
  if (family == 'write' || family == 'edit' || family == 'delete') {
    return groupChanges ? 'changes' : null;
  }
  if (isExploreConversationTool(row)) {
    return groupExplore ? 'explore' : null;
  }
  if (family == 'command' && groupTerminal) return 'terminal';
  return null;
}

/// Applies the settings gates to one turn's assistant rows. This is a view
/// projection only; the source rows and task data are never removed.
List<Map<String, dynamic>> runtimeVisibleAssistantRows(
    List<Map<String, dynamic>> rows,
    RemoteSettingsSnapshot? settings) {
  final showReasoning = settings?.showReasoning ?? true;
  final showTodos = settings?.showTodos ?? false;
  var seenReasoning = false;
  final visible = <Map<String, dynamic>>[];
  for (final row in rows) {
    if (row['kind'] == 'reasoning') {
      if (!showReasoning && seenReasoning) continue;
      seenReasoning = true;
    }
    if (!showTodos && isTodoConversationRow(row)) continue;
    visible.add(row);
  }
  return visible;
}

dynamic toolInput(Map<String, dynamic> row) {
  if (row['input'] != null) return row['input'];
  final text = _text(row['inputText']);
  if (text.isEmpty) return null;
  try {
    return jsonDecode(text);
  } on FormatException {
    return text;
  }
}

/// Extracts file paths from tool input/output (official mge() fields).
List<String> toolFilePaths(Map<String, dynamic> row) {
  final pathFields = [
    'path',
    'filePath',
    'file_path',
    'targetPath',
    'target_path',
    'filename',
    'file'
  ];
  final sources = <dynamic>[toolInput(row), row['output'], row['raw']];
  final paths = <String>[];
  for (final source in sources) {
    if (source is Map) {
      for (final field in pathFields) {
        final v = _text(source[field]);
        if (v.isNotEmpty && !paths.contains(v)) paths.add(v);
      }
    }
  }
  return paths;
}

/// Extracts http(s) URLs from tool output text.
List<String> toolUrls(Map<String, dynamic> row) {
  final output = row['output'];
  final text = output is Map ? _text(output['text']) : _text(output);
  if (text.isEmpty) return const [];
  final urls = RegExp(r'https?://\S+', multiLine: false)
      .allMatches(text)
      .map((m) => m.group(0)!)
      .toSet()
      .toList();
  return urls;
}

/// True when the tool output is truncated (official output?.truncated).
bool toolOutputTruncated(Map<String, dynamic> row) {
  final output = row['output'];
  return output is Map && output['truncated'] == true;
}

class ToolDiffCount {
  const ToolDiffCount({required this.added, required this.removed});
  final int added, removed;
}

int? _nonNegativeCount(dynamic value) =>
    value is num && value.isFinite && value >= 0 ? value.round() : null;

ToolDiffCount? _diffFromMap(Map source) {
  final added = _nonNegativeCount(source['added'] ?? source['additions']);
  final removed = _nonNegativeCount(source['removed'] ?? source['deletions']);
  if (added != null || removed != null) {
    return ToolDiffCount(added: added ?? 0, removed: removed ?? 0);
  }
  for (final key in ['changes', 'files']) {
    if (source[key] case final List entries) {
      var added = 0, removed = 0, found = false;
      for (final entry in entries.whereType<Map>()) {
        final stat =
            entry['changeStat'] is Map ? entry['changeStat'] as Map : entry;
        final entryAdded =
            _nonNegativeCount(stat['added'] ?? stat['additions']);
        final entryRemoved =
            _nonNegativeCount(stat['removed'] ?? stat['deletions']);
        if (entryAdded != null || entryRemoved != null) {
          found = true;
          added += entryAdded ?? 0;
          removed += entryRemoved ?? 0;
        }
      }
      if (found) return ToolDiffCount(added: added, removed: removed);
    }
  }
  return null;
}

/// Official WK rows sum changeStat/additions+deletions into a +N -N badge.
ToolDiffCount? toolDiffCount(Map<String, dynamic> row) {
  final output = row['output'];
  for (final source in [
    if (output is Map) output,
    if (output is Map && output['raw'] is Map) output['raw'] as Map,
    if (output is Map && output['rawOutput'] is Map) output['rawOutput'] as Map,
    if (row['raw'] is Map) row['raw'] as Map,
    if (row['rawOutput'] is Map) row['rawOutput'] as Map,
  ]) {
    final diff = _diffFromMap(source);
    if (diff != null) return diff;
  }
  return null;
}

String reasoningLabel(BuildContext context, Map<String, dynamic> row) {
  if (row['state'] == 'streaming') return uiText(context, '正在思考', 'Thinking');
  final ms = row['durationMs'];
  final seconds =
      ms is num && ms.isFinite ? (ms / 1000).round().clamp(0, 1 << 40) : null;
  final duration = seconds == null
      ? uiText(context, '持续了几秒', 'a few seconds')
      : uiText(context, '持续了 $seconds 秒', '$seconds seconds');
  return '${uiText(context, '思考', 'Thought')} · $duration';
}

class ReasoningRow extends StatefulWidget {
  const ReasoningRow({super.key, required this.row});
  final Map<String, dynamic> row;
  @override
  State<ReasoningRow> createState() => _ReasoningRowState();
}

class _ReasoningRowState extends State<ReasoningRow> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final text = _text(widget.row['text']);
    final active = widget.row['state'] == 'streaming';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
          onTap: text.isEmpty
              ? null
              : () => setState(() => _expanded = !_expanded),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                LucideIcon('brain', size: 16, color: ink.subtlest),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(reasoningLabel(context, widget.row),
                        style: TextStyle(
                            fontSize: 14,
                            color: active ? ink.text : ink.subtlest))),
                // Official shows inline streaming preview of reasoning text
                // while active (data-reasoning-streaming-marker).
                if (active && text.isNotEmpty && !_expanded) ...[
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(text,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: ink.subtlest))),
                ],
                if (text.isNotEmpty) ...[
                  const SizedBox(width: 4),
                  LucideIcon(_expanded ? 'chevron-down' : 'chevron-right',
                      size: 12, color: ink.subtlest),
                ],
              ]))),
      if (_expanded && text.isNotEmpty)
        Padding(
            padding: const EdgeInsets.only(left: 24, top: 6),
            child: SelectableText(text,
                style:
                    TextStyle(fontSize: 14, height: 1.6, color: ink.subtlest))),
    ]);
  }
}

/// Compact container for consecutive official Explore/Terminal/Changes tool
/// rows. Individual ToolCallRow widgets stay mounted inside the group so
/// expansion state and row actions remain tied to their original row ids.
class ToolGroupRow extends StatefulWidget {
  const ToolGroupRow({
    super.key,
    required this.family,
    required this.children,
    required this.rowId,
  });

  final String family;
  final List<Widget> children;
  final int rowId;

  @override
  State<ToolGroupRow> createState() => _ToolGroupRowState();
}

class _ToolGroupRowState extends State<ToolGroupRow> {
  bool _expanded = false;

  String _title(BuildContext context) {
    final label = switch (widget.family) {
      'explore' => uiText(context, '探索', 'Explore'),
      'terminal' => uiText(context, '终端', 'Terminal'),
      'changes' => uiText(context, '变更', 'Changes'),
      _ => uiText(context, '工具', 'Tools'),
    };
    final count = widget.children.length;
    return '$label · $count';
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          key: ValueKey('tool-group-${widget.rowId}'),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                LucideIcon(
                  widget.family == 'changes' ? 'file-diff' : 'layers-2',
                  size: 16,
                  color: ink.subtlest,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _title(context),
                    style: TextStyle(fontSize: 14, color: ink.subtlest),
                  ),
                ),
                LucideIcon(
                  _expanded ? 'chevron-down' : 'chevron-right',
                  size: 12,
                  color: ink.subtlest,
                ),
              ],
            ),
          ),
        ),
        if (_expanded)
          Padding(
            padding: const EdgeInsets.only(left: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: widget.children,
            ),
          ),
      ],
    );
  }
}

class ToolCallRow extends StatefulWidget {
  const ToolCallRow({super.key, required this.row});
  final Map<String, dynamic> row;
  @override
  State<ToolCallRow> createState() => _ToolCallRowState();
}

class _ToolCallRowState extends State<ToolCallRow> {
  bool _expanded = false;
  bool _fullOutput = false;
  bool _showArguments = true;
  bool _fullArguments = false;
  String _kind(BuildContext context, String family) => switch (family) {
        'mcp' => 'MCP',
        'read' => uiText(context, '读取', 'Read'),
        'search' => uiText(context, '搜索', 'Search'),
        'write' => uiText(context, '写入', 'Write'),
        'edit' => uiText(context, '编辑', 'Edit'),
        'delete' => uiText(context, '删除', 'Delete'),
        'command' => uiText(context, '运行', 'Run'),
        'webSearch' => uiText(context, '搜索', 'Search'),
        'webFetch' => uiText(context, '获取', 'Fetch'),
        'plan' => uiText(context, '计划', 'Plan'),
        'agent' => uiText(context, '智能体', 'Agent'),
        _ => uiText(context, '工具调用', 'Tool call'),
      };
  String _status(BuildContext context, String status) => switch (status) {
        'inputStreaming' => uiText(context, '准备中', 'Preparing'),
        'pendingApproval' ||
        'waiting' =>
          uiText(context, '等待确认', 'Awaiting approval'),
        'running' => uiText(context, '执行中', 'Running'),
        'error' || 'failed' => uiText(context, '执行失败', 'Failed'),
        'cancelled' || 'stopped' => uiText(context, '已停止', 'Stopped'),
        _ => '',
      };
  String _json(dynamic value) => value == null
      ? ''
      : value is String
          ? value
          : const JsonEncoder.withIndent('  ').convert(value);
  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final info = ToolRowInfo.fromRow(row);
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final status = _text(row['status']);
    final failed = status == 'error' || status == 'failed';
    final active = const [
      'running',
      'inputStreaming',
      'pendingApproval',
      'waiting'
    ].contains(status);
    final label = [
      _kind(context, info.family),
      if (info.server != null) info.server!,
      if (info.title.isNotEmpty) info.title
    ].join(' · ');
    final output = row['output'];
    final fullResult = _json(output is Map ? output['text'] : output);
    const outputPreviewLimit = 1200;
    final result = fullResult.length <= outputPreviewLimit || _fullOutput
        ? fullResult
        : '${fullResult.substring(0, outputPreviewLimit)}\n…';
    final error = row['error'];
    final errorText = _json(error is Map ? error['message'] : error);
    final rawArguments = _expanded ? toolInput(row) : null;
    final fullArguments = _json(rawArguments);
    const argumentPreviewLimit = 1200;
    final renderedArguments =
        fullArguments.length <= argumentPreviewLimit || _fullArguments
            ? fullArguments
            : '${fullArguments.substring(0, argumentPreviewLimit)}\n…';
    final diff = ['write', 'edit', 'delete'].contains(info.family)
        ? toolDiffCount(row)
        : null;
    final inlineDiff =
        _expanded && ['write', 'edit', 'delete'].contains(info.family)
            ? parseToolInlineDiff(row)
            : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      InkWell(
          key: ValueKey('tool-row-${row['rowId']}'),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                LucideIcon(info.icon, size: 16, color: ink.subtlest),
                const SizedBox(width: 8),
                Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 14,
                            color: failed
                                ? ink.diffRemoved
                                : active
                                    ? ink.text
                                    : ink.subtlest))),
                if (_status(context, status).isNotEmpty)
                  Flexible(
                      child: Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Text(_status(context, status),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontSize: 12,
                                  color: failed
                                      ? ink.diffRemoved
                                      : ink.subtlest)))),
                const SizedBox(width: 4),
                if (diff != null) ...[
                  const SizedBox(width: 4),
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('+${diff.added}',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontSize: 12,
                            color: ink.diffAdded)),
                    const SizedBox(width: 4),
                    Text('-${diff.removed}',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontFeatures: const [FontFeature.tabularFigures()],
                            fontSize: 12,
                            color: ink.diffRemoved)),
                  ]),
                ],
                LucideIcon(_expanded ? 'chevron-down' : 'chevron-right',
                    size: 12, color: ink.subtlest),
              ]))),
      if (_expanded)
        Padding(
            padding: const EdgeInsets.only(left: 24, top: 6),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (info.description?.isNotEmpty == true)
                    Text(info.description!,
                        style: TextStyle(fontSize: 13, color: ink.subtlest)),
                  if (errorText.isNotEmpty)
                    _detail(context, uiText(context, '错误', 'Error'), errorText,
                        failed: true),
                  if (toolOutputTruncated(row))
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(children: [
                          LucideIcon('alert-triangle',
                              size: 14, color: ink.subtlest),
                          const SizedBox(width: 6),
                          Text(uiText(context, '输出已截断', 'Output truncated'),
                              style:
                                  TextStyle(fontSize: 12, color: ink.subtlest)),
                        ])),
                  if (inlineDiff != null) ToolInlineDiffView(diff: inlineDiff),
                  if (result.isNotEmpty)
                    Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _detail(
                              context, uiText(context, '结果', 'Result'), result),
                          if (fullResult.length > outputPreviewLimit)
                            Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton(
                                    onPressed: () => setState(
                                        () => _fullOutput = !_fullOutput),
                                    child: Text(_fullOutput
                                        ? uiText(
                                            context, '收起大输出', 'Collapse output')
                                        : uiText(context, '展开大输出',
                                            'Expand output')))),
                        ]),
                  if (toolFilePaths(row).isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(spacing: 4, runSpacing: 4, children: [
                          for (final path in toolFilePaths(row))
                            ActionChip(
                                label: Text(path,
                                    style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                onPressed: () async {
                                  try {
                                    if (Platform.isWindows) {
                                      await Process.run(
                                          'explorer', ['/select,', path]);
                                    }
                                  } catch (_) {}
                                }),
                        ])),
                  if (toolUrls(row).isNotEmpty)
                    Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Wrap(spacing: 4, runSpacing: 4, children: [
                          for (final url in toolUrls(row))
                            ActionChip(
                                label: Text(url,
                                    style: const TextStyle(fontSize: 11)),
                                visualDensity: VisualDensity.compact,
                                onPressed: () async {
                                  try {
                                    if (Platform.isWindows) {
                                      await Process.run(
                                          'cmd', ['/c', 'start', '', url]);
                                    }
                                  } catch (_) {}
                                }),
                        ])),
                  _detail(context, uiText(context, '调用', 'Call'), info.name),
                  if (rawArguments != null) ...[
                    if (inlineDiff != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _showArguments = !_showArguments),
                          child: Text(_showArguments
                              ? uiText(context, '隐藏原始参数', 'Hide raw arguments')
                              : uiText(
                                  context, '显示原始参数', 'Show raw arguments')),
                        ),
                      ),
                    if (_showArguments || inlineDiff == null)
                      _detail(context, uiText(context, '参数', 'Arguments'),
                          renderedArguments),
                    if ((_showArguments || inlineDiff == null) &&
                        fullArguments.length > argumentPreviewLimit)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton(
                          onPressed: () =>
                              setState(() => _fullArguments = !_fullArguments),
                          child: Text(_fullArguments
                              ? uiText(context, '收起大参数', 'Collapse arguments')
                              : uiText(context, '展开大参数', 'Expand arguments')),
                        ),
                      ),
                  ],
                ])),
    ]);
  }

  Widget _detail(BuildContext context, String title, String text,
      {bool failed = false}) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child:
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: TextStyle(fontSize: 12, color: ink.subtlest)),
          const SizedBox(height: 4),
          Container(
              constraints: const BoxConstraints(maxHeight: 288),
              decoration: BoxDecoration(
                  color: ink.card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ink.border)),
              padding: const EdgeInsets.all(12),
              child: CodeViewer(
                source: text,
                theme: CodeThemeCatalog.fromContext(context),
                fontSize:
                    ClientPreferencesScope.maybeOf(context)?.codeFontSize ??
                        12,
                showLineNumbers: false,
                wrapLongLines:
                    ClientPreferencesScope.maybeOf(context)?.wrapLongLines ??
                        false,
              )),
        ]));
  }
}

/// Official `goal_verification` synthetic stream row (bundle `fc`/`dc`):
/// `{version:1, kind:'synthetic', type:'goal_verification',
///   display:'separator', targetId, verificationId,
///   status: started|completed|failed_closed|cancelled,
///   verification?: {nextAction?: string|null, passed: bool, reason: string},
///   goalIteration?, anchorAssistantMessageId?, anchorTurnId?, startedAt?}`.
///
/// Schema-driven rendering (rule 24): implemented against the captured wire
/// schema with synthetic fixtures; the official visual sample is pending a
/// live desktop stream (implemented pending real verification).
class GoalVerificationRow extends StatelessWidget {
  const GoalVerificationRow({super.key, required this.row});

  final Map<String, dynamic> row;

  static const _statusStarted = 'started';
  static const _statusCompleted = 'completed';
  static const _statusFailedClosed = 'failed_closed';
  static const _statusCancelled = 'cancelled';

  /// Schema-valid statuses from the captured bundle enum `M([
  /// 'started','completed','failed_closed','cancelled'])`.
  static const knownStatuses = [
    _statusStarted,
    _statusCompleted,
    _statusFailedClosed,
    _statusCancelled,
  ];

  static bool isGoalVerification(Map<String, dynamic> row) =>
      row['type'] == 'goal_verification' &&
          (row['kind'] == 'synthetic' || row['kind'] == null) ||
      row['kind'] == 'goal_verification';

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final status =
        row['status'] is String ? row['status'] as String : _statusStarted;
    final verification =
        row['verification'] is Map ? row['verification'] as Map : null;
    final passed = verification?['passed'] is bool
        ? verification!['passed'] as bool
        : null;
    final reason = _text(verification?['reason']);
    final nextAction = _text(verification?['nextAction']);
    final iteration = row['goalIteration'] is num
        ? (row['goalIteration'] as num).toInt()
        : null;

    final (label, color) = switch (status) {
      _statusStarted when passed == null => (
          uiText(context, '目标验证中', 'Goal verification running'),
          ink.subtlest,
        ),
      _statusCompleted when passed == true => (
          uiText(context, '目标验证通过', 'Goal verification passed'),
          ink.diffAdded,
        ),
      _statusCompleted => (
          uiText(context, '目标验证未通过', 'Goal verification not passed'),
          ink.diffRemoved,
        ),
      _statusFailedClosed => (
          uiText(context, '目标验证失败关闭', 'Goal verification failed closed'),
          ink.diffRemoved,
        ),
      _statusCancelled => (
          uiText(context, '目标验证已取消', 'Goal verification cancelled'),
          ink.subtlest,
        ),
      _ => (status, ink.subtlest),
    };

    final headline = [
      if (iteration != null) '#$iteration',
      label,
    ].join(' ');

    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Divider(height: 1, color: ink.border)),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Text(headline,
                    style: TextStyle(fontSize: 12, color: color))),
            Expanded(child: Divider(height: 1, color: ink.border)),
          ]),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(reason, style: TextStyle(fontSize: 12, color: ink.subtlest)),
          ],
          if (nextAction.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(uiText(context, '下一步：$nextAction', 'Next: $nextAction'),
                style: TextStyle(fontSize: 12, color: ink.subtlest)),
          ],
        ]));
  }
}
