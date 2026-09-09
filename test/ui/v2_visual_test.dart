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
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/workspace_catalog.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';
import 'package:zcode_remote/ui/settings_center_page.dart';
import 'fake_workspace.dart';

/// Optional review captures: set ZCODE_UI_CAPTURE_DIR and ZCODE_TEST_FONT.
/// These use synthetic tasks with real Flutter widgets, never pairing URLs.
void main() {
  testWidgets('V2 shell renders in five shapes, both themes and large text',
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
          await (FontLoader('V2Preview')
                ..addFont(Future.value(ByteData.sublistView(bytes))))
              .load();
          for (final entry in {
            'monospace': Platform.environment['ZCODE_TEST_MONO_FONT'],
            'MaterialIcons': Platform.environment['ZCODE_TEST_ICON_FONT']
          }.entries) {
            if (entry.value == null) continue;
            final font = await File(entry.value!).readAsBytes();
            await (FontLoader(entry.key)
                  ..addFont(Future.value(ByteData.sublistView(font))))
                .load();
          }
        });
      }
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final store =
          DeviceStore(requireEncryption: false, encrypt: (_) async => null);
      final device = await store.addUrl(
          'https://zcode.z.ai/remote/v4?sid=synthetic-preview&hash=synthetic&t=1',
          label: '工作电脑');
      final bridge = FakeBridge();
      final sessions = FakeAppSessions(
          store: store,
          sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
      final prefs = ClientPreferences();
      await prefs.setLanguage('zh');
      final monitor = await sessions.openWorkspace(
          device, 'workspace', {'workspaceIdentity': 'workspace'});
      final now = DateTime.now().millisecondsSinceEpoch;
      monitor.catalog.index = [
        SessionEntry({
          'sessionId': 'task',
          'title': '继续界面重构',
          'phase': 'idle',
          'lastActivityAt': now - 3600000
        }),
        SessionEntry({
          'sessionId': 'task-2',
          'title': '修复消息阅读位置',
          'lastActivityAt': now - 7200000
        }),
        SessionEntry({
          'sessionId': 'task-3',
          'title': 'Android 系统能力验收',
          'lastActivityAt': now - 86400000
        }),
      ];
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
              {'source': 'skills', 'chars': 10000}
            ]
          }
        }
      });
      bridge.conversationTransport.states['task'] = conversation;
      final boundary = GlobalKey();
      Widget themed(Widget child) => Builder(
          builder: (context) => Theme(
              data: Theme.of(context).copyWith(
                  textTheme: Theme.of(context).textTheme.apply(
                      fontFamily: fontPath == null ? null : 'V2Preview',
                      fontFamilyFallback:
                          fontPath == null ? null : const ['V2Preview']),
                  appBarTheme: Theme.of(context).appBarTheme.copyWith(
                      titleTextStyle: Theme.of(context)
                          .appBarTheme
                          .titleTextStyle
                          ?.copyWith(
                              fontFamily:
                                  fontPath == null ? null : 'V2Preview'))),
              child: child));
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

      Widget app(Widget home) => RepaintBoundary(
          key: boundary,
          child: ZcodeRemoteApp(preferences: prefs, home: themed(home)));
      Widget shell() => WorkspaceShell(
          device: device,
          workspace: const WorkspaceDescriptor(
              key: 'workspace',
              title: 'ZcodeRemote',
              scope: {'workspaceIdentity': 'workspace'}),
          monitor: monitor,
          sessions: sessions,
          preferences: prefs,
          sessionId: 'task');

      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await prefs.setTheme(mode);
        for (final width in [344.0, 390.0, 720.0, 834.0, 1180.0]) {
          tester.view.physicalSize = Size(width, 820);
          await tester.pumpWidget(app(shell()));
          await tester.pumpAndSettle();
          await capture('${mode.name}-${width.toInt()}');
          await tester.tap(find.byTooltip('工作面板').last);
          await tester.pumpAndSettle();
          await capture('${mode.name}-${width.toInt()}-panel');
          await tester.tap(find.byTooltip('关闭面板').last);
          await tester.pumpAndSettle();
        }
      }
      await prefs.setLanguage('en');
      await prefs.setTextScale(1.4);
      conversation.optimisticPatch({
        'revision': 10,
        'config': {
          'provider': 'provider-b',
          'model': 'second-model',
          'thought': 'enabled',
          'mode': 'plan'
        },
        'control': {
          'phase': 'running',
          'canStop': true,
          'stopState': 'stoppable',
          'activeWorks': [
            {'foregroundExecutionId': 'synthetic-run'}
          ]
        },
        'inputRouting': {'mode': 'enqueue'},
        'queue': {
          'autoDrain': true,
          'items': [
            {
              'queueItemId': 'q1',
              'text': 'Check the next composer state',
              'dispatch': {'state': 'queued'}
            },
          ]
        },
      });
      for (final width in [344.0, 720.0, 1180.0]) {
        tester.view.physicalSize = Size(width, 820);
        await tester.pumpWidget(app(shell()));
        await tester.pumpAndSettle();
        await capture('dark-${width.toInt()}-composer-large');
        await tester.tap(find.byKey(const ValueKey('composer-model')).first);
        await tester.pumpAndSettle();
        await capture('dark-${width.toInt()}-composer-model-menu');
        await tester.tapAt(const Offset(4, 90));
        await tester.pumpAndSettle();
      }
      final composer = sessions.composers.obtain(
          transport: bridge.conversationTransport,
          deviceId: device.id,
          workspaceKey: 'workspace',
          sessionId: 'task');
      final gate = Completer<dynamic>();
      bridge.conversationTransport.commandHandler =
          (sid, type, payload) => gate.future;
      final selecting = composer.selectThought('off');
      await tester.pump(const Duration(milliseconds: 100));
      await capture('dark-1180-composer-pending');
      gate.complete({'status': 'rejected'});
      await selecting;
      await tester.pumpAndSettle();
      await capture('dark-1180-composer-failure');
      // Rich official-schema fixture, including the missing-duration and MCP
      // presentation regressions. No real task content or credentials.
      await prefs.setLanguage('zh');
      await prefs.setTextScale(1);
      final richRows = [
        {'kind': 'userInput', 'rowId': 1, 'text': '检查正文宽度、工具详情和输入框是否对齐。'},
        {
          'kind': 'turnHeader',
          'rowId': 2,
          'state': 'completed',
          'activeMs': 6000
        },
        {
          'kind': 'reasoning',
          'rowId': 3,
          'state': 'complete',
          'text': '先核对资源，再检查布局。'
        },
        {'kind': 'assistantText', 'rowId': 4, 'text': '已核对官方布局规格，开始检查当前界面的细节。'},
        {
          'kind': 'toolCall',
          'rowId': 5,
          'toolName': 'mcp__ssh-server__ssh_exec',
          'status': 'success',
          'inputText': '{"command":"uname"}',
          'output': {'text': 'Linux synthetic'}
        },
        {
          'kind': 'toolCall',
          'rowId': 6,
          'toolName': 'Read',
          'status': 'success',
          'inputText': '{"file_path":"lib/ui/composer/composer_bar.dart"}',
          'output': {'text': 'Synthetic source preview'}
        },
        {
          'kind': 'reasoning',
          'rowId': 7,
          'state': 'complete',
          'durationMs': 2100,
          'text': '正文与输入框已使用相同宽度。'
        },
        {
          'kind': 'assistantText',
          'rowId': 8,
          'text':
              '正文与输入框使用同一阅读列。\n\n- 工具调用可展开查看参数和结果。\n- 模式文案随语言切换。\n- 上下文用量来自当前会话。'
        },
      ];
      conversation.applyFrame({
        'toSeq': 30,
        'payload': {
          'kind': 'snapshot',
          'snapshot': {
            ...composerSnapshotFixture,
            'revision': 30,
            'logEpoch': 'test',
            'config': {
              ...composerSnapshotFixture['config'] as Map,
              'mode': 'yolo'
            },
            'usage': {
              'contextWindow': {
                'usedTokens': 40000,
                'maxTokens': 128000,
                'cache': {'hitRate': .84},
                'breakdown': [
                  {'source': 'messages', 'chars': 70},
                  {'source': 'system_prompt', 'chars': 20},
                  {'source': 'skills', 'chars': 10}
                ]
              }
            },
            'rows': {
              'totalCount': richRows.length,
              'firstRowId': 1,
              'window': richRows
            }
          }
        }
      }, onGap: () {});
      composer.dismissFailure();
      for (final view in sessions.conversationViewStates.values) {
        view.expandedTurns[2] = true;
        view.following = true;
      }
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        await prefs.setTheme(mode);
        tester.view.physicalSize = const Size(1280, 552);
        await tester.pumpWidget(app(shell()));
        await tester.pumpAndSettle();
        await capture('${mode.name}-1280-official-details');
        await tester
            .tap(find.byKey(const ValueKey('composer-context-usage')).first);
        await tester.pumpAndSettle();
        await capture('${mode.name}-1280-context-usage');
        await tester.tapAt(const Offset(4, 50));
        await tester.pumpAndSettle();
      }
      tester.view.physicalSize = const Size(344, 740);
      await tester.pumpWidget(app(SettingsCenterPage(
          preferences: prefs,
          sessions: sessions,
          onManageDevices: () {},
          initialSection: 'appearance')));
      await tester.pumpAndSettle();
      await capture('dark-344-settings-large');
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled;
      prefs.dispose();
    } finally {
      debugDisableShadows = disableShadows;
    }
  });
}
