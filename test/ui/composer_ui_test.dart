import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import 'package:zcode_remote/ui/composer/composer_toolbar.dart';
import 'package:zcode_remote/ui/theme.dart';
import 'fake_workspace.dart';

void main() {
  late FakeBridge bridge;
  late ComposerStore store;
  late ComposerController controller;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    bridge = FakeBridge();
    store = ComposerStore();
    controller = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace',
        sessionId: 'task');
    final subscription = await bridge.conversationTransport.subscribe('task');
    controller.bind(subscription.state);
    await controller.loadOptions();
  });
  tearDown(() {
    store.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
  Widget editor() => MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
          body: Column(children: [
        const Spacer(),
        ComposerBar(controller: controller)
      ])));

  test(
      'thought meter follows official rank when remote options arrive descending',
      () {
    expect(thoughtFraction(['max', 'high', 'nothink'], 'max'), 1);
    expect(thoughtFraction(['max', 'high', 'nothink'], 'high'), .5);
    expect(thoughtFraction(['max', 'high', 'nothink'], 'nothink'), 0);
  });

  testWidgets(
      'surface padding does not move the official composer region breakpoints',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1300, 900);
    addTearDown(tester.view.reset);
    for (final regionWidth in [383.0, 384.0, 575.0, 576.0, 671.0, 672.0]) {
      await tester.pumpWidget(MaterialApp(
          theme: ZInkTheme.light(),
          home: Scaffold(
              body: Center(
                  child: SizedBox(
                      width: regionWidth + 32,
                      child: ComposerBar(controller: controller))))));
      await tester.pumpAndSettle();
      expect(
          tester.getSize(find.byKey(const ValueKey('composer-surface'))).width,
          regionWidth);
      expect(tester.getSize(find.byType(ComposerToolbar)).width,
          lessThan(regionWidth));
      expect(find.byKey(const ValueKey('composer-model-label')),
          regionWidth >= 384 ? findsOneWidget : findsNothing);
      expect(find.byKey(const ValueKey('composer-mode-label')),
          regionWidth >= 576 ? findsOneWidget : findsNothing);
      expect(
          find.byKey(const ValueKey('composer-thought-meter')),
          regionWidth >= 384 && regionWidth < 576
              ? findsOneWidget
              : findsNothing);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'container 384/576/672 breakpoints are independent of viewport and text scale',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1300, 900);
    addTearDown(tester.view.reset);
    await controller.selectModel('custom:provider-b:second-model');
    for (final dark in [false, true]) {
      for (final scale in [1.0, 1.4]) {
        for (final width in [
          240.0,
          343.0,
          383.0,
          384.0,
          575.0,
          576.0,
          671.0,
          672.0,
          800.0
        ]) {
          await tester.pumpWidget(MaterialApp(
              theme: dark ? ZInkTheme.dark() : ZInkTheme.light(),
              home: Scaffold(
                  body: Center(
                      child: MediaQuery(
                          data: MediaQueryData(
                              textScaler: TextScaler.linear(scale)),
                          child: SizedBox(
                              width: width,
                              child: ComposerToolbar(
                                  controller: controller, onSend: () {})))))));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '$dark $scale $width');
          expect(find.byKey(const ValueKey('composer-model-label')),
              width >= 384 ? findsOneWidget : findsNothing);
          expect(find.byKey(const ValueKey('composer-model-icon')),
              width < 384 ? findsOneWidget : findsNothing);
          expect(find.byKey(const ValueKey('composer-mode-label')),
              width >= 576 ? findsOneWidget : findsNothing);
          expect(find.byKey(const ValueKey('composer-thought-label')),
              width >= 576 ? findsOneWidget : findsNothing);
          expect(find.byKey(const ValueKey('composer-thought-meter')),
              width >= 384 && width < 576 ? findsOneWidget : findsNothing);
          if (width >= 384) {
            final label = tester
                .widget<Text>(
                    find.byKey(const ValueKey('composer-model-label')))
                .data!;
            expect(label.startsWith('Provider B/'), width >= 672);
          }
        }
      }
    }
  });

  testWidgets(
      'model/provider, mode and thought menus perform real controller choices',
      (tester) async {
    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-model')));
    await tester.pumpAndSettle();
    expect(find.text('Provider B'), findsOneWidget);
    await tester.tap(find.text('Second model'));
    await tester.pumpAndSettle();
    expect(controller.config['model'], 'second-model');
    await tester.tap(find.byKey(const ValueKey('composer-mode')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Plan mode'));
    await tester.pumpAndSettle();
    expect(controller.config['mode'], 'plan');
    await tester.tap(find.byKey(const ValueKey('composer-thought')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Off'));
    await tester.pumpAndSettle();
    expect(controller.config['thought'], 'off');
    expect(bridge.conversationTransport.commands.map((e) => e.type),
        ['switchModelConfig', 'switchCollaborationMode', 'switchModelConfig']);
  });

  testWidgets('Android IME confirm and multiline actions never send messages',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    await tester.showKeyboard(find.byType(TextField));
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'zhong',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5)));
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '中文\n下一行', selection: TextSelection.collapsed(offset: 6)));
    await tester.testTextInput.receiveAction(TextInputAction.newline);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(bridge.conversationTransport.sent, isEmpty);
    expect(controller.input.text, contains('\n'));
    await tester.tap(find.byKey(const ValueKey('composer-submit')));
    await tester.pumpAndSettle();
    expect(bridge.conversationTransport.sent, ['中文\n下一行']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'desktop Enter submits, Shift Enter inserts newline and IME commit is guarded',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'line');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    expect(bridge.conversationTransport.sent, isEmpty);
    expect(controller.input.text, 'line\n');
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: 'zhong',
        selection: TextSelection.collapsed(offset: 5),
        composing: TextRange(start: 0, end: 5)));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(bridge.conversationTransport.sent, isEmpty);
    tester.testTextInput.updateEditingValue(const TextEditingValue(
        text: '中文', selection: TextSelection.collapsed(offset: 2)));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(bridge.conversationTransport.sent, isEmpty);
    await tester.pump(const Duration(milliseconds: 160));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(bridge.conversationTransport.sent, ['中文']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'configuration pending state and rejected response remain visible',
      (tester) async {
    final gate = Completer<dynamic>();
    bridge.conversationTransport.commandHandler =
        (sid, type, payload) => gate.future;
    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    final selection = controller.selectThought('high');
    await tester.pump();
    expect(find.text('Applying configuration…'), findsOneWidget);
    gate.complete({'status': 'rejected'});
    await selection;
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-error')), findsOneWidget);
    expect(controller.config['thought'], 'max');
  });

  testWidgets(
      'held queue confirmation cancels without send, keep sends expected item ids',
      (tester) async {
    controller.state!.optimisticPatch({
      'inputRouting': {'mode': 'choice'},
      'queue': {
        'autoDrain': false,
        'items': [
          {
            'queueItemId': 'q1',
            'text': 'queued',
            'dispatch': {'state': 'queued'}
          }
        ]
      }
    });
    await tester.pumpWidget(editor());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'next');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Queued messages'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(bridge.conversationTransport.commands, isEmpty);
    expect(controller.input.text, 'next');
    await tester.tap(find.byKey(const ValueKey('composer-submit')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep and send'));
    await tester.pumpAndSettle();
    expect(
        bridge.conversationTransport.commands.single
            .payload['expectedHeldQueueItemIds'],
        ['q1']);
    expect(controller.input.text, isEmpty);
  });

  testWidgets(
      'queue and composer fit all five shapes in English 140 percent and both themes',
      (tester) async {
    final prefs = ClientPreferences();
    await prefs.setLanguage('en');
    await prefs.setTextScale(1.4);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller.state!.optimisticPatch({
      'control': {'phase': 'running', 'canStop': true},
      'inputRouting': {'mode': 'enqueue'},
      'queue': {
        'autoDrain': true,
        'items': [
          {
            'queueItemId': 'q1',
            'text':
                'Check the long queued message across narrow and wide layouts',
            'dispatch': {'state': 'queued'}
          },
        ]
      }
    });
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      await prefs.setTheme(theme);
      for (final width in [344.0, 390.0, 720.0, 834.0, 1180.0]) {
        tester.view.physicalSize = Size(width, 820);
        await tester.pumpWidget(ZcodeRemoteApp(
            preferences: prefs,
            home: Scaffold(
                body: Column(children: [
              const Spacer(),
              ComposerBar(controller: controller)
            ]))));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('Working · Messages will be queued'), findsOneWidget);
        expect(find.byTooltip('Stop'), findsOneWidget);
      }
    }
    await tester.pumpWidget(const SizedBox.shrink());
    prefs.dispose();
  });

  testWidgets(
      'created session binds once and a reopened route uses promoted editor',
      (tester) async {
    final draftStore = ComposerStore();
    final ids = <String>[];
    Widget page(String? id) => ZcodeRemoteApp(
        home: ChatPage(
            key: ValueKey(id),
            session: bridge,
            scope: const {},
            workspaceKey: 'workspace',
            deviceId: 'A',
            sessionId: id,
            title: 'Draft',
            composerStore: draftStore,
            onSessionCreated: ids.add));
    await tester.pumpWidget(page(null));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'first');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('composer-submit')));
    await tester.pumpAndSettle();
    expect(ids, ['created-task']);
    expect(bridge.conversationTransport.subscriptions['created-task'], 1);
    expect(
        bridge.conversationTransport.commands
            .where((e) => e.type == 'createSession'),
        hasLength(1));
    expect(bridge.conversationTransport.sent, isEmpty);
    await tester.enterText(find.byType(TextField), 'next draft');
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(page('created-task'));
    await tester.pumpAndSettle();
    expect(find.text('next draft'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    draftStore.dispose();
  });
}
