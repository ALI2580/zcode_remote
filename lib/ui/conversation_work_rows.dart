import 'dart:convert';
import 'package:flutter/material.dart';
import '../state/client_preferences.dart';
import 'official_icons.dart';
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
        'agent' => ['description'],
        _ => ['file_path', 'path'],
      };
      for (final field in fields) {
        summary = _text(input[field]);
        if (summary.isNotEmpty) break;
      }
    }
    return ToolRowInfo(
        name: name,
        family: family,
        title: summary.isNotEmpty ? summary : _pretty(name));
  }
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

class ToolCallRow extends StatefulWidget {
  const ToolCallRow({super.key, required this.row});
  final Map<String, dynamic> row;
  @override
  State<ToolCallRow> createState() => _ToolCallRowState();
}

class _ToolCallRowState extends State<ToolCallRow> {
  bool _expanded = false;
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
    final result = _json(output is Map ? output['text'] : output);
    final error = row['error'];
    final errorText = _json(error is Map ? error['message'] : error);
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
                  if (result.isNotEmpty)
                    _detail(context, uiText(context, '结果', 'Result'), result),
                  _detail(context, uiText(context, '调用详情', 'Call details'),
                      '${info.name}\n${_json(toolInput(row))}'.trim()),
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
              child: SingleChildScrollView(
                  child: SelectableText(text,
                      style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: ClientPreferencesScope.maybeOf(context)
                                  ?.codeFontSize ??
                              13,
                          color: failed ? ink.diffRemoved : ink.text)))),
        ]));
  }
}
