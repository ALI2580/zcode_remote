import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import '../ui/fake_features.dart';

class _Bridge implements BridgeSession {
  @override
  FeatureChannels channels = FeatureChannels();
  @override
  final degraded = ValueSignal<String?>(null);
  @override
  final recovered = ValueSignal<int>(0);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('late old hello cannot initialize new channels or replace connection ID',
      () async {
    final bridge = _Bridge();
    final oldHello = Completer<dynamic>();
    bridge.channels.handler = (channel, method, args) => oldHello.future;
    final transport = ConversationTransport(session: bridge, scope: const {});
    final old = transport.handshake();
    final oldFailure = expectLater(old, throwsStateError);
    bridge.channels = FeatureChannels()
      ..handler = (channel, method, args) =>
          method == 'helloConversationV4' ? {'connectionId': 'new'} : {};
    bridge.recovered.value++;
    await transport.handshake();
    oldHello.complete({'connectionId': 'old'});
    await oldFailure;
    expect(transport.connectionId, 'new');
    expect(
        bridge.channels.calls
            .where((call) => call.method == 'initializeConversationV4'),
        hasLength(1));
  });

  test('old handshake failure cannot clear a newer in-flight handshake',
      () async {
    final bridge = _Bridge();
    final oldHello = Completer<dynamic>();
    bridge.channels.handler = (channel, method, args) => oldHello.future;
    final transport = ConversationTransport(session: bridge, scope: const {});
    final oldFailure = expectLater(transport.handshake(), throwsStateError);
    final newInit = Completer<dynamic>();
    bridge.channels = FeatureChannels()
      ..handler = (channel, method, args) => method == 'helloConversationV4'
          ? {'connectionId': 'new'}
          : newInit.future;
    bridge.recovered.value++;
    final fresh = transport.handshake();
    await Future<void>.delayed(Duration.zero);
    oldHello.completeError(StateError('old connection closed'));
    await oldFailure;
    final repeated = transport.handshake();
    await Future<void>.delayed(Duration.zero);
    expect(
        bridge.channels.calls
            .where((call) => call.method == 'helloConversationV4'),
        hasLength(1));
    newInit.complete({});
    await Future.wait([fresh, repeated]);
    expect(transport.connectionId, 'new');
  });
}
