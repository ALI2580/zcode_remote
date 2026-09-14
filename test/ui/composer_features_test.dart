import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/composer_input.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import 'package:zcode_remote/ui/composer/quota_section.dart';
import 'package:zcode_remote/ui/shell/shell_layout.dart';
import 'package:zcode_remote/ui/theme.dart';
import 'package:zcode_remote/ui/usage/usage_page.dart';
import 'fake_features.dart';
import 'usage_fixtures.dart';
import 'fake_workspace.dart';

void snapState(ConversationState state, Map<String, dynamic> patch) {
  state.applyFrame({
    'toSeq': state.seq + 1,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {...composerSnapshotFixture, ...patch}
    }
  }, onGap: () => fail('unexpected gap'));
}

void main() {
  late FeatureBridge bridge;
  late ComposerStore store;
  late ComposerController controller;
  late ClientPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    bridge = FeatureBridge();
    store = ComposerStore();
    controller = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'synthetic-A',
        workspaceKey: 'workspace');
    await controller.loadOptions();
    prefs = ClientPreferences();
    await prefs.setLanguage('zh');
  });
  tearDown(() {
    store.dispose();
    prefs.dispose();
  });
  Widget app() => ZcodeRemoteApp(
      preferences: prefs,
      home: Scaffold(
          body: Column(children: [
        const Spacer(),
        ComposerBar(controller: controller)
      ])));

  testWidgets(
      'More route starts shared quota reads after building and returns cleanly',
      (tester) async {
    const channel = MethodChannel('zcode_remote/platform');
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'Asia/Shanghai');
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    bridge.channels.handler = (_, method, args) =>
        method == 'getCodingPlanResetStatus'
            ? {
                'availableFiveHourResets': [],
                'availableWeekResets': [],
                'hasUnreadHistory': false
              }
            : statisticsFixture((args.single as Map)['range'],
                application: method == 'getAppUsageSnapshot');
    await controller.selectModel('builtin:bigmodel-coding-plan/GLM-5.2');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-context-usage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quota-more')));
    await tester.pumpAndSettle();
    expect(find.byType(UsagePage), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(UsagePage), findsNothing);
    expect(
        find.byKey(const ValueKey('composer-context-usage')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an open popover updates theme and keyboard safe area',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    await tester.runAsync(() => prefs.setTheme(ThemeMode.light));
    await controller.selectModel('builtin:bigmodel-coding-plan/GLM-5.2');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-context-usage')));
    await tester.pumpAndSettle();
    final popover = find.byKey(const ValueKey('composer-popover'));
    expect(tester.widget<Material>(popover).color, const LightInk().card);
    await tester.runAsync(() => prefs.setTheme(ThemeMode.dark));
    await tester.pumpAndSettle();
    expect(tester.widget<Material>(popover).color, const DarkInk().card);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pumpAndSettle();
    expect(tester.getRect(popover).bottom, lessThanOrEqualTo(520));
    expect(tester.takeException(), isNull);
  });

  testWidgets('new task shows plan without context and MCP stays independent',
      (tester) async {
    await controller.selectModel('builtin:bigmodel-coding-plan/GLM-5.2');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(controller.state, isNull);
    await tester.tap(find.byKey(const ValueKey('composer-context-usage')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('quota-fiveHour')), findsOneWidget);
    expect(find.byKey(const ValueKey('quota-weekly')), findsOneWidget);
    expect(find.byKey(const ValueKey('quota-toolCalls')), findsOneWidget);
    expect(find.byKey(const ValueKey('quota-mcp')), findsOneWidget);
    final mcp = tester.getRect(find.byKey(const ValueKey('quota-mcp')));
    final first = tester.getRect(find.byKey(const ValueKey('quota-fiveHour')));
    expect(mcp.top, greaterThan(first.bottom));
    expect(mcp.width, greaterThan(first.width));
    final resetDate =
        DateTime.fromMillisecondsSinceEpoch(1790080000000).toLocal();
    expect(
        find.textContaining('${resetDate.month}月${resetDate.day}日',
            findRichText: true),
        findsOneWidget);
    expect(find.textContaining('上下文容量'), findsNothing);
    expect(bridge.conversationTransport.sent, isEmpty);
    expect(bridge.conversationTransport.commands, isEmpty);
  });

  testWidgets('invalid MCP date and missing percent never invent values',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(820, 620);
    addTearDown(tester.view.reset);
    await controller.selectModel('builtin:bigmodel-coding-plan/GLM-5.2');
    bridge.conversationTransport.quotaHandler =
        (provider, org, project) async => {
              'provider': {'id': provider},
              'context': {'scope': 'personal'},
              'quota': {
                'level': 'pro',
                'limits': [
                  {
                    'type': 'TOKENS_LIMIT',
                    'unit': 3,
                    'number': 5,
                    'percentage': 20
                  },
                  {'type': 'TOKENS_LIMIT', 'unit': 6, 'percentage': 30},
                  {
                    'type': 'TIME_LIMIT',
                    'unit': 5,
                    'number': 1,
                    'percentage': 40
                  },
                ]
              },
              'mcpQuota': {
                'aggregate': {
                  'type': 'TIME_LIMIT',
                  'nextResetTime': 'not-a-timestamp'
                }
              },
            };
    await controller.usage.refresh();
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: Scaffold(
            body: Center(
                child: SizedBox(
                    width: 780,
                    child: QuotaSection(usage: controller.usage))))));
    await tester.pumpAndSettle();
    final section = tester.getRect(find.byType(QuotaSection));
    final mcp = tester.getRect(find.byKey(const ValueKey('quota-mcp')));
    final first = tester.getRect(find.byKey(const ValueKey('quota-fiveHour')));
    expect(mcp.width, greaterThan(first.width));
    expect(mcp.left, greaterThanOrEqualTo(section.left));
    expect(mcp.right, lessThanOrEqualTo(section.right));
    expect(find.text('ZCode MCP'), findsOneWidget);
    expect(find.text('--'), findsOneWidget);
    expect(find.textContaining('1970'), findsNothing);
    expect(find.textContaining('100%'), findsNothing);
    expect(
        find.descendant(
            of: find.byKey(const ValueKey('quota-mcp')),
            matching: find.textContaining('0%')),
        findsNothing);
    expect(bridge.conversationTransport.commands, isEmpty);
  });

  testWidgets(
      'unresolved team has an actionable empty state at 140 percent English text',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(344, 780);
    addTearDown(tester.view.reset);
    await tester.runAsync(() async {
      await prefs.setLanguage('en');
      await prefs.setTextScale(1.4);
    });
    bridge.conversationTransport.families['modelProviderFamilySelectedKeys'] = {
      'bigmodel': 'team-plan:builtin:bigmodel-coding-plan:missing:0'
    };
    await controller.selectModel('builtin:bigmodel-coding-plan/GLM-5.2');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-context-usage')));
    await tester.pumpAndSettle();
    expect(find.textContaining('selected team project is unavailable'),
        findsOneWidget);
    expect(find.byKey(const ValueKey('quota-refresh')), findsOneWidget);
    expect(find.byKey(const ValueKey('quota-fiveHour')), findsNothing);
    expect(find.textContaining('0%'), findsNothing);
    expect(bridge.conversationTransport.commands, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('unknown Start balance has no fake percentage or filled bar',
      (tester) async {
    bridge.conversationTransport.quotaHandler =
        (provider, org, project) async => {
              'provider': {'id': provider},
              'quota': {
                'limits': [
                  {'type': 'TOKENS_LIMIT', 'number': 100}
                ]
              }
            };
    await controller.selectModel('builtin:zai-start-plan/GLM-5.2');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-context-usage')));
    await tester.pumpAndSettle();
    expect(find.text('今日余额'), findsOneWidget);
    expect(find.textContaining('0%'), findsNothing);
    expect(tester.widget<QuotaBar>(find.byType(QuotaBar)).percent, isNull);
    expect(find.textContaining('--', findRichText: true), findsOneWidget);
  });

  testWidgets('quota failure is visible with stale data and refresh recovers',
      (tester) async {
    await controller.selectModel('builtin:bigmodel-coding-plan/GLM-5.2');
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-context-usage')));
    await tester.pumpAndSettle();
    bridge.conversationTransport.quotaHandler = (provider, org, project) =>
        Future.error(TimeoutException('synthetic quota timeout'));
    await controller.usage.refresh(force: true);
    await tester.pumpAndSettle();
    expect(find.text('可能网络原因，更新失败'), findsOneWidget);
    expect(find.byKey(const ValueKey('quota-fiveHour')), findsOneWidget);
    bridge.conversationTransport.quotaHandler = null;
    await tester.tap(find.byKey(const ValueKey('quota-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('可能网络原因，更新失败'), findsNothing);
  });

  testWidgets(
      'plus menu resolves references, serializes them and restores focus',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-actions')));
    await tester.pumpAndSettle();
    for (final action in ['file', '@', '/', r'$']) {
      expect(find.byKey(ValueKey('composer-action-$action')), findsOneWidget);
    }
    await tester.tap(find.byKey(const ValueKey('composer-action-@')));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('reference-file:lib/main.dart')));
    await tester.pumpAndSettle();
    expect(controller.input.markdown, '[main.dart](./lib/main.dart) ');
    expect(
        tester
            .widget<EditableText>(find.byType(EditableText))
            .focusNode
            .hasFocus,
        isTrue);
    controller.input.value = const TextEditingValue(
        text: '@main.dart ￥', selection: TextSelection.collapsed(offset: 12));
    await tester.pumpAndSettle();
    await tester
        .tap(find.byKey(const ValueKey('reference-skill:workspace-skill')));
    await tester.pumpAndSettle();
    expect(controller.input.markdown,
        r'[main.dart](./lib/main.dart) [$review-code](./skills/review.md) ');
    expect(bridge.conversationTransport.commands, isEmpty);
  });

  testWidgets('session references expose real scope labels', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    controller.input.value = const TextEditingValue(
        text: '#', selection: TextSelection.collapsed(offset: 1));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('composer-reference-panel')), findsOneWidget);
    await tester
        .tap(find.byKey(const ValueKey('reference-session:other-task')));
    await tester.pumpAndSettle();
    expect(controller.input.text, '#Other task ');
    expect(controller.input.markdown, '[#Other task](#other-task) ');
    expect(controller.input.referenceCount, 1);
  });

  testWidgets('command references expose real scope labels', (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    controller.input.value = const TextEditingValue(
        text: '/', selection: TextSelection.collapsed(offset: 1));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('composer-reference-panel')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('reference-command:plan')));
    await tester.pumpAndSettle();
    expect(controller.input.text, '/plan ');
    expect(controller.input.markdown, '/plan ');
    expect(controller.input.contextReferenceCount, 0);
    expect(bridge.conversationTransport.commands, isEmpty);
  });

  testWidgets('IME composition does not choose references or send the draft',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byType(TextField));
    controller.input.value = const TextEditingValue(
        text: '@测试',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 1, end: 3));
    await tester.pump();
    expect(
        find.byKey(const ValueKey('composer-reference-panel')), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(bridge.conversationTransport.commands, isEmpty);
    expect(controller.input.referenceCount, 0);
    controller.input.value =
        controller.input.value.copyWith(composing: TextRange.empty);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump(const Duration(milliseconds: 160));
    expect(bridge.conversationTransport.commands, isEmpty);
    expect(controller.input.referenceCount, 0);
  });

  testWidgets('composition underline survives beside an existing reference',
      (tester) async {
    controller.input.insertReference(
        const TextRange(start: 0, end: 0),
        const ComposerReference(
            id: 'file',
            category: 'files',
            label: 'main.dart',
            value: 'lib/main.dart'));
    final prefix = controller.input.text;
    controller.input.value = TextEditingValue(
        text: '$prefix中文',
        selection: TextSelection.collapsed(offset: prefix.length + 2),
        composing: TextRange(start: prefix.length, end: prefix.length + 2));
    await tester.pumpWidget(app());
    await tester.pump();
    final span = controller.input.buildTextSpan(
        context: tester.element(find.byType(TextField)), withComposing: true);
    final composing = span.children!
        .whereType<TextSpan>()
        .where((s) => s.style?.decoration == TextDecoration.underline);
    expect(composing.single.text, '中文');
    expect(controller.input.markdown, '[main.dart](./lib/main.dart) 中文');
  });

  testWidgets(
      'Chinese and English large text quota and plus menus fit five form factors',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await controller.selectModel('builtin:bigmodel-coding-plan/GLM-5.2');
    await tester.runAsync(() async {
      await prefs.setTextScale(1.4);
    });
    for (final language in ['zh', 'en']) {
      await tester.runAsync(() => prefs.setLanguage(language));
      for (final theme in [ThemeMode.light, ThemeMode.dark]) {
        await tester.runAsync(() => prefs.setTheme(theme));
        for (final width in [344.0, 390.0, 720.0, 834.0, 1180.0]) {
          tester.view.physicalSize = Size(width, 820);
          await tester.pumpWidget(app());
          await tester.pumpAndSettle();
          await tester
              .tap(find.byKey(const ValueKey('composer-context-usage')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'quota $language $theme $width');
          final rect = tester.getRect(find.byType(QuotaSection));
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          await tester.tapAt(const Offset(4, 90));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('composer-actions')));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull,
              reason: 'plus $language $theme $width');
          await tester.tapAt(const Offset(4, 90));
          await tester.pumpAndSettle();
        }
      }
    }
  });

  testWidgets(
      'references stay inside fold, tablet and panel widths at 140 percent',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await controller.selectModel('builtin:bigmodel-coding-plan/GLM-5.2');
    await tester.runAsync(() => prefs.setTextScale(1.4));
    final sizes = [
      const Size(344.0, 880.0),
      const Size(720.0, 880.0),
      const Size(834.0, 1194.0),
      const Size(1194.0, 834.0),
    ];
    for (final language in ['zh', 'en']) {
      await tester.runAsync(() => prefs.setLanguage(language));
      for (final theme in [ThemeMode.light, ThemeMode.dark]) {
        await tester.runAsync(() => prefs.setTheme(theme));
        for (final size in sizes) {
          tester.view.physicalSize = size;
          controller.input.clear();
          await tester.pumpWidget(ZcodeRemoteApp(
              preferences: prefs,
              home: Scaffold(
                  body: SafeArea(
                      child: SingleChildScrollView(
                          child: ComposerBar(controller: controller))))));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('composer-actions')));
          await tester.pumpAndSettle();
          await tester.tap(find.byKey(const ValueKey('composer-action-@')));
          await tester.pumpAndSettle();
          final panelRect = tester
              .getRect(find.byKey(const ValueKey('composer-reference-panel')));
          expect(panelRect.left, greaterThanOrEqualTo(0),
              reason: '$language $theme $size');
          expect(panelRect.right, lessThanOrEqualTo(size.width),
              reason: '$language $theme $size');
          await tester
              .tap(find.byKey(const ValueKey('reference-file:lib/main.dart')));
          await tester.pumpAndSettle();
          expect(controller.input.markdown, '[main.dart](./lib/main.dart) ');
          final end = controller.input.text.length;
          controller.input.insertReference(
              TextRange(start: end, end: end),
              const ComposerReference(
                  id: 'skill:workspace-skill',
                  category: 'skills',
                  label: 'review-code',
                  value: 'skills/review.md'));
          expect(
              controller.input.markdown,
              r'[main.dart](./lib/main.dart) '
              r'[$review-code](./skills/review.md) ');
          expect(
              tester
                  .widget<EditableText>(find.byType(EditableText))
                  .focusNode
                  .hasFocus,
              isTrue);
          expect(tester.takeException(), isNull,
              reason: '$language $theme $size');
          await tester.pumpWidget(const SizedBox());
        }
      }
    }
  });

  testWidgets('main and side panel composers keep drafts and refs isolated',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await controller.selectModel('builtin:bigmodel-coding-plan/GLM-5.2');
    final side = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'synthetic-A',
        workspaceKey: 'workspace',
        sessionId: 'side');
    await side.loadOptions();
    addTearDown(side.dispose);
    for (final language in ['zh', 'en']) {
      await tester.runAsync(() async {
        await prefs.setLanguage(language);
        await prefs.setTextScale(1.4);
      });
      for (final size in [const Size(1180, 880), const Size(834, 1194)]) {
        controller.input.clear();
        side.input.clear();
        await tester.pumpWidget(ZcodeRemoteApp(
            preferences: prefs,
            home: WorkspaceShellLayout(
                title: 'Main',
                project: 'Project',
                sidebar: const Text('sidebar'),
                sidebarCollapsed: false,
                onSidebarCollapsed: (_) {},
                conversation: ComposerBar(controller: controller),
                panel: ComposerBar(controller: side))));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField).first, 'main-$language');
        await tester.enterText(find.byType(TextField).last, 'side-$language ');
        await tester.pump();
        expect(controller.input.text, 'main-$language');
        expect(side.input.text, 'side-$language ');
        final mainSurface = tester
            .getRect(find.byKey(const ValueKey('composer-surface')).first);
        final sideSurface =
            tester.getRect(find.byKey(const ValueKey('composer-surface')).last);
        expect(mainSurface.width, greaterThanOrEqualTo(320));
        expect(sideSurface.width, greaterThanOrEqualTo(280));
        final end = side.input.text.length;
        side.input.insertReference(
            TextRange(start: end, end: end),
            const ComposerReference(
                id: 'file:lib/main.dart',
                category: 'files',
                label: 'main.dart',
                value: 'lib/main.dart'));
        expect(controller.input.markdown, 'main-$language');
        expect(side.input.markdown,
            'side-$language [main.dart](./lib/main.dart) ');
        expect(tester.takeException(), isNull, reason: '$language $size');
        await tester.pumpWidget(const SizedBox());
      }
    }
  });

  testWidgets(
      'side panel reopen keeps its own config instead of inheriting main',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 880);
    addTearDown(tester.view.reset);
    await controller.selectModel('builtin:bigmodel-coding-plan/GLM-5.2');
    final side = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'synthetic-A',
        workspaceKey: 'workspace',
        sessionId: 'side');
    await side.loadOptions();
    final sideState = ConversationState();
    snapState(sideState, {
      'availability': {
        'switchModelConfig': {'allowed': true}
      }
    });
    side.bind(sideState);
    expect(side.state?.ready, isTrue, reason: 'side state ready');
    expect(side.allowed('switchModelConfig'), isTrue,
        reason: 'switchModelConfig allowed');
    final sideOk = await side.selectModel('custom:provider-b:second-model');
    expect(sideOk, isTrue, reason: 'side selectModel accepted');
    addTearDown(side.dispose);

    Future<void> pump() async {
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: prefs,
          home: WorkspaceShellLayout(
              title: 'Main',
              project: 'Project',
              sidebar: const Text('sidebar'),
              sidebarCollapsed: false,
              onSidebarCollapsed: (_) {},
              conversation: ComposerBar(controller: controller),
              panel: ComposerBar(controller: side))));
      await tester.pumpAndSettle();
    }

    await pump();
    expect(find.textContaining('GLM-5.2'), findsWidgets);
    // Config isolation is authoritative at the controller level: each
    // panel holds its own confirmed model selection.
    expect(side.config['model'], 'second-model');
    expect(controller.config['model'], 'GLM-5.2');
    await tester.pumpWidget(const SizedBox());

    // Reopen: obtaining the panel again keeps its own live controller —
    // the confirmed config stays the side panel's own, never the main
    // panel's selection.
    final reopened = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'synthetic-A',
        workspaceKey: 'workspace',
        sessionId: 'side');
    await reopened.loadOptions();
    addTearDown(reopened.dispose);
    expect(identical(reopened, side), isTrue);
    expect(reopened.config['model'], 'second-model');
    expect(reopened.config['model'], isNot(controller.config['model']));
    await pump();
    expect(find.byType(TextField), findsAtLeast(2));
  });

  testWidgets('side panel queue state stays isolated from the main panel',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 880);
    addTearDown(tester.view.reset);
    final side = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'synthetic-A',
        workspaceKey: 'workspace',
        sessionId: 'side');
    await side.loadOptions();
    final sideState = ConversationState();
    snapState(sideState, {
      'availability': {
        'switchModelConfig': {'allowed': true},
        'queueEdit': {'allowed': true},
      },
      'queue': {
        'autoDrain': false,
        'items': [
          {
            'queueItemId': 'q1',
            'text': 'side queued item',
            'dispatch': {'state': 'queued'}
          },
        ]
      }
    });
    side.bind(sideState);
    addTearDown(side.dispose);

    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: WorkspaceShellLayout(
            title: 'Main',
            project: 'Project',
            sidebar: const Text('sidebar'),
            sidebarCollapsed: false,
            onSidebarCollapsed: (_) {},
            conversation: ComposerBar(controller: controller),
            panel: ComposerBar(controller: side))));
    await tester.pumpAndSettle();

    // The queued item exists only in the side panel's own conversation
    // state; the main panel's controller never sees it.
    expect(side.queue, hasLength(1));
    expect(controller.queue, isEmpty);
    expect(find.textContaining('side queued item'), findsOneWidget);

    // Queue actions route through the side panel's own session id.
    expect(await side.queueAction('setAutoDrain', autoDrain: true), isTrue);
    expect(
        bridge.conversationTransport.commands
            .where((c) => c.type == 'setAutoDrain')
            .map((c) => c.sessionId),
        everyElement('side'));
    expect(controller.queue, isEmpty);
  });

  testWidgets('rotation keeps drafts and panel state across size change',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    controller.input.text = 'rotation draft';
    final side = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'synthetic-A',
        workspaceKey: 'workspace',
        sessionId: 'side');
    await side.loadOptions();
    addTearDown(side.dispose);

    Future<void> pump(Size size, {required bool panelOpen}) async {
      tester.view.physicalSize = size;
      await tester.pumpWidget(ZcodeRemoteApp(
          preferences: prefs,
          home: WorkspaceShellLayout(
              title: 'Main',
              project: 'Project',
              sidebar: const Text('side-col'),
              sidebarCollapsed: false,
              onSidebarCollapsed: (_) {},
              conversation: ComposerBar(controller: controller),
              panel: panelOpen ? ComposerBar(controller: side) : null)));
      await tester.pumpAndSettle();
    }

    // Portrait tablet: panel closed, draft on the main composer.
    await pump(const Size(720, 1280), panelOpen: false);
    expect(find.text('rotation draft'), findsOneWidget);

    // Rotate: panel opens, the draft must survive the size change.
    await pump(const Size(1280, 720), panelOpen: true);
    expect(find.text('rotation draft'), findsOneWidget);

    // Rotate back with the panel closed again: still isolated.
    await pump(const Size(720, 1280), panelOpen: false);
    expect(find.text('rotation draft'), findsOneWidget);
    expect(find.textContaining('GLM-5.2'), findsWidgets);
  });
}
