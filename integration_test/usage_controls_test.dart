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
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import 'package:zcode_remote/ui/theme.dart';
import '../test/ui/fake_features.dart';
import '../test/ui/fake_workspace.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native quota controls with synthetic reset service',
      (tester) async {
    final environment = await const MethodChannel('zcode_remote/attachments')
        .invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa');
    final bridge = FeatureBridge();
    final store = ComposerStore();
    final controller = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'synthetic-reset',
        workspaceKey: 'usage',
        sessionId: 'task');
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    await prefs.setTheme(ThemeMode.light);
    await prefs.setTextScale(1);
    var used = 6;
    final now = DateTime.now().millisecondsSinceEpoch;
    var status = <String, dynamic>{
      'availableFiveHourResets': [],
      'availableWeekResets': [],
      'hasUnreadHistory': false
    };
    bridge.channels.handler = (channel, method, args) {
      if (method == 'requestCodingPlanResetOpportunity') {
        status = {
          ...status,
          'availableWeekResets': [
            {
              'expireAt':
                  now + const Duration(days: 22, hours: 15).inMilliseconds
            }
          ]
        };
        return {'granted': true};
      }
      if (method == 'markCodingPlanResetHistoryRead') {
        status = {...status, 'hasUnreadHistory': false};
        return {};
      }
      if (method == 'getCodingPlanResetStatus') return status;
      if (method == 'useCodingPlanReset') {
        used = 0;
        status = {
          ...status,
          'availableWeekResets': [],
          'latestWeekResetHistory': {'usedAt': now}
        };
        return {};
      }
      throw StateError('unexpected synthetic quota request');
    };
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
                    'percentage': 0
                  },
                  {
                    'type': 'TOKENS_LIMIT',
                    'unit': 6,
                    'percentage': used,
                    'nextResetTime':
                        DateTime(2026, 9, 15, 23, 54).millisecondsSinceEpoch
                  },
                  {
                    'type': 'TIME_LIMIT',
                    'unit': 5,
                    'number': 1,
                    'percentage': 5,
                    'nextResetTime':
                        DateTime(2026, 9, 14, 15, 11).millisecondsSinceEpoch
                  },
                ]
              },
              'mcpQuota': {
                'aggregate': {
                  'type': 'TIME_LIMIT',
                  'percentage': 0,
                  'nextResetTime': DateTime(2026, 9, 10).millisecondsSinceEpoch
                }
              },
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
    await controller.loadOptions();
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ZcodeRemoteApp(
            preferences: prefs,
            home: Scaffold(
                appBar: AppBar(title: const Text('额度 QA · 合成数据')),
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
      await File('${environment!['cacheDirectory']}/qa-usage-$name.png')
          .writeAsBytes(bytes!.buffer
              .asUint8List(bytes.offsetInBytes, bytes.lengthInBytes));
      image.dispose();
    }

    await tester.tap(find.byKey(const ValueKey('composer-context-usage')));
    await tester.pumpAndSettle();
    expect(find.text('14.1万/100万 (14.1%)'), findsOneWidget);
    expect(find.text('93.8%'), findsOneWidget);
    await capture('popover');
    await tester.tap(find.byKey(const ValueKey('quota-reset-open')));
    await tester.pumpAndSettle();
    expect(find.text('可重置额度'), findsOneWidget);
    await capture('reset');
    expect(
        bridge.channels.calls.where((c) =>
            c.method != 'getCodingPlanResetStatus' &&
            c.method != 'requestCodingPlanResetOpportunity'),
        isEmpty);
    final reset = find.byKey(const ValueKey('quota-reset-use-WEEK'));
    await prefs.setLanguage('en');
    await prefs.setTheme(ThemeMode.dark);
    await prefs.setTextScale(1.4);
    await tester.pumpAndSettle();
    await tester.ensureVisible(reset);
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<Material>(find.byKey(const ValueKey('composer-popover')))
            .color,
        const DarkInk().card);
    final resetRect = tester.getRect(reset);
    final viewport = MediaQuery.sizeOf(tester.element(reset));
    expect(resetRect.left, greaterThanOrEqualTo(0));
    expect(resetRect.right, lessThanOrEqualTo(viewport.width));
    expect(resetRect.bottom, lessThanOrEqualTo(viewport.height));
    expect(tester.takeException(), isNull);
    await capture('reset-large');
    await prefs.setLanguage('zh');
    await prefs.setTheme(ThemeMode.light);
    await prefs.setTextScale(1);
    await tester.pumpAndSettle();
    await tester.ensureVisible(reset);
    await tester.tap(reset);
    await tester.tap(reset);
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 1100));
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'useCodingPlanReset')
            .length,
        1);
    expect(controller.usage.snapshot!.weekly!.remainingPercent, 100);
    expect(bridge.conversationTransport.commands, isEmpty);
    expect(bridge.conversationTransport.sent, isEmpty);
    await capture('completed');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    status = {
      ...status,
      'latestFiveHourResetHistory': {
        'usedAt': DateTime.now().millisecondsSinceEpoch
      },
      'hasUnreadHistory': true
    };
    await controller.usage.refreshResetStatus(force: true);
    await tester.pump();
    await capture('automatic-processing');
    await tester.pump(const Duration(milliseconds: 1150));
    expect(find.byKey(const ValueKey('quota-reset-completed-FIVE_HOUR')),
        findsOneWidget);
    await capture('automatic-completed');
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'requestCodingPlanResetOpportunity')
            .length,
        1);
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'markCodingPlanResetHistoryRead')
            .length,
        1);
    expect(
        bridge.channels.calls
            .where((c) => c.method == 'useCodingPlanReset')
            .length,
        1);
    await tester.pump(const Duration(milliseconds: 1600));
    expect(find.byKey(const ValueKey('quota-reset-completed-FIVE_HOUR')),
        findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    store.dispose();
    prefs.dispose();
    debugPrint(
        'QA quota: popover, reset dialog, duplicate-tap guard and confirmed quota passed; synthetic service only.');
  });
}
