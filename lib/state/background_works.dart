import 'package:flutter/foundation.dart';

import '../protocol/conversation.dart';

/// Owns cancellation state for the bound conversation's official
/// `backgroundWorks`. Snapshot data remains authoritative; this controller
/// only adds in-flight dedupe and late/failure protection.
class BackgroundWorksController extends ChangeNotifier {
  BackgroundWorksController({
    required this.transport,
    required this.sessionId,
    required this.state,
  }) {
    state.addListener(_onStateChanged);
  }

  final ConversationTransport transport;
  final String sessionId;
  final ConversationState state;

  final Map<String, Future<bool>> _operations = {};
  final Map<String, Object> _failures = {};
  bool _disposed = false;

  /// Official projection shows running bash and subagent work; only entries
  /// with a work id can be cancelled.
  List<Map<String, dynamic>> get running {
    return state.backgroundWorks
        .where((raw) =>
            const ['bash', 'subagent'].contains('${raw['kind'] ?? ''}') &&
            '${raw['status'] ?? ''}' == 'running' &&
            '${raw['workId'] ?? ''}'.isNotEmpty)
        .toList();
  }

  bool isCancellable(Map<String, dynamic> work) => work['cancellable'] != false;

  Object? failureFor(String workId) => _failures[workId];

  bool get isBusy => _operations.isNotEmpty;

  bool isCancelling(String workId) => _operations.containsKey(workId);

  Future<bool> cancel(String workId) {
    if (_disposed || workId.isEmpty) return Future.value(false);
    final existing = _operations[workId];
    if (existing != null) return existing;
    final operation = _send(workId);
    _operations[workId] = operation;
    notifyListeners();
    return operation.whenComplete(() {
      _operations.remove(workId);
      if (!_disposed) notifyListeners();
    });
  }

  Future<bool> _send(String workId) async {
    try {
      final result = await transport.cancelBackgroundWork(sessionId, workId);
      final status = result is Map ? result['status'] as String? : null;
      final success = status == 'accepted' || status == 'noop';
      if (_disposed || success) {
        if (!_disposed) {
          _failures.remove(workId);
          notifyListeners();
        }
        return success;
      }
      _failures[workId] =
          result is Map ? result : {'status': status ?? 'invalid-response'};
      notifyListeners();
      return false;
    } catch (error) {
      if (_disposed) return false;
      _failures[workId] = error;
      notifyListeners();
      return false;
    }
  }

  void _onStateChanged() {
    if (_disposed) return;
    final finished = state.backgroundWorks
        .where((item) => '${item['status'] ?? ''}' != 'running')
        .map((item) => '${item['workId'] ?? ''}')
        .where((id) => id.isNotEmpty)
        .toSet();
    _failures.removeWhere((workId, _) => finished.contains(workId));
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    state.removeListener(_onStateChanged);
    super.dispose();
  }
}
