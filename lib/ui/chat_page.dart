import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../protocol/conversation.dart';
import '../protocol/zemote_client.dart';
import '../state/background_works.dart';
import '../state/client_preferences.dart';
import '../state/conversation_view_state.dart';
import '../state/conversation_history.dart';
import '../state/composer_controller.dart';
import '../state/device_session.dart';
import '../state/composer_store.dart';
import '../state/remote_settings.dart';
import '../state/interaction_requests.dart';
import 'background_works_banner.dart';
import 'device_connection_status.dart';
import 'interaction_request_card.dart';
import 'workspace_hook_review_card.dart';
import '../state/file_changes_review.dart';
import 'composer/attachment_strip.dart';
import 'composer/composer_bar.dart';
import 'conversation_viewport.dart';
import 'conversation_work_rows.dart';
import 'code_renderer.dart';
import 'file_changes_review_panel.dart';
export 'conversation/turn_projection.dart'
    // S2: canonical home of the turn projection; this export keeps the
    // existing external imports of chat_page stable.
    show TurnFileChangeStats, chatTurnGroupComputeMicros,
    chatTurnGroupComputations, chatTurnGroupProfiling,
    conversationFileChangeSummaryRows, conversationTurnGroups,
    formatTurnDuration, rowIsActive, turnDefaultOpen, turnDurationMs,
    turnFileChangeStats, turnWorkLabel, turnWorkLabelEnglish;
import 'conversation/change_summary.dart';
export 'conversation/change_summary.dart' show ConversationChangeSummary;
import 'conversation/turn_projection.dart';
import 'official_icons.dart';
import 'mobile/mobile_layout.dart';
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

String normalizeConversationSearchSource(String value) => value
    .replaceFirst(RegExp(r'^\.\.\.'), '')
    .replaceFirst(RegExp(r'\.\.\.$'), '')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim()
    .toLowerCase();

/// Chat view for one task (session), backed by Conversation V4 subscription.
/// Draft mode (no [sessionId]): the first message issues `createSession`.
/// P2-conv deterministic counters: one increment per ChatPage build. The
/// streaming chain is state notification → setState → build → full turn
/// grouping; these counters make each stage observable in tests and CI.
int chatPageBuildCount = 0;

class ChatPage extends StatefulWidget {
  final BridgeSession session;
  final Map<String, dynamic> scope;
  final String workspaceKey;
  final String? sessionId;
  final String? searchSnippet;
  final int? searchSnippetIndex;
  final String? searchQuery;
  final int? searchRequestId;
  final String title;
  final String? workspaceName;
  final String? deviceId;
  final Map<String, String>? drafts;
  final ValueChanged<String>? onSessionCreated;
  final ValueChanged<ConversationState>? onStateChanged;
  final VoidCallback? onOpenHooks;
  final VoidCallback? onOpenModels;
  final Map<String, ConversationViewState>? viewStates;
  final bool embedded;
  /// Mirrors the official `selectionSideChat` pane flag. A side chat keeps
  /// the normal composer and configuration controls, while message actions
  /// that mutate, branch, or rate the parent conversation are unavailable.
  final bool isSideChat;
  final ComposerStore? composerStore;
  final DeviceSession? deviceSession;
  /// Shared by the shell's main and side panes. When omitted, ChatPage owns a
  /// scope-local fallback for standalone tests and embedded callers.
  final RemoteSettingsController? settingsController;
  final Future<void> Function()? onPairAgain;

  const ChatPage({
    super.key,
    required this.session,
    required this.scope,
    required this.workspaceKey,
    this.sessionId,
    this.searchSnippet,
    this.searchSnippetIndex,
    this.searchQuery,
    this.searchRequestId,
    required this.title,
    this.workspaceName,
    this.deviceId,
    this.drafts,
    this.onSessionCreated,
    this.onStateChanged,
    this.onOpenHooks,
    this.onOpenModels,
    this.viewStates,
    this.embedded = false,
    this.isSideChat = false,
    this.composerStore,
    this.deviceSession,
    this.settingsController,
    this.onPairAgain,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final ConversationTransport _transport;
  ConversationSubscription? _sub;
  ConversationState? _state;
  late final ComposerStore _composerStore;
  late ComposerController _composer;
  late RemoteSettingsController _settingsController;
  bool _ownsSettingsController = false;
  bool _connecting = true;
  String? _error;
  late ConversationViewState _view;
  ConversationHistory? _history;
  InteractionController? _interactions;
  WorkspaceHookReviewController? _workspaceHookReview;
  BackgroundWorksController? _backgroundWorks;
  bool _subscribing = false;
  bool _retrying = false;
  int _subscriptionRequest = 0;
  int _searchRequestId = 0;
  int? _pendingSearchRequestId;
  final _conversationRoot = GlobalKey();
  Timer? _searchHighlightTimer;
  String? _searchHighlightQuery;
  final _searchTargetKey = GlobalKey();
  final _searchTargetGroupKey = GlobalKey();
  final _searchHighlightLink = LayerLink();
  int? _searchTargetRowId;
  List<Rect> _searchHighlightRects = const [];
  int _searchHighlightAttempts = 0;
  int _forkGeneration = 0;
  int? _forkingRowId;
  int _editGeneration = 0;
  int? _editingRowId;
  String? _editFailure;
  final _feedbackByRowId = <int, String?>{};
  int _feedbackGeneration = 0;
  String? _activeSessionOverride;

  // Search may need to walk beyond the first projected history window. Keep
  // the walk finite even when a malformed/unstable peer keeps reporting more
  // rows; each page still passes through ConversationHistory's epoch/cursor
  // checks before it can mutate the conversation state.
  static const _searchPageSize = 200;
  static const _searchPageBudget = 24;
  static const _searchRowBudget = 5000;

  // Draft mode: first send creates the session.
  String get _sessionId =>
      _activeSessionOverride ?? widget.sessionId ?? _liveSessionId;
  String _liveSessionId = '';
  String get _draftKey =>
      composerKey(widget.deviceId, widget.workspaceKey, _sessionId);

  void _refreshSettingsAfterFrame(RemoteSettingsController controller) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_settingsController, controller)) return;
      unawaited(controller.refresh());
    });
  }

  void _loadComposerOptionsAfterFrame(ComposerController composer) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_composer, composer)) return;
      unawaited(composer.loadOptions());
    });
  }

  @override
  void initState() {
    super.initState();
    _transport = widget.session.conversation(widget.scope);
    _view =
        widget.viewStates?.putIfAbsent(_draftKey, ConversationViewState.new) ??
            ConversationViewState();
    _composerStore = widget.composerStore ??
        ComposerStore(drafts: widget.drafts, viewStates: widget.viewStates);
    _settingsController = widget.settingsController ??
        RemoteSettingsController(
            session: widget.session,
            scopeKey: '${widget.deviceId}|${widget.workspaceKey}');
    _ownsSettingsController = widget.settingsController == null;
    _settingsController.addListener(_onSettingsChanged);
    // Refresh is coalesced by the shared controller, so main/side panes do
    // not issue duplicate setting reads after the shell creates both views.
    _refreshSettingsAfterFrame(_settingsController);
    _composer = _composerStore.obtain(
        transport: _transport,
        deviceId: widget.deviceId,
        workspaceKey: widget.workspaceKey,
        sessionId: widget.sessionId);
    _liveSessionId = _composer.sessionId ?? '';
    _composer.addListener(_onComposerChanged);
    _loadComposerOptionsAfterFrame(_composer);
    _subscribe();
  }

  @override
  void dispose() {
    _history?.removeListener(_onHistory);
    _history?.dispose();
    _sub?.state.removeListener(_onState);
    _sub?.dispose();
    _composer.removeListener(_onComposerChanged);
    _settingsController.removeListener(_onSettingsChanged);
    if (_ownsSettingsController) _settingsController.dispose();
    _interactions?.dispose();
    _interactions = null;
    _workspaceHookReview?.dispose();
    _workspaceHookReview = null;
    _backgroundWorks?.dispose();
    _backgroundWorks = null;
    _searchHighlightTimer?.cancel();
    _searchHighlightTimer = null;
    _composer.unbind(_state);
    if (widget.composerStore == null) _composerStore.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    final sid = widget.sessionId;
    if (sid == oldWidget.sessionId) {
      if (widget.searchQuery != oldWidget.searchQuery ||
          widget.searchSnippet != oldWidget.searchSnippet ||
          widget.searchSnippetIndex != oldWidget.searchSnippetIndex ||
          widget.searchRequestId != oldWidget.searchRequestId) {
        final requestId = ++_searchRequestId;
        final state = _state;
        if (state != null) {
          unawaited(_locateSearchSnippet(state, requestId));
        }
      }
      return;
    }
    _forkGeneration++;
    _subscriptionRequest++;
    _searchRequestId++;
    _forkingRowId = null;
    _activeSessionOverride = null;
    _sub?.state.removeListener(_onState);
    final oldSubscription = _sub;
    final oldState = _state;
    _sub = null;
    _state = null;
    _composer.removeListener(_onComposerChanged);
    _composer.unbind(oldState);
    _interactions?.dispose();
    _interactions = null;
    _workspaceHookReview?.dispose();
    _workspaceHookReview = null;
    _backgroundWorks?.dispose();
    _backgroundWorks = null;
    _history?.removeListener(_onHistory);
    _history?.dispose();
    _history = null;
    if (oldSubscription != null) unawaited(oldSubscription.dispose());
    _liveSessionId = sid ?? '';
    _view =
        widget.viewStates?.putIfAbsent(_draftKey, ConversationViewState.new) ??
            ConversationViewState();
    _composer = _composerStore.obtain(
        transport: _transport,
        deviceId: widget.deviceId,
        workspaceKey: widget.workspaceKey,
        sessionId: sid);
    _composer.addListener(_onComposerChanged);
    _loadComposerOptionsAfterFrame(_composer);
    if (sid == null) {
      _composer.unbind(null);
      setState(() => _connecting = false);
    } else {
      unawaited(_subscribe());
    }
  }

  Future<void> _subscribe() async {
    if (!mounted) return;
    final request = ++_subscriptionRequest;
    if (_subscribing) return;
    if (_error != null) {
      // 重试进行中要有可见反馈，不能让按钮看起来像没有响应。
      setState(() => _retrying = true);
    }
    final sid = _sessionId;
    if (sid.isEmpty) {
      setState(() => _connecting = false);
      return;
    }
    _subscribing = true;
    try {
      final sub = await _transport.subscribe(sid);
      if (!mounted || request != _subscriptionRequest) {
        await sub.dispose();
        return;
      }
      final previous = _sub;
      previous?.state.removeListener(_onState);
      if (previous != null) await previous.dispose();
      if (!mounted || request != _subscriptionRequest) {
        await sub.dispose();
        return;
      }
      _interactions?.dispose();
      _interactions = null;
      _workspaceHookReview?.dispose();
      _workspaceHookReview = null;
      _backgroundWorks?.dispose();
      _backgroundWorks = null;
      _sub = sub;
      _state = sub.state;
      _interactions = InteractionController(
          transport: _transport, sessionId: sid, state: sub.state);
      _workspaceHookReview = WorkspaceHookReviewController(
        transport: _transport,
        sessionId: sid,
        state: sub.state,
        workspaceIdentity:
            widget.scope['workspaceIdentity'] as String? ?? widget.workspaceKey,
      );
      _backgroundWorks = BackgroundWorksController(
        transport: _transport,
        sessionId: sid,
        state: sub.state,
      );
      _history?.removeListener(_onHistory);
      _history?.dispose();
      _history = ConversationHistory(
          transport: _transport, sessionId: sid, state: sub.state, view: _view)
        ..addListener(_onHistory);
      _composer.bind(sub.state);
      unawaited(_locateSearchSnippet(sub.state, ++_searchRequestId));
      sub.state.addListener(_onState);
      setState(() {
        _connecting = false;
        _error = null;
      });
      widget.onStateChanged?.call(sub.state);
      unawaited(_history!.restoreReading());
    } catch (e) {
      if (!mounted || request != _subscriptionRequest) return;
      setState(() {
        _connecting = false;
        _error = e.toString();
      });
    } finally {
      if (mounted && _retrying) {
        setState(() => _retrying = false);
      }
      if (request == _subscriptionRequest) {
        _subscribing = false;
      } else {
        _subscribing = false;
        unawaited(_subscribe());
      }
    }
  }

  Future<void> _locateSearchSnippet(
      ConversationState state, int requestId) async {
    if (!_isCurrentSearch(state, requestId)) return;
    _searchHighlightTimer?.cancel();
    _searchHighlightQuery = null;
    _searchTargetRowId = null;
    _searchHighlightAttempts = 0;
    if (mounted && _searchHighlightRects.isNotEmpty) {
      setState(() => _searchHighlightRects = const []);
    }
    final query = normalizeConversationSearchSource(widget.searchQuery ?? '');
    final snippet =
        normalizeConversationSearchSource(widget.searchSnippet ?? '');
    if (query.isEmpty && snippet.isEmpty) return;
    if (!state.ready) {
      _pendingSearchRequestId = requestId;
      return;
    }
    final history = _history;
    if (history == null) {
      _pendingSearchRequestId = requestId;
      return;
    }
    bool matchesRow(Map<String, dynamic> row, String needle) {
      final text = row['text'] ?? row['content'] ?? row['value'];
      return text is String &&
          normalizeConversationSearchSource(text).contains(needle);
    }

    List<Map<String, dynamic>> findMatches(String needle) => state.rows
        .where((row) => needle.isNotEmpty && matchesRow(row, needle))
        .toList();
    // A result snippet is the location token returned by the scoped search
    // source. A broad query such as "flutter" commonly appears in newer
    // rows, so falling back to it before walking history would stop on the
    // wrong turn and make an old result look like the latest conversation.
    final snippetIsAuthoritative = snippet.isNotEmpty;
    var matches = findMatches(snippetIsAuthoritative ? snippet : query);
    var snippetMatched = snippetIsAuthoritative && matches.isNotEmpty;
    final searchEpoch = state.logEpoch;
    var attempts = 0;
    if (!_canLoadSearchHistory(state) && matches.isEmpty) {
      _pendingSearchRequestId = requestId;
      return;
    }
    final maxRows = state.totalCount <= 0
        ? _searchRowBudget
        : state.totalCount.clamp(0, _searchRowBudget);
    while (matches.isEmpty &&
        _canLoadSearchHistory(state) &&
        state.canLoadOlder &&
        state.rows.length < maxRows &&
        attempts < _searchPageBudget &&
        _isCurrentSearch(state, requestId)) {
      HistoryPageResult result;
      try {
        result = await history.loadOlder(limit: _searchPageSize);
      } catch (_) {
        if (!mounted ||
            requestId != _searchRequestId ||
            !identical(_state, state)) {
          return;
        }
        _toast(uiText(context, '历史加载失败，请重试',
            'Could not load older messages. Try again.'));
        return;
      }
      if (!_isCurrentSearch(state, requestId)) return;
      // A snapshot or delta can replace the log while rowsRange is in flight.
      // Do not toast against the old projection; retry from its new cursor.
      if (state.logEpoch != searchEpoch) {
        _deferSearch(state, requestId);
        return;
      }
      if (result == HistoryPageResult.stale) {
        if (!mounted ||
            requestId != _searchRequestId ||
            !identical(_state, state)) {
          return;
        }
        _toast(uiText(context, '历史记录已变化，请重试',
            'History changed. Try again.'));
        return;
      }
      if (result != HistoryPageResult.applied) break;
      attempts++;
      matches = findMatches(snippetIsAuthoritative ? snippet : query);
      snippetMatched = snippetIsAuthoritative && matches.isNotEmpty;
    }
    if (!mounted || requestId != _searchRequestId || !identical(_state, state)) {
      return;
    }
    if (matches.isEmpty) {
      _toast(uiText(context, '未找到搜索片段', 'Search result was not found'));
      return;
    }
    final index = snippetMatched
        ? 0
        : (widget.searchSnippetIndex ?? 0).clamp(0, matches.length - 1);
    final rowId = matches[index]['rowId'];
    if (rowId != null) {
      final targetRowId = rowId is num ? rowId.toInt() : null;
      final containingGroup = targetRowId == null
          ? null
          : conversationTurnGroups(state.rows)
              .where((group) => group.any((row) =>
                  (row['rowId'] as num?)?.toInt() == targetRowId))
              .firstOrNull;
      final anchorRowId = containingGroup?.first['rowId'] ?? rowId;
      final anchorRowIdInt = anchorRowId is num ? anchorRowId.toInt() : null;
      if (mounted) {
        setState(() {
          _searchTargetRowId = targetRowId;
          _view.anchor = '$anchorRowId';
          _view.anchorOffset = 0;
          _view.following = false;
          if (anchorRowIdInt != null) {
            _view.expandedTurns[anchorRowIdInt] = true;
          }
          _searchHighlightQuery = widget.searchQuery?.trim();
        });
      }
      unawaited(_history?.restoreSearchAnchor());
      _scheduleSearchHighlight();
    }
  }

  bool _isCurrentSearch(ConversationState state, int requestId) =>
      mounted && requestId == _searchRequestId && identical(_state, state);

  bool _canLoadSearchHistory(ConversationState state) {
    final phase = state.control?['phase'];
    return phase != 'running' && phase != 'prewarming';
  }

  void _deferSearch(ConversationState state, int requestId) {
    if (!_isCurrentSearch(state, requestId)) return;
    _pendingSearchRequestId = requestId;
    if (!state.ready || !_canLoadSearchHistory(state)) return;
    // The state listener may have run before applyHistoryPage reported stale.
    // Give it one microtask to retry against the current epoch/cursor without
    // allowing two locators for the same request to run concurrently.
    scheduleMicrotask(() {
      if (!_isCurrentSearch(state, requestId) ||
          _pendingSearchRequestId != requestId) {
        return;
      }
      _pendingSearchRequestId = null;
      unawaited(_locateSearchSnippet(state, requestId));
    });
  }

  void _scheduleSearchHighlight() {
    _searchHighlightTimer?.cancel();
    _searchHighlightAttempts++;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _searchHighlightQuery?.isEmpty != false) return;
      final root = _conversationRoot.currentContext?.findRenderObject();
      if (root is! RenderBox || !root.hasSize) return;
      final rects = <Rect>[];
      final targetRootObject =
          _searchTargetKey.currentContext?.findRenderObject();
      final targetRoot =
          targetRootObject is RenderBox && targetRootObject.hasSize
              ? targetRootObject
              : null;
      if (targetRootObject == null || targetRoot == null) {
        if (_searchHighlightAttempts < 10) {
          _searchHighlightTimer = Timer(const Duration(milliseconds: 40), () {
            if (mounted && _searchHighlightQuery?.isNotEmpty == true) {
              _scheduleSearchHighlight();
            }
          });
        }
        return;
      }
      final targetOrigin = targetRoot.localToGlobal(Offset.zero);
      final rootOrigin = root.localToGlobal(Offset.zero);
      void visit(RenderObject object) {
        if (object is RenderParagraph) {
          final source = object.text.toPlainText();
          final query = _searchHighlightQuery!.toLowerCase();
          final pattern = RegExp(RegExp.escape(query).replaceAll(r'\ ', r'\s+'),
              caseSensitive: false);
          final match = pattern.firstMatch(source);
          if (match != null) {
            final start = match.start;
            final boxes = object.getBoxesForSelection(
                TextSelection(baseOffset: start, extentOffset: match.end));
            final origin = object.localToGlobal(Offset.zero);
            for (final box in boxes) {
              rects.add(box.toRect().shift(origin - targetOrigin));
            }
          }
        }
        object.visitChildren(visit);
      }

      visit(targetRootObject);
      if (rects.isEmpty && _searchHighlightAttempts < 10) {
        _searchHighlightTimer = Timer(const Duration(milliseconds: 40), () {
          if (mounted && _searchHighlightQuery?.isNotEmpty == true) {
            _scheduleSearchHighlight();
          }
        });
        return;
      }
      if (rects.isEmpty) return;
      final targetOffset = targetOrigin - rootOrigin;
      final viewportRects = [
        for (final rect in rects) rect.shift(targetOffset),
      ];
      final outsideViewport = viewportRects.any((rect) =>
          rect.top < 0 || rect.bottom > root.size.height || rect.left < 0);
      if (outsideViewport) {
        // Search anchors a rendered turn, but a long user bubble can place the
        // matched assistant paragraph below the viewport. Adjust the existing
        // group offset by the target's movement delta and let
        // ConversationViewport perform the one scroll restoration.
        final target = viewportRects.first;
        final desiredTop =
            (root.size.height * .28).clamp(0.0, 120.0).toDouble();
        final delta = target.top - desiredTop;
        final groupRoot =
            _searchTargetGroupKey.currentContext?.findRenderObject();
        if (groupRoot is RenderBox && groupRoot.hasSize) {
          final rootOrigin = root.localToGlobal(Offset.zero);
          final groupOrigin = groupRoot.localToGlobal(Offset.zero);
          final actualGroupTop = groupOrigin.dy - rootOrigin.dy;
          final nextAnchorOffset = actualGroupTop - delta;
          if ((nextAnchorOffset - _view.anchorOffset).abs() > 1) {
            _view.anchorOffset = nextAnchorOffset;
          }
          if (mounted) setState(() {});
        }
        if (_searchHighlightAttempts < 10) {
          _searchHighlightTimer = Timer(const Duration(milliseconds: 40), () {
            if (mounted && _searchHighlightQuery?.isNotEmpty == true) {
              _scheduleSearchHighlight();
            }
          });
        }
        return;
      }
      if (!mounted) return;
      setState(() => _searchHighlightRects = rects);
      _searchHighlightTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _searchHighlightRects = const []);
      });
    });
  }

  void _editMessage(Map<String, dynamic> row) {
    final rowId = (row['rowId'] as num?)?.toInt();
    if (rowId == null) return;
    setState(() {
      _editingRowId = _editingRowId == rowId ? null : rowId;
      _editFailure = null;
    });
  }

  /// Official `editUserQuery` flow: the edited text replaces the turn's user
  /// query in place and the assistant regenerates its most recent response,
  /// so the old answer is superseded server-side (no client-side truncation).
  Future<void> _submitMessageEdit(Map<String, dynamic> row, String newText) =>
      _submitEdit(
          rowId: (row['rowId'] as num?)?.toInt(),
          entityId: row['entityId'],
          newText: newText);

  Future<void> _submitEdit({
    required int? rowId,
    required dynamic entityId,
    required String newText,
  }) async {
    final trimmed = newText.trim();
    final targetRowId = rowId;
    final targetEntityId = entityId;
    final sessionId = _sessionId;
    if (trimmed.isEmpty ||
        targetRowId == null ||
        targetEntityId == null ||
        sessionId.isEmpty) {
      return;
    }
    final generation = ++_editGeneration;
    final target = {'rowId': targetRowId, 'entityId': targetEntityId};
    setState(() {
      _editingRowId = targetRowId;
      _editFailure = null;
    });
    try {
      final response =
          await _transport.editUserQuery(sessionId, target, trimmed);
      if (!mounted || generation != _editGeneration) return;
      final map = response is Map ? response : null;
      final status = map?['status'];
      if (status != 'accepted' && status != 'duplicate') {
        setState(() {
          _editFailure =
              uiText(context, '编辑重发失败，请重试', 'Edit failed. Try again.');
        });
        return;
      }
      setState(() {
        _editingRowId = null;
        _editFailure = null;
      });
    } catch (_) {
      if (!mounted || generation != _editGeneration) return;
      setState(() {
        _editFailure =
            uiText(context, '编辑重发失败，请重试', 'Edit failed. Try again.');
      });
    }
  }

  /// Official kX feedback flow: optimistic reaction, `setAssistantFeedback`
  /// persist, rollback to the previous reaction on failure (official w()).
  Future<void> _sendFeedback(Map<String, dynamic> row, String? reaction) async {
    final rowId = (row['rowId'] as num?)?.toInt();
    final entityId = row['entityId'];
    if (rowId == null || entityId == null) return;
    final sessionId = _sessionId;
    final generation = ++_feedbackGeneration;
    final previous = _feedbackByRowId[rowId] ??
        (row['feedback'] is String ? row['feedback'] as String : null);
    final next = previous == reaction ? null : reaction;
    setState(() => _feedbackByRowId[rowId] = next);
    try {
      await _transport.setAssistantFeedback(
          sessionId, {'rowId': rowId, 'entityId': entityId}, next);
      if (!mounted || generation != _feedbackGeneration) return;
    } catch (_) {
      if (!mounted || generation != _feedbackGeneration) {
        return;
      }
      setState(() => _feedbackByRowId[rowId] = previous);
      _toast(uiText(context, '反馈保存失败', 'Failed to save feedback'));
    }
  }

  Future<void> _forkMessage(Map<String, dynamic> row) async {
    final rowId = (row['rowId'] as num?)?.toInt();
    final entityId = row['entityId'];
    if (rowId == null || entityId == null) return;
    if (_forkingRowId == rowId) return;
    final generation = ++_forkGeneration;
    final sessionId = _sessionId;
    final target = {'rowId': rowId, 'entityId': entityId};
    setState(() => _forkingRowId = rowId);
    try {
      final response = await _transport.forkAssistant(sessionId, target);
      if (!mounted || generation != _forkGeneration) return;
      final map = response is Map ? response : null;
      final status = map?['status'];
      if (status != 'accepted' && status != 'duplicate') {
        _toast(uiText(context, 'Fork 失败，请重试', 'Fork failed. Try again.'));
        return;
      }
      final result = map?['result'];
      final newSessionId =
          result is Map ? result['sessionId'] as String? : null;
      if (newSessionId == null || newSessionId == sessionId) return;
      _forkGeneration++;
      _forkingRowId = null;
      _activeSessionOverride = newSessionId;
      _liveSessionId = newSessionId;
      _view = widget.viewStates
              ?.putIfAbsent(_draftKey, ConversationViewState.new) ??
          ConversationViewState();
      _composer.removeListener(_onComposerChanged);
      _composer.unbind(_state);
      _composer = _composerStore.obtain(
          transport: _transport,
          deviceId: widget.deviceId,
          workspaceKey: widget.workspaceKey,
          sessionId: newSessionId);
      _composer.addListener(_onComposerChanged);
      _loadComposerOptionsAfterFrame(_composer);
      widget.onSessionCreated?.call(newSessionId);
      setState(() {});
      unawaited(_subscribe());
    } catch (_) {
      if (!mounted || generation != _forkGeneration) return;
      _toast(uiText(context, 'Fork 失败，请重试', 'Fork failed. Try again.'));
    } finally {
      if (mounted && generation == _forkGeneration) {
        setState(() => _forkingRowId = null);
      }
    }
  }

  void _onState() {
    if (mounted) {
      setState(() {});
      if (_state != null) widget.onStateChanged?.call(_state!);
      final pending = _pendingSearchRequestId;
      final state = _state;
      if (pending != null &&
          state != null &&
          state.ready &&
          pending == _searchRequestId &&
          _canLoadSearchHistory(state)) {
        _pendingSearchRequestId = null;
        unawaited(_locateSearchSnippet(state, pending));
      }
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

  void _onSettingsChanged() {
    if (mounted) setState(() {});
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
    chatPageBuildCount++;
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
      body: Stack(
        children: [
          Column(
            children: [
              ConnectionStatusBanner(
                session: widget.deviceSession,
                bridge: widget.session,
                onReconnect: widget.deviceSession?.reconnect,
                onPairAgain: widget.onPairAgain,
                onCancel: widget.deviceSession?.cancelRecovery,
              ),
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
              ComposerBar(
                  controller: _composer, onManageModels: widget.onOpenModels),
            ],
          ),
          if (_interactions != null)
            InteractionRequestCard(controller: _interactions!),
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
            _RetryButton(onRetry: _subscribe, busy: _retrying),
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
    final groups = conversationTurnGroups(rows);
    final lastIndex = groups.length - 1;
    // P2-conv: `singleTurn` is a pure function of `state.rows` but every
    // _TurnGroup previously rescanned ALL rows for it — O(groups × rows) per
    // build. Rows cannot change mid-build, so compute it once here.
    final singleTurn = rows
            .where((r) => r['kind'] == 'userInput' || r['kind'] == 'turnHeader')
            .length <=
        1;
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
      if (_backgroundWorks != null)
        BackgroundWorksBanner(controller: _backgroundWorks!),
      if (_workspaceHookReview != null)
        WorkspaceHookReviewBanner(
          controller: _workspaceHookReview!,
          onOpenHooks: widget.onOpenHooks,
        ),
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
          child: Stack(
        key: _conversationRoot,
        fit: StackFit.expand,
        children: [
          ConversationViewport(
            view: _view,
            ids: [for (final group in groups) '${group.first['rowId']}'],
            onLoadOlder: _state?.canLoadOlder == true ? _loadOlder : null,
            loadingOlder: history?.loading ?? false,
            itemBuilder: (context, i) {
              final group = groups[i];
              final hasSearchTarget = _searchTargetRowId != null &&
                  group.any((row) => row['rowId'] == _searchTargetRowId);
              return _TurnGroup(
                key: hasSearchTarget ? _searchTargetGroupKey : null,
                rows: group,
                transport: _transport,
                sessionId: _sessionId,
                deviceId: widget.deviceId ?? 'local',
                workspaceKey: widget.workspaceKey,
                state: _state!,
                settings: _settingsController.snapshot,
                isSideChat: widget.isSideChat,
                isLastTurn: i == lastIndex,
                singleTurn: singleTurn,
                expandedOverride:
                    _view.expandedTurns[group.first['rowId'] as int?],
                searchTargetKey:
                    hasSearchTarget ? _searchTargetKey : null,
                searchTargetRowId: _searchTargetRowId,
                searchHighlightLink:
                    hasSearchTarget ? _searchHighlightLink : null,
                onToggleExpanded: (v) {
                  final key = group.first['rowId'] as int?;
                  if (key != null) setState(() => _view.expandedTurns[key] = v);
                },
                onEdit: widget.isSideChat
                    ? null
                    : (row) => _editMessage(row),
                onSubmitEdit:
                    widget.isSideChat ? null : _submitMessageEdit,
                editingRowId: widget.isSideChat ? null : _editingRowId,
                editFailure: widget.isSideChat ? null : _editFailure,
                onFork: widget.isSideChat ? null : _forkMessage,
                forkingRowId: widget.isSideChat ? null : _forkingRowId,
                feedbackFor: (rowId) => _feedbackByRowId[rowId],
                onFeedback: widget.isSideChat ? null : _sendFeedback,
              );
            },
          ),
          if (_searchHighlightRects.isNotEmpty)
            IgnorePointer(
                child: ClipRect(
                    child: CompositedTransformFollower(
                        link: _searchHighlightLink,
                        showWhenUnlinked: false,
                        child: CustomPaint(
                            key: const ValueKey('search-highlight-overlay'),
                            painter: SearchHighlightPainter(
                                _searchHighlightRects,
                                ZInk.of(Theme.of(context).colorScheme).hover))))),
        ],
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
    return LayoutBuilder(builder: (context, constraints) {
      final minHeight =
          constraints.hasBoundedHeight ? constraints.maxHeight : 0.0;
      return SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minWidth: constraints.maxWidth, minHeight: minHeight),
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
    });
  }
}

class _RetryButton extends StatelessWidget {
  const _RetryButton({required this.onRetry, this.busy = false});

  final VoidCallback onRetry;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ZInk.running.withValues(alpha: 0.9),
      borderRadius: BorderRadius.circular(ZRadius.lg),
      child: InkWell(
        onTap: busy ? null : onRetry,
        borderRadius: BorderRadius.circular(ZRadius.lg),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          child: busy
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : const Text(
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
  final String deviceId;
  final String workspaceKey;
  final ConversationState state;
  final RemoteSettingsSnapshot? settings;
  final bool isSideChat;
  final bool isLastTurn;
  /// Whether the whole conversation holds at most one user turn. Computed
  /// once per build in `_buildChat` (pure function of `state.rows`);
  /// per-group recomputation was an O(rows) scan per turn.
  final bool singleTurn;
  final bool? expandedOverride;
  final GlobalKey? searchTargetKey;
  final int? searchTargetRowId;
  final LayerLink? searchHighlightLink;
  final ValueChanged<bool>? onToggleExpanded;
  final ValueChanged<Map<String, dynamic>>? onEdit;
  final Future<void> Function(Map<String, dynamic> row, String newText)?
      onSubmitEdit;
  final int? editingRowId;
  final String? editFailure;
  final Future<void> Function(Map<String, dynamic> row)? onFork;
  final int? forkingRowId;
  final String? Function(int? rowId)? feedbackFor;
  final Future<void> Function(Map<String, dynamic> row, String? reaction)?
      onFeedback;

  const _TurnGroup({
    super.key,
    required this.rows,
    required this.transport,
    required this.sessionId,
    required this.deviceId,
    required this.workspaceKey,
    required this.state,
    this.settings,
    this.isSideChat = false,
    required this.isLastTurn,
    required this.singleTurn,
    this.expandedOverride,
    this.searchTargetKey,
    this.searchTargetRowId,
    this.searchHighlightLink,
    this.onToggleExpanded,
    this.onEdit,
    this.onSubmitEdit,
    this.editingRowId,
    this.editFailure,
    this.onFork,
    this.forkingRowId,
    this.feedbackFor,
    this.onFeedback,
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
    final running = assistantRows.any(rowIsActive);
    final header = assistantRows.lastWhere(
      (r) => r['kind'] == 'turnHeader',
      orElse: () => const {},
    );
    final officialFileChanges = turnFileChangeStats(header);
    final hasOfficialFileChanges = header['fileChanges'] is Map;
    final hasAssistantText =
        assistantRows.any((r) => r['kind'] == 'assistantText');
    final hasSearchTarget = searchTargetRowId != null &&
        rows.any((row) => row['rowId'] == searchTargetRowId);
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
          _UserBubble(
            key: userRows[i]['rowId'] == searchTargetRowId
                ? searchTargetKey
                : null,
            row: userRows[i],
            searchHighlightLink: userRows[i]['rowId'] == searchTargetRowId
                ? searchHighlightLink
                : null,
            onEdit: onEdit != null ? (row) => onEdit!(row) : null,
            onSubmitEdit: onSubmitEdit,
            editing: editingRowId != null &&
                userRows[i]['rowId'] == editingRowId,
            editFailure:
                editingRowId != null && userRows[i]['rowId'] == editingRowId
                    ? editFailure
                    : null,
            readAttachment: (ref) async =>
                (await transport.attachmentRead(sessionId, ref: ref)).bytes,
          ),
        ],
        if (assistantRows.isNotEmpty) ...[
          if (userRows.isNotEmpty) const SizedBox(height: 20),
          if (showTurnHeader) ...[
            _TurnTrigger(
              key: hasSearchTarget
                  ? const ValueKey('search-target-turn-trigger')
                  : null,
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
                    ? _assistantBody(context, assistantRows,
                        hideLegacyChangeSummary: hasOfficialFileChanges)
                    : _collapsedBody(context, assistantRows),
              ),
            ),
            if (officialFileChanges != null && officialFileChanges.files > 0)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: ConversationChangeSummary(
                  key: ValueKey('turn-file-changes-${header['rowId']}'),
                  row: header,
                  reviewCacheVersion:
                      '${state.logEpoch}|${header['state']}|${header['fileChanges']}',
                  createReview: _createReview,
                  onOpenReview: _reviewOpener(context, header),
                ),
              ),
          ] else
            ..._assistantBody(context, assistantRows),
        ],
      ],
    );
  }

  List<Widget> _assistantBody(
      BuildContext context, List<Map<String, dynamic>> rows,
      {bool hideLegacyChangeSummary = false}) {
    final visibleRows = runtimeVisibleAssistantRows(rows, settings)
        .where((row) =>
            row['kind'] != 'turnHeader' &&
            !(hideLegacyChangeSummary && row['kind'] == 'changeSummary'))
        .toList();
    final latestAssistantRowId = visibleRows.lastWhere(
        (row) => row['kind'] == 'assistantText',
        orElse: () => const {})['rowId'];
    // 折叠触发行已在外面渲染，这里渲染其后的真实内容（含 turnHeader
    // 本身已并入触发行，跳过重复）。
    final result = <Widget>[];
    var index = 0;
    while (index < visibleRows.length) {
      final first = visibleRows[index];
      final family = runtimeToolGroupingFamily(first,
          groupExplore: settings?.groupExplore ?? true,
          groupTerminal: settings?.groupTerminal ?? true,
          groupChanges: settings?.groupChanges ?? false);
      final grouped = <Map<String, dynamic>>[first];
      if (family != null) {
        while (index + grouped.length < visibleRows.length) {
          final candidate = visibleRows[index + grouped.length];
          if (candidate['kind'] == 'turnHeader' ||
              runtimeToolGroupingFamily(candidate,
                      groupExplore: settings?.groupExplore ?? true,
                      groupTerminal: settings?.groupTerminal ?? true,
                      groupChanges: settings?.groupChanges ?? false) !=
                  family) {
            break;
          }
          grouped.add(candidate);
        }
      }
      index += grouped.length;
      final children = [
        for (final row in grouped)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: _rowWidget(
              context,
              row,
              searchTargetKey: row['rowId'] == searchTargetRowId
                  ? searchTargetKey
                  : null,
              searchHighlightLink: row['rowId'] == searchTargetRowId
                  ? searchHighlightLink
                  : null,
              isLatestAssistantText: latestAssistantRowId != null &&
                  row['rowId'] == latestAssistantRowId,
            ),
          ),
      ];
      if (family != null && grouped.length > 1) {
        result.add(Padding(
          padding: const EdgeInsets.only(top: 8),
          child: ToolGroupRow(
              key: ValueKey('tool-group-${first['rowId']}'),
              family: family,
              rowId: first['rowId'] as int? ?? 0,
              children: children),
        ));
      } else {
        result.add(children.single);
      }
    }
    return result;
  }

  FileChangesReviewController _createReview(Map<String, dynamic> target) {
    return FileChangesReviewController(
      transport: transport,
      scope: FileChangesScope(
        deviceId: deviceId,
        workspaceKey: workspaceKey,
        sessionId: sessionId,
        rowId: target['rowId'] as int? ?? 0,
        entityId: target['entityId'],
      ),
      revision: () => state.revision,
      logEpoch: () => state.logEpoch,
    );
  }

  void Function(String path)? _reviewOpener(
      BuildContext context, Map<String, dynamic> target) {
    final host = FileChangesReviewHost.maybeOf(context);
    return host == null ? null : (path) => host.openReview(target, path);
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
        child: _rowWidget(
          context,
          rows[lastTextIdx],
          searchTargetKey: rows[lastTextIdx]['rowId'] == searchTargetRowId
              ? searchTargetKey
              : null,
          searchHighlightLink:
              rows[lastTextIdx]['rowId'] == searchTargetRowId
                  ? searchHighlightLink
                  : null,
          isLatestAssistantText: true,
        ),
      ),
    ];
  }

  Widget _rowWidget(BuildContext context, Map<String, dynamic> row,
      {GlobalKey? searchTargetKey,
      LayerLink? searchHighlightLink,
      bool isLatestAssistantText = false}) {
    return switch (row['kind']) {
      'assistantText' => _AssistantText(
          key: searchTargetKey,
          searchHighlightLink: searchHighlightLink,
          row: row,
          onFork: isLatestAssistantText &&
                  row['state'] == 'complete' &&
                  row['entityId'] != null &&
                  row['actions'] is Map &&
                  (row['actions'] as Map)['canFork'] == true &&
                  onFork != null &&
                  forkingRowId != (row['rowId'] as num?)?.toInt()
              ? () => onFork!(row)
              : null,
          forkPending: forkingRowId == (row['rowId'] as num?)?.toInt(),
          feedback: row['entityId'] != null
              ? (feedbackFor?.call((row['rowId'] as num?)?.toInt()) ??
                  (row['feedback'] is String
                      ? row['feedback'] as String
                      : null))
              : null,
          onFeedback: row['entityId'] != null &&
                  row['state'] == 'complete' &&
                  isLatestAssistantText &&
                  onFeedback != null
              ? (reaction) => onFeedback!(row, reaction)
              : null,
          showActions: isLatestAssistantText && row['state'] == 'complete',
        ),
      'reasoning' => ReasoningRow(key: ValueKey(row['rowId']), row: row),
      'toolCall' => ToolCallRow(key: ValueKey(row['rowId']), row: row),
      'changeSummary' => ConversationChangeSummary(
          row: row,
          reviewCacheVersion:
              '${state.logEpoch}|${row['state']}|${row['fileChanges']}',
          createReview: _createReview,
          onOpenReview: _reviewOpener(context, row),
        ),
      'subagent' => _SubagentRow(row: row),
      // Official `goal_verification` synthetic separator row (rule 24
      // implementation; official visual sample pending live stream).
      // Wire shape may be flattened (`kind: goal_verification`) or raw
      // schema (`kind: synthetic` + `type: goal_verification`).
      'goal_verification' when isSideChat => const SizedBox.shrink(),
      'goal_verification' =>
          GoalVerificationRow(key: ValueKey(row['rowId']), row: row),
      _ when isSideChat && GoalVerificationRow.isGoalVerification(row) =>
        const SizedBox.shrink(),
      _ when GoalVerificationRow.isGoalVerification(row) =>
          GoalVerificationRow(key: ValueKey(row['rowId']), row: row),
      _ => const SizedBox.shrink(),
    };
  }
}

String _conversationUiText(
    BuildContext context, String chinese, String english) {
  // Standalone summary widgets historically default to Chinese in focused
  // tests; the product tree supplies ClientPreferencesScope and gets the
  // selected locale through uiText.
  if (ClientPreferencesScope.maybeOf(context) == null) return chinese;
  return uiText(context, chinese, english);
}

/// 官方 turn 触发行（PX/§1）：`border-b border-border/50` subtle 文字 +
/// chevron（闭合朝右、展开转 90° 朝下）。
class _TurnTrigger extends StatelessWidget {
  final Map<String, dynamic> header;
  final bool running;
  final bool expanded;
  final VoidCallback onToggle;

  const _TurnTrigger({
    super.key,
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
    final label = _conversationUiText(
        context,
        turnWorkLabel(state: st, durationMs: ms),
        turnWorkLabelEnglish(state: st, durationMs: ms));
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
class SearchHighlightPainter extends CustomPainter {
  const SearchHighlightPainter(this.rects, this.color);

  final List<Rect> rects;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color.withValues(alpha: .32);
    for (final rect in rects) {
      canvas.drawRRect(
          RRect.fromRectAndRadius(rect, const Radius.circular(3)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant SearchHighlightPainter oldDelegate) =>
      oldDelegate.rects != rects || oldDelegate.color != color;
}

class _UserBubble extends StatefulWidget {
  final Map<String, dynamic> row;
  final ValueChanged<Map<String, dynamic>>? onEdit;
  final Future<void> Function(Map<String, dynamic> row, String newText)?
      onSubmitEdit;
  final bool editing;
  final String? editFailure;
  final Future<Uint8List> Function(String ref)? readAttachment;
  final LayerLink? searchHighlightLink;

  const _UserBubble({
    super.key,
    required this.row,
    this.onEdit,
    this.onSubmitEdit,
    this.editing = false,
    this.editFailure,
    this.readAttachment,
    this.searchHighlightLink,
  });

  @override
  State<_UserBubble> createState() => _UserBubbleState();
}

class _UserBubbleState extends State<_UserBubble> {
  TextEditingController? _editController;
  final _editFocus = FocusNode();

  @override
  void dispose() {
    _editController?.dispose();
    _editFocus.dispose();
    super.dispose();
  }

  void _beginEdit(String text) {
    setState(() {
      _editController?.dispose();
      _editController = TextEditingController(text: text)
        ..selection = TextSelection(
            baseOffset: text.length, extentOffset: text.length);
    });
    widget.onEdit?.call(widget.row);
    // Focus after the field mounts this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _editFocus.requestFocus();
    });
  }

  void _cancelEdit() {
    setState(() {
      _editController?.dispose();
      _editController = null;
    });
    _editFocus.unfocus();
  }

  Future<void> _submitEdit() async {
    final controller = _editController;
    final text = controller?.text ?? '';
    if (text.trim().isEmpty) return;
    _editFocus.unfocus();
    await widget.onSubmitEdit?.call(widget.row, text);
    if (mounted && widget.editing == false) {
      setState(() {
        _editController?.dispose();
        _editController = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final text = widget.row['text'] as String? ?? '';
    final attachments = switch (widget.row['attachments']) {
      final List items => items
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false),
      _ => const <Map<String, dynamic>>[],
    };
    final editing = widget.editing && _editController != null;

    // Official user bubble: a bordered rounded container around the message,
    // not bare text. While editing, the same container hosts an in-place
    // TextField so the message never jumps to the composer.
    final Widget content = Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: editing ? ink.background : ink.messageSurface,
          border: Border.all(
              color: editing ? ink.text : ink.messageBorder,
              width: editing ? 1.4 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (attachments.isNotEmpty && !editing) ...[
              SentAttachmentPills(
                  attachments: attachments,
                  readAttachment: widget.readAttachment),
              const SizedBox(height: 8),
            ],
            if (editing)
              TextField(
                controller: _editController,
                focusNode: _editFocus,
                maxLines: null,
                minLines: 1,
                style: TextStyle(fontSize: 14, height: 1.5, color: ink.text),
                decoration: const InputDecoration(
                    isDense: true, border: InputBorder.none),
                textInputAction: TextInputAction.newline,
              )
            else if (text.isNotEmpty)
              SelectableText(
                text,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.5,
                  color: ink.text,
                ),
              ),
            if (widget.editFailure != null && editing) ...[
              const SizedBox(height: 6),
              Text(widget.editFailure!,
                  style: TextStyle(
                      fontSize: 12, color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: editing
                  ? MainAxisAlignment.start
                  : MainAxisAlignment.end,
              children: [
                if (editing) ...[
                  TextButton.icon(
                    onPressed: _submitEdit,
                    icon: const Icon(Icons.send, size: 14),
                    label: Text(
                        uiText(context, '重新发送', 'Resend'),
                        style: const TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 30)),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: _cancelEdit,
                    style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        minimumSize: const Size(0, 30)),
                    child: Text(uiText(context, '取消', 'Cancel'),
                        style: const TextStyle(fontSize: 12)),
                  ),
                ] else
                  _MessageActions(
                    text: text,
                    onEdit: widget.row['entityId'] != null &&
                            widget.onEdit != null &&
                            widget.onSubmitEdit != null
                        ? () => _beginEdit(text)
                        : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
    final link = widget.searchHighlightLink;
    return link == null
        ? content
        : CompositedTransformTarget(link: link, child: content);
  }
}

/// Per-message action row: copy and optionally edit for user messages.
/// Official evidence: user rows show copy + edit (edit requires entityId);
/// assistant rows show copy; feedback (like/dislike) is hidden in remote
/// control (compactForRemoteControl voids callback, official JS ~2182314).
class _MessageActions extends StatelessWidget {
  final String text;
  final VoidCallback? onEdit;
  final VoidCallback? onFork;
  final bool forkPending;
  final String? feedback;
  final ValueChanged<String?>? onFeedback;

  const _MessageActions({
    required this.text,
    this.onEdit,
    this.onFork,
    this.forkPending = false,
    this.feedback,
    this.onFeedback,
  });

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              _ActionIcon(
                  icon: Icons.copy_outlined,
                  label: "Copy",
                  ink: ink,
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: text));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text(uiText(context, "已复制", "Copied")),
                          duration: const Duration(seconds: 1)));
                    }
                  }),
              if (onEdit != null)
                _ActionIcon(
                    icon: Icons.edit_outlined,
                    label: "Edit",
                    ink: ink,
                    onTap: onEdit),
              if (onFeedback != null) ...[
                _ActionIcon(
                    icon: feedback == 'like'
                        ? Icons.thumb_up
                        : Icons.thumb_up_alt_outlined,
                    label: feedback == 'like' ? "Liked" : "Like",
                    ink: ink,
                    onTap: () =>
                        onFeedback!(feedback == 'like' ? null : 'like')),
                _ActionIcon(
                    icon: feedback == 'dislike'
                        ? Icons.thumb_down
                        : Icons.thumb_down_alt_outlined,
                    label: feedback == 'dislike' ? "Disliked" : "Dislike",
                    ink: ink,
                    onTap: () =>
                        onFeedback!(feedback == 'dislike' ? null : 'dislike')),
              ],
              if (onFork != null)
                _ActionIcon(
                    icon: Icons.account_tree_outlined,
                    label: "Fork",
                    ink: ink,
                    onTap: forkPending ? null : onFork),
            ]));
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final InkTokens ink;
  final VoidCallback? onTap;

  const _ActionIcon(
      {required this.icon,
      required this.label,
      required this.ink,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    // Compact shells raise the touch target; the glyph keeps its size.
    final compact = MobileLayout.isCompact(
        MediaQuery.sizeOf(context).width -
            MediaQuery.paddingOf(context).horizontal,
        MediaQuery.textScalerOf(context));
    final extent = compact ? 48.0 : 28.0;
    return Tooltip(
        message: label,
        child: SizedBox(
            width: extent,
            height: extent,
            child: IconButton(
                onPressed: onTap,
                icon: Icon(icon, size: 14, color: ink.subtlest),
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                    minWidth: extent, minHeight: extent))));
  }
}

/// Assistant 正文和代码按当前客户端主题及代码字号渲染。
class _AssistantText extends StatelessWidget {
  final Map<String, dynamic> row;
  final VoidCallback? onFork;
  final bool forkPending;
  final bool showActions;
  final String? feedback;
  final ValueChanged<String?>? onFeedback;
  final LayerLink? searchHighlightLink;

  const _AssistantText({
    super.key,
    required this.row,
    this.onFork,
    this.forkPending = false,
    this.showActions = true,
    this.feedback,
    this.onFeedback,
    this.searchHighlightLink,
  });

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final text = row['text'] as String? ?? '';
    final prefs = ClientPreferencesScope.maybeOf(context);
    final codeTheme = CodeThemeCatalog.fromContext(context);
    final codeFontSize = prefs?.codeFontSize ?? 12;
    final showLineNumbers = prefs?.showLineNumbers ?? true;
    final wrapLongLines = prefs?.wrapLongLines ?? false;
    // RenderEditable keeps cached link semantics across accessibility restarts.
    // Text.rich under SelectionArea recreates paragraph semantics correctly and
    // preserves Android selection/copy across this complete Markdown message.
    final content = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SelectionArea(
          child: MarkdownBody(
              data: text,
               styleSheet:
                   MarkdownStyleSheet.fromTheme(Theme.of(context)).copyWith(
                 p: TextStyle(fontSize: 14, height: 1.6, color: ink.text),
                 code: TextStyle(
                     fontFamily: 'monospace',
                    fontSize: codeFontSize,
                    color: codeTheme.foreground,
                    backgroundColor: codeTheme.background),
                 codeblockDecoration: BoxDecoration(
                     color: codeTheme.background,
                     borderRadius: BorderRadius.circular(8)),
                 blockquoteDecoration: BoxDecoration(
                     color: ink.surface,
                     border:
                         Border(left: BorderSide(color: ink.border, width: 2))),
                 tableBorder: TableBorder.all(color: ink.border),
               ),
              builders: {
                'pre': CodeMarkdownBuilder(
                  theme: codeTheme,
                  fontSize: codeFontSize,
                  showLineNumbers: showLineNumbers,
                  wrapLongLines: wrapLongLines,
                ),
              })),
      if (showActions)
        _MessageActions(
          text: text,
          onFork: onFork,
          forkPending: forkPending,
          feedback: feedback,
          onFeedback: onFeedback,
        ),
    ]);
    final link = searchHighlightLink;
    return link == null
        ? content
        : CompositedTransformTarget(link: link, child: content);
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

