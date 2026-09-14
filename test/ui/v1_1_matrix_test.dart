import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/shell/shell_layout.dart';
import 'fake_workspace.dart';

/// V1.1 review matrix. PNGs are only written when ZCODE_UI_CAPTURE_DIR is set;
/// every run still pumps the full real-widget matrix and asserts no exception.
void main() {
  testWidgets(
      'final shell covers the base matrix plus keyboard and required states',
      (tester) async {
    final disableShadows = debugDisableShadows;
    debugDisableShadows = false;
    try {
      SharedPreferences.setMockInitialValues({});
      final captureDir = Platform.environment['ZCODE_UI_CAPTURE_DIR'];
      final fontPath = Platform.environment['ZCODE_TEST_FONT'];
      if (fontPath != null) {
        await tester.runAsync(() async {
          final bytes = await File(fontPath).readAsBytes();
          await (FontLoader('V1Preview')
                ..addFont(Future.value(ByteData.sublistView(bytes))))
              .load();
          for (final entry in {
            'monospace': Platform.environment['ZCODE_TEST_MONO_FONT'],
            'MaterialIcons': Platform.environment['ZCODE_TEST_ICON_FONT'],
          }.entries) {
            if (entry.value == null) continue;
            final bytes = await File(entry.value!).readAsBytes();
            await (FontLoader(entry.key)
                  ..addFont(Future.value(ByteData.sublistView(bytes))))
                .load();
          }
        });
      }

      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bridge = FakeBridge();
      final conversation = ConversationState();
      seedConversation(conversation, count: 2);
      conversation.optimisticPatch({
        'usage': {
          'contextWindow': {
            'usedTokens': 40000,
            'maxTokens': 128000,
            'cache': {'hitRate': .84},
            'breakdown': [
              {'source': 'messages', 'chars': 70000},
              {'source': 'system_prompt', 'chars': 20000},
              {'source': 'skills', 'chars': 10000},
            ]
          }
        }
      });
      bridge.conversationTransport.states['task'] = conversation;
      final sideConversation = ConversationState();
      seedConversation(sideConversation, count: 1);
      bridge.conversationTransport.states['side'] = sideConversation;
      final composerStore = ComposerStore();
      final prefs = ClientPreferences();

      final boundary = GlobalKey();
      Widget themed(Widget child) => Builder(builder: (context) {
            final family = fontPath == null ? null : 'V1Preview';
            return Theme(
                data: Theme.of(context).copyWith(
                    textTheme: Theme.of(context).textTheme.apply(
                        fontFamily: family,
                        fontFamilyFallback:
                            family == null ? null : const ['V1Preview']),
                    appBarTheme: Theme.of(context).appBarTheme.copyWith(
                        titleTextStyle: Theme.of(context)
                            .appBarTheme
                            .titleTextStyle
                            ?.copyWith(fontFamily: family))),
                child: child);
          });

      Future<void> capture(String name) async {
        final error = tester.takeException();
        expect(error, isNull,
            reason:
                '$name: ${error is FlutterError ? error.toStringDeep() : error}');
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

      Widget page({String? sessionId, Key? key}) => ChatPage(
          key: key,
          session: bridge,
          scope: const {'workspaceIdentity': 'workspace'},
          workspaceKey: 'workspace',
          sessionId: sessionId,
          title: sessionId == 'side' ? 'Side panel' : 'Final matrix',
          workspaceName: 'ZcodeRemote',
          deviceId: 'matrix-device',
          composerStore: composerStore);

      Widget app(Widget child) => RepaintBoundary(
          key: boundary,
          child: ZcodeRemoteApp(preferences: prefs, home: themed(child)));

      Widget matrixShell({required bool panelOpen}) => WorkspaceShellLayout(
          title: 'Final matrix',
          project: 'ZcodeRemote',
          sidebarCollapsed: false,
          onSidebarCollapsed: (_) {},
          sidebar: const SizedBox.shrink(),
          conversation: page(sessionId: 'task'),
          panel: page(sessionId: 'side'),
          panelOpen: panelOpen);

      // Full base cartesian matrix: five shapes x two themes x two languages
      // x 100/140 percent. Each combo also renders its primary/side panel.
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final language in ['zh', 'en']) {
          for (final scale in [1.0, 1.4]) {
            for (final width in [344.0, 390.0, 720.0, 834.0, 1180.0]) {
              await prefs.setTheme(mode);
              await prefs.setLanguage(language);
              await prefs.setTextScale(scale);
              tester.view.physicalSize = Size(width, 820);
              await tester.pumpWidget(app(matrixShell(panelOpen: false)));
              await tester.pumpAndSettle();
              await capture(
                  'v1-base-${mode.name}-$language-${scale.toStringAsFixed(1)}-$width');
              await tester.pumpWidget(app(matrixShell(panelOpen: true)));
              await tester.pumpAndSettle();
              await capture(
                  'v1-panel-${mode.name}-$language-${scale.toStringAsFixed(1)}-$width');
            }
          }
        }
      }

      // Keyboard insets are covered on the two critical endpoints for each
      // theme/language/scale combination.
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final language in ['zh', 'en']) {
          for (final scale in [1.0, 1.4]) {
            for (final width in [344.0, 1180.0]) {
              await prefs.setTheme(mode);
              await prefs.setLanguage(language);
              await prefs.setTextScale(scale);
              tester.view.physicalSize = Size(width, 820);
              await tester.pumpWidget(MediaQuery(
                  data: MediaQueryData(
                      textScaler: TextScaler.linear(scale),
                      viewInsets: const EdgeInsets.only(bottom: 220)),
                  child: app(matrixShell(panelOpen: true))));
              await tester.pumpAndSettle();
              final composer = tester.getRect(find.byType(TextField).first);
              expect(composer.bottom, lessThanOrEqualTo(600),
                  reason: '$mode/$language/$scale/$width keyboard inset');
              await capture(
                  'v1-keyboard-${mode.name}-$language-${scale.toStringAsFixed(1)}-$width');
            }
          }
        }
      }

      // Required non-content states on the small and large endpoints.
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        for (final language in ['zh', 'en']) {
          for (final scale in [1.0, 1.4]) {
            for (final width in [344.0, 1180.0]) {
              await prefs.setTheme(mode);
              await prefs.setLanguage(language);
              await prefs.setTextScale(scale);
              tester.view.physicalSize = Size(width, 820);

              await tester.pumpWidget(app(page(
                  sessionId: null,
                  key: ValueKey('empty-$language-$scale-$width'))));
              await tester.pumpAndSettle();
              await capture(
                  'v1-empty-${mode.name}-$language-${scale.toStringAsFixed(1)}-$width');

              final loading = Completer<void>();
              bridge.conversationTransport.subscribeHandler = (sessionId) =>
                  loading.future.then(
                      (_) => bridge.conversationTransport.subscribe(sessionId));
              final loadingSession = 'loading-$language-$scale-$width';
              await tester.pumpWidget(app(page(
                  sessionId: loadingSession, key: ValueKey(loadingSession))));
              await tester.pump(const Duration(milliseconds: 50));
              await capture(
                  'v1-loading-${mode.name}-$language-${scale.toStringAsFixed(1)}-$width');

              bridge.conversationTransport.subscribeHandler = (sessionId) {
                return Future.error(
                    StateError('synthetic conversation load failed'));
              };
              final errorSession = 'error-$language-$scale-$width';
              await tester.pumpWidget(app(
                  page(sessionId: errorSession, key: ValueKey(errorSession))));
              await tester.pump(const Duration(seconds: 1));
              await tester.pumpAndSettle();
              expect(find.text('无法加载会话'), findsOneWidget);
              await capture(
                  'v1-error-${mode.name}-$language-${scale.toStringAsFixed(1)}-$width');
              bridge.conversationTransport.subscribeHandler = null;
              loading.complete();
              await tester.pump();
            }
          }
        }
      }

      expect(bridge.conversationTransport.sent, isEmpty);
      expect(bridge.conversationTransport.commands, isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
      composerStore.dispose();
      prefs.dispose();
    } finally {
      debugDisableShadows = disableShadows;
    }
  }, timeout: const Timeout(Duration(minutes: 6)));
}
