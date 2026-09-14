import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/protocol/terminal.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/terminal_session.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/code_renderer.dart';
import 'package:zcode_remote/ui/device_connection_status.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/terminal_panel.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';

import '../test/ui/fake_features.dart';
import '../test/ui/fake_workspace.dart';
import '../test/ui/review_connected_session.dart';

const _enabled = bool.fromEnvironment('NATIVE_WORKSPACE_VISUAL_REVIEW');

/// Channel endpoint paired with [FeatureTransport]. All calls are retained
/// in memory and all terminal events are manually fired by this test service.
/// No request reaches a real relay or desktop.
class _ReviewChannels extends FeatureChannels {
  _ReviewChannels();

  final records = <({String channel, String method, List<Object?> args})>[];
  final listeners = <int,
      ({
    String channel,
    String event,
    Object? arg,
    void Function(dynamic) onEvent
  })>{};
  var _nextListener = 0;
  var _nextSubscription = 0;

  @override
  Future<dynamic> call(
    String channel,
    String method,
    List<Object?> args, {
    Duration timeout = const Duration(seconds: 30),
  }) async {
    records.add((channel: channel, method: method, args: args));
    if (method == 'helloConversationV4') {
      return {'connectionId': 'synthetic-native-review'};
    }
    if (method == 'initializeConversationV4') return <String, dynamic>{};
    if (method == 'subscribeConversationV4' ||
        method == 'subscribeSessionsIndexV4') {
      _nextSubscription++;
      return {
        'ack': {'subscriptionId': 'synthetic-sub-$_nextSubscription'}
      };
    }
    if (method == 'sendConversationCommandV4') {
      return {
        'status': 'accepted',
        'revisionAtDecision': 1,
        'result': {'sessionId': 'synthetic-created'},
      };
    }
    if (channel == Channels.terminal && method == 'create') {
      return {
        'id': 'synthetic-terminal-${records.length}',
        'shell': 'bash',
        'fontFamily': 'monospace',
        'fontSize': 12,
        'theme': {'background': '#161616'},
        'fontFamilySource': 'synthetic',
      };
    }
    if (channel == Channels.terminal &&
        (method == 'write' || method == 'resize' || method == 'dispose')) {
      return null;
    }
    if (method == 'getAll' || method == 'getDisplayOrder') return <dynamic>[];
    if (method.startsWith('list')) return <dynamic>[];
    return <String, dynamic>{};
  }

  @override
  void Function() addEventListener(
    String channel,
    String event,
    void Function(dynamic) onEvent, {
    Object? arg,
  }) {
    final id = _nextListener++;
    listeners[id] =
        (channel: channel, event: event, arg: arg, onEvent: onEvent);
    return () => listeners.remove(id);
  }

  void fire(String event, Object? arg, dynamic payload) {
    for (final listener in listeners.values.toList()) {
      if (listener.event == event && _sameArg(listener.arg, arg)) {
        listener.onEvent(payload);
      }
    }
  }

  bool _sameArg(Object? left, Object? right) {
    if (left is Map && right is Map) {
      return jsonEncode(left) == jsonEncode(right);
    }
    return left == right;
  }

  void clear() => listeners.clear();
}

class _ReviewBridge extends FeatureBridge {
  final _reviewChannels = _ReviewChannels();

  @override
  _ReviewChannels get channels => _reviewChannels;
}

ConversationState _conversationState(
  String epoch,
  List<Map<String, dynamic>> rows,
) {
  final state = ConversationState();
  state.applyFrame({
    'toSeq': 1,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {
        ...composerSnapshotFixture,
        'revision': 1,
        'logEpoch': epoch,
        'rows': {
          'totalCount': rows.length,
          'firstRowId': rows.isEmpty ? null : rows.first['rowId'],
          'window': rows,
        },
      },
    },
  }, onGap: () => fail('synthetic conversation frame gap'));
  return state;
}

List<Map<String, dynamic>> _mainRows(String task) => [
      {
        'kind': 'userInput',
        'rowId': 1,
        'turnId': 'turn-$task',
        'text': '检查 $task 工作区的变更',
      },
      {
        'kind': 'turnHeader',
        'rowId': 2,
        'turnId': 'turn-$task',
        'entityId': 'header-$task',
        'state': 'complete',
        'fileChanges': {
          'files': 1,
          'additions': 1,
          'deletions': 1,
          'state': 'active',
        },
        'actions': {'canRewindFiles': true},
      },
      {
        'kind': 'toolCall',
        'rowId': 3,
        'turnId': 'turn-$task',
        'toolName': 'Edit',
        'status': 'success',
        'input': {
          'file_path': 'lib/main.dart',
          'old_string': 'return 1;\nkeep();\n',
          'new_string': 'return 2;\nkeep();\n',
        },
      },
      {
        'kind': 'assistantText',
        'rowId': 4,
        'turnId': 'turn-$task',
        'state': 'complete',
        'text': '已完成当前工作区的检查。',
      },
    ];

List<Map<String, dynamic>> _sideRows() => [
      {
        'kind': 'userInput',
        'rowId': 11,
        'text': '从选中内容开始辅助检查',
      },
      {
        'kind': 'assistantText',
        'rowId': 12,
        'state': 'complete',
        'text': '辅助对话已就绪。',
      },
    ];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'native WorkspaceShell visual paths use paired synthetic transport',
    (tester) async {
      final environment = await const MethodChannel('zcode_remote/attachments')
          .invokeMapMethod<String, dynamic>('environment');
      expect(
        environment?['packageName'],
        'com.zcoderemote.zcode_remote.qa',
        reason: 'Run only against the isolated .qa package.',
      );
      if (!_enabled) {
        debugPrint(
            'NATIVE_WORKSPACE_VISUAL_REVIEW skipped; pass --dart-define=NATIVE_WORKSPACE_VISUAL_REVIEW=true to enable.');
        return;
      }

      final cacheDirectory = environment?['cacheDirectory'] as String?;
      expect(cacheDirectory, isNotNull,
          reason: 'The .qa environment must expose its cache directory.');
      final configuredRunId =
          const String.fromEnvironment('NATIVE_WORKSPACE_VISUAL_RUN_ID');
      final runId = configuredRunId.trim().isEmpty
          ? 'run-${DateTime.now().millisecondsSinceEpoch}'
          : configuredRunId.trim().replaceAll(RegExp(r'[^A-Za-z0-9_.-]'), '_');
      final runDirectory =
          Directory('${cacheDirectory!}/native-workspace-visual/$runId');
      expect(await runDirectory.exists(), isFalse,
          reason: 'Use a new cache run directory for every native review.');
      await runDirectory.create(recursive: true);

      final store = DeviceStore(
        requireEncryption: false,
        encrypt: (_) async => null,
      );
      final device = await store.addUrl(
        'https://zcode.z.ai/remote/v4?sid=native-workspace-review&hash=synthetic&t=1',
        label: 'Native workspace review',
      );
      final bridge = _ReviewBridge();
      bridge.conversationTransport.states['task-A'] =
          _conversationState('task-A', _mainRows('A'));
      bridge.conversationTransport.states['task-B'] =
          _conversationState('task-B', _mainRows('B'));
      bridge.conversationTransport.states['task-A-side'] =
          _conversationState('task-A-side', _sideRows());
      final sessions = FakeAppSessions(
        store: store,
        sessionFactory: (value) =>
            ReviewConnectedSession(value.params!, bridge),
      );
      sessions.sessionFor(device);
      expect(
          connectionStatusSnapshot(sessions.sessionOf(device.id), bridge)
              .healthy,
          isTrue,
          reason: 'Native workspace capture uses a paired synthetic source.');
      final preferences = ClientPreferences();
      await preferences.load();
      final originalTheme = preferences.theme;
      final originalLanguage = preferences.language;
      final originalTextScale = preferences.textScale;
      final originalUiFontSize = preferences.uiFontSizePx;
      final boundary = GlobalKey();
      final manifestEntries = <Map<String, String>>[];

      Future<void> writeManifest() async {
        final rows = <String>[
          'frame\tevidence\tcondition\tsource\tstatus\tunverified',
          for (final entry in manifestEntries)
            [
              entry['frame'],
              entry['evidence'],
              entry['condition'],
              entry['source'],
              entry['status'],
              entry['unverified'],
            ].join('\t'),
        ];
        await File('${runDirectory.path}/manifest.tsv')
            .writeAsString('${rows.join('\n')}\n');
      }

      Future<void> capture(String frame, String condition) async {
        await tester.runAsync(() async {
          final render = boundary.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
          final image = await render.toImage(pixelRatio: 1);
          try {
            final data = await image.toByteData(format: ui.ImageByteFormat.png);
            expect(data, isNotNull);
            final path = '${runDirectory.path}/$frame.png';
            await File(path).writeAsBytes(data!.buffer.asUint8List());
            final entry = <String, String>{
              'frame': frame,
              'evidence': path,
              'condition': condition,
              'source': 'native WorkspaceShell with paired synthetic transport',
              'status': 'native Flutter surface captured; inspect required',
              'unverified':
                  'no real remote/desktop and no official same-data screenshot comparison',
            };
            manifestEntries.add(entry);
            await writeManifest();
            debugPrint('NATIVE_WORKSPACE_IMAGE ${jsonEncode(entry)}');
          } finally {
            image.dispose();
          }
        });
      }

      Future<void> pumpBounded({int frames = 20}) async {
        for (var index = 0; index < frames; index++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> waitUntil(
        bool Function() condition,
        String description, {
        Duration timeout = const Duration(seconds: 15),
      }) async {
        final watch = Stopwatch()..start();
        while (!condition()) {
          if (watch.elapsed >= timeout) {
            fail('Timed out waiting for $description.');
          }
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      Future<void> openTask(String id, String title) async {
        final context = tester.element(find.byType(WorkspaceShell).last);
        await openDeviceWorkspace(
          context,
          sessions,
          preferences,
          device,
          target: TaskTarget(
            deviceId: device.id,
            workspaceKey: 'workspace',
            sessionId: id,
            title: title,
            workspacePath: 'D:/Synthetic',
          ),
        );
        await pumpBounded();
      }

      try {
        await preferences.setLanguage('zh');
        await preferences.setTheme(ThemeMode.dark);
        await preferences.setTextScale(1);
        late BuildContext rootContext;
        await tester.pumpWidget(RepaintBoundary(
          key: boundary,
          child: ZcodeRemoteApp(
            preferences: preferences,
            home: Builder(builder: (context) {
              rootContext = context;
              return const Scaffold();
            }),
          ),
        ));
        await pumpBounded();
        await openDeviceWorkspace(
          rootContext,
          sessions,
          preferences,
          device,
          target: TaskTarget(
            deviceId: device.id,
            workspaceKey: 'workspace',
            sessionId: 'task-A',
            title: '任务 A',
            workspacePath: 'D:/Synthetic',
          ),
        );
        await pumpBounded(frames: 30);
        expect(find.byType(WorkspaceShell), findsOneWidget);
        expect(find.byType(ChatPage), findsOneWidget);
        await tester.enterText(
            find.byKey(const ValueKey('composer-input')), '草稿 A');
        await pumpBounded(frames: 4);
        await capture(
            'task-a-main', 'tablet or phone native task A with draft');

        final diff = find.byType(CodeDiffViewer);
        if (diff.evaluate().isEmpty) {
          final toolRow = find.byKey(const ValueKey('tool-row-3'));
          if (toolRow.evaluate().isEmpty) {
            await tester.tap(find.text(turnWorkLabel(state: 'completed')));
            await pumpBounded(frames: 4);
          }
          expect(toolRow, findsOneWidget,
              reason: 'Synthetic task A must expose the real Edit tool row.');
          await tester.ensureVisible(toolRow);
          await tester.tap(toolRow);
          await pumpBounded(frames: 4);
        }
        expect(find.byType(CodeDiffViewer), findsOneWidget);
        await capture('main-inline-edit', 'real ChatPage Edit inline diff row');

        final workPanel = find.byTooltip('工作面板').last;
        expect(workPanel, findsOneWidget);
        await tester.tap(workPanel);
        await pumpBounded(frames: 4);
        expect(find.text('任务状态'), findsOneWidget);
        await capture(
            'main-summary', 'real summary panel with turnHeader file change');
        await tester.tap(find.text('辅助对话').last);
        await pumpBounded(frames: 4);
        final openSide = find.text('打开辅助对话');
        expect(openSide, findsOneWidget);
        await tester.tap(openSide);
        await waitUntil(
          () => find
              .byWidgetPredicate(
                (widget) =>
                    widget is ChatPage && widget.sessionId == 'task-A-side',
              )
              .evaluate()
              .isNotEmpty,
          'real side ChatPage',
        );
        // FeatureTransport.createSelectionSideSession returns parent-side;
        // the channel command fallback is not used for this synthetic path.
        expect(bridge.conversationTransport.sideCreates, 1);
        await pumpBounded(frames: 6);
        await capture('side-chat', 'real main plus side ChatPage path');
        await tester.tap(find.byTooltip('关闭面板').last);
        await pumpBounded(frames: 4);

        await tester.tap(find.byKey(const ValueKey('composer-mode')));
        await pumpBounded(frames: 4);
        expect(find.byKey(const ValueKey('composer-mode-option-build')),
            findsOneWidget);
        await capture('mode-menu', 'real Composer mode menu');
        await tester
            .tap(find.byKey(const ValueKey('composer-mode-option-plan')));
        await pumpBounded(frames: 5);

        await tester.tap(find.byKey(const ValueKey('composer-model')));
        await pumpBounded(frames: 6);
        expect(find.byType(Overlay), findsOneWidget);
        await capture('model-menu', 'real Composer model menu');
        await tester.binding.handlePopRoute();
        await pumpBounded(frames: 3);

        final shell = tester.state(find.byType(WorkspaceShell));
        final width =
            MediaQuery.sizeOf(tester.element(find.byType(WorkspaceShell)))
                .width;
        await tester.tap(find.byTooltip('项目与任务').last);
        await tester.pump(const Duration(milliseconds: 100));
        await capture(
            'sidebar-mid-open-close',
            width < 640
                ? 'narrow drawer menu representative state'
                : 'sidebar collapse mid-animation frame');
        if (width < 640) {
          await tester.binding.handlePopRoute();
          await pumpBounded(frames: 3);
        } else {
          await pumpBounded(frames: 4);
          await tester.tap(find.byTooltip('项目与任务').last);
          await tester.pump(const Duration(milliseconds: 100));
          await capture(
              'sidebar-mid-reopen', 'sidebar reopen mid-animation frame');
          await pumpBounded(frames: 4);
        }

        await openTask('task-B', '任务 B');
        await tester.enterText(
            find.byKey(const ValueKey('composer-input')).last, '草稿 B');
        await pumpBounded(frames: 3);
        await openTask('task-A', '任务 A');
        expect(find.text('草稿 A'), findsOneWidget,
            reason: 'Task A draft must survive A to B to A navigation.');
        if (width >= 640) {
          expect(identical(tester.state(find.byType(WorkspaceShell)), shell),
              isTrue,
              reason:
                  'Wide A to B to A navigation must retain one shell state.');
          expect(
              find.byType(WorkspaceShell, skipOffstage: false), findsOneWidget);
        }
        await capture(
            'task-a-restored', 'task A restored after task B navigation');

        await tester.tap(find.byTooltip('切换终端').last);
        await pumpBounded(frames: 8);
        final workspaceTerminals = sessions.terminalSessions.workspace(
          deviceId: device.id,
          workspaceKey: 'workspace',
          client: TerminalClient(session: bridge),
          cwd: 'D:/Synthetic',
        );
        final terminal = workspaceTerminals.activeController!;
        await waitUntil(
          () => terminal.status == TerminalSessionStatus.ready,
          'synthetic terminal ready',
        );
        expect(
            bridge.channels.records.any((call) =>
                call.channel == Channels.terminal && call.method == 'create'),
            isTrue);
        bridge.channels.fire('onDynamicData', terminal.terminalId,
            '\u001b[32mSynthetic output\u001b[0m\r\n');
        await pumpBounded(frames: 4);
        expect(terminal.output, contains('Synthetic output'));
        final terminalOutputNonEmpty = terminal.output.isNotEmpty;
        final terminalPanel = find.byType(TerminalPanel);
        final terminalInput = find.descendant(
            of: terminalPanel, matching: find.byType(TextField));
        expect(terminalInput, findsOneWidget);
        await tester.enterText(terminalInput, 'printf synthetic');
        await tester
            .tap(find.descendant(of: terminalPanel, matching: find.text('发送')));
        await waitUntil(
          () => bridge.channels.records.any((call) =>
              call.channel == Channels.terminal && call.method == 'write'),
          'synthetic terminal write',
        );
        await capture('terminal-output',
            'bottom terminal drawer non-empty output and synthetic write');
        final terminalClose =
            find.descendant(of: terminalPanel, matching: find.text('关闭'));
        expect(terminalClose, findsOneWidget);
        await tester.tap(terminalClose);
        await waitUntil(() => terminal.status == TerminalSessionStatus.idle,
            'synthetic terminal close');
        expect(
            bridge.channels.records.any((call) =>
                call.channel == Channels.terminal && call.method == 'dispose'),
            isTrue);
        await pumpBounded(frames: 3);
        await capture(
            'terminal-closed', 'terminal session closed before drawer close');
        await tester.tap(find.byTooltip('关闭终端抽屉').last);
        await pumpBounded(frames: 3);
        expect(find.byType(TerminalDrawer), findsNothing);

        expect(tester.takeException(), isNull);
        expect(manifestEntries.length, greaterThanOrEqualTo(10));
        debugPrint('NATIVE_WORKSPACE_MANIFEST ${jsonEncode({
              'path': '${runDirectory.path}/manifest.tsv',
              'entries': manifestEntries.length,
              'packageName': environment?['packageName'],
              'physicalSizeOverridden': false,
              'fontOverride': false,
              'syntheticTransport': true,
              'terminalOutputNonEmpty': terminalOutputNonEmpty,
              'terminalCreateWriteDisposeSynthetic': bridge.channels.records
                  .where((call) => call.channel == Channels.terminal)
                  .map((call) => call.method)
                  .toList(),
              'narrowObserved': width < 640,
            })}');
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await pumpBounded(frames: 2);
        final session = sessions.sessionOf(device.id);
        if (session is ReviewConnectedSession) {
          await tester.runAsync(session.reviewClient.dispose);
        }
        sessions.dispose();
        await sessions.notifications.settled;
        bridge.channels.clear();
        bridge.channels.dispose();
        await store.remove(device.id);
        store.dispose();
        await preferences.setTheme(originalTheme);
        await preferences.setLanguage(originalLanguage);
        await preferences.setUiFontSizePx(originalUiFontSize);
        await preferences.setTextScale(originalTextScale);
        await preferences.settled;
        preferences.dispose();
      }
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
