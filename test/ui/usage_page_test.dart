import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_usage.dart';
import 'package:zcode_remote/state/usage_statistics.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/usage/usage_page.dart';
import 'package:zcode_remote/ui/usage/usage_charts.dart';
import 'fake_features.dart';
import 'usage_fixtures.dart';

void main() {
  late FeatureBridge bridge;
  late ComposerUsage usage;
  late UsageStatistics stats;
  late ClientPreferences prefs;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    bridge = FeatureBridge();
    usage = ComposerUsage(bridge.conversationTransport)
      ..selectProvider('builtin:bigmodel-coding-plan');
    await usage.refresh();
    prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    stats = UsageStatistics(bridge.conversationTransport,
        timeZone: () async => 'Asia/Shanghai');
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
      final query = args.single as Map;
      return statisticsFixture(query['range'],
          application: method == 'getAppUsageSnapshot');
    };
  });
  tearDown(() {
    stats.dispose();
    usage.dispose();
    bridge.channels.dispose();
  });
  Widget app({Widget? child}) => ZcodeRemoteApp(
      preferences: prefs,
      home: child ?? UsagePage(usage: usage, statistics: stats));
  testWidgets(
      'application tab and range fetch their own data, charts expose tapped values',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('活跃度'), findsOneWidget);
    await tester.tap(find.text('应用统计'));
    await tester.pumpAndSettle();
    expect(stats.app.snapshot!.range, '7d');
    expect(stats.lifetime.snapshot!.range, 'all');
    final range = find.text('近 30 天');
    await tester.ensureVisible(range);
    await tester.tap(range);
    await tester.pumpAndSettle();
    expect(stats.app.snapshot!.range, '30d');
    final chart = find.byType(UsageChart).first;
    await tester.ensureVisible(chart);
    await tester.pumpAndSettle();
    final paint =
        find.descendant(of: chart, matching: find.byType(CustomPaint)).first;
    await tester.tapAt(tester.getCenter(paint));
    await tester.pumpAndSettle();
    expect(find.textContaining('GLM-5.1:'), findsOneWidget);
    expect(bridge.channels.calls.any((c) => c.method == 'useCodingPlanReset'),
        isFalse);
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'requestCodingPlanResetOpportunity')
            .length,
        1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'plan model selection stays between one and three and tools has independent plot',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 1300);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final fourth = find.textContaining('GLM-5.4:').first;
    await tester.ensureVisible(fourth);
    await tester.tap(fourth);
    await tester.pumpAndSettle();
    UsageChart bars() => tester
        .widgetList<UsageChart>(find.byType(UsageChart))
        .firstWhere((c) => c.bars);
    expect(bars().plot.series.map((s) => s.name),
        ['GLM-5.2', 'GLM-5.3', 'GLM-5.4']);
    for (final name in ['GLM-5.2:', 'GLM-5.3:', 'GLM-5.4:']) {
      await tester.tap(find.textContaining(name).first);
      await tester.pumpAndSettle();
    }
    expect(bars().plot.series.length, 1);
    await tester.tap(find.text('工具'));
    await tester.pumpAndSettle();
    expect(bars().plot.series.single.name, 'Web search');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'credit cards normalize percent inputs and preserve signed trends at narrow width',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(344, 900);
    addTearDown(tester.view.reset);
    await tester.runAsync(() => prefs.setTextScale(1.4));
    bridge.channels.handler = (_, method, args) {
      if (method == 'getCodingPlanResetStatus') {
        return {
          'availableFiveHourResets': [],
          'availableWeekResets': [],
          'hasUnreadHistory': false
        };
      }
      final result =
          statisticsFixture((args.single as Map)['range'], credits: true);
      (result['detail']['model'] as Map)['cacheHitRate'] = 94;
      return result;
    };
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final scroll = find
        .descendant(
            of: find.byKey(const ValueKey('usage-page-scroll')),
            matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('缓存命中率'), 500,
        scrollable: scroll);
    await tester.pumpAndSettle();
    expect(find.text('94%'), findsOneWidget);
    expect(find.text('-3%'), findsOneWidget);
    expect(find.text('10,000'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
      'five shapes, themes, languages and large text render every section',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final font = Platform.environment['ZCODE_TEST_FONT'],
        capture = Platform.environment['ZCODE_UI_CAPTURE_DIR'];
    if (font != null) {
      await tester.runAsync(() async {
        final bytes = await File(font).readAsBytes();
        await (FontLoader('UsagePreview')
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
        final mono = Platform.environment['ZCODE_TEST_MONO_FONT'];
        if (mono != null) {
          final bytes = await File(mono).readAsBytes();
          await (FontLoader('monospace')
                ..addFont(Future.value(ByteData.sublistView(bytes))))
              .load();
        }
      });
    }
    final boundary = GlobalKey();
    Future<void> snapshot(String name) async {
      expect(tester.takeException(), isNull, reason: name);
      if (capture == null) return;
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(capture).create(recursive: true);
        await File('$capture/$name.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    for (final language in ['zh', 'en']) {
      for (final theme in [ThemeMode.light, ThemeMode.dark]) {
        for (final scale in [1.0, 1.4]) {
          await tester.runAsync(() async {
            await prefs.setLanguage(language);
            await prefs.setTheme(theme);
            await prefs.setTextScale(scale);
          });
          for (final width in [344.0, 390.0, 720.0, 834.0, 1180.0]) {
            tester.view.physicalSize = Size(width, 900);
            await tester.pumpWidget(RepaintBoundary(
                key: boundary,
                child: app(
                    child: Builder(
                        builder: (context) => Theme(
                            data: Theme.of(context).copyWith(
                                appBarTheme:
                                    Theme.of(context)
                                        .appBarTheme
                                        .copyWith(
                                            titleTextStyle:
                                                TextStyle(
                                                    fontFamily: font == null
                                                        ? null
                                                        : 'UsagePreview',
                                                    fontSize: 20,
                                                    color: Theme.of(context)
                                                        .colorScheme
                                                        .onSurface)),
                                textTheme: Theme.of(context).textTheme.apply(
                                    fontFamily:
                                        font == null ? null : 'UsagePreview')),
                            child: UsagePage(key: ValueKey('$width$language$theme$scale'), usage: usage, statistics: stats))))));
            await tester.pumpAndSettle();
            await snapshot(
                'usage-$language-${theme.name}-${width.toInt()}-$scale-top');
            final scroll = find.byKey(const ValueKey('usage-page-scroll'));
            for (var i = 0; i < 7; i++) {
              await tester.drag(scroll, const Offset(0, -650));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull,
                  reason: '$language $theme $width step $i');
            }
            await snapshot(
                'usage-$language-${theme.name}-${width.toInt()}-$scale-bottom');
            final position = tester
                .state<ScrollableState>(find
                    .descendant(of: scroll, matching: find.byType(Scrollable))
                    .first)
                .position;
            position.jumpTo(0);
            await tester.pumpAndSettle();
            await tester
                .tap(find.text(language == 'zh' ? '应用统计' : 'Application'));
            await tester.pumpAndSettle();
            for (var i = 0; i < 6; i++) {
              await tester.drag(scroll, const Offset(0, -650));
              await tester.pumpAndSettle();
              expect(tester.takeException(), isNull,
                  reason: 'app $language $theme $width step $i');
            }
            await snapshot(
                'usage-$language-${theme.name}-${width.toInt()}-$scale-app');
          }
        }
      }
    }
    await tester.pumpWidget(const SizedBox());
  });
}
