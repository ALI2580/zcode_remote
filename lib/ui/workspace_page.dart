import 'dart:async';

import 'package:flutter/material.dart';

import '../state/device_session.dart';
import '../state/app_sessions.dart';
import '../state/device_store.dart';
import '../notifications/task_target.dart';
import 'chat_page.dart';
import 'official_icons.dart';
import 'theme.dart';
import 'task_list_page.dart';

/// Workspace key for a workspace entry: identity first, then path (mirrors
/// the web client's `workspaceKeyOf` — identity is stable across renames).
String? workspaceKeyOf(Map<String, dynamic> w) {
  final identity = w['workspaceIdentity'];
  if (identity is String && identity.trim().isNotEmpty) return identity.trim();
  final path = w['workspacePath'];
  if (path is String && path.isNotEmpty) return path;
  for (final key in const ['workspaceKey', 'key', 'id']) {
    final v = w[key];
    if (v is String && v.isNotEmpty) return v;
  }
  return null;
}

/// Display title for a workspace entry.
String workspaceTitle(Map<String, dynamic> w) {
  final identity = w['workspaceIdentity'] as String?;
  if (identity is String && identity.trim().isNotEmpty) return identity;
  final path = w['workspacePath'] as String?;
  if (path is String && path.isNotEmpty) {
    final name = path.replaceAll('\\', '/').split('/').last;
    if (name.isNotEmpty) return name;
  }
  return workspaceKeyOf(w) ?? '未知工作区';
}

/// Workspace picker for one connected desktop: connect animation → workspace
/// list → open a workspace bridge. Completes the device → workspace →
/// session navigation chain (批 2 收尾).
class WorkspacePage extends StatefulWidget {
  const WorkspacePage(
      {super.key,
      required this.device,
      required this.sessions,
      this.initialTarget});

  final Device device;
  final AppSessions sessions;
  final TaskTarget? initialTarget;

  @override
  State<WorkspacePage> createState() => _WorkspacePageState();
}

class _WorkspacePageState extends State<WorkspacePage> {
  late final DeviceSession _session;
  final List<String> _logs = [];
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    final params = widget.device.params;
    if (params == null) {
      throw StateError('无效的设备链接');
    }
    _session = widget.sessions.sessionFor(widget.device);
    _session.addListener(_onSessionChanged);
    _connect();
  }

  @override
  void dispose() {
    _session.removeListener(_onSessionChanged);
    super.dispose();
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  void _onLog(String line) {
    if (!mounted) return;
    setState(() => _logs.add(line));
  }

  Future<void> _connect() async {
    try {
      await _session.connect(onLog: _onLog);
      final target = widget.initialTarget;
      if (mounted && target != null) {
        await _openWorkspace({
          'workspaceIdentity': target.workspaceKey,
          if (target.workspacePath != null)
            'workspacePath': target.workspacePath,
        }, target: target);
      }
    } catch (e) {
      if (!mounted) return;
      _onLog('连接失败：$e');
    }
  }

  Future<void> _openWorkspace(Map<String, dynamic> workspace,
      {TaskTarget? target}) async {
    if (_opening) return;
    final key = workspaceKeyOf(workspace);
    if (key == null) {
      _toast('无法解析该工作区，请重试');
      return;
    }
    setState(() => _opening = true);
    try {
      final scope = {
        'workspaceIdentity': key,
        if (workspace['workspacePath'] != null)
          'workspacePath': workspace['workspacePath'],
      };
      final monitor =
          await widget.sessions.openWorkspace(widget.device, key, scope);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => target == null
              ? TaskListPage(
                  monitor: monitor,
                  sessions: widget.sessions,
                  title: workspaceTitle(workspace),
                )
              : ChatPage(
                  session: monitor.bridge,
                  scope: scope,
                  workspaceKey: key,
                  deviceId: widget.device.id,
                  drafts: widget.sessions.drafts,
                  sessionId: target.sessionId,
                  title: target.title,
                  workspaceName: workspaceTitle(workspace),
                ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _toast('打开失败：$e');
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ZInk.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZRadius.lg),
          side: const BorderSide(color: ZInk.border),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Scaffold(
      backgroundColor: ink.background,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(ink),
            Expanded(
              child: switch ((_session.error, _session.connected)) {
                (String(), _) => _buildError(ink),
                (_, false) => _buildConnecting(ink),
                (_, true) => _buildWorkspaces(ink),
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(InkTokens ink) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
      decoration: BoxDecoration(
        color: ink.surface,
        border: Border(bottom: BorderSide(color: ink.border)),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: _opening ? null : () => Navigator.pop(context),
            icon:
                const LucideIcon('arrow-left', size: 18, color: ZInk.textLight),
            tooltip: '返回',
          ),
          const SizedBox(width: 4),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: ZInk.running.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(ZRadius.lg),
            ),
            child: const LucideIcon('bot', size: 16, color: ZInk.running),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.device.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: ink.text,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  _session.connected ? '已连接' : '正在连接…',
                  style: TextStyle(
                    color: _session.connected
                        ? ZInk.running
                        : ink.text.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          if (_session.connected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: ZInk.running.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '${_session.workspaces.length} 个工作区',
                style: const TextStyle(
                  color: ZInk.running,
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildConnecting(InkTokens ink) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: ZInk.running,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              '正在连接桌面端…',
              style: TextStyle(
                color: ink.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '完成配对并获取工作区列表',
              style: TextStyle(
                color: ink.text.withValues(alpha: 0.5),
                fontSize: 12,
              ),
            ),
            if (_logs.isNotEmpty) ...[
              const SizedBox(height: 20),
              _LogPanel(logs: _logs, ink: ink),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildError(InkTokens ink) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: const Color(0xFFF87171).withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const LucideIcon('alert-triangle',
                  size: 26, color: Color(0xFFF87171)),
            ),
            const SizedBox(height: 18),
            Text(
              '连接失败',
              style: TextStyle(
                color: ink.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _session.error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ink.text.withValues(alpha: 0.6),
                fontSize: 12,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 20),
            _RetryButton(onRetry: _connect, disabled: _opening),
          ],
        ),
      ),
    );
  }

  Widget _buildWorkspaces(InkTokens ink) {
    final workspaces = _session.workspaces;
    if (workspaces.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const LucideIcon('folder-open', size: 34, color: ZInk.textLight),
              const SizedBox(height: 14),
              Text(
                '没有可用的工作区',
                style: TextStyle(
                  color: ink.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                '在桌面端打开项目后再试',
                style: TextStyle(
                  color: ink.text.withValues(alpha: 0.5),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 18),
              _RetryButton(
                onRetry: _session.connect,
                disabled: _opening,
                label: '刷新',
              ),
            ],
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      itemCount: workspaces.length,
      separatorBuilder: (_, __) => const SizedBox(height: 10),
      itemBuilder: (context, i) {
        final workspace = workspaces[i];
        return _WorkspaceRow(
          title: workspaceTitle(workspace),
          subtitle: workspaceKeyOf(workspace) ?? '',
          busy: _opening,
          onTap: () => _openWorkspace(workspace),
        );
      },
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton(
      {required this.onRetry, required this.disabled, this.label});

  final VoidCallback onRetry;
  final bool disabled;
  final String? label;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZInk.running.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(ZRadius.lg),
      child: InkWell(
        onTap: disabled ? null : onRetry,
        borderRadius: BorderRadius.circular(ZRadius.lg),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Text(
            label ?? '重试',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

/// 连接期间的调试日志面板（协议层 onLog 输出）。
class _LogPanel extends StatelessWidget {
  const _LogPanel({required this.logs, required this.ink});

  final List<String> logs;
  final InkTokens ink;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 140),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(ZRadius.lg),
        border: Border.all(color: ink.border),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: logs.length,
        itemBuilder: (context, i) => Text(
          logs[i],
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: ink.text.withValues(alpha: 0.55),
            fontSize: 11,
            fontFamily: 'monospace',
          ),
        ),
      ),
    );
  }
}

/// 单个工作区行：官方 card 质感（ZInk card + hairline + xl 圆角）。
class _WorkspaceRow extends StatelessWidget {
  const _WorkspaceRow({
    required this.title,
    required this.subtitle,
    required this.busy,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Material(
      color: ink.card,
      borderRadius: BorderRadius.circular(ZRadius.xl),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(ZRadius.xl),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(ZRadius.xl),
            border: Border.all(color: ink.border),
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: ZInk.reasoning.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(ZRadius.lg),
                ),
                child:
                    const LucideIcon('folder', size: 18, color: ZInk.reasoning),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink.text,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (subtitle.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: ink.text.withValues(alpha: 0.45),
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (busy)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: ZInk.running,
                  ),
                )
              else
                const LucideIcon('chevron-right',
                    size: 16, color: ZInk.textLight),
            ],
          ),
        ),
      ),
    );
  }
}
