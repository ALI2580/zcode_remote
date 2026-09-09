import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import 'package:zcode_remote/ui/composer/composer_popover.dart';
import 'package:zcode_remote/ui/composer/composer_toolbar.dart';
import 'package:zcode_remote/ui/composer/context_usage.dart';
import 'package:zcode_remote/ui/conversation_viewport.dart';
import 'package:zcode_remote/ui/conversation_work_rows.dart';
import 'fake_workspace.dart';

void main() {
  late FakeBridge bridge;
  late ComposerStore store;
  late ComposerController controller;
  late ClientPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    bridge = FakeBridge();
    store = ComposerStore();
    controller = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'detail-device',
        workspaceKey: 'workspace',
        sessionId: 'task');
    controller
        .bind((await bridge.conversationTransport.subscribe('task')).state);
    await controller.loadOptions();
    prefs = ClientPreferences();
    await prefs.setLanguage('zh');
  });
  tearDown(() {
    store.dispose();
    prefs.dispose();
  });
  Widget app(Widget child) =>
      ZcodeRemoteApp(preferences: prefs, home: Scaffold(body: child));

  test(
      'context usage rejects invalid windows and aggregates official char sources',
      () {
    expect(ContextUsageInfo.parse(null), isNull);
    for (final invalid in [
      {'usedTokens': 2, 'maxTokens': 0},
      {'usedTokens': -1, 'maxTokens': 100},
      {'usedTokens': 0, 'maxTokens': 100},
      {'usedTokens': double.nan, 'maxTokens': 100},
      {'usedTokens': 20, 'maxTokens': double.infinity},
    ]) {
      expect(ContextUsageInfo.parse({'contextWindow': invalid}), isNull);
    }
    final info = ContextUsageInfo.parse({
      'contextWindow': {
        'usedTokens': 120,
        'maxTokens': 100,
        'cache': {'hitRate': .779},
        'breakdown': [
          {'source': 'skills', 'chars': 30},
          {'source': 'messages', 'chars': 20},
          {'source': 'messages', 'chars': 10},
          {'source': 'system_prompt', 'chars': 30},
          {'source': 'tool_prompt', 'chars': -8},
          {'source': 'mcp_tool_schemas', 'chars': double.nan},
        ]
      }
    })!;
    expect(info.ratio, 1);
    expect(info.breakdown.keys, ['messages', 'system_prompt', 'skills']);
    expect(info.breakdown['messages'], 30);
    expect(info.cacheHitRate, isNull);
    expect(
        ContextUsageInfo.parse({
          'contextWindow': {
            'usedTokens': 1,
            'maxTokens': 100,
            'cache': {'hitRate': .78}
          }
        })!
            .cacheHitRate,
        .78);
  });

  test(
      'MCP display metadata wins and name fallback removes duplicated provider prefix',
      () {
    final metadata = ToolRowInfo.fromRow({
      'toolName': 'mcp__old__old_action',
      'display': {
        'kind': 'mcp_tool',
        'serverName': 'plugin:New Server',
        'toolName': 'new_server_get_status',
        'description': 'Status details'
      }
    });
    expect(metadata.family, 'mcp');
    expect(metadata.server, 'New Server');
    expect(metadata.title, 'Get status');
    expect(metadata.description, 'Status details');
    final fallback = ToolRowInfo.fromRow(
        {'toolName': 'Mcp__plugin_service__service_get_status'});
    expect(fallback.server, 'Service');
    expect(fallback.title, 'Get status');
    expect(ToolRowInfo.fromRow({'toolName': 'mcp__ssh-server__ssh_exec'}).title,
        'Ssh exec');
    expect(ToolRowInfo.fromRow({'toolName': 'novel_search_protocol'}).family,
        'unknown');
    expect(
        ToolRowInfo.fromRow({
          'toolName': 'Read',
          'inputText': '{"file_path":"lib/main.dart"}'
        }).title,
        'lib/main.dart');
    expect(ToolRowInfo.fromRow({'toolName': 'Read'}).icon, 'search');
    expect(ToolRowInfo.fromRow({'toolName': 'web_search'}).icon, 'earth');
  });

  testWidgets(
      'reasoning fallback is complete and tool expansion preserves real fields',
      (tester) async {
    await tester.pumpWidget(app(Column(children: [
      const ReasoningRow(row: {'text': '分析内容', 'state': 'complete'}),
      const ReasoningRow(row: {'durationMs': 2400, 'state': 'complete'}),
      const ToolCallRow(row: {
        'rowId': 7,
        'toolName': 'mcp__ssh-server__ssh_exec',
        'status': 'success',
        'inputText': '{"command":"uname"}',
        'output': {'text': 'Linux synthetic'}
      }),
      const ToolCallRow(row: {
        'rowId': 8,
        'toolName': 'unknown_tool',
        'status': 'error',
        'error': {'code': 'test', 'message': 'Synthetic failure'}
      }),
    ])));
    await tester.pumpAndSettle();
    expect(find.text('思考 · 持续了几秒'), findsOneWidget);
    expect(find.text('思考 · 持续了 2 秒'), findsOneWidget);
    expect(find.text('已执行'), findsNothing);
    expect(find.text('MCP · Ssh server · Ssh exec'), findsOneWidget);
    expect(find.text('工具调用 · Unknown tool'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tool-row-7')));
    await tester.pumpAndSettle();
    expect(find.text('Linux synthetic'), findsOneWidget);
    expect(find.textContaining('uname'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('tool-row-8')));
    await tester.pumpAndSettle();
    expect(find.text('Synthetic failure'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'timeline and composer align through both official conversation breakpoints',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    for (final width in [344.0, 863.0, 864.0, 1014.0, 1279.0, 1280.0, 1600.0]) {
      tester.view.physicalSize = Size(width, 700);
      await tester.pumpWidget(app(Column(children: [
        Expanded(
            child: ConversationViewport(
                view: ConversationViewState(),
                ids: const ['body'],
                itemBuilder: (context, i) => const SizedBox(
                    key: ValueKey('reading-column'), height: 40))),
        ComposerBar(controller: controller),
      ])));
      await tester.pumpAndSettle();
      final body = tester.getRect(find.byKey(const ValueKey('reading-column')));
      final input =
          tester.getRect(find.byKey(const ValueKey('composer-surface')));
      expect(input.left, closeTo(body.left, .01), reason: '$width');
      expect(input.right, closeTo(body.right, .01), reason: '$width');
      if (width == 1014) expect(body.width, 864);
      if (width == 1280) expect(body.width, 864);
      expect(tester.takeException(), isNull, reason: '$width');
    }
  });

  testWidgets(
      'full access follows official localization and each theme warning color',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1000, 700);
    addTearDown(tester.view.reset);
    await tester.runAsync(() => controller.selectMode('yolo'));
    for (final theme in [ThemeMode.light, ThemeMode.dark]) {
      await tester.runAsync(() => prefs.setTheme(theme));
      await tester.pumpWidget(app(Center(
          child: SizedBox(
              width: 800,
              child: ComposerToolbar(controller: controller, onSend: () {})))));
      await tester.pumpAndSettle();
      final label = tester
          .widget<Text>(find.byKey(const ValueKey('composer-mode-label')));
      expect(label.data, '完全访问');
      expect(
          label.style!.color,
          theme == ThemeMode.dark
              ? const Color(0xFFFF8A30)
              : const Color(0xFFE07B00));
      expect(tester.getSize(find.byKey(const ValueKey('composer-submit'))),
          const Size(28, 28));
      expect(tester.getSize(find.byKey(const ValueKey('composer-mode'))).height,
          28);
    }
  });

  testWidgets('context precision and total progress match the official popup',
      (tester) async {
    ContextUsageInfo info({List<Map<String, dynamic>> breakdown = const []}) =>
        ContextUsageInfo.parse({
          'contextWindow': {
            'usedTokens': 140794,
            'maxTokens': 1000000,
            'cache': {'hitRate': .938},
            'breakdown': breakdown
          }
        })!;
    await tester.pumpWidget(app(Center(
        child:
            SizedBox(width: 320, child: ContextUsageDetails(info: info())))));
    await tester.pumpAndSettle();
    expect(find.text('14.1万/100万 (14.1%)'), findsOneWidget);
    expect(find.text('93.8%'), findsOneWidget);
    final total = tester
        .getSize(find.byKey(const ValueKey('context-total-progress')))
        .width;
    expect(
        tester
            .getSize(find.byKey(const ValueKey('context-used-progress')))
            .width,
        closeTo(total * .140794, .001));
    expect(find.byType(Divider), findsNothing);
    expect(find.textContaining('提示词、工具调用'), findsNothing);
    await tester.pumpWidget(app(Center(
        child: SizedBox(
            width: 320,
            child: ContextUsageDetails(
                info: info(breakdown: [
              {'source': 'messages', 'chars': 100},
              {'source': 'skills', 'chars': 50}
            ]))))));
    await tester.pumpAndSettle();
    expect(find.text('66.7%'), findsOneWidget);
    expect(find.text('33.3%'), findsOneWidget);
    expect(
        tester
            .getSize(find.byKey(const ValueKey('context-used-progress')))
            .width,
        closeTo(total * .140794, .001));
    expect(find.byType(Divider), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'usage opens on touch down, refreshes, fits large text and never writes remote config',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(344, 600);
    addTearDown(tester.view.reset);
    await tester.runAsync(() => prefs.setTextScale(1.4));
    controller.state!.optimisticPatch({
      'usage': {
        'contextWindow': {
          'usedTokens': 40000,
          'maxTokens': 128000,
          'cache': {'hitRate': .8},
          'breakdown': [
            {'source': 'messages', 'chars': 80},
            {'source': 'skills', 'chars': 20}
          ]
        }
      }
    });
    await tester.pumpWidget(app(Column(
        children: [const Spacer(), ComposerBar(controller: controller)])));
    await tester.pumpAndSettle();
    final trigger =
        tester.getRect(find.byKey(const ValueKey('composer-context-usage')));
    final gesture = await tester.startGesture(trigger.center);
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const ValueKey('composer-popover')));
    expect(rect.bottom, closeTo(trigger.top - 2, .01));
    expect(rect.left, greaterThanOrEqualTo(8));
    expect(rect.right, lessThanOrEqualTo(336));
    expect(find.text('平均缓存命中率'), findsOneWidget);
    expect(find.textContaining('4万/13万 (31.3%)'), findsOneWidget);
    await gesture.up();
    controller.state!.optimisticPatch({
      'usage': {
        'contextWindow': {'usedTokens': 64000, 'maxTokens': 128000}
      }
    });
    await tester.pumpAndSettle();
    expect(find.textContaining('6.4万/13万 (50%)'), findsOneWidget);
    expect(find.text('平均缓存命中率'), findsNothing);
    expect(bridge.conversationTransport.commands, isEmpty);
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(4, 50));
    await tester.pumpAndSettle();
  });

  testWidgets(
      'composer popover flips below top trigger and stays out of keyboard',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(344, 650);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app(MediaQuery(
        data: const MediaQueryData(
            padding: EdgeInsets.only(top: 24),
            viewInsets: EdgeInsets.only(bottom: 200)),
        child: Align(
            alignment: Alignment.topRight,
            child: Padding(
                padding: const EdgeInsets.only(top: 30),
                child: Builder(
                    builder: (context) => TextButton(
                        key: const ValueKey('top-trigger'),
                        onPressed: () => showComposerPopover<void>(context,
                            width: 320,
                            child: const SizedBox(
                                height: 190, child: Text('Measured content'))),
                        child: const Text('Open'))))))));
    await tester.pumpAndSettle();
    final trigger = tester.getRect(find.byKey(const ValueKey('top-trigger')));
    await tester.tap(find.byKey(const ValueKey('top-trigger')));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const ValueKey('composer-popover')));
    expect(rect.top, closeTo(trigger.bottom + 4, .01));
    expect(rect.bottom, lessThanOrEqualTo(442));
    expect(rect.right, lessThanOrEqualTo(336));
    expect(tester.takeException(), isNull);
    await tester.tapAt(const Offset(4, 500));
    await tester.pumpAndSettle();
  });
}
