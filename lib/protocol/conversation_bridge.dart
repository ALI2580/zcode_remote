import 'channel_client.dart';
import 'observable.dart';

/// Bridge surface consumed by [ConversationTransport] and its clients.
///
/// `conversation.dart` types its session against this interface instead of
/// importing `zemote_client.dart` (which constructs transports), keeping
/// `lib/protocol` import-acyclic (test/structure/boundary_guard_test.dart).
abstract interface class ConversationBridge {
  ChannelClient get channels;

  /// Bumped when a reopened bridge starts rebuilding — handshakes restart.
  ValueSignal<int> get recoveryStarting;

  /// Advances only after live subscriptions confirm the reopened bridge.
  ValueSignal<int> get recovered;

  /// Non-null while the bridge is degraded (rpc-transport-fault etc.).
  ValueSignal<String?> get degraded;

  /// Resolves once the bridge is healthy again, or throws TimeoutException.
  Future<void> waitHealthy({Duration timeout});
}
