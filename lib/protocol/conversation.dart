import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'channel_client.dart';
import 'id.dart';
import 'zemote_client.dart';
import 'conversation_state.dart';
export 'conversation_state.dart';
import 'observable.dart';

/// Conversation V4 protocol over the `zcode-agent` channel.
const conversationProtocolAppVersion = '3.6.5';

///
/// Flow (mirrors `sk()`/`uk()` in the web client):
/// 1. `helloConversationV4()` + `initializeConversationV4(clientHello)`
/// 2. `subscribeConversationV4(scope + sessionId)` -> ack.subscriptionId
/// 3. frames pushed via dynamic event `onDynamicConversationFrame(scope)`:
///    wire frames `{wireVersion:3, kind:'complete'|'fragment', topic,
///    subscriptionId, frame | fragment*}`; complete frames carry
///    `{topic, subscriptionId, fromSeq, toSeq, sentAt, payload}` where payload
///    is `{kind:'snapshot', snapshot}` or `{kind:'deltas', deltas}`.
/// 4. commands via `sendConversationCommandV4(scope + envelope)` with
///    envelope `{commandId, clientId, sessionId, type, payload, issuedAt}`.
class ConversationTransport {
  static const channel = Channels.zcodeAgent;

  final BridgeSession session;
  final Map<String, dynamic> scope;
  final String appVersion;
  final void Function(String line)? onLog;

  final String clientId = generateUuid();
  bool _handshaken = false;
  Future<void>? _handshakeFuture;
  int _handshakeGeneration = 0;
  late final ValueSignal<int> _recoverySignal;

  /// From the server hello — required for attachment uploads.
  String? connectionId;

  ConversationTransport({
    required this.session,
    required this.scope,
    // This is the desktop Conversation protocol capability version, not the
    // Zemote release version. Sending 0.x here can disable V4 capabilities
    // such as sessions-index during server negotiation.
    this.appVersion = conversationProtocolAppVersion,
    this.onLog,
  }) {
    // A reopened bridge has no handshake state — start over (mirrors the
    // web client's `wD` cache being per service instance).
    _recoverySignal = session.recoveryStarting;
    _recoverySignal.addListener(_onBridgeRecovered);
  }

  void _onBridgeRecovered() {
    _handshakeGeneration++;
    _handshaken = false;
    _handshakeFuture = null;
    connectionId = null;
    _prep = null;
    _prepGeneration++;
  }

  ChannelClient get _channels => session.channels;

  void _log(String line) => onLog?.call(line);

  Future<void> handshake() {
    if (_handshaken) return Future.value();
    final pending = _handshakeFuture;
    if (pending != null) return pending;
    final generation = _handshakeGeneration;
    final channels = _channels;
    void checkCurrent() {
      if (generation != _handshakeGeneration ||
          !identical(channels, _channels)) {
        throw StateError('conversation handshake superseded');
      }
    }

    late final Future<void> operation;
    operation = () async {
      final hello = await channels.call(channel, 'helloConversationV4', []);
      checkCurrent();
      await channels.call(channel, 'initializeConversationV4', [
        {
          'kind': 'clientHello',
          'protocolVersion': 3,
          'clientId': clientId,
          'clientKind': 'mobileApp',
          'appVersion': appVersion,
          // Official web declares this capability (gb()); servers may gate
          // workspace hook review payloads on it.
          'capabilities': {'workspaceHookReviewUi': true},
        },
      ]);
      checkCurrent();
      connectionId = hello is Map ? hello['connectionId'] as String? : null;
      _handshaken = true;
      _log('[v4] handshake ready');
    }()
        .whenComplete(() {
      if (identical(_handshakeFuture, operation)) _handshakeFuture = null;
    });
    _handshakeFuture = operation;
    return operation;
  }

  Future<ConversationSubscription> subscribe(String sessionId) async {
    await handshake();
    final subscription = ConversationSubscription._(this, sessionId);
    try {
      await subscription._start();
    } catch (_) {
      await subscription.dispose();
      rethrow;
    }
    _subscriptions[sessionId] = subscription;
    return subscription;
  }

  void _untrackSubscription(String sessionId) {
    _subscriptions.remove(sessionId);
  }

  /// Commands that require `baseRevision` (CAS, mirrors `eAe` in the web
  /// client) and row-target commands that also require `baseLogEpoch`
  /// (mirrors `tAe`).
  static const _casCommands = {
    'applyFileRewind',
    'forkAssistant',
    'editUserQuery',
    'retryTurn',
    'setAssistantFeedback',
    'sendQueuedNow',
    'editQueueItem',
    'reorderQueueItem',
    'deleteQueueItem',
    'setAutoDrain',
    'switchModelConfig',
    'switchCollaborationMode',
    'setFollowupMode',
    'pauseGoal',
    'resumeGoal',
  };
  static const _rowTargetCommands = {
    'applyFileRewind',
    'forkAssistant',
    'editUserQuery',
    'retryTurn',
    'setAssistantFeedback',
  };

  /// Live subscriptions by sessionId — source of the current
  /// revision/logEpoch for CAS commands.
  final _subscriptions = <String, ConversationSubscription>{};
  final _activeSubscriptions = <_SubscriptionBase>{};

  /// subscriptionId 退订失败后按 topic 登记：agent 侧注册可能残留，导致
  /// 同一连接再次订阅该会话时收不到 ack（表现为 subscribe 超时）。
  /// 下次订阅同 topic 前先补发一次退订。
  final _leakedSubscriptionIds = <String, String>{};

  void _trackSubscription(_SubscriptionBase subscription) {
    _activeSubscriptions.add(subscription);
  }

  void _untrackActiveSubscription(_SubscriptionBase subscription) {
    _activeSubscriptions.remove(subscription);
  }

  /// A bridge is only healthy for UI/commands after every live subscription
  /// has completed its post-recovery handshake and subscribe ack.
  Future<void> waitForSubscriptionsHealthy(
      {Duration timeout = const Duration(seconds: 45)}) {
    final waits = [
      for (final subscription
          in List<_SubscriptionBase>.from(_activeSubscriptions))
        subscription._waitForRecovery(),
    ];
    return Future.wait(waits).timeout(timeout);
  }

  /// Highest revision seen from command acks (`revisionAtDecision`) —
  /// acks land before the follow-up `state.updated` frame, and the next
  /// CAS command must not go stale.
  final _ackedRevisions = <String, int>{};

  Future<dynamic> sendCommand(
    String? sessionId,
    String type,
    Map<String, dynamic> payload, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    // Gate on a healthy bridge: during a relay drop/recovery the old bridge
    // is dead and requests would otherwise hang until timeout. Once the
    // bridge recovers, the send goes through on the fresh transport.
    await session.waitHealthy(timeout: const Duration(seconds: 45));
    await handshake();
    final sub = sessionId == null ? null : _subscriptions[sessionId];
    final baseRevision = sessionId == null
        ? null
        : [
            sub?.state.revision ?? 0,
            _ackedRevisions[sessionId] ?? 0,
          ].reduce((a, b) => a > b ? a : b);
    final envelope = {
      'commandId': generateUuid(),
      'clientId': clientId,
      'sessionId': sessionId,
      if (_casCommands.contains(type)) 'baseRevision': baseRevision,
      if (_rowTargetCommands.contains(type) && sub?.state.logEpoch != null)
        'baseLogEpoch': sub!.state.logEpoch,
      'type': type,
      'payload': payload,
      'issuedAt': DateTime.now().millisecondsSinceEpoch,
    };
    _log('[v4] command $type');
    var res = await _sendCommandWithRetry(envelope, timeout);
    // Runtime events (turn completion etc.) also bump the revision, so a
    // CAS base can go stale even with ack tracking. The stale ack tells
    // the server's current revision — retry once with it (mirrors the
    // web client's stale-revision retry).
    if (sessionId != null &&
        res is Map &&
        res['status'] == 'stale' &&
        res['revisionAtDecision'] is num) {
      final serverRevision = (res['revisionAtDecision'] as num).toInt();
      _log('[v4] command $type stale, retry at rev $serverRevision');
      if (serverRevision > (_ackedRevisions[sessionId] ?? 0)) {
        _ackedRevisions[sessionId] = serverRevision;
      }
      final retryEnvelope = {
        ...envelope,
        'commandId': generateUuid(),
        'baseRevision': serverRevision,
        'issuedAt': DateTime.now().millisecondsSinceEpoch,
      };
      res = await _sendCommandWithRetry(retryEnvelope, timeout);
    }
    if (sessionId != null && res is Map && res['revisionAtDecision'] is num) {
      final rev = (res['revisionAtDecision'] as num).toInt();
      final status = res['status'];
      // revisionAtDecision is the base at decision time; an accepted
      // command bumps the revision by one, so the next CAS base is +1.
      final floor =
          (status == 'accepted' || status == 'noop' || status == 'duplicate')
              ? rev + 1
              : rev;
      if (floor > (_ackedRevisions[sessionId] ?? 0)) {
        _ackedRevisions[sessionId] = floor;
      }
    }
    return res;
  }

  /// Sends one command envelope; on timeout (likely a relay drop mid-flight)
  /// waits for bridge recovery and replays the SAME id for deduplication.
  Future<dynamic> _sendCommandWithRetry(
      Map<String, dynamic> envelope, Duration timeout) async {
    try {
      return await _channels.call(
          channel,
          'sendConversationCommandV4',
          [
            {...scope, 'envelope': envelope},
          ],
          timeout: timeout);
    } on TimeoutException {
      // A drop does not prove the command was never accepted. Preserve its
      // identity when replaying. If the bridge is still
      // healthy, rethrow — a retry would double-deliver (e.g. sendText).
      if (session.degraded.value == null) rethrow;
      _log('[v4] command timed out during drop, waiting for recovery and '
          'retrying');
      await session.waitHealthy(timeout: const Duration(seconds: 45));
      await handshake();
      return _channels.call(
          channel,
          'sendConversationCommandV4',
          [
            {...scope, 'envelope': envelope},
          ],
          timeout: timeout);
    }
  }

  /// Creates a new session (mirrors the composer's first-send path):
  /// command `createSession` with `{workspaceId, firstInput:{text}}` and a
  /// null envelope sessionId. Returns the new sessionId on `accepted`.
  Future<String> createSession(
    String workspaceId, {
    String? firstText,
    List<Map<String, dynamic>>? attachments,
    Map<String, dynamic>? config,
    String? runtimeModel,
    List<String>? mcpServers,
    Duration timeout = const Duration(seconds: 90),
  }) async {
    final res = await sendCommand(
      null,
      'createSession',
      {
        'workspaceId': workspaceId,
        if (firstText != null)
          'firstInput': {
            'text': firstText,
            if (attachments != null && attachments.isNotEmpty)
              'attachments': attachments,
          },
        if (config != null) 'config': config,
        if (runtimeModel != null) 'runtimeModel': runtimeModel,
        if (mcpServers != null && mcpServers.isNotEmpty)
          'mcpServers': mcpServers,
      },
      timeout: timeout,
    );
    final map = res is Map ? res.cast<String, dynamic>() : null;
    final status = map?['status'];
    if (status != 'accepted' && status != 'duplicate') {
      throw StateError(
          'createSession rejected: ${map?['reasonCode'] ?? status} ${map?['message'] ?? ''}');
    }
    final result = map?['result'];
    final sessionId = result is Map ? result['sessionId'] : null;
    if (sessionId is! String || sessionId.isEmpty) {
      throw StateError('createSession: missing sessionId in result');
    }
    return sessionId;
  }

  /// Creates a selection-side (auxiliary) chat attached to [parentSessionId]
  /// (command `createSelectionSideSession` with an empty payload, mirrors
  /// the web client's "ask in side chat" flow). Returns the new sessionId.
  Future<String> createSelectionSideSession(
    String parentSessionId, {
    Duration timeout = const Duration(seconds: 60),
  }) async {
    final res = await sendCommand(
      parentSessionId,
      'createSelectionSideSession',
      {},
      timeout: timeout,
    );
    final map = res is Map ? res.cast<String, dynamic>() : null;
    final status = map?['status'];
    if (status != 'accepted' && status != 'duplicate') {
      throw StateError(
          'createSelectionSideSession rejected: ${map?['reasonCode'] ?? status} ${map?['message'] ?? ''}');
    }
    final result = map?['result'];
    final sessionId = result is Map ? result['sessionId'] : null;
    if (sessionId is! String || sessionId.isEmpty) {
      throw StateError(
          'createSelectionSideSession: missing sessionId in result');
    }
    return sessionId;
  }

  Future<dynamic> sendText(
    String sessionId,
    String text, {
    List<Map<String, dynamic>>? attachments,
    String? heldQueueDisposition,
    List<String>? expectedHeldQueueItemIds,
    String? automationId,
    String? offPeakTaskId,
    String? offPeakRunType,
    String? botDeliveryTarget,
    List<String>? toolDisallowlist,
  }) =>
      sendCommand(sessionId, 'sendText', {
        'text': text,
        if (attachments != null && attachments.isNotEmpty)
          'attachments': attachments,
        if (heldQueueDisposition != null)
          'heldQueueDisposition': heldQueueDisposition,
        if (expectedHeldQueueItemIds != null &&
            expectedHeldQueueItemIds.isNotEmpty)
          'expectedHeldQueueItemIds': expectedHeldQueueItemIds,
        if (automationId != null) 'automationId': automationId,
        if (offPeakTaskId != null) 'offPeakTaskId': offPeakTaskId,
        if (offPeakRunType != null) 'offPeakRunType': offPeakRunType,
        if (botDeliveryTarget != null) 'botDeliveryTarget': botDeliveryTarget,
        if (toolDisallowlist != null && toolDisallowlist.isNotEmpty)
          'toolDisallowlist': toolDisallowlist,
      });

  Future<dynamic> sendGoalCommand(
    String sessionId,
    String text, {
    String? displayText,
    String? heldQueueDisposition,
    List<String>? expectedHeldQueueItemIds,
  }) =>
      sendCommand(sessionId, 'sendGoalCommand', {
        'text': text,
        if (displayText != null) 'displayText': displayText,
        if (heldQueueDisposition != null)
          'heldQueueDisposition': heldQueueDisposition,
        if (expectedHeldQueueItemIds != null &&
            expectedHeldQueueItemIds.isNotEmpty)
          'expectedHeldQueueItemIds': expectedHeldQueueItemIds,
      });

  Future<dynamic> pauseGoal(String sessionId) =>
      sendCommand(sessionId, 'pauseGoal', {});

  /// Official v4-pane background-work cancellation. The work id comes from
  /// `snapshot.backgroundWorks[]`, not from a task or terminal session id.
  Future<dynamic> cancelBackgroundWork(String sessionId, String workId) =>
      sendCommand(sessionId, 'cancelBackgroundWork', {'workId': workId});

  Future<dynamic> resumeGoal(String sessionId) =>
      sendCommand(sessionId, 'resumeGoal', {});

  Future<dynamic> stop(String sessionId,
          {String? expectedForegroundExecutionId}) =>
      sendCommand(sessionId, 'stop', {
        if (expectedForegroundExecutionId != null)
          'expectedForegroundExecutionId': expectedForegroundExecutionId,
      });

  Future<dynamic> compact(String sessionId) =>
      sendCommand(sessionId, 'compact', {});

  /// Switch model config. All of provider/model/thought are required by the
  /// protocol schema — pass current values for the ones not changing.
  /// The caller resolves thought levels from advertised model metadata.
  /// A rejection must never trigger a guessed configuration write.
  Future<dynamic> switchModelConfig(
    String sessionId, {
    required String provider,
    required String model,
    required String thought,
  }) =>
      sendCommand(sessionId, 'switchModelConfig', {
        'provider': provider,
        'model': model,
        'thought': thought,
      });

  /// build / edit / plan / yolo. Mirrors `switchCollaborationMode`.
  Future<dynamic> switchCollaborationMode(String sessionId, String mode) =>
      sendCommand(sessionId, 'switchCollaborationMode', {'mode': mode});

  /// queue / guide followup. Mirrors `setFollowupMode`.
  Future<dynamic> setFollowupMode(String sessionId, String mode) =>
      sendCommand(sessionId, 'setFollowupMode', {'mode': mode});

  /// like / dislike / null on an assistant row. Target is
  /// `{rowId, entityId}` (entityId optional for some row kinds).
  Future<dynamic> setAssistantFeedback(
    String sessionId,
    Map<String, dynamic> target,
    String? feedback,
  ) =>
      sendCommand(sessionId, 'setAssistantFeedback', {
        'target': target,
        'feedback': feedback,
      });

  Future<dynamic> retryTurn(String sessionId, Map<String, dynamic> target) =>
      sendCommand(sessionId, 'retryTurn', {'target': target});

  Future<dynamic> sendQueuedNow(String sessionId, String queueItemId) =>
      sendCommand(sessionId, 'sendQueuedNow', {'queueItemId': queueItemId});

  Future<dynamic> editQueueItem(
          String sessionId, String queueItemId, String newText) =>
      sendCommand(sessionId, 'editQueueItem',
          {'queueItemId': queueItemId, 'newText': newText});

  Future<dynamic> reorderQueueItem(
          String sessionId, String queueItemId, String? beforeQueueItemId) =>
      sendCommand(sessionId, 'reorderQueueItem',
          {'queueItemId': queueItemId, 'beforeQueueItemId': beforeQueueItemId});

  Future<dynamic> deleteQueueItem(String sessionId, String queueItemId) =>
      sendCommand(sessionId, 'deleteQueueItem', {'queueItemId': queueItemId});

  Future<dynamic> setAutoDrain(String sessionId, bool autoDrain) =>
      sendCommand(sessionId, 'setAutoDrain', {'autoDrain': autoDrain});

  Future<dynamic> forkAssistant(
          String sessionId, Map<String, dynamic> target) =>
      sendCommand(sessionId, 'forkAssistant', {'target': target});

  Future<dynamic> editUserQuery(
    String sessionId,
    Map<String, dynamic> target,
    String newText,
  ) =>
      sendCommand(
          sessionId, 'editUserQuery', {'target': target, 'newText': newText});

  Future<dynamic> applyFileRewind(
          String sessionId, Map<String, dynamic> target) =>
      sendCommand(sessionId, 'applyFileRewind', {'target': target});

  Future<dynamic> plans(String sessionId) async {
    await handshake();
    return _channels.call(channel, 'conversationPlansV4', [
      {...scope, 'sessionId': sessionId},
    ]);
  }

  Future<dynamic> fileChanges(
    String sessionId, {
    required Map<String, dynamic> target,
    int? baseRevision,
    String? baseLogEpoch,
  }) async {
    await handshake();
    return _channels.call(channel, 'conversationFileChangesV4', [
      {
        ...scope,
        'sessionId': sessionId,
        'target': target,
        if (baseRevision != null) 'baseRevision': baseRevision,
        if (baseLogEpoch != null) 'baseLogEpoch': baseLogEpoch,
      },
    ]);
  }

  Future<dynamic> fileRewindPreview(
    String sessionId, {
    required Map<String, dynamic> target,
    int? baseRevision,
    String? baseLogEpoch,
  }) async {
    await handshake();
    return _channels.call(channel, 'conversationFileRewindPreviewV4', [
      {
        ...scope,
        'sessionId': sessionId,
        'target': target,
        if (baseRevision != null) 'baseRevision': baseRevision,
        if (baseLogEpoch != null) 'baseLogEpoch': baseLogEpoch,
      },
    ]);
  }

  // ------------------------------------------------------------ attachments

  static const _attachmentChunkBytes = 384 * 1024;

  /// Uploads an attachment (begin/chunk/commit, mirrors `rNe()`).
  /// Returns the attachment descriptor `{ref, fileName, mime, bytes}` to be
  /// passed to sendText/createSession.
  Future<Map<String, dynamic>> attachmentPut(
    String sessionId, {
    required String fileName,
    required String mime,
    required Uint8List bytes,
    void Function(double progress)? onProgress,
    bool Function()? isCancelled,
  }) async {
    if (bytes.length > 20 * 1024 * 1024) {
      throw StateError('proto.payloadTooLarge');
    }
    void checkCancelled() {
      if (isCancelled?.call() == true) throw StateError('attachment.cancelled');
    }

    checkCancelled();
    await handshake();
    final uploadId = 'upload-${generateUuid()}';
    final base = {
      'uploadId': uploadId,
      'sessionId': sessionId,
    };
    final totalChunks =
        (bytes.length + _attachmentChunkBytes - 1) ~/ _attachmentChunkBytes;
    final checksum = 'sha256:${sha256.convert(bytes).toString()}';

    var begun = false;
    var committed = false;
    try {
      checkCancelled();
      final beginRes = await _channels.call(channel, 'attachmentBeginV4', [
        {
          ...scope,
          ...base,
          'fileName': fileName,
          'mime': mime,
          'totalBytes': bytes.length,
          'totalChunks': totalChunks,
          'checksum': checksum,
        },
      ]);
      begun = true;
      if (beginRes is Map && beginRes['state'] == 'committed') {
        if (beginRes['ref'] is! String || (beginRes['ref'] as String).isEmpty) {
          throw StateError('attachment.missingRef');
        }
        committed = true;
        onProgress?.call(1);
        return {
          'ref': beginRes['ref'],
          'fileName': fileName,
          'mime': mime,
          'bytes': bytes.length,
        };
      }
      var nextChunk = beginRes is Map
          ? (beginRes['nextChunkIndex'] as num?)?.toInt() ?? 0
          : 0;
      if (nextChunk < 0 || nextChunk > totalChunks) {
        throw StateError('fault.attachment.invalidServerProgress');
      }
      for (var n = nextChunk; n < totalChunks; n++) {
        checkCancelled();
        final start = n * _attachmentChunkBytes;
        final end = start + _attachmentChunkBytes > bytes.length
            ? bytes.length
            : start + _attachmentChunkBytes;
        final chunkRes = await _channels.call(channel, 'attachmentChunkV4', [
          {
            ...scope,
            ...base,
            'chunkIndex': n,
            'dataBase64':
                base64.encode(Uint8List.sublistView(bytes, start, end)),
          },
        ]);
        nextChunk = chunkRes is Map
            ? (chunkRes['nextChunkIndex'] as num?)?.toInt() ?? n + 1
            : n + 1;
        if (nextChunk != n + 1) {
          throw StateError('fault.attachment.invalidServerProgress');
        }
        onProgress?.call((nextChunk / totalChunks) * .99);
      }
      checkCancelled();
      final commitRes = await _channels.call(channel, 'attachmentCommitV4', [
        {...scope, ...base},
      ]);
      final ref = commitRes is Map ? commitRes['ref'] : null;
      if (ref is! String || ref.isEmpty) {
        throw StateError('attachment.missingRef');
      }
      committed = true;
      onProgress?.call(1);
      return {
        'ref': ref,
        'fileName': fileName,
        'mime': mime,
        'bytes': bytes.length,
      };
    } catch (_) {
      if (begun && !committed) {
        try {
          await _channels.call(channel, 'attachmentAbortV4', [
            {...scope, ...base}
          ]);
        } catch (_) {/* Best effort, as TTe. */}
      }
      rethrow;
    }
  }

  /// Reads an attachment (for previews). Returns `{bytes, mediaType}`.
  Future<({Uint8List bytes, String? mediaType})> attachmentRead(
    String sessionId, {
    required String ref,
  }) async {
    await handshake();
    final chunks = <int>[];
    var offset = 0;
    String? mediaType;
    for (var round = 0; round < 1024; round++) {
      final res = await _channels.call(channel, 'attachmentReadV4', [
        {
          ...scope,
          'sessionId': sessionId,
          'ref': ref,
          'offset': offset,
          'limit': _attachmentChunkBytes,
        },
      ]);
      if (res is! Map) break;
      mediaType ??= res['mediaType'] as String?;
      final data = res['dataBase64'] as String?;
      if (data != null && data.isNotEmpty) {
        chunks.addAll(base64.decode(data));
      }
      final next = (res['nextOffset'] as num?)?.toInt();
      final total = (res['totalBytes'] as num?)?.toInt();
      if (next == null || next <= offset) break;
      offset = next;
      if (total != null && offset >= total) break;
    }
    return (bytes: Uint8List.fromList(chunks), mediaType: mediaType);
  }

  Future<dynamic> resolveInteraction(
    String sessionId,
    String interactionId, {
    String? optionId,
    String? freeText,
    String? action,
    Map<String, dynamic>? content,
  }) =>
      sendCommand(sessionId, 'resolveInteraction', {
        'interactionId': interactionId,
        'answer': {
          if (optionId != null) 'optionId': optionId,
          if (freeText != null) 'freeText': freeText,
          if (action != null) 'action': action,
          if (content != null) 'content': content,
        },
      });

  /// Mirrors the official workspace-hook review commands. The review payload
  /// is immutable; `respond...` must send the request identity fields with a
  /// `trust_selected` decision.
  Future<dynamic> respondWorkspaceHookReview(
    String sessionId,
    Map<String, dynamic> base,
    List<String> reviewItemIds,
  ) =>
      sendCommand(sessionId, 'respondWorkspaceHookReview', {
        ...base,
        'decision': {
          'action': 'trust_selected',
          'reviewItemIds': List<String>.unmodifiable(reviewItemIds),
        },
      });

  Future<dynamic> toggleWorkspaceHookReviewItem(
    String sessionId,
    Map<String, dynamic> base,
    String reviewItemId,
    bool enabled,
  ) =>
      sendCommand(sessionId, 'toggleWorkspaceHookReviewItem', {
        ...base,
        'reviewItemId': reviewItemId,
        'enabled': enabled,
      });

  Future<dynamic> revokeWorkspaceHookTrust(
    String sessionId,
    Map<String, dynamic> base,
    List<String> reviewItemIds,
  ) =>
      sendCommand(sessionId, 'revokeWorkspaceHookTrust', {
        ...base,
        'reviewItemIds': List<String>.unmodifiable(reviewItemIds),
      });

  Future<dynamic> requestWorkspaceHookReview(
    String sessionId, {
    String? remoteSessionId,
    required String workspaceIdentity,
    required String bundleDigest,
  }) =>
      sendCommand(sessionId, 'requestWorkspaceHookReview', {
        'sessionId': sessionId,
        if (remoteSessionId != null) 'remoteSessionId': remoteSessionId,
        'workspaceIdentity': workspaceIdentity,
        'bundleDigest': bundleDigest,
      });

  Future<dynamic> rowsRange(
    String sessionId, {
    int? beforeRowId,
    int limit = 60,
  }) async {
    await handshake();
    return _channels.call(channel, 'conversationRowsRangeV4', [
      {
        ...scope,
        'sessionId': sessionId,
        if (beforeRowId != null) 'beforeRowId': beforeRowId,
        'limit': limit,
      },
    ]);
  }

  // ------------------------------------------------------ sessions-index

  /// Subscribes the sessions-index of this workspace
  /// (`subscribeSessionsIndexV4` + `onDynamicSessionsIndexFrame`).
  /// Provides the live session list with title/phase/lastAssistantPreview.
  Future<SessionsIndexSubscription> subscribeSessionsIndex() async {
    await handshake();
    final subscription = SessionsIndexSubscription._(this);
    try {
      await subscription._start();
    } catch (_) {
      await subscription.dispose();
      rethrow;
    }
    return subscription;
  }

  // ---------------------------------------------------- workspace config

  Future<List<Map<String, dynamic>>> workspaceFiles() async {
    final root = scope['workspacePath'];
    if (root is! String || root.isEmpty) return const [];
    return workspaceFilesForRoot(root);
  }

  Future<List<Map<String, dynamic>>> workspaceFilesForRoot(
      String rootPath) async {
    if (rootPath.isEmpty) return const [];
    final result = await _channels.call(
        Channels.file,
        'listWorkspaceFiles',
        [
          {'rootPath': rootPath}
        ],
        timeout: const Duration(seconds: 20));
    final raw = result is Map
        ? result['items'] ?? result['files'] ?? result['entries']
        : result;
    return raw is List
        ? raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : const [];
  }

  Future<TextFileReadResult> readTextFile(String path,
      {int offset = 0, int length = 200000}) async {
    final result = await _channels.call(
        Channels.file,
        'readTextFile',
        [
          {'path': path, 'offset': offset, 'length': length}
        ],
        timeout: const Duration(seconds: 20));
    if (result is String) return TextFileReadResult(text: result);
    if (result is Map) {
      final text = result['text'] ?? result['content'] ?? result['data'];
      return TextFileReadResult(
          text: text is String ? text : null,
          isBinary: result['isBinary'] == true,
          truncated: result['truncated'] == true);
    }
    throw const FormatException('invalid fileService.readTextFile response');
  }

  /// Official window-controller search used by the sidebar command center.
  /// The service accepts full workspace scopes so one request can search all
  /// visible workspaces without locally filtering task previews.
  Future<Map<String, dynamic>> listTaskList({
    required List<Map<String, dynamic>> workspaceScopes,
    String? search,
    int limit = 80,
  }) async {
    final request = <String, dynamic>{
      'kind': 'active',
      'workspaceScopes': workspaceScopes,
      'sortBy': 'updated',
      'limit': limit,
      if (search != null && search.trim().isNotEmpty) 'search': search.trim(),
    };
    final result = await _channels.call(
        Channels.windowController, 'listTaskList', [request],
        timeout: const Duration(seconds: 20));
    if (result is Map && result['items'] is List) {
      return result.cast<String, dynamic>();
    }
    if (result is List) return {'items': result};
    throw const FormatException('invalid window-controller task list response');
  }

  Future<List<Map<String, dynamic>>> skillReferences(String? sessionId) async {
    final result = await _channels.call(
        Channels.zcodeAgent,
        'getSkillReferenceCatalog',
        [
          {...scope, if (sessionId != null) 'sessionId': sessionId}
        ],
        timeout: const Duration(seconds: 20));
    final rows = result is Map ? result['skills'] : null;
    return rows is List
        ? rows.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : const [];
  }

  Future<List<Map<String, dynamic>>> pluginReferences(String? sessionId) async {
    final result = await _channels.call(
        Channels.pluginManagement,
        'getPluginReferenceCatalog',
        [
          {...scope, if (sessionId != null) 'sessionId': sessionId}
        ],
        timeout: const Duration(seconds: 20));
    final rows = result is Map ? result['plugins'] : null;
    return rows is List
        ? rows.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : const [];
  }

  Future<List<Map<String, dynamic>>> sessionReferences() async {
    final result = await _channels.call(
        Channels.zcodeTask, 'listTasks', [scope],
        timeout: const Duration(seconds: 20));
    return result is List
        ? result.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList()
        : const [];
  }

  /// Official yC/O2e: only retain the non-secret family selection fields.
  /// The provider summary mirrors the official sidebar usage candidate input
  /// (`wB` reads `modelProviders` entries by id with `systemDisabledReason`
  /// and a key-presence check); API key material never leaves this layer.
  Future<Map<String, dynamic>> providerFamilySelection() async {
    final result = await _channels.call(Channels.setting, 'get', const [],
        timeout: const Duration(seconds: 20));
    if (result is! Map) {
      throw const FormatException('missing provider settings');
    }
    return {
      for (final key in [
        'modelProviderFamilyModes',
        'modelProviderFamilySelectedKeys'
      ])
        if (result[key] is Map)
          key: Map<String, dynamic>.from(result[key] as Map),
      if (result['modelProviders'] is List)
        'modelProviders': [
          for (final entry
              in (result['modelProviders'] as List).whereType<Map>())
            {
              'id': '${entry['id'] ?? ''}',
              'enabled': entry['enabled'] != false,
              'hasApiKey':
                  entry['apiKey'] is String && (entry['apiKey'] as String).trim().isNotEmpty,
              if (entry['systemDisabledReason'] is String)
                'systemDisabledReason': entry['systemDisabledReason'],
            },
        ],
    };
  }

  /// Official ES/qke; no API-key fallback, and never silently select another
  /// provider or team when the requested source is unavailable.
  Future<dynamic> entitlementSnapshot(String providerId,
          {String? organizationId, String? projectId}) =>
      _channels.call(
          Channels.usageStats,
          'getEntitlementSnapshot',
          [
            {
              'includeSubscription': true,
              'preferredProviderId': providerId,
              'requirePreferredProvider': true,
              'allowDisabledPreferredProvider': true,
              'allowEnvApiKey': false,
              if (organizationId != null) 'organizationId': organizationId,
              if (projectId != null) 'projectId': projectId,
            }
          ],
          timeout: const Duration(seconds: 20));

  /// Official lB uses authenticated enterprise pricing to discover the
  /// selected team's concrete organization/project identities.
  Future<dynamic> teamPlanProducts(String family) => _channels.call(
      Channels.codingPlanSubscription,
      'getEnterprisePricing',
      [
        {'authenticated': true, 'family': family}
      ],
      timeout: const Duration(seconds: 20));

  /// Official rI scope. Reset RPCs have no workspace or conversation argument.
  Future<dynamic> appUsageSnapshot(String range, String timeZone) =>
      _channels.call(
          Channels.usageStats,
          'getAppUsageSnapshot',
          [
            {'range': range, 'timeZone': timeZone}
          ],
          timeout: const Duration(seconds: 20));

  Future<dynamic> codingUsageSnapshot(
          Map<String, dynamic> source, String range, String timeZone) =>
      _channels.call(
          Channels.usageStats,
          'getCodingPlanUsageSnapshot',
          [
            {
              ...source,
              'range': range,
              'customStartDate': null,
              'customEndDate': null,
              'timeZone': timeZone
            }
          ],
          timeout: const Duration(seconds: 20));

  Future<dynamic> planResetStatus(Map<String, dynamic> source) =>
      _channels.call(Channels.usageStats, 'getCodingPlanResetStatus', [source],
          timeout: const Duration(seconds: 20));

  Future<dynamic> requestPlanResetOpportunity(
          Map<String, dynamic> source, String idempotencyKey) =>
      _channels.call(
          Channels.usageStats,
          'requestCodingPlanResetOpportunity',
          [
            {...source, 'idempotencyKey': idempotencyKey}
          ],
          timeout: const Duration(seconds: 20));

  Future<dynamic> usePlanReset(Map<String, dynamic> source,
          {required String resetType, required String idempotencyKey}) =>
      _channels.call(
          Channels.usageStats,
          'useCodingPlanReset',
          [
            {
              ...source,
              'idempotencyKey': idempotencyKey,
              'resetType': resetType
            }
          ],
          timeout: const Duration(seconds: 20));

  Future<dynamic> markPlanResetHistoryRead(Map<String, dynamic> source) =>
      _channels.call(
          Channels.usageStats, 'markCodingPlanResetHistoryRead', [source],
          timeout: const Duration(seconds: 20));

  WorkspacePrep? _prep;
  int _prepGeneration = 0;

  /// `zcode-task.prepareWorkspace` — returns configOptions (model/mode/
  /// thought selects) and slashCommands (builtin + custom skills/MCP).
  Future<WorkspacePrep> prepareWorkspace({bool refresh = false}) async {
    final cached = _prep;
    if (cached != null && !refresh) return cached;
    final generation = ++_prepGeneration;
    final res = await _channels.call(
      Channels.zcodeTask,
      'prepareWorkspace',
      [scope],
    );
    final prep = WorkspacePrep._(res is Map ? res : const {});
    if (generation == _prepGeneration) _prep = prep;
    return prep;
  }

  /// `skills.list` — enabled skills of this workspace (mirrors the web
  /// client's `skillsService.list`). Skills are invoked in the composer as
  /// `$name`. Returns an empty list when the channel rejects or returns no
  /// skill data.
  Future<List<SkillEntry>> skills() async {
    final res = await _channels.call(
      Channels.skills,
      'list',
      [
        {
          'workspacePath': scope['workspacePath'],
          if (scope['workspaceIdentity'] != null)
            'workspaceIdentity': scope['workspaceIdentity'],
          'provider': 'glm',
        },
      ],
      timeout: const Duration(seconds: 20),
    );
    final raw = res is List ? res : (res is Map ? res['skills'] : null);
    if (raw is! List) return const [];
    return [
      for (final item in raw.whereType<Map>())
        SkillEntry._(item.cast<String, dynamic>()),
    ].where((s) => s.name.isNotEmpty).toList();
  }

  /// `fileService.readdir` — lists a directory via the desktop file service
  /// on the `file` channel (mirrors the web client's file browser). Used by
  /// the composer's `@` mention menu. An unrecognized response shape yields
  /// an empty list, so callers degrade to a menu without the files section
  /// instead of surfacing an error.
  Future<List<Map<String, dynamic>>> readdir(
    String path, {
    bool includeHidden = false,
  }) async {
    final res = await _channels.call(
      Channels.file,
      'fileService.readdir',
      [
        {'path': path, 'includeHidden': includeHidden},
      ],
      timeout: const Duration(seconds: 20),
    );
    _log('[conversation] readdir($path) -> ${res.runtimeType}');
    return parseFileEntries(res);
  }
}

class TextFileReadResult {
  const TextFileReadResult(
      {this.text, this.isBinary = false, this.truncated = false});

  final String? text;
  final bool isBinary;
  final bool truncated;
}

/// Lenient decoder for `fileService.readdir` responses whose exact shape is
/// not fully mapped yet: accept a bare list or a map with `entries`/
/// `children`/`files`.
List<Map<String, dynamic>> parseFileEntries(Object? res) {
  Object? raw = res;
  if (raw is Map) {
    raw = raw['entries'] ?? raw['children'] ?? raw['files'];
  }
  if (raw is! List) return const [];
  return [
    for (final item in raw.whereType<Map>()) item.cast<String, dynamic>()
  ];
}

/// Shared base for Conversation/SessionsIndex subscriptions.
/// Extracts the common wire-frame staging, fragment reassembly, bridge
/// recovery, and resubscribe retry logic.
abstract class _SubscriptionBase<T extends ProtocolNotifier> {
  final ConversationTransport _transport;
  final String _logTag;

  final T state;

  String? _subscriptionId;
  String? get subscriptionId => _subscriptionId;
  void Function()? _cancelFrameListener;
  bool _disposed = false;
  bool _resyncing = false;
  int _lifecycleGeneration = 0;
  Timer? _resubscribeTimer;
  Future<void>? _recoveryFuture;
  late final ValueSignal<int> _recoverySignal;
  Completer<void>? _recoverySync;
  final _disposedSignal = Completer<void>();
  bool _waitingForRecoverySync = false;

  final _stagedFrames = <Map<String, dynamic>>[];
  final _fragments = <String, _LogicalFrameAssembly>{};
  Timer? _fragmentCleanup;

  _SubscriptionBase(this._transport, this.state, this._logTag) {
    _transport._trackSubscription(this);
    _recoverySignal = _transport.session.recoveryStarting;
    _recoverySignal.addListener(_onBridgeRecovered);
    _fragmentCleanup =
        Timer.periodic(const Duration(seconds: 30), (_) => _purgeFragments());
  }

  // --- abstract: subclasses define channel/protocol specifics

  /// Frame event name (e.g. `onDynamicConversationFrame`).
  String get _frameEventName;

  /// Subscribe method name (e.g. `subscribeConversationV4`).
  String get _subscribeMethod;

  /// Unsubscribe method name (e.g. `unsubscribeConversationV4`).
  String get _unsubscribeMethod;

  /// Resync method name (e.g. `resyncConversationV4`).
  String get _resyncMethod;

  /// Extra subscribe request args (merged with scope).
  Map<String, dynamic> get _subscribeArgs;

  /// Extra unsubscribe request args.
  Map<String, dynamic> get _unsubscribeArgs;

  /// Extra resync request args.
  Map<String, dynamic> get _resyncArgs;

  /// Topic for wire-frame routing.
  String get topic;

  /// Process a logical frame against [state].
  void _acceptLogicalFrame(Map<String, dynamic> frame);

  /// Called with the subscribe ack map — hook for state-specific processing.
  void _onSubscribeAck(Map<String, dynamic> ack) {}

  /// Called after a successful _start() — hook for post-start logic.
  void _onStarted() {}

  /// Called during resubscribe cleanup before re-connect.
  void _onResubscribeCleanup() {}

  /// Called during dispose — extra cleanup.
  Future<void> _onDispose() async {}

  int get _resyncSeq => 0;
  String? get _resyncEpoch => null;

  void _purgeFragments() {
    if (_disposed) return;
    final stale = <String>[];
    final now = DateTime.now();
    _fragments.forEach((id, a) {
      if (now.difference(a.createdAt).inSeconds > 60) stale.add(id);
    });
    for (final id in stale) {
      _fragments.remove(id);
      _transport._log('[$_logTag] purged stale fragment $id');
    }
  }

  Future<void> _start() async {
    final generation = ++_lifecycleGeneration;
    void ensureCurrent() {
      if (_disposed || generation != _lifecycleGeneration) {
        throw StateError('subscription start superseded');
      }
    }

    void Function()? cancel;
    try {
      await _transport.handshake();
      ensureCurrent();
      cancel = _transport._channels.addEventListener(
        ConversationTransport.channel,
        _frameEventName,
        _handleWireFrame,
        arg: _transport.scope,
      );
      _cancelFrameListener = cancel;
      // 之前退订失败留下的注册会挡住本次订阅 ack，先补发一次退订（尽力而为）。
      final leakedId = _transport._leakedSubscriptionIds.remove(topic);
      if (leakedId != null) {
        _transport._log(
            '[$_logTag] resending leaked unsubscribe for $topic id=$leakedId');
        try {
          await _transport._channels.call(
            ConversationTransport.channel,
            _unsubscribeMethod,
            [
              {..._transport.scope, 'subscriptionId': leakedId, ..._unsubscribeArgs},
            ],
            timeout: const Duration(seconds: 10),
          );
        } catch (error) {
          _transport._leakedSubscriptionIds[topic] = leakedId;
          _transport._log(
              '[$_logTag] leaked unsubscribe retry failed for $topic: $error');
        }
      }
      final res = await _transport._channels.call(
        ConversationTransport.channel,
        _subscribeMethod,
        [
          {..._transport.scope, ..._subscribeArgs}
        ],
        // The desktop may need to warm the session runtime before answering —
        // give the subscribe call generous room instead of timing out at the
        // 30s channel default.
        timeout: const Duration(seconds: 60),
      );
      ensureCurrent();
      final ack = (res as Map?)?['ack'] as Map?;
      final nextId = ack?['subscriptionId'] as String?;
      _transport._log('[$_logTag] subscribed $topic id=$nextId');
      if (nextId == null) {
        throw StateError('$_subscribeMethod: missing ack.subscriptionId');
      }
      ensureCurrent();
      _subscriptionId = nextId;
      _onSubscribeAck(ack?.cast<String, dynamic>() ?? const {});
      final staged = List<Map<String, dynamic>>.from(_stagedFrames);
      _stagedFrames.clear();
      for (final frame in staged) {
        _acceptLogicalFrame(frame);
      }
      _onStarted();
    } catch (_) {
      cancel?.call();
      if (identical(_cancelFrameListener, cancel)) {
        _cancelFrameListener = null;
        _subscriptionId = null;
        _stagedFrames.clear();
        _fragments.clear();
      }
      rethrow;
    }
  }

  void _onBridgeRecovered() {
    if (_disposed) return;
    _transport._log('[$_logTag] bridge recovered, resubscribing $topic');
    _lifecycleGeneration++;
    _recoveryRequested = true;
    _recoveryOldSubscriptionId ??= _subscriptionId;
    _waitingForRecoverySync = true;
    _recoverySync ??= Completer<void>();
    // Frames from the dead bridge must not update the old projection while a
    // fresh subscription is being established.
    _subscriptionId = null;
    _recoveryFuture ??= _resubscribeUntilReady().whenComplete(() {
      _recoveryFuture = null;
    });
  }

  bool _recoveryRequested = false;
  String? _recoveryOldSubscriptionId;

  Future<void> _waitForRecovery() async {
    if (_disposed) return;
    await Future.any<void>([
      _recoveryFuture ?? Future<void>.value(),
      _disposedSignal.future,
    ]);
    if (_disposed) return;
    final sync = _recoverySync;
    if (_waitingForRecoverySync && sync != null) {
      await sync.future.timeout(const Duration(seconds: 45));
    }
  }

  void _markRecoverySynchronized() {
    if (!_waitingForRecoverySync) return;
    _waitingForRecoverySync = false;
    final sync = _recoverySync;
    _recoverySync = null;
    if (sync != null && !sync.isCompleted) sync.complete();
  }

  Future<void> _resubscribeUntilReady() async {
    while (!_disposed && _recoveryRequested) {
      try {
        await _resubscribe();
      } catch (e) {
        _transport._log('[$_logTag] resubscribe failed: $e');
      }
      if (_disposed || _subscriptionId != null) {
        _recoveryRequested = false;
        return;
      }
      await Future<void>.delayed(const Duration(seconds: 3));
    }
  }

  Future<void> _resubscribe() async {
    await _transport.handshake();
    _onResubscribeCleanup();
    _cancelFrameListener?.call();
    _cancelFrameListener = null;
    final oldId = _recoveryOldSubscriptionId ?? _subscriptionId;
    _recoveryOldSubscriptionId = null;
    _subscriptionId = null;
    _stagedFrames.clear();
    _fragments.clear();
    if (oldId != null) {
      try {
        await _transport._channels.call(
          ConversationTransport.channel,
          _unsubscribeMethod,
          [
            {..._transport.scope, 'subscriptionId': oldId, ..._unsubscribeArgs}
          ],
        );
      } catch (_) {}
    }
    try {
      await _start();
    } catch (e) {
      _transport._log('[$_logTag] resubscribe failed: $e');
      rethrow;
    }
  }

  void _handleWireFrame(dynamic data) {
    if (_disposed || data is! Map) return;
    final frame = data.cast<String, dynamic>();
    if (frame['topic'] != topic) return;
    switch (frame['kind']) {
      case 'complete':
        final inner = frame['frame'];
        if (inner is Map) {
          _acceptOrStage(inner.cast<String, dynamic>());
        }
        break;
      case 'fragment':
        _acceptFragment(frame);
        break;
    }
  }

  void _acceptOrStage(Map<String, dynamic> frame) {
    if (_subscriptionId == null) {
      _stagedFrames.add(frame);
      return;
    }
    _acceptLogicalFrame(frame);
  }

  void _acceptFragment(Map<String, dynamic> frame) {
    final id = frame['logicalFrameId'] as String?;
    final index = (frame['fragmentIndex'] as num?)?.toInt();
    final count = (frame['fragmentCount'] as num?)?.toInt();
    final dataBase64 = frame['dataBase64'] as String?;
    if (id == null || index == null || count == null || dataBase64 == null) {
      return;
    }
    if (count < 1 || count > 64 || index < 0 || index >= count) return;
    final assembly =
        _fragments.putIfAbsent(id, () => _LogicalFrameAssembly(count));
    if (assembly.count != count) {
      _fragments.remove(id);
      return;
    }
    try {
      assembly.add(index, base64.decode(dataBase64));
    } catch (e) {
      _fragments.remove(id);
      _transport._log('[$_logTag] bad fragment: $e');
      return;
    }
    if (assembly.isComplete) {
      _fragments.remove(id);
      try {
        final decoded = jsonDecode(utf8.decode(assembly.assemble()));
        if (decoded is Map) {
          _acceptOrStage(decoded.cast<String, dynamic>());
        }
      } catch (e) {
        _transport._log('[$_logTag] bad logical frame: $e');
      }
    }
  }

  Future<void> _resync() async {
    final id = _subscriptionId;
    if (id == null || _disposed || _resyncing) return;
    _resyncing = true;
    _transport._log(
        '[$_logTag] resync (gap detected) seq=$_resyncSeq logEpoch=$_resyncEpoch');
    try {
      await _transport._channels.call(
        ConversationTransport.channel,
        _resyncMethod,
        [
          {
            ..._transport.scope,
            'subscriptionId': id,
            ..._resyncArgs,
            if (_resyncEpoch != null)
              'base': {'logEpoch': _resyncEpoch, 'seq': _resyncSeq},
          },
        ],
      );
    } catch (e) {
      _transport._log('[$_logTag] resync failed: $e');
    } finally {
      _resyncing = false;
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _disposedSignal.complete();
    _transport._untrackActiveSubscription(this);
    final sync = _recoverySync;
    if (sync != null && !sync.isCompleted) {
      // This subscription is no longer required by the active workspace.
      // Release its recovery wait without an unobserved async error.
      sync.complete();
    }
    _recoverySync = null;
    _waitingForRecoverySync = false;
    _resubscribeTimer?.cancel();
    _fragmentCleanup?.cancel();
    await _onDispose();
    _recoverySignal.removeListener(_onBridgeRecovered);
    _cancelFrameListener?.call();
    final id = _subscriptionId;
    if (id != null) {
      try {
        await _transport._channels.call(
          ConversationTransport.channel,
          _unsubscribeMethod,
          [
            {..._transport.scope, 'subscriptionId': id, ..._unsubscribeArgs},
          ],
        );
        _transport._leakedSubscriptionIds.remove(topic);
      } catch (error) {
        // 退订失败不能静默丢弃：登记泄漏的 id，下一次订阅该 topic 前补发退订，
        // 否则 agent 侧残留注册会让重复订阅永远等不到 ack。
        _transport._leakedSubscriptionIds[topic] = id;
        _transport._log(
            '[$_logTag] unsubscribe failed for $topic id=$id: $error');
      }
    }
    _fragments.clear();
  }
}

class ConversationSubscription extends _SubscriptionBase<ConversationState> {
  final String sessionId;

  DateTime _lastFrameAt = DateTime.now();
  Timer? _watchdog;

  ConversationSubscription._(ConversationTransport transport, this.sessionId)
      : super(transport, ConversationState(), 'v4');

  @override
  String get _frameEventName => 'onDynamicConversationFrame';
  @override
  String get _subscribeMethod => 'subscribeConversationV4';
  @override
  String get _unsubscribeMethod => 'unsubscribeConversationV4';
  @override
  String get _resyncMethod => 'resyncConversationV4';
  @override
  Map<String, dynamic> get _subscribeArgs => {'sessionId': sessionId};
  @override
  Map<String, dynamic> get _unsubscribeArgs => const {};
  @override
  Map<String, dynamic> get _resyncArgs => const {'forceSnapshot': true};
  @override
  String get topic => 'conversation/$sessionId';
  @override
  int get _resyncSeq => state.seq;
  @override
  String? get _resyncEpoch => state.logEpoch;

  @override
  void _onSubscribeAck(Map<String, dynamic> ack) {
    if (ack['logEpoch'] is String) {
      state.logEpoch = ack['logEpoch'] as String;
    }
  }

  @override
  void _onStarted() {
    _startWatchdog();
  }

  @override
  void _onResubscribeCleanup() {
    _watchdog?.cancel();
  }

  @override
  Future<void> _onDispose() async {
    _watchdog?.cancel();
    _transport._untrackSubscription(sessionId);
    state.dispose();
  }

  @override
  void _acceptLogicalFrame(Map<String, dynamic> frame) {
    final subId = subscriptionId;
    if (subId == null || frame['subscriptionId'] != subId) return;
    final payload = frame['payload'];
    if (payload is Map && payload['kind'] == 'snapshot') {
      final snapshot = payload['snapshot'];
      final epoch = snapshot is Map ? snapshot['logEpoch'] : null;
      if (_waitingForRecoverySync &&
          (epoch is! String ||
              (state.logEpoch != null && epoch != state.logEpoch))) {
        return;
      }
    }
    _lastFrameAt = DateTime.now();
    if (payload is Map && state.applyFrame(frame, onGap: _resync)) {
      if (payload['kind'] == 'snapshot') {
        _markRecoverySynchronized();
      }
    }
  }

  void _startWatchdog() {
    _watchdog?.cancel();
    _watchdog = Timer.periodic(const Duration(seconds: 10), (_) {
      if (_disposed) return;
      final quietSeconds = DateTime.now().difference(_lastFrameAt).inSeconds;
      if (quietSeconds < 20) return;
      final streaming = state.rows.any((r) => r['state'] == 'streaming');
      if (state.isRunning || streaming) {
        _transport._log(
            '[v4] watchdog: no frames for ${quietSeconds}s while active, resync');
        _resync();
      }
    });
  }
}

class WorkspacePrep {
  final List<ConfigOption> configOptions;
  final List<SlashCommand> slashCommands;
  final Map raw;
  factory WorkspacePrep.fromRaw(Map raw) => WorkspacePrep._(raw);

  WorkspacePrep._(this.raw)
      : configOptions = [
          if (raw['configOptions'] is List)
            for (final o in raw['configOptions'] as List)
              if (o is Map) ConfigOption._(o),
        ],
        slashCommands = [
          if (raw['slashCommands'] is List)
            for (final c in raw['slashCommands'] as List)
              if (c is Map) SlashCommand._(c),
        ];

  ConfigOption? option(String id) {
    for (final o in configOptions) {
      if (o.id == id) return o;
    }
    return null;
  }
}

/// A desktop skill (`skills.list`), triggered in the composer as `$name`.
class SkillEntry {
  final String id;
  final String name;
  final String path;
  final String scope;
  final String? description;
  final String? argumentHint;
  final bool enabled;

  SkillEntry._(Map raw)
      : id = '${raw['id'] ?? ''}',
        name = '${raw['name'] ?? ''}',
        path = '${raw['path'] ?? ''}',
        scope = '${raw['scope'] ?? 'workspace'}',
        description = raw['description'] as String?,
        argumentHint = raw['argumentHint'] as String?,
        enabled = raw['enabled'] != false;
}

class ConfigOption {
  final String id;
  final String name;
  final String category;
  final String type;
  final Object? currentValue;
  final List<ConfigOptionValue> options;

  ConfigOption._(Map raw)
      : id = '${raw['id'] ?? ''}',
        name = '${raw['name'] ?? ''}',
        category = '${raw['category'] ?? ''}',
        type = '${raw['type'] ?? ''}',
        currentValue = raw['currentValue'],
        options = [
          if (raw['options'] is List)
            for (final v in raw['options'] as List)
              if (v is Map) ConfigOptionValue._(v),
        ];
}

class ConfigOptionValue {
  final String value;
  final String name;
  final String? description;

  /// Official option schema carries both `modelProviderId` (stable id,
  /// e.g. `builtin:zai-coding-plan`) and `modelProviderName` (display
  /// label). The id drives first-party checks and menu pinning.
  final String? modelProviderId;
  final String? modelProviderName;
  final String? origin;
  final List<String>? modelThoughtLevels;
  final String? modelDefaultThoughtLevel;

  ConfigOptionValue._(Map raw)
      : value = '${raw['value'] ?? ''}',
        name = '${raw['name'] ?? raw['value'] ?? ''}',
        description = raw['description'] as String?,
        modelProviderId = raw['modelProviderId'] as String?,
        modelProviderName = raw['modelProviderName'] as String?,
        origin = raw['origin'] as String?,
        modelThoughtLevels = raw['modelThoughtLevels'] is List
            ? (raw['modelThoughtLevels'] as List).map((e) => '$e').toList()
            : null,
        modelDefaultThoughtLevel = raw['modelDefaultThoughtLevel'] as String?;

  /// Test/dev seam mirroring the wire shape, so UI tests can build option
  /// values without a live prepareWorkspace response.
  factory ConfigOptionValue.fromRaw(Map raw) => ConfigOptionValue._(raw);
}

class SlashCommand {
  final String name;
  final String description;
  final String? inputHint;
  final String source;

  SlashCommand._(Map raw)
      : name = '${raw['name'] ?? ''}',
        description = '${raw['description'] ?? ''}',
        inputHint = raw['inputHint'] as String?,
        source = '${raw['source'] ?? ''}';
}

class _LogicalFrameAssembly {
  final int count;
  final List<Uint8List?> parts;
  final DateTime createdAt = DateTime.now();
  int received = 0;

  _LogicalFrameAssembly(this.count) : parts = List.filled(count, null);

  void add(int index, Uint8List data) {
    if (index < 0 || index >= count) return;
    if (parts[index] == null) received += 1;
    parts[index] = data;
  }

  bool get isComplete => received == count;

  Uint8List assemble() {
    final builder = BytesBuilder();
    for (final p in parts) {
      if (p != null) builder.add(p);
    }
    return builder.toBytes();
  }
}

/// Live sessions-index state (task list of a workspace), mirrors the
/// sessions-index subscription in the web client (`QAe` delta application).
class SessionEntry {
  final String sessionId;
  final String? parentSessionId;
  final String title;
  final String phase;
  final String? lastAssistantPreview;
  final int lastActivityAt;
  final int createdAt;
  final bool hasBackgroundWork;
  final Map<String, dynamic>? pendingInteraction;
  final Map<String, dynamic> raw;

  SessionEntry(this.raw)
      : sessionId = '${raw['sessionId'] ?? ''}',
        parentSessionId = raw['parentSessionId'] as String?,
        title = '${raw['title'] ?? ''}',
        phase = '${raw['phase'] ?? ''}',
        lastAssistantPreview = raw['lastAssistantPreview'] as String?,
        lastActivityAt = (raw['lastActivityAt'] as num?)?.toInt() ?? 0,
        createdAt = (raw['createdAt'] as num?)?.toInt() ?? 0,
        hasBackgroundWork = raw['hasBackgroundWork'] == true,
        pendingInteraction =
            (raw['pendingInteraction'] as Map?)?.cast<String, dynamic>();
}

class SessionsIndexState extends ProtocolNotifier {
  String? workspaceId;
  String? logEpoch;
  int seq = 0;
  final Map<String, SessionEntry> sessions = {};
  bool ready = false;

  List<SessionEntry> get list {
    final values = sessions.values.toList()
      ..sort((a, b) => b.lastActivityAt.compareTo(a.lastActivityAt));
    return values;
  }

  bool applyFrame(Map<String, dynamic> frame,
      {required void Function() onGap}) {
    final payload = frame['payload'];
    if (payload is! Map) return false;
    final toSeq = (frame['toSeq'] as num?)?.toInt() ?? seq;

    if (payload['kind'] == 'snapshot') {
      if (payload['snapshot'] is! Map) return false;
      final snap = (payload['snapshot'] as Map).cast<String, dynamic>();
      workspaceId = snap['workspaceId'] as String?;
      logEpoch = snap['logEpoch'] as String?;
      sessions.clear();
      final list = snap['sessions'];
      if (list is List) {
        for (final s in list) {
          if (s is Map) {
            final entry = SessionEntry(s.cast<String, dynamic>());
            sessions[entry.sessionId] = entry;
          }
        }
      }
      seq = toSeq;
    } else if (payload['kind'] == 'deltas') {
      final fromSeq = (frame['fromSeq'] as num?)?.toInt() ?? seq;
      if (fromSeq != seq) {
        onGap();
        return false;
      }
      final deltas = payload['deltas'];
      if (deltas is List) {
        for (final d in deltas) {
          if (d is! Map) continue;
          if (d['op'] == 'session.upserted' && d['session'] is Map) {
            final entry =
                SessionEntry((d['session'] as Map).cast<String, dynamic>());
            sessions[entry.sessionId] = entry;
          } else if (d['op'] == 'session.removed') {
            sessions.remove('${d['sessionId']}');
          }
        }
      }
      seq = toSeq;
    } else {
      return false;
    }
    ready = true;
    notifyListeners();
    return true;
  }
}

class SessionsIndexSubscription extends _SubscriptionBase<SessionsIndexState> {
  SessionsIndexSubscription._(ConversationTransport transport)
      : super(transport, SessionsIndexState(), 'v4-si');

  @override
  String get _frameEventName => 'onDynamicSessionsIndexFrame';
  @override
  String get _subscribeMethod => 'subscribeSessionsIndexV4';
  @override
  String get _unsubscribeMethod => 'unsubscribeSessionsIndexV4';
  @override
  String get _resyncMethod => 'resyncSessionsIndexV4';
  @override
  Map<String, dynamic> get _subscribeArgs =>
      const {'runtimePolicy': 'existing-only'};
  @override
  Map<String, dynamic> get _unsubscribeArgs =>
      const {'runtimePolicy': 'existing-only'};
  @override
  Map<String, dynamic> get _resyncArgs =>
      const {'runtimePolicy': 'existing-only'};
  @override
  String get topic =>
      'sessions-index/${_transport.scope['workspaceIdentity'] ?? _transport.scope['workspacePath']}';
  @override
  int get _resyncSeq => state.seq;
  @override
  String? get _resyncEpoch => state.logEpoch;

  @override
  void _onSubscribeAck(Map<String, dynamic> ack) {
    if (ack['logEpoch'] is String) {
      state.logEpoch = ack['logEpoch'] as String;
    }
  }

  @override
  Future<void> _onDispose() async {
    state.dispose();
  }

  @override
  void _acceptLogicalFrame(Map<String, dynamic> frame) {
    final subId = subscriptionId;
    if (subId == null || frame['subscriptionId'] != subId) return;
    final payload = frame['payload'];
    if (payload is Map && payload['kind'] == 'snapshot') {
      final snapshot = payload['snapshot'];
      final epoch = snapshot is Map ? snapshot['logEpoch'] : null;
      if (_waitingForRecoverySync &&
          (epoch is! String ||
              (state.logEpoch != null && epoch != state.logEpoch))) {
        return;
      }
    }
    if (payload is Map && state.applyFrame(frame, onGap: _resync)) {
      if (payload['kind'] == 'snapshot') {
        _markRecoverySynchronized();
      }
    }
  }
}
