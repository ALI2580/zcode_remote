import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/composer_usage.dart';
import 'package:zcode_remote/state/plan_resets.dart';
import 'package:zcode_remote/protocol/plan_reset.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/plan_reset_dialog.dart';
import 'package:zcode_remote/ui/composer/quota_section.dart';
import 'package:zcode_remote/ui/composer/quota_reset_status.dart';
import 'fake_features.dart';

void main() {
  late FeatureBridge bridge;
  late ComposerUsage usage;
  late PlanResets resets;
  late ClientPreferences prefs;
  late Map<String, dynamic> status;
  late int now;
  var readOnly = false;
  setUp(() async {
    readOnly = false;
    SharedPreferences.setMockInitialValues({});
    now = DateTime.utc(2026, 9, 9).millisecondsSinceEpoch;
    bridge = FeatureBridge();
    resets = PlanResets(bridge.conversationTransport,
        readOnly: () => readOnly,
        now: () => DateTime.fromMillisecondsSinceEpoch(now),
        delay: (_) async {});
    usage = ComposerUsage(bridge.conversationTransport, resets: resets);
    prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    status = {
      'availableFiveHourResets': [
        {'expireAt': now + 10000}
      ],
      'availableWeekResets': [
        {'expireAt': now + 1200000}
      ],
      'hasUnreadHistory': false,
    };
    bridge.channels.handler = (channel, method, args) =>
        method == 'getCodingPlanResetStatus' ? status : {};
    usage.selectProvider('builtin:bigmodel-coding-plan');
    await usage.refresh();
    await usage.refreshResetStatus();
  });
  tearDown(() {
    usage.dispose();
    resets.dispose();
    prefs.dispose();
    bridge.channels.dispose();
  });
  Widget app({bool dialog = false}) => ZcodeRemoteApp(
      preferences: prefs,
      home: Scaffold(
          body: dialog
              ? PlanResetDialog(usage: usage, sourceKey: usage.source!.key)
              : Center(
                  child: SizedBox(
                      width: 320, child: QuotaSection(usage: usage)))));

  testWidgets(
      'opening the reset dialog reads status without consuming or granting',
      (tester) async {
    readOnly = true;
    await tester.pumpWidget(app());
    await tester.tap(find.byKey(const ValueKey('quota-reset-open')));
    await tester.pumpAndSettle();
    expect(find.text('可重置额度'), findsOneWidget);
    expect(find.byKey(const ValueKey('quota-reset-use-WEEK')), findsOneWidget);
    expect(find.byKey(const ValueKey('quota-reset-use-FIVE_HOUR')),
        findsOneWidget);
    expect(find.text('ZCode MCP'), findsNWidgets(2));
    expect(
        bridge.channels.calls
            .every((c) => c.method == 'getCodingPlanResetStatus'),
        isTrue);
    now += 10000;
    await tester.pump(const Duration(seconds: 1));
    expect(
        find.byKey(const ValueKey('quota-reset-use-FIVE_HOUR')), findsNothing);
    expect(find.byKey(const ValueKey('quota-reset-use-WEEK')), findsOneWidget);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
  });

  testWidgets('double reset gestures submit once and show confirmed completion',
      (tester) async {
    final gate = Completer<Object>();
    bridge.channels.handler = (channel, method, args) =>
        method == 'getCodingPlanResetStatus' ? status : gate.future;
    await tester.pumpWidget(app(dialog: true));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('quota-reset-use-WEEK'));
    await tester.tap(button);
    await tester.tap(button);
    await tester.pump();
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'useCodingPlanReset')
            .length,
        1);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(
        tester
            .widget<FilledButton>(
                find.byKey(const ValueKey('quota-reset-use-FIVE_HOUR')))
            .onPressed,
        isNull);
    status = {
      ...status,
      'availableWeekResets': [],
      'latestWeekResetHistory': {'usedAt': now}
    };
    gate.complete({});
    await tester.pump();
    expect(find.text('已完成'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 1100));
    expect(button, findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'external reset shows progress then completion once across two views',
      (tester) async {
    status = {
      ...status,
      'availableWeekResets': [],
      'latestWeekResetHistory': {'usedAt': now},
      'hasUnreadHistory': true
    };
    await usage.refreshResetStatus(force: true);
    await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: Scaffold(
            body: Column(children: [
          QuotaResetStatus(usage: usage, type: PlanResetType.week),
          QuotaResetStatus(usage: usage, type: PlanResetType.week)
        ]))));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNWidgets(2));
    now += 1000;
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('已完成'), findsNWidgets(2));
    await tester.pump();
    expect(find.byType(TweenAnimationBuilder<double>), findsOneWidget);
    now += 1600;
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.text('已完成'), findsNothing);
    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'source switch clears modal quota and makes the stale reset unreachable',
      (tester) async {
    await tester.pumpWidget(app(dialog: true));
    await tester.pumpAndSettle();
    usage.selectProvider('builtin:zai-start-plan');
    await tester.pump();
    expect(find.textContaining('套餐来源已变更'), findsOneWidget);
    expect(find.byKey(const ValueKey('quota-reset-use-WEEK')), findsNothing);
    expect(find.text('ZCode MCP'), findsNothing);
    expect(bridge.channels.calls.where((c) => c.method == 'useCodingPlanReset'),
        isEmpty);
  });

  testWidgets('unconfirmed result exposes status refresh and cannot resubmit',
      (tester) async {
    await tester.pumpWidget(app(dialog: true));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('quota-reset-use-WEEK'));
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(find.textContaining('尚未确认重置结果'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '刷新'), findsOneWidget);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'useCodingPlanReset')
            .length,
        1);
  });

  testWidgets(
      'full pools hide opportunities and five shapes fit both languages at 140 percent',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bridge.conversationTransport.quotaHandler =
        (provider, org, project) async => quotaFixture(provider, used: 0);
    await usage.refresh(force: true);
    await tester.pumpWidget(app(dialog: true));
    await tester.pumpAndSettle();
    expect(
        find.byKey(const ValueKey('quota-reset-use-FIVE_HOUR')), findsNothing);
    bridge.conversationTransport.quotaHandler = null;
    await usage.refresh(force: true);
    for (final language in ['zh', 'en']) {
      for (final theme in [ThemeMode.light, ThemeMode.dark]) {
        await tester.runAsync(() async {
          await prefs.setLanguage(language);
          await prefs.setTheme(theme);
          await prefs.setTextScale(1.4);
        });
        for (final width in [344.0, 390.0, 720.0, 834.0, 1180.0]) {
          tester.view.physicalSize = Size(width, 820);
          await tester.pumpWidget(app(dialog: true));
          await tester.pumpAndSettle();
          final button = find.byKey(const ValueKey('quota-reset-use-WEEK'));
          await tester.ensureVisible(button);
          await tester.pumpAndSettle();
          final rect = tester.getRect(button);
          expect(rect.left, greaterThanOrEqualTo(0));
          expect(rect.right, lessThanOrEqualTo(width));
          expect(rect.bottom, lessThanOrEqualTo(820));
          expect(tester.takeException(), isNull,
              reason: '$language $theme $width');
        }
      }
    }
  });
}
