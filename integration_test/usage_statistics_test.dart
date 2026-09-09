import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/usage_statistics.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import 'package:zcode_remote/ui/usage/usage_page.dart';
import 'package:zcode_remote/ui/usage/usage_charts.dart';
import '../test/ui/fake_features.dart';
import '../test/ui/fake_workspace.dart';
import '../test/ui/usage_fixtures.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
      'native More opens complete statistics, range, detail, theme and return',
      (tester) async {
    final environment = await const MethodChannel('zcode_remote/attachments')
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa');
    final zone = await usageTimeZone();
    expect(zone, 'Asia/Shanghai');
    final bridge = FeatureBridge(), store = ComposerStore();
    final controller = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'synthetic-stats',
        workspaceKey: 'usage',
        sessionId: 'task');
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    await prefs.setTheme(ThemeMode.light);
    await prefs.setTextScale(1);
    bridge.channels.handler = (_, method, args) {
      if (method == 'requestCodingPlanResetOpportunity') {
        return {'granted': false};
      }
      if (method == 'getCodingPlanResetStatus') {
        return {
          'availableFiveHourResets': [],
          'availableWeekResets': [],
          'hasUnreadHistory': false
        };
      }
      if (method == 'getAppUsageSnapshot' ||
          method == 'getCodingPlanUsageSnapshot') {
        final query = args.single as Map;
        return statisticsFixture(query['range'],
            application: method == 'getAppUsageSnapshot', timeZone: zone);
      }
      throw StateError('unexpected synthetic statistics operation');
    };
    final state = ConversationState()
      ..applyFrame({
        'payload': {
          'kind': 'snapshot',
          'snapshot': {
            ...composerSnapshotFixture,
            'config': {
              ...(composerSnapshotFixture['config'] as Map),
              'provider': 'builtin:bigmodel-coding-plan',
              'model': 'GLM-5.2'
            },
            'usage': {
              'contextWindow': {
                'usedTokens': 140794,
                'maxTokens': 1000000,
                'cache': {'hitRate': .938}
              }
            },
          }
        },
        'toSeq': 1
      }, onGap: () {});
    controller.bind(state);
    await controller.usage.refresh();
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ZcodeRemoteApp(
            preferences: prefs,
            home: Scaffold(
                appBar: AppBar(title: const Text('统计 QA · 合成数据')),
                body: Column(children: [
                  const Spacer(),
                  ComposerBar(controller: controller)
                ])))));
    await tester.pumpAndSettle();
    Future<void> capture(String name) async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${environment!['cacheDirectory']}/qa-statistics-$name.png')
          .writeAsBytes(bytes!.buffer
              .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      image.dispose();
    }

    await tester.tap(find.byKey(const ValueKey('composer-context-usage')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('quota-more')));
    await tester.pumpAndSettle();
    expect(
        bridge.channels.calls
            .where((c) => c.method.endsWith('UsageSnapshot'))
            .map((c) => (c.args.single as Map)['timeZone']),
        everyElement(zone));
    expect(find.byType(UsagePage), findsOneWidget);
    expect(find.text('使用统计'), findsOneWidget);
    await capture('plan');
    final scroll = find.byKey(const ValueKey('usage-page-scroll'));
    await tester.scrollUntilVisible(find.text('近 30 天'), 500,
        scrollable: find
            .descendant(of: scroll, matching: find.byType(Scrollable))
            .first);
    await tester.tap(find.text('近 30 天'));
    await tester.pumpAndSettle();
    expect(
        bridge.channels.calls.any((c) =>
            c.method == 'getCodingPlanUsageSnapshot' &&
            (c.args.single as Map)['range'] == '30d'),
        isTrue);
    final bars = find.byType(UsageChart).first;
    await tester.ensureVisible(bars);
    await tester.pumpAndSettle();
    await tester.tapAt(tester.getCenter(
        find.descendant(of: bars, matching: find.byType(CustomPaint)).first));
    await tester.pumpAndSettle();
    expect(find.textContaining('GLM-5.1:'), findsWidgets);
    await capture('trends');
    final position = tester
        .state<ScrollableState>(find
            .descendant(of: scroll, matching: find.byType(Scrollable))
            .first)
        .position;
    position.jumpTo(0);
    await tester.pumpAndSettle();
    await tester.tap(find.text('应用统计'));
    await tester.pumpAndSettle();
    await capture('application');
    expect(
        bridge.channels.calls.any((c) =>
            c.method == 'getAppUsageSnapshot' &&
            (c.args.single as Map)['range'] == 'all'),
        isTrue);
    expect(
        bridge.channels.calls.any((c) =>
            c.method == 'getAppUsageSnapshot' &&
            (c.args.single as Map)['range'] == '7d'),
        isTrue);
    expect(
        bridge.channels.calls.any((c) =>
            c.method == 'getAppUsageSnapshot' &&
            (c.args.single as Map)['range'] == '30d'),
        isFalse);
    await prefs.setLanguage('en');
    await prefs.setTheme(ThemeMode.dark);
    await prefs.setTextScale(1.4);
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
        find.byKey(const ValueKey('usage-page-refresh')), 600,
        scrollable: find
            .descendant(of: scroll, matching: find.byType(Scrollable))
            .first);
    await tester.pumpAndSettle();
    await capture('large');
    expect(tester.takeException(), isNull);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.byType(UsagePage), findsNothing);
    expect(
        find.byKey(const ValueKey('composer-context-usage')), findsOneWidget);
    expect(bridge.conversationTransport.commands, isEmpty);
    expect(bridge.conversationTransport.sent, isEmpty);
    expect(
        bridge.channels.calls.every((c) =>
            c.method.startsWith('get') ||
            c.method == 'requestCodingPlanResetOpportunity'),
        isTrue);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
    prefs.dispose();
    bridge.channels.dispose();
    debugPrint(
        'QA statistics: native IANA zone, More navigation, 30-day plan, chart detail, all-time application data, dark/140% and return passed; synthetic service only.');
  });
}
