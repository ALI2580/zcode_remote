import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import 'package:zcode_remote/ui/composer/composer_toolbar.dart';
import 'package:zcode_remote/ui/voice_model_manager.dart';

import 'fake_workspace.dart';

void main() {
  testWidgets('review: missing model has visible composer recovery without menu overflow',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('zcode-voice-review-')))!;
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('zcode_remote/platform'),
        (call) async => call.method == 'voiceModelsRoot' ? root.path : null);
    messenger.setMockMethodCallHandler(const MethodChannel('com.llfbandit.record/messages'),
        (_) async => null);
    final captureDir = Platform.environment['ZCODE_UI_CAPTURE_DIR'];
    if (captureDir != null) {
      await tester.runAsync(() async {
        for (final font in {
          'VoiceReviewFont': 'C:/Windows/Fonts/msyh.ttc',
          'MaterialIcons': 'D:/SoftWare/Develop/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
        }.entries) {
          final bytes = await File(font.value).readAsBytes();
          await (FontLoader(font.key)..addFont(Future.value(ByteData.sublistView(bytes)))).load();
        }
      });
    }
    final preferences = ClientPreferences();
    await preferences.setLanguage('zh');
    final bridge = FakeBridge();
    final composers = ComposerStore();
    final composer = composers.obtain(transport: bridge.conversationTransport,
        deviceId: 'voice-review', workspaceKey: 'workspace', sessionId: 'task');
    final subscription = await bridge.conversationTransport.subscribe('task');
    composer.bind(subscription.state);
    await composer.loadOptions();
    composer.input.text = '保留原有草稿';
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final boundary = GlobalKey();
    try {
      for (final scenario in [(390.0, 'zh'), (344.0, 'zh'), (390.0, 'en')]) {
        final width = scenario.$1;
        final language = scenario.$2;
        await preferences.setLanguage(language);
        await preferences.setTheme(language == 'en' ? ThemeMode.dark : ThemeMode.light);
        final modelsLabel = language == 'zh' ? '模型管理' : 'Models';
        tester.view.physicalSize = Size(width, 820);
        await preferences.setTextScale(width == 344 ? 1.4 : 1.0);
        await tester.pumpWidget(RepaintBoundary(key: boundary, child: ZcodeRemoteApp(
          preferences: preferences,
          home: Builder(builder: (context) {
            final theme = Theme.of(context);
            return Theme(data: theme.copyWith(textTheme: theme.textTheme.apply(
              fontFamily: captureDir == null ? null : 'VoiceReviewFont')),
              child: Scaffold(body: Column(children: [
                const Expanded(child: Center(child: Text('语音引导验收'))),
                ComposerBar(controller: composer),
              ])));
          }),
        )));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('composer-voice')));
        for (var attempt = 0; attempt < 30; attempt++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
          await tester.pump();
          if (find.byKey(const ValueKey('voice-error')).evaluate().isNotEmpty) break;
        }
        expect(find.byKey(const ValueKey('voice-error')), findsOneWidget);
        expect(find.text(modelsLabel), findsOneWidget);
        if (language == 'en') {
          final errorText = tester.widgetList<Text>(find.descendant(
              of: find.byKey(const ValueKey('voice-error')), matching: find.byType(Text))).first;
          expect(errorText.data?.toLowerCase(), contains('model'),
              reason: 'The visible model recovery message follows the English UI locale.');
        }
        expect(composer.input.text, '保留原有草稿');
        expect(bridge.conversationTransport.sent, isEmpty);
        expect(tester.getSize(find.byType(ComposerToolbar)).height, lessThan(60));
        expect(tester.takeException(), isNull);
        if (captureDir != null) {
          await tester.runAsync(() async {
            final render = boundary.currentContext!.findRenderObject() as RenderRepaintBoundary;
            final rendered = await render.toImage(pixelRatio: 1);
            final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
            await Directory(captureDir).create(recursive: true);
            await File('$captureDir/voice-missing-${width.toInt()}-$language.png').writeAsBytes(data!.buffer.asUint8List());
            rendered.dispose();
          });
        }
        await tester.tap(find.text(modelsLabel));
        await tester.pumpAndSettle();
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
        expect(find.byType(VoiceModelManager), findsOneWidget);
        expect(find.text(language == 'zh' ? '下载' : 'Download'), findsWidgets);
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(VoiceModelManager))).pop();
        await tester.pumpAndSettle();
      }
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      composers.dispose();
      preferences.dispose();
      messenger.setMockMethodCallHandler(const MethodChannel('zcode_remote/platform'), null);
      messenger.setMockMethodCallHandler(const MethodChannel('com.llfbandit.record/messages'), null);
      await tester.runAsync(() => root.delete(recursive: true));
    }
  });
}
