import 'dart:async';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';

/// Channel-only fixture keeps state acceptance independent of changing UI files.
class ReviewChannels extends ChannelClient {
  ReviewChannels() : super(sendBody: (_) {});
  FutureOr<dynamic> Function(String, String, List<Object?>)? handler;
  @override
  Future<dynamic> call(String channel, String method, List<Object?> args,
      {Duration timeout = const Duration(seconds: 30)}) async =>
      handler == null ? null : await handler!(channel, method, args);
}

class ReviewChannelBridge implements BridgeSession {
  @override
  final ReviewChannels channels = ReviewChannels();
  @override
  final degraded = ValueSignal<String?>(null);
  @override
  final recovered = ValueSignal<int>(0);
  @override
  final recoveryStarting = ValueSignal<int>(0);
  @override
  Future<void> waitHealthy({Duration timeout = const Duration(seconds: 45)}) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
