import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/relay_client.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'fake_workspace.dart';
import 'fake_features.dart';

class _CaptureRelay implements RelayClient {
  final signal = ValueSignal(RelayState.paired);
  @override
  RelayState get state => signal.value;
  @override
  ProtocolValueListenable<RelayState> get stateListenable => signal;
  @override
  bool get wasPaired => true;
  @override
  bool get intentionallyClosed => false;
  @override
  Future<void> dispose() async => signal.dispose();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CaptureClient implements ZemoteClient {
  _CaptureClient(this.relay);
  @override
  final RelayClient relay;
  @override
  Future<void> dispose() => relay.dispose();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CaptureSession extends FakeDeviceSession {
  _CaptureSession(super.params, super.bridge) {
    captureRelay = _CaptureRelay();
    captureClient = _CaptureClient(captureRelay);
  }
  late final _CaptureRelay captureRelay;
  late final _CaptureClient captureClient;
  String? reason;
  @override
  ZemoteClient get client => captureClient;
  @override
  String? get failureReason => reason;
  @override
  bool get connected => captureRelay.state == RelayState.paired;
  @override
  Future<void> reconnect({void Function(String)? onLog}) async {}
  @override
  Future<void> cancelRecovery() async {}
}

void main() {
  testWidgets(
      'review captures connection states with preserved real Flutter content',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('com.llfbandit.record/messages'),
            (_) async => null);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = ClientPreferences();
    final composers = ComposerStore();
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-capture&hash=synthetic&t=1',
        label: '验收电脑');
    final bridge = FeatureBridge();
    final deviceSession = _CaptureSession(device.params!, bridge);
    final sessions =
        FakeAppSessions(store: store, sessionFactory: (_) => deviceSession);
    final monitor = await sessions
        .openWorkspace(device, 'workspace', {'workspaceIdentity': 'workspace'});
    final state = ConversationState();
    seedConversation(state, count: 4);
    bridge.conversationTransport.states['task'] = state;
    final composer = composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: device.id,
        workspaceKey: 'workspace',
        sessionId: 'task');
    composer.input.text = '断线时保留这段草稿，不自动发送';
    final boundary = GlobalKey();
    final captureDir = Platform.environment['ZCODE_UI_CAPTURE_DIR'];
    if (captureDir != null) {
      await tester.runAsync(() async {
        for (final entry in {
          'ReviewFont': 'C:/Windows/Fonts/msyh.ttc',
          'monospace': 'C:/Windows/Fonts/consola.ttf',
          'MaterialIcons':
              'D:/SoftWare/Develop/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf'
        }.entries) {
          final bytes = await File(entry.value).readAsBytes();
          await (FontLoader(entry.key)
                ..addFont(Future.value(ByteData.sublistView(bytes))))
              .load();
        }
      });
    }
    Widget app(Widget page) => RepaintBoundary(
        key: boundary,
        child: ZcodeRemoteApp(
            preferences: prefs,
            home: Builder(builder: (context) {
              final theme = Theme.of(context);
              return Theme(
                  data: theme.copyWith(
                      textTheme: theme.textTheme.apply(
                          fontFamily: captureDir == null ? null : 'ReviewFont',
                          fontFamilyFallback:
                              captureDir == null ? null : const ['ReviewFont']),
                      primaryTextTheme: theme.primaryTextTheme.apply(
                          fontFamily: captureDir == null ? null : 'ReviewFont',
                          fontFamilyFallback:
                              captureDir == null ? null : const ['ReviewFont']),
                      appBarTheme: theme.appBarTheme.copyWith(
                          titleTextStyle: TextStyle(
                              fontFamily:
                                  captureDir == null ? null : 'ReviewFont',
                              fontSize: 20,
                              color: theme.colorScheme.onSurface))),
                  child: page);
            })));
    Widget chat() => ChatPage(
        session: bridge,
        deviceSession: deviceSession,
        onPairAgain: () async {},
        scope: const {'workspaceIdentity': 'workspace'},
        workspaceKey: 'workspace',
        sessionId: 'task',
        title: '连接恢复独立验收',
        deviceId: device.id,
        composerStore: composers);
    Future<void> capture(String name) async {
      expect(tester.takeException(), isNull, reason: name);
      if (captureDir == null) return;
      await tester.runAsync(() async {
        final render = boundary.currentContext!.findRenderObject()
            as RenderRepaintBoundary;
        final image = await render.toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(captureDir).create(recursive: true);
        await File('$captureDir/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final variant in [
      (390.0, ThemeMode.light, 'zh', 1.0),
      (1180.0, ThemeMode.light, 'zh', 1.0),
      (390.0, ThemeMode.dark, 'en', 1.4),
      (1180.0, ThemeMode.dark, 'en', 1.4)
    ]) {
      final (width, theme, language, scale) = variant;
      await prefs.setTheme(theme);
      await prefs.setLanguage(language);
      await prefs.setTextScale(scale);
      tester.view.physicalSize = Size(width, 820);
      final prefix =
          '${width.toInt()}-${theme.name}-$language-${(scale * 100).toInt()}';
      bridge.degraded.value = null;
      deviceSession.reason = null;
      await tester.pumpWidget(app(chat()));
      await tester.pumpAndSettle();
      expect(
          find.byKey(const ValueKey('connection-status-banner')), findsNothing);
      await capture('chat-$prefix-healthy');
      bridge.degraded.value = 'reconnecting';
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          find.byKey(const ValueKey('connection-status-banner')).hitTestable(),
          findsOneWidget);
      expect(composer.canSend, isFalse);
      expect(composer.input.text, '断线时保留这段草稿，不自动发送');
      await capture('chat-$prefix-interrupted');
      if (width == 390 && language == 'zh') {
        bridge.degraded.value = 'reopen-failed: synthetic unavailable';
        await tester.pump(const Duration(milliseconds: 100));
        await capture('chat-$prefix-failed');
        deviceSession.reason = 'session-expired';
        bridge.degraded.value = 'credentials-invalid';
        await tester.pump(const Duration(milliseconds: 100));
        await capture('chat-$prefix-pair-again');
      }
      deviceSession.reason = null;
      bridge.degraded.value = null;
      seedConversation(state, count: 4);
      await tester.pumpWidget(app(SettingsCenterPage(
          preferences: prefs,
          sessions: sessions,
          remoteMonitor: monitor,
          onManageDevices: () {})));
      await tester.pumpAndSettle();
      bridge.degraded.value = 'reconnecting';
      await tester.pump(const Duration(milliseconds: 100));
      expect(
          find.byKey(const ValueKey('connection-status-banner')).hitTestable(),
          findsOneWidget);
      await capture('settings-$prefix-interrupted');
      await tester.pumpWidget(const SizedBox());
    }
    expect(bridge.conversationTransport.commands, isEmpty);
    composers.dispose();
    sessions.dispose();
    await deviceSession.captureClient.dispose();
    prefs.dispose();
  }, skip: Platform.environment['ZCODE_UI_CAPTURE_DIR'] == null);
}
