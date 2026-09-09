import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../protocol/conversation.dart';
import '../protocol/zemote_client.dart';
import '../state/client_preferences.dart';
import '../state/conversation_view_state.dart';
import '../state/conversation_history.dart';
import '../state/composer_controller.dart';
import '../state/composer_store.dart';
import 'composer/composer_bar.dart';
import 'conversation_viewport.dart';
import 'conversation_work_rows.dart';
import 'official_icons.dart';
import 'theme.dart';

/// Time-of-day greeting for the draft (empty) chat — official chat.empty
/// greeting copy (conversation-page-spec §6).
String emptyGreeting(DateTime now) {
  final h = now.hour;
  if (h >= 5 && h < 8) return '早上好呀，新的一天开始啦';
  if (h >= 8 && h < 11) return '上午好呀，有什么想让我帮忙的吗';
  if (h >= 11 && h < 13) return '中午好呀，要不要先休息一下';
  if (h >= 13 && h < 18) return '下午好呀，接下来交给我吧';
  if (h >= 18 && h < 23) return '晚上好呀，今天辛苦啦';
  return '夜深啦，别忘了照顾好自己哦';
}

/// Official turnHeader duration (bundle BX): activeMs first, then
/// endedAt-startedAt, running uses now-startedAt.
int? turnDurationMs(Map<String, dynamic> row, {required bool running}) {
  final active = (row['activeMs'] as num?)?.toInt();
  if (active != null) return active;
  final startedAt = (row['startedAt'] as num?)?.toInt();
  final endedAt = (row['endedAt'] as num?)?.toInt();
  if (startedAt != null && endedAt != null) {
    return (endedAt - startedAt).clamp(0, 1 << 40);
  }
  if (running && startedAt != null) {
    return (DateTime.now().millisecondsSinceEpoch - startedAt)
        .clamp(0, 1 << 40);
  }
  return null;
}

/// Official turn work-status label (chat.history.*): running = 工作中
/// {duration}, interrupted/failed = 已停止, completed = 已工作 {duration}
/// (or 已处理 when no duration was reported).
String turnWorkLabel({required String state, int? durationMs}) {
  switch (state) {
    case 'running':
    case 'inputStreaming':
      return durationMs == null || durationMs <= 0
          ? '工作中'
          : '工作中 ${formatTurnDuration(durationMs)}';
    case 'completedInterrupted':
    case 'cancelled':
    case 'interrupted':
    case 'failed':
    case 'error':
      return '已停止';
    default:
      return durationMs == null || durationMs <= 0
          ? '已处理'
          : '已工作 ${formatTurnDuration(durationMs)}';
  }
}

/// zh compact duration (chat.history.duration.*): 秒/分/时/天, zero-value
/// trailing units dropped, everything-zero collapses to 0秒.
String formatTurnDuration(int ms) {
  if (ms < 0) ms = 0;
  final duration = Duration(milliseconds: ms);
  final days = duration.inDays;
  final hours = duration.inHours % 24;
  final minutes = duration.inMinutes % 60;
  final seconds = duration.inSeconds % 60;
  final parts = <String>[
    if (days > 0) '$days天',
    if (hours > 0) '$hours时',
    if (minutes > 0) '$minutes分',
    if (seconds > 0) '$seconds秒',
  ];
  return parts.isEmpty ? '0秒' : parts.join();
}

/// Official default-open rule for a turn's collapsible history: the latest
/// turn stays open while running; a lone turn with no assistant text yet
/// stays open; everything else defaults to collapsed (conversation-page-spec
/// §1). Collapsing keeps only the final assistant summary text.
bool turnDefaultOpen({
  required bool isLastTurn,
  required bool running,
  required bool singleTurn,
  required bool hasAssistantText,
  required bool hasWorkRows,
}) {
  if (isLastTurn && running) return true;
  if (singleTurn && !hasAssistantText && hasWorkRows) return true;
  return false;
}

/// Groups rows into turns (mirrors the web timeline): a user message starts
/// a new group; assistant text/reasoning/tool rows that follow belong to
/// the same turn and render as ONE message. Consecutive assistant rows merge
/// even if the server bumps `turnId` mid-response (lesson #6).
List<List<Map<String, dynamic>>> _groupRows(List<Map<String, dynamic>> rows) {
  final groups = <List<Map<String, dynamic>>>[];
  List<Map<String, dynamic>>? current;
  for (final row in rows) {
    final kind = row['kind'];
    if (kind == 'timelineMarker') {
      current = null;
      groups.add([row]);
      continue;
    }
    final isUser = kind == 'userInput';
    final startsGroup =
        isUser || current == null || current.first['kind'] == 'userInput';
    if (startsGroup) {
      current = [row];
      groups.add(current);
    } else {
      current.add(row);
    }
  }
  return groups;
}

/// Chat view for one task (session), backed by Conversation V4 subscription.
/// Draft mode (no [sessionId]): the first message issues `createSession`.
class ChatPage extends StatefulWidget {
  final BridgeSession session;
  final Map<String, dynamic> scope;
  final String workspaceKey;
  final String? sessionId;
  final String title;
  final String? workspaceName;
  final String? deviceId;
  final Map<String, String>? drafts;
  final ValueChanged<String>? onSessionCreated;
  final ValueChanged<ConversationState>? onStateChanged;
  final Map<String, ConversationViewState>? viewStates;
  final bool embedded;
  final ComposerStore? composerStore;

  const ChatPage({
    super.key,
    required this.session,
    required this.scope,
    required this.workspaceKey,
    this.sessionId,
    required this.title,
    this.workspaceName,
    this.deviceId,
    this.drafts,
    this.onSessionCreated,
    this.onStateChanged,
    this.viewStates,
    this.embedded = false,
    this.composerStore,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ConversationTransport _transport;
  ConversationSubscription? _sub;
  ConversationState? _state;
  late final ComposerStore _composerStore;
  late final ComposerController _composer;
  bool _connecting = true;
  String? _error;
  late ConversationViewState _view;
  ConversationHistory? _history;
  bool _subscribing = false;

  // Draft mode: first send creates the session.
  String get _sessionId => widget.sessionId ?? _liveSessionId;
  String _liveSessionId = '';
  String get _draftKey =>
      composerKey(widget.deviceId, widget.workspaceKey, _sessionId);

  @override
  void initState() {
    super.initState();
    _transport = widget.session.conversation(widget.scope);
    _view =
        widget.viewStates?.putIfAbsent(_draftKey, ConversationViewState.new) ??
            ConversationViewState();
    _composerStore = widget.composerStore ??
        ComposerStore(drafts: widget.drafts, viewStates: widget.viewStates);
    _composer = _composerStore.obtain(
        transport: _transport,
        deviceId: widget.deviceId,
        workspaceKey: widget.workspaceKey,
        sessionId: widget.sessionId);
    _liveSessionId = _composer.sessionId ?? '';
    _composer.addListener(_onComposerChanged);
    unawaited(_composer.loadOptions());
    _subscribe();
  }

  @override
  void dispose() {
    _history?.removeListener(_onHistory);
    _history?.dispose();
    _sub?.state.removeListener(_onState);
    _sub?.dispose();
    _composer.removeListener(_onComposerChanged);
    _composer.unbind(_state);
    if (widget.composerStore == null) _composerStore.dispose();
    super.dispose();
  }

  Future<void> _subscribe() async {
    if (!mounted || _subscribing) return;
    final sid = _sessionId;
    if (sid.isEmpty) {
      setState(() => _connecting = false);
      return;
    }
    _subscribing = true;
    try {
      final sub = await _transport.subscribe(sid);
      if (!mounted) {
        await sub.dispose();
        return;
      }
      final previous = _sub;
      previous?.state.removeListener(_onState);
      if (previous != null) await previous.dispose();
      if (!mounted) {
        await sub.dispose();
        return;
      }
      _sub = sub;
      _state = sub.state;
      _history?.removeListener(_onHistory);
      _history?.dispose();
      _history = ConversationHistory(
          transport: _transport, sessionId: sid, state: sub.state, view: _view)
        ..addListener(_onHistory);
      _composer.bind(sub.state);
      sub.state.addListener(_onState);
      setState(() {
        _connecting = false;
        _error = null;
      });
      widget.onStateChanged?.call(sub.state);
      unawaited(_history!.restoreReading());
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _connecting = false;
        _error = e.toString();
      });
    } finally {
      _subscribing = false;
    }
  }

  void _onState() {
    if (mounted) {
      setState(() {});
      if (_state != null) widget.onStateChanged?.call(_state!);
    }
  }

  void _onHistory() {
    if (mounted) setState(() {});
  }

  void _onComposerChanged() {
    if (!mounted) return;
    final id = _composer.sessionId;
    if (id != null && id != _sessionId) {
      setState(() => _liveSessionId = id);
      widget.onSessionCreated?.call(id);
      unawaited(_subscribe());
    }
  }

  void _toast(String message) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: ink.card,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(ZRadius.lg),
          side: BorderSide(color: ink.border),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final rows = _state?.rows ?? const <Map<String, dynamic>>[];
    return Scaffold(
      backgroundColor: ink.background,
      resizeToAvoidBottomInset: !widget.embedded,
      appBar: widget.embedded
          ? null
          : AppBar(
              backgroundColor: ink.surface,
              foregroundColor: ink.text,
              elevation: 0,
              scrolledUnderElevation: 0,
              titleSpacing: 0,
              title: Text(
                widget.title,
                style: TextStyle(
                  color: ink.text,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
      body: Column(
        children: [
          Expanded(
            child: switch ((_connecting, _error)) {
              (true, _) => const Center(
                  child: SizedBox(
                    width: 26,
                    height: 26,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: ZInk.running,
                    ),
                  ),
                ),
              (_, String()) => _buildError(ink),
              _ => _buildChat(ink, rows),
            },
          ),
          ComposerBar(controller: _composer),
        ],
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
            const LucideIcon('alert-triangle',
                size: 28, color: Color(0xFFF87171)),
            const SizedBox(height: 14),
            Text(
              '无法加载会话',
              style: TextStyle(
                color: ink.text,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error ?? '',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ink.text.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 18),
            _RetryButton(onRetry: _subscribe),
          ],
        ),
      ),
    );
  }

  Widget _buildChat(InkTokens ink, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty && _sessionId.isEmpty) {
      return _buildDraftEmpty(ink);
    }
    if (rows.isEmpty) {
      return Center(
        child: Text(
          '还没有消息',
          style:
              TextStyle(color: ink.text.withValues(alpha: 0.4), fontSize: 13),
        ),
      );
    }
    final groups = _groupRows(rows);
    final lastIndex = groups.length - 1;
    final history = _history;
    if (history?.blocksViewport == true) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          if (history!.restoring) const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
              history.restoreFailed
                  ? uiText(context, '阅读位置恢复失败，已加载的历史已保留',
                      'Could not restore your reading position. Loaded history is preserved.')
                  : uiText(context, '正在恢复阅读位置…', 'Restoring reading position…'),
              textAlign: TextAlign.center),
          const SizedBox(height: 12),
          Wrap(spacing: 12, children: [
            if (history.restoreFailed)
              TextButton(
                  onPressed: history.restoreReading,
                  child: Text(uiText(context, '重试', 'Retry'))),
            TextButton(
                onPressed: history.showLatest,
                child: Text(uiText(context, '回到最新', 'Latest'))),
          ]),
        ]),
      ));
    }
    // A projection tail can initially begin inside a turn. Once older rows
    // arrive, address the containing rendered group rather than a lost key.
    final anchor = int.tryParse(_view.anchor ?? '');
    if (anchor != null && !_view.following) {
      final group = groups
          .where((rows) => rows.any((row) => row['rowId'] == anchor))
          .firstOrNull;
      if (group != null) _view.anchor = '${group.first['rowId']}';
    }
    return Column(children: [
      if (history?.notice != null)
        Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Expanded(
                  child: Text(history!.notice == ReadingNotice.historyChanged
                      ? uiText(context, '历史记录已更新，已回到最新位置',
                          'History changed. Showing the latest messages.')
                      : uiText(context, '原阅读位置已不存在，已回到最新位置',
                          'The previous reading position is unavailable. Showing the latest messages.'))),
              IconButton(
                  onPressed: history.dismissNotice,
                  tooltip: uiText(context, '关闭', 'Close'),
                  icon: const LucideIcon('x', size: 16)),
            ])),
      Expanded(
          child: ConversationViewport(
        view: _view,
        ids: [for (final group in groups) '${group.first['rowId']}'],
        onLoadOlder: _state?.canLoadOlder == true ? _loadOlder : null,
        loadingOlder: history?.loading ?? false,
        itemBuilder: (context, i) => _TurnGroup(
          rows: groups[i],
          transport: _transport,
          sessionId: _sessionId,
          state: _state!,
          isLastTurn: i == lastIndex,
          expandedOverride:
              _view.expandedTurns[groups[i].first['rowId'] as int?],
          onToggleExpanded: (v) {
            final key = groups[i].first['rowId'] as int?;
            if (key != null) setState(() => _view.expandedTurns[key] = v);
          },
        ),
      ))
    ]);
  }

  Future<void> _loadOlder() async {
    final history = _history;
    if (history == null || history.loading) return;
    try {
      final result = await history.loadOlder();
      if (!mounted || !identical(history, _history)) return;
      if (result != HistoryPageResult.applied) {
        throw StateError('history did not advance');
      }
    } catch (_) {
      if (mounted) {
        _toast(uiText(context, '历史消息加载失败，请重试',
            'Could not load earlier messages. Try again.'));
      }
    }
  }

  /// 空态：官方时段问候 + 「开始对话」+ 在 {workspace} 新建任务（§6）。
  Widget _buildDraftEmpty(InkTokens ink) {
    final workspace = widget.workspaceName ?? widget.workspaceKey;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              emptyGreeting(DateTime.now()),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ink.text,
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '开始对话',
              style: TextStyle(
                color: ink.text.withValues(alpha: 0.55),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '开始在 $workspace 项目新建任务',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: ink.text.withValues(alpha: 0.4),
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZInk.running.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(ZRadius.lg),
      child: InkWell(
        onTap: onRetry,
        borderRadius: BorderRadius.circular(ZRadius.lg),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: Text(
            '重试',
            style: TextStyle(
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

/// 一轮对话：用户消息 + 可折叠的 assistant 工作流程（官方 history-message，
/// §1）。块间距 mt-5 = 20px。
class _TurnGroup extends StatelessWidget {
  final List<Map<String, dynamic>> rows;
  final ConversationTransport transport;
  final String sessionId;
  final ConversationState state;
  final bool isLastTurn;
  final bool? expandedOverride;
  final ValueChanged<bool>? onToggleExpanded;

  const _TurnGroup({
    required this.rows,
    required this.transport,
    required this.sessionId,
    required this.state,
    required this.isLastTurn,
    this.expandedOverride,
    this.onToggleExpanded,
  });

  @override
  Widget build(BuildContext context) {
    if (rows.length == 1 && rows.first['kind'] == 'timelineMarker') {
      return _TimelineMarker(row: rows.first);
    }
    var lead = 0;
    while (lead < rows.length && rows[lead]['kind'] == 'userInput') {
      lead++;
    }
    final userRows = rows.sublist(0, lead);
    final assistantRows = rows.sublist(lead);
    final showTurnHeader = assistantRows.isNotEmpty;
    final running = assistantRows.any(_rowIsActive);
    final header = assistantRows.firstWhere(
      (r) => r['kind'] == 'turnHeader',
      orElse: () => const {},
    );
    final hasAssistantText =
        assistantRows.any((r) => r['kind'] == 'assistantText');
    final singleTurn = state.rows
            .where((r) => r['kind'] == 'userInput' || r['kind'] == 'turnHeader')
            .length <=
        1;
    final defaultOpen = turnDefaultOpen(
      isLastTurn: isLastTurn,
      running: running,
      singleTurn: singleTurn,
      hasAssistantText: hasAssistantText,
      hasWorkRows: assistantRows.isNotEmpty,
    );
    final expanded = expandedOverride ?? defaultOpen;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < userRows.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _UserBubble(row: userRows[i]),
        ],
        if (assistantRows.isNotEmpty) ...[
          if (userRows.isNotEmpty) const SizedBox(height: 20),
          if (showTurnHeader) ...[
            _TurnTrigger(
              header: header,
              running: running,
              expanded: expanded,
              onToggle: () => onToggleExpanded?.call(!expanded),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: expanded
                    ? _assistantBody(context, assistantRows)
                    : _collapsedBody(context, assistantRows),
              ),
            ),
          ] else
            ..._assistantBody(context, assistantRows),
        ],
      ],
    );
  }

  List<Widget> _assistantBody(
      BuildContext context, List<Map<String, dynamic>> rows) {
    // 折叠触发行已在外面渲染，这里渲染其后的真实内容（含 turnHeader
    // 本身已并入触发行，跳过重复）。
    return [
      for (final row in rows)
        if (row['kind'] != 'turnHeader')
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _rowWidget(context, row),
          ),
    ];
  }

  /// 折叠态只保留最后一段 assistant 总结正文（官方语义）。
  List<Widget> _collapsedBody(
      BuildContext context, List<Map<String, dynamic>> rows) {
    var lastTextIdx = -1;
    for (var i = 0; i < rows.length; i++) {
      if (rows[i]['kind'] == 'assistantText') lastTextIdx = i;
    }
    if (lastTextIdx < 0) return const [];
    return [
      Padding(
        padding: const EdgeInsets.only(top: 8),
        child: _rowWidget(context, rows[lastTextIdx]),
      ),
    ];
  }

  Widget _rowWidget(BuildContext context, Map<String, dynamic> row) {
    return switch (row['kind']) {
      'assistantText' => _AssistantText(row: row),
      'reasoning' => ReasoningRow(key: ValueKey(row['rowId']), row: row),
      'toolCall' => ToolCallRow(key: ValueKey(row['rowId']), row: row),
      'changeSummary' => ConversationChangeSummary(row: row),
      'subagent' => _SubagentRow(row: row),
      _ => const SizedBox.shrink(),
    };
  }
}

bool _rowIsActive(Map<String, dynamic> row) {
  if (row['state'] == 'streaming' || row['state'] == 'running') return true;
  if (row['kind'] == 'toolCall') {
    final status = row['status'];
    if (const ['running', 'waiting', 'inputStreaming', 'pendingApproval']
        .contains(status)) {
      return true;
    }
    if (row['requiresInteraction'] == true) return true;
  }
  return false;
}

/// 官方 turn 触发行（PX/§1）：`border-b border-border/50` subtle 文字 +
/// chevron（闭合朝右、展开转 90° 朝下）。
class _TurnTrigger extends StatelessWidget {
  final Map<String, dynamic> header;
  final bool running;
  final bool expanded;
  final VoidCallback onToggle;

  const _TurnTrigger({
    required this.header,
    required this.running,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final st = header['state'] as String? ?? 'completed';
    final ms = turnDurationMs(header, running: running);
    final label = turnWorkLabel(state: st, durationMs: ms);
    return InkWell(
      onTap: onToggle,
      child: Container(
        padding: const EdgeInsets.only(top: 4, bottom: 8),
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
                color: ink.border.withValues(alpha: ink.border.a * 0.5)),
          ),
        ),
        child: Row(
          children: [
            AnimatedRotation(
              turns: expanded ? 0.25 : 0,
              duration: const Duration(milliseconds: 150),
              child: LucideIcon('chevron-right', size: 16, color: ink.subtlest),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color:
                      running ? ink.text.withValues(alpha: 0.7) : ink.subtlest,
                  fontSize: 14,
                  fontWeight: running ? FontWeight.w500 : FontWeight.w400,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 官方用户消息气泡（data-v4-user-input-bubble）：12px 圆角 + 右上 2px 尖角，
/// surface 底 + 10% hairline，16/12 padding，max-w-xl 576px，右对齐。
class _UserBubble extends StatelessWidget {
  final Map<String, dynamic> row;

  const _UserBubble({required this.row});

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final text = row['text'] as String? ?? '';
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 576),
        margin: const EdgeInsets.only(left: 56, top: 4, bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: ink.messageSurface,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            topRight: Radius.circular(2),
            bottomLeft: Radius.circular(12),
            bottomRight: Radius.circular(12),
          ),
          border: Border.all(color: ink.messageBorder),
        ),
        child: text.isEmpty
            ? null
            : SelectableText(
                text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: ink.text,
                ),
              ),
      ),
    );
  }
}

/// Assistant 正文和代码按当前客户端主题及代码字号渲染。
class _AssistantText extends StatelessWidget {
  final Map<String, dynamic> row;

  const _AssistantText({required this.row});

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final text = row['text'] as String? ?? '';
    // RenderEditable keeps cached link semantics across accessibility restarts.
    // Text.rich under SelectionArea recreates paragraph semantics correctly and
    // preserves Android selection/copy across this complete Markdown message.
    return SelectionArea(
        child: MarkdownBody(
            data: text,
            styleSheet:
                MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
              p: TextStyle(fontSize: 14, height: 1.6, color: ink.text),
              code: TextStyle(
                  fontFamily: 'monospace',
                  fontSize:
                      ClientPreferencesScope.maybeOf(context)?.codeFontSize ??
                          13,
                  color: ink.text,
                  backgroundColor: ink.card),
              codeblockDecoration: BoxDecoration(
                  color: ink.card, borderRadius: BorderRadius.circular(8)),
              blockquoteDecoration: BoxDecoration(
                  color: ink.surface,
                  border:
                      Border(left: BorderSide(color: ink.border, width: 2))),
              tableBorder: TableBorder.all(color: ink.border),
            )));
  }
}

/// 子智能体行（not）：一行 subtle 小字 `类型 · 状态 — 摘要`。
class _SubagentRow extends StatelessWidget {
  final Map<String, dynamic> row;

  const _SubagentRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final parts = <String>[
      row['subagentType'] as String? ?? row['type'] as String? ?? '',
      row['status'] as String? ?? '',
    ];
    final summary = row['summaryText'] as String? ??
        row['summary'] as String? ??
        row['text'] as String? ??
        '';
    final line = [
      parts.where((p) => p.isNotEmpty).join(' · '),
      if (summary.isNotEmpty) summary,
    ].where((p) => p.isNotEmpty).join(' — ');
    return Text(
      line,
      style: TextStyle(
        fontSize: 13,
        color: ink.text.withValues(alpha: 0.55),
      ),
    );
  }
}

/// 时间线标记（$at）：左右两条 1px 细线夹中央 icon + label。
class _TimelineMarker extends StatelessWidget {
  final Map<String, dynamic> row;

  const _TimelineMarker({required this.row});

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final label = row['label'] as String? ?? '';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Expanded(
              child: Container(
                  height: 1, color: ink.border.withValues(alpha: 0.5))),
          const SizedBox(width: 8),
          LucideIcon('git-branch', size: 14, color: ink.subtlest),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: ink.subtlest,
              ),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
              child: Container(
                  height: 1, color: ink.border.withValues(alpha: 0.5))),
        ],
      ),
    );
  }
}

/// 变更摘要卡（utt，§3）：`rounded-xl border bg-card`，头部 chevron +
/// 「N 个文件已更改」+ `+N -N`，展开文件行。
class ConversationChangeSummary extends StatefulWidget {
  final Map<String, dynamic> row;

  const ConversationChangeSummary({super.key, required this.row});

  @override
  State<ConversationChangeSummary> createState() => _ChangeSummaryCardState();
}

class _ChangeSummaryCardState extends State<ConversationChangeSummary> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final files = switch (widget.row['files']) {
      final List l =>
        l.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList(),
      _ => const <Map<String, dynamic>>[],
    };
    final count = (widget.row['count'] as num?)?.toInt() ?? files.length;
    var added = 0;
    var removed = 0;
    for (final f in files) {
      added += (f['addedLines'] as num?)?.toInt() ?? 0;
      removed += (f['removedLines'] as num?)?.toInt() ?? 0;
    }
    return Container(
      decoration: BoxDecoration(
        color: ink.card,
        borderRadius: BorderRadius.circular(ZRadius.xl),
        border: Border.all(color: ink.border),
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Container(
              height: 40,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Row(
                children: [
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 150),
                    child: LucideIcon('chevron-right',
                        size: 12, color: ink.subtlest),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                      child: Text(
                    '$count 个文件已更改',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: ink.text,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  )),
                  const SizedBox(width: 8),
                  Text(
                    '+$added -$removed',
                    style: TextStyle(
                      fontSize: 12,
                      fontFamily: 'monospace',
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: ink.text.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            for (final f in files)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    LucideIcon('chevron-right', size: 12, color: ink.subtlest),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        f['path'] as String? ?? '',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: ink.text.withValues(alpha: 0.7),
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                    Text(
                      '+${f['addedLines'] ?? 0} -${f['removedLines'] ?? 0}',
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: ink.text.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
