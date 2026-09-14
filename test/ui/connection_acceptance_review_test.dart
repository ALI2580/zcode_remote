import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/device_connection_status.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'fake_features.dart';
import 'fake_workspace.dart';

// Acceptance authored by the main agent against the requested behavior.
void main() {
  test('review: an independently hosted healthy chat is not disconnected', () {
    final bridge = FeatureBridge();
    expect(connectionStatusSnapshot(null, bridge).healthy, isTrue);
  });

  test('review: terminal bridge failure is not presented as automatic recovery',
      () {
    final bridge = FeatureBridge()..degraded.value = 'kicked';
    // A terminal kick is its own state (official takeover copy), never the
    // automatic-recovering presentation.
    expect(connectionStatusSnapshot(null, bridge).state,
        ConnectionBannerState.kicked);
    bridge.degraded.value = 'user-disconnected';
    expect(connectionStatusSnapshot(null, bridge).state,
        ConnectionBannerState.disconnected);
  });

  test(
      'review: a failed bridge attempt is distinguishable from active recovery',
      () {
    final bridge = FeatureBridge();
    bridge.degraded.value = 'reopen-failed: synthetic outage';
    expect(connectionStatusSnapshot(null, bridge).state,
        ConnectionBannerState.failed);
  });

  testWidgets(
      'review: pending reconnect remains cancellable and source switch is independent',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    final oldBridge = FeatureBridge()..degraded.value = 'reconnecting';
    final nextBridge = FeatureBridge()..degraded.value = 'reconnecting';
    final oldRetry = Completer<void>();
    final nextRetry = Completer<void>();
    int oldCalls = 0;
    int nextCalls = 0;
    int cancels = 0;
    Widget page(FeatureBridge bridge, Future<void> Function() retry) =>
        ZcodeRemoteApp(
            preferences: prefs,
            home: Scaffold(
                body: ConnectionStatusBanner(
              bridge: bridge,
              onReconnect: retry,
              onCancel: () async {
                cancels++;
              },
            )));
    await tester.pumpWidget(page(oldBridge, () {
      oldCalls++;
      return oldRetry.future;
    }));
    await tester.tap(find.text('重新连接'));
    await tester.pump();
    expect(oldCalls, 1);
    final cancel = find.widgetWithText(TextButton, '取消恢复');
    expect(cancel, findsOneWidget);
    expect(tester.widget<TextButton>(cancel).onPressed, isNotNull,
        reason: 'A pending reconnect must not remove its cancellation path.');
    await tester.tap(cancel);
    await tester.pump();
    expect(cancels, 1);
    await tester.pumpWidget(page(nextBridge, () {
      nextCalls++;
      return nextRetry.future;
    }));
    await tester.pump();
    await tester.tap(find.text('重新连接'));
    await tester.pump();
    expect(nextCalls, 1,
        reason: 'The old source pending action must not lock the new source.');
    oldRetry.complete();
    await tester.pump();
    expect(tester.widget<OutlinedButton>(find.byType(OutlinedButton)).onPressed,
        isNull,
        reason:
            'Completion from the old source cannot clear the new source pending state.');
    nextRetry.complete();
    await tester.pump();
    await tester.pumpWidget(const SizedBox());
    prefs.dispose();
  });

  testWidgets(
      'review: remote settings retain their content and block stale remote actions',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.record/messages'),
            (_) async => null);
    tester.view.physicalSize = const Size(1180, 820);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-settings-review&hash=synthetic&t=1');
    final bridge = FeatureBridge();
    final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
    final monitor = await sessions
        .openWorkspace(device, 'workspace', {'workspaceIdentity': 'workspace'});
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: SettingsCenterPage(
          preferences: prefs,
          sessions: sessions,
          remoteMonitor: monitor,
          onManageDevices: () {},
          initialSection: 'general',
        )));
    await tester.pumpAndSettle();
    expect(find.text('继承系统终端 Profile'), findsOneWidget);
    final switches = find.byType(Switch);
    expect(switches, findsWidgets);
    final count = switches.evaluate().length;
    await tester.enterText(find.byType(TextField).first, 'review-unsaved-font');
    await tester.pump();
    bridge.degraded.value = 'reconnecting';
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.text('继承系统终端 Profile'), findsOneWidget,
        reason: 'Offline remote values remain readable.');
    expect(switches.evaluate().length, count);
    expect(find.text('review-unsaved-font'), findsOneWidget,
        reason:
            'Disabling remote fields must not unmount their unsaved form state.');
    final writesBefore =
        bridge.channels.calls.where((c) => c.method == 'update').length;
    await tester.tap(switches.first, warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 50));
    expect(bridge.channels.calls.where((c) => c.method == 'update').length,
        writesBefore,
        reason:
            'The general page mixes local and remote settings; its remote switches must be gated.');
    bridge.degraded.value = null;
    await tester.pump(const Duration(milliseconds: 50));
    await tester.drag(find.byType(ListView).last, const Offset(0, -650));
    await tester.pumpAndSettle();
    bridge.degraded.value = 'reconnecting';
    await tester.pump(const Duration(milliseconds: 50));
    expect(find.byKey(const ValueKey('connection-status-banner')).hitTestable(),
        findsOneWidget,
        reason:
            'The interruption notice must remain visible when settings are scrolled down.');
    await tester.pumpWidget(const SizedBox());
    sessions.dispose();
    prefs.dispose();
    expect(tester.takeException(), isNull);
  });
}
