import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/ui/device_connection_status.dart';

class _Bridge implements BridgeSession {
  @override
  final channels = ChannelClient(sendBody: (_) {});
  @override
  final degraded = ValueSignal<String?>(null);
  @override
  final recovered = ValueSignal<int>(0);
  @override
  final recoveryStarting = ValueSignal<int>(0);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('bridge interruption is visible and clears after recovery',
      (tester) async {
    final bridge = _Bridge();
    addTearDown(() {
      bridge.channels.dispose();
      bridge.degraded.dispose();
      bridge.recovered.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConnectionStatusBanner(
          bridge: bridge,
          onReconnect: () async {},
          onCancel: () async {},
        ),
      ),
    ));
    expect(
        find.byKey(const ValueKey('connection-status-banner')), findsNothing);

    bridge.degraded.value = 'reconnecting';
    await tester.pump();
    expect(
        find.byKey(const ValueKey('connection-status-banner')), findsOneWidget);
    expect(find.text('Connection interrupted. Reconnecting'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    bridge.degraded.value = null;
    await tester.pump();
    expect(
        find.byKey(const ValueKey('connection-status-banner')), findsNothing);
  });

  testWidgets('relay kick shows the official takeover reason and reconnect',
      (tester) async {
    final bridge = _Bridge();
    addTearDown(() {
      bridge.channels.dispose();
      bridge.degraded.dispose();
      bridge.recovered.dispose();
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ConnectionStatusBanner(
          bridge: bridge,
          onReconnect: () async {},
        ),
      ),
    ));
    // Official kicked screen (rog-official-kicked-screen.png): the takeover
    // reason is explicit, not a generic failure.
    bridge.degraded.value = 'kicked';
    await tester.pump();
    expect(
        find.byKey(const ValueKey('connection-status-banner')), findsOneWidget);
    expect(find.text('Taken over by another device'), findsOneWidget);
    expect(find.textContaining('Another remote controller'), findsOneWidget);
    expect(find.text('Reconnect'), findsOneWidget);
    // Recovery UI stays out of the kicked state: no cancel-recovery entry.
    expect(find.text('Cancel'), findsNothing);

    bridge.degraded.value = null;
    await tester.pump();
    expect(
        find.byKey(const ValueKey('connection-status-banner')), findsNothing);
  });
}
