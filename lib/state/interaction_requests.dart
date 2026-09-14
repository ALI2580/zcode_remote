import 'package:flutter/foundation.dart';

import '../protocol/conversation.dart';

class InteractionFailure {
  const InteractionFailure({
    required this.interactionId,
    this.error,
    this.status,
    this.reasonCode,
  });

  final String interactionId;
  final Object? error;
  final String? status;
  final String? reasonCode;
}

class WorkspaceHookFailure {
  const WorkspaceHookFailure({
    required this.interactionId,
    required this.reviewItemId,
    this.error,
    this.status,
    this.reasonCode,
  });

  final String interactionId;
  final String reviewItemId;
  final Object? error;
  final String? status;
  final String? reasonCode;
}

/// Owns one session's blocking `pendingInteractions`. The raw protocol
/// snapshot remains the authority; this controller only adds submit dedupe,
/// visible failures and late/invalidated response protection.
class InteractionController extends ChangeNotifier {
  InteractionController({
    required this.transport,
    required this.sessionId,
    required this.state,
  }) {
    state.addListener(_onStateChanged);
  }

  final ConversationTransport transport;
  final String sessionId;
  final ConversationState state;

  final Set<String> _resolving = {};
  final Map<String, Future<bool>> _operations = {};
  final Map<String, InteractionFailure> _failures = {};
  bool _disposed = false;

  /// Official shows one blocking permission/user-input card; workspace hook
  /// review has its own admission UI and is intentionally not collapsed into
  /// this request card.
  Map<String, dynamic>? get active {
    for (final raw in state.pendingInteractions) {
      final kind = raw['kind'];
      if (kind == 'permission' || kind == 'userInput') return raw;
    }
    return null;
  }

  List<Map<String, dynamic>> get pending => state.pendingInteractions;

  int get pendingCount => state.pendingInteractions.length;

  int get workspaceHookReviewCount => state.pendingInteractions
      .where((item) => item['kind'] == 'workspaceHookReview')
      .length;

  Set<String> get resolvingIds => Set.unmodifiable(_resolving);

  InteractionFailure? failureFor(String interactionId) =>
      _failures[interactionId];

  bool get isBusy => _resolving.isNotEmpty;

  Future<bool> resolve(
    String interactionId, {
    String? optionId,
    String? freeText,
    String? action,
    Map<String, dynamic>? content,
  }) {
    final answer = {
      if (optionId != null) 'optionId': optionId,
      if (freeText != null) 'freeText': freeText,
      if (action != null) 'action': action,
      if (content != null) 'content': content,
    };
    return _submit(
      interactionId,
      'resolveInteraction',
      {
        'interactionId': interactionId,
        'answer': answer,
      },
      removeOnSuccess: true,
    );
  }

  Future<bool> snoozeAutoResolution(String interactionId) => _submit(
        interactionId,
        'snoozeInteractionAutoResolution',
        {'interactionId': interactionId},
        removeOnSuccess: false,
      );

  Future<bool> _submit(
    String interactionId,
    String type,
    Map<String, dynamic> payload, {
    required bool removeOnSuccess,
  }) {
    if (_disposed) return Future.value(false);
    if (!_pendingIds.contains(interactionId)) return Future.value(false);
    final existing = _operations[interactionId];
    if (existing != null) return existing;

    final operation =
        _send(interactionId, type, payload, removeOnSuccess: removeOnSuccess);
    _operations[interactionId] = operation;
    _resolving.add(interactionId);
    notifyListeners();
    return operation.whenComplete(() {
      _operations.remove(interactionId);
      _resolving.remove(interactionId);
      if (!_disposed) notifyListeners();
    });
  }

  Future<bool> _send(
    String interactionId,
    String type,
    Map<String, dynamic> payload, {
    required bool removeOnSuccess,
  }) async {
    try {
      final result = await transport.sendCommand(sessionId, type, payload);
      // The request can be resolved on another client while our RPC is in
      // flight. Never resurrect or attach a stale failure to a new request.
      if (_disposed || !_pendingIds.contains(interactionId)) return false;
      final status = result is Map ? result['status'] as String? : null;
      final success =
          status == 'accepted' || status == 'duplicate' || status == 'noop';
      if (success) {
        if (removeOnSuccess) state.removePendingInteraction(interactionId);
        _failures.remove(interactionId);
        notifyListeners();
        return true;
      }
      _failures[interactionId] = InteractionFailure(
        interactionId: interactionId,
        status: status,
        reasonCode: result is Map ? result['reasonCode'] as String? : null,
      );
      notifyListeners();
      return false;
    } catch (error) {
      if (_disposed || !_pendingIds.contains(interactionId)) return false;
      _failures[interactionId] = InteractionFailure(
        interactionId: interactionId,
        error: error,
      );
      notifyListeners();
      return false;
    }
  }

  void _onStateChanged() {
    if (_disposed) return;
    final ids = _pendingIds;
    _failures.removeWhere((id, _) => !ids.contains(id));
    notifyListeners();
  }

  Set<String> get _pendingIds => state.pendingInteractions
      .map((item) => '${item['interactionId'] ?? ''}')
      .where((id) => id.isNotEmpty)
      .toSet();

  @override
  void dispose() {
    _disposed = true;
    state.removeListener(_onStateChanged);
    super.dispose();
  }
}

/// Owns the workspace-hook review flow for the bound conversation. The
/// Conversation snapshot is authoritative; this controller adds official
/// optimistic removal, local dismissal, request dedupe and failure context.
class WorkspaceHookReviewController extends ChangeNotifier {
  WorkspaceHookReviewController({
    required this.transport,
    required this.sessionId,
    required this.state,
    this.workspaceIdentity,
  }) {
    state.addListener(_onStateChanged);
  }

  final ConversationTransport transport;
  final String sessionId;
  final ConversationState state;
  final String? workspaceIdentity;

  final Set<String> _dismissed = {};
  final Set<String> _dismissedAdmission = {};
  final Set<String> _resolving = {};
  final Map<String, Future<bool>> _operations = {};
  final Map<String, WorkspaceHookFailure> _failures = {};
  final Set<String> _admissionRequestKeys = {};
  final Map<String, Object> _admissionRequestErrors = {};
  bool _disposed = false;

  static const _actionableTrustStates = {
    'pending_trust',
    'revoked',
    'stale_digest',
  };

  Map<String, dynamic>? get _dismissableRequest {
    final reviews = state.pendingInteractions.where(_isHookReview).toList();
    // Official upsert accepts a later generation in the same review flow, but
    // never lets a lower generation replace it. Cross-flow reviews are ordered
    // by creation time.
    reviews.sort((a, b) {
      final flow = '${a['payload']?['reviewFlowId'] ?? ''}'
          .compareTo('${b['payload']?['reviewFlowId'] ?? ''}');
      if (flow != 0) return flow;
      final generation = _generation(a).compareTo(_generation(b));
      if (generation != 0) return generation;
      return _createdAt(a).compareTo(_createdAt(b));
    });
    if (reviews.isEmpty) return null;
    final byFlow = <String, List<Map<String, dynamic>>>{};
    for (final review in reviews) {
      byFlow
          .putIfAbsent('${review['payload']?['reviewFlowId'] ?? ''}', () => [])
          .add(review);
    }
    final latestPerFlow = [
      for (final entries in byFlow.values) entries.last,
    ]..sort((a, b) => _createdAt(b).compareTo(_createdAt(a)));
    for (final raw in latestPerFlow) {
      if (pendingItemCount(raw) <= 0) continue;
      return raw;
    }
    return null;
  }

  bool _isHookReview(Map<String, dynamic> raw) =>
      raw['kind'] == 'workspaceHookReview' &&
      (raw['payload'] as Map?)?['kind'] == 'workspaceHookReview';

  int _generation(Map<String, dynamic> raw) {
    final value = (raw['payload'] as Map?)?['generation'];
    return value is num ? value.toInt() : 0;
  }

  int _createdAt(Map<String, dynamic> raw) {
    final value = raw['createdAt'];
    return value is num ? value.toInt() : 0;
  }

  Map<String, dynamic>? get active => _visible(_dismissableRequest);

  int get pendingCount {
    final request = active;
    return request == null ? 0 : pendingItemCount(request);
  }

  List<Map<String, dynamic>> items(Map<String, dynamic> request) =>
      ((request['payload'] as Map?)?['items'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList();

  int pendingItemCount(Map<String, dynamic> request) {
    final payload = (request['payload'] as Map?)?.cast<String, dynamic>();
    final summary = (payload?['summary'] as Map?)?.cast<String, dynamic>();
    final declared = summary?['pendingCount'];
    if (declared is num) return declared.toInt();
    return items(request)
        .where((item) =>
            _actionableTrustStates.contains('${item['trustState'] ?? ''}'))
        .length;
  }

  /// Independent conversation admission. Official renders it before any
  /// pending interaction surfaces and uses it to pull the full review payload.
  Map<String, dynamic>? get admission =>
      _visibleAdmission(state.workspaceHookAdmission);

  int get admissionCount {
    final value = admission?['pendingCount'];
    return value is num ? value.toInt() : 0;
  }

  Map<String, Object> get admissionRequestErrors =>
      Map.unmodifiable(_admissionRequestErrors);

  Set<String> get resolvingOperationIds => Set.unmodifiable(_resolving);

  Map<String, WorkspaceHookFailure> get failures => Map.unmodifiable(_failures);

  WorkspaceHookFailure? failureFor(String interactionId, String reviewItemId) =>
      _failures[operationIdFor(interactionId, reviewItemId)];

  String operationIdFor(String interactionId, String reviewItemId) =>
      '$interactionId|$reviewItemId|trust';

  void dismiss(Map<String, dynamic> request) {
    final interactionId = '${request['interactionId'] ?? ''}';
    final bundleDigest =
        '${(request['payload'] as Map?)?['bundleDigest'] ?? ''}';
    if (interactionId.isEmpty) return;
    _dismissed.add('$interactionId|$bundleDigest');
    notifyListeners();
  }

  void dismissAdmission() {
    final raw = state.workspaceHookAdmission;
    final digest = '${raw?['bundleDigest'] ?? ''}';
    if (digest.isEmpty) return;
    _dismissedAdmission.add('$sessionId|$digest');
    notifyListeners();
  }

  Future<bool> requestAdmissionReview() {
    final raw = _visibleAdmission(state.workspaceHookAdmission);
    final bundleDigest = '${raw?['bundleDigest'] ?? ''}';
    if (_disposed || raw == null || bundleDigest.isEmpty) {
      return Future.value(false);
    }
    final identity = '${raw['workspaceIdentity'] ?? workspaceIdentity ?? ''}';
    final operationKey = '$sessionId|$identity|$bundleDigest';
    if (_admissionRequestKeys.contains(operationKey)) return Future.value(true);
    _admissionRequestKeys.add(operationKey);
    _admissionRequestErrors.remove(operationKey);
    return _sendAdmissionReview(
      operationKey: operationKey,
      workspaceIdentity: identity,
      bundleDigest: bundleDigest,
    );
  }

  Future<bool> _sendAdmissionReview({
    required String operationKey,
    required String workspaceIdentity,
    required String bundleDigest,
  }) async {
    try {
      final result = await transport.requestWorkspaceHookReview(
        sessionId,
        workspaceIdentity: workspaceIdentity,
        bundleDigest: bundleDigest,
      );
      _admissionRequestKeys.remove(operationKey);
      final accepted = result is! Map || result['accepted'] != false;
      if (_disposed || !accepted) {
        if (!_disposed && !accepted) {
          _admissionRequestErrors[operationKey] = result;
        }
        return false;
      }
      return true;
    } catch (error) {
      _admissionRequestKeys.remove(operationKey);
      if (!_disposed) _admissionRequestErrors[operationKey] = error;
      return false;
    }
  }

  Future<bool> trustItem(Map<String, dynamic> request, Map item) =>
      trustItems(request, ['${item['reviewItemId'] ?? ''}']);

  Future<bool> trustItems(
    Map<String, dynamic> request,
    List<String> reviewItemIds,
  ) async {
    final ids = reviewItemIds.where((id) => id.isNotEmpty).toList();
    if (ids.isEmpty) return false;
    final interactionId = '${request['interactionId'] ?? ''}';
    final payload = (request['payload'] as Map?)?.cast<String, dynamic>();
    final valid = ids.every((id) => items(request).any((item) =>
        '${item['reviewItemId'] ?? ''}' == id &&
        _actionableTrustStates.contains('${item['trustState'] ?? ''}')));
    if (_disposed || interactionId.isEmpty || payload == null || !valid) {
      return false;
    }
    final operationKey = ids.length == 1
        ? operationIdFor(interactionId, ids.single)
        : '$interactionId|${ids.join(',')}|trust';
    final existing = _operations[operationKey];
    if (existing != null) return existing;
    final operation = _submit(
      operationKey,
      interactionId,
      'respondWorkspaceHookReview',
      {
        ..._basePayload(payload),
        'decision': {
          'action': 'trust_selected',
          'reviewItemIds': ids,
        },
      },
      removeOnSuccess: true,
    );
    _operations[operationKey] = operation;
    _resolving.add(operationKey);
    notifyListeners();
    return operation.whenComplete(() {
      _operations.remove(operationKey);
      _resolving.remove(operationKey);
      if (!_disposed) notifyListeners();
    });
  }

  Map<String, dynamic> _basePayload(Map<String, dynamic> payload) => {
        'sessionId': '${payload['sessionId'] ?? sessionId}',
        'taskId': '${payload['taskId'] ?? ''}',
        'runId': '${payload['runId'] ?? ''}',
        if (payload['remoteSessionId'] != null)
          'remoteSessionId': '${payload['remoteSessionId']}',
        'workspaceIdentity': '${payload['workspaceIdentity'] ?? ''}',
        'bundleDigest': '${payload['bundleDigest'] ?? ''}',
        'reviewFlowId': '${payload['reviewFlowId'] ?? ''}',
        'generation': payload['generation'] ?? 0,
        'interactionId': '${payload['interactionId'] ?? ''}',
      };

  Map<String, dynamic>? _visible(Map<String, dynamic>? request) {
    if (request == null) return null;
    final interactionId = '${request['interactionId'] ?? ''}';
    final bundleDigest =
        '${(request['payload'] as Map?)?['bundleDigest'] ?? ''}';
    return _dismissed.contains('$interactionId|$bundleDigest') ? null : request;
  }

  Map<String, dynamic>? _visibleAdmission(Map<String, dynamic>? raw) {
    final count = raw?['pendingCount'];
    final bundleDigest = '${raw?['bundleDigest'] ?? ''}';
    if (raw == null || count is! num || count.toInt() <= 0) return null;
    return _dismissedAdmission.contains('$sessionId|$bundleDigest')
        ? null
        : raw;
  }

  Future<bool> _submit(
    String operationKey,
    String interactionId,
    String type,
    Map<String, dynamic> payload, {
    required bool removeOnSuccess,
  }) async {
    try {
      final result = await transport.sendCommand(sessionId, type, payload);
      // A review can be accepted from another client while this response is
      // in flight. A late response never attaches to a newer review flow.
      final current = _dismissableRequest;
      final currentId = '${current?['interactionId'] ?? ''}';
      if (_disposed ||
          current == null ||
          currentId != interactionId ||
          !_sameFlowIdentity(current, payload)) {
        return false;
      }
      final status = result is Map ? result['status'] as String? : null;
      final success =
          status == 'accepted' || status == 'duplicate' || status == 'noop';
      if (success) {
        if (removeOnSuccess) state.removePendingInteraction(interactionId);
        _failures.removeWhere((key, _) => key.startsWith('$interactionId|'));
        notifyListeners();
        return true;
      }
      final reviewItemId = '${payload['decision']?['reviewItemIds']?.first}';
      _failures[operationKey] = WorkspaceHookFailure(
        interactionId: interactionId,
        reviewItemId: reviewItemId,
        status: status,
        reasonCode: result is Map ? result['reasonCode'] as String? : null,
      );
      notifyListeners();
      return false;
    } catch (error) {
      final current = _dismissableRequest;
      if (_disposed ||
          current == null ||
          '${current['interactionId'] ?? ''}' != interactionId ||
          !_sameFlowIdentity(current, payload)) {
        return false;
      }
      final reviewItemId = '${payload['decision']?['reviewItemIds']?.first}';
      _failures[operationKey] = WorkspaceHookFailure(
        interactionId: interactionId,
        reviewItemId: reviewItemId,
        error: error,
      );
      notifyListeners();
      return false;
    }
  }

  bool _sameFlowIdentity(
    Map<String, dynamic> request,
    Map<String, dynamic> payload,
  ) {
    final requestPayload = (request['payload'] as Map?) ?? const {};
    return requestPayload['reviewFlowId'] == payload['reviewFlowId'] &&
        requestPayload['generation'] == payload['generation'] &&
        requestPayload['bundleDigest'] == payload['bundleDigest'] &&
        requestPayload['interactionId'] == payload['interactionId'];
  }

  void _onStateChanged() {
    if (_disposed) return;
    final interactionId = '${_dismissableRequest?['interactionId'] ?? ''}';
    _failures.removeWhere((key, value) => value.interactionId != interactionId);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    state.removeListener(_onStateChanged);
    super.dispose();
  }
}
