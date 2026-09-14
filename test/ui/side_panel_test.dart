import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_notification_controller.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/app_sessions.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/device_session.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/file_changes_review.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/navigation.dart';
import 'package:zcode_remote/ui/theme.dart';
import 'package:zcode_remote/ui/workspace_shell.dart';

import '../notifications/fake_notification_platform.dart';
import 'fake_workspace.dart';
import 'review_capture.dart';

class _ScenarioBridge implements BridgeSession {
  _ScenarioBridge() {
    conversationTransport = _ScenarioTransport(this);
  }

  late final _ScenarioTransport conversationTransport;
  @override
  final degraded = ValueSignal<String?>(null);
  @override
  final recovered = ValueSignal<int>(0);
  @override
  final recoveryStarting = ValueSignal<int>(0);
  final states = <String, ConversationState>{};

  @override
  ConversationTransport conversation(Map<String, dynamic> scope,
          {void Function(String)? onLog}) =>
      conversationTransport;

  @override
  Future<void> waitHealthy(
          {Duration timeout = const Duration(seconds: 45)}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ScenarioTransport extends ConversationTransport {
  _ScenarioTransport(this.owner)
      : super(session: owner, scope: const {'workspaceIdentity': 'workspace'});

  final _ScenarioBridge owner;
  final subscriptions = <String, int>{};
  final disposals = <String, int>{};
  final reviewRequests = <Map<String, dynamic>>[];
  int sideCreates = 0;
  Object response = const {
    'files': 1,
    'additions': 1,
    'deletions': 0,
    'state': 'active',
    'items': [
      {
        'path': 'lib/review.dart',
        'additions': 1,
        'deletions': 0,
        'writeCount': 1,
        'toolNames': ['edit'],
        'patches': [],
      },
    ],
  };
  Future<String> Function(String parentSessionId)? sideCreateHandler;

  @override
  Future<WorkspacePrep> prepareWorkspace({bool refresh = false}) async =>
      WorkspacePrep.fromRaw(composerPrepFixture);

  @override
  Future<ConversationSubscription> subscribe(String sessionId) async {
    subscriptions.update(sessionId, (value) => value + 1, ifAbsent: () => 1);
    final state = owner.states.putIfAbsent(
        sessionId, () => _stateFor(sessionId, side: sessionId.endsWith('-side')));
    return FakeConversationSubscription(
        state,
        () => disposals.update(sessionId, (value) => value + 1,
            ifAbsent: () => 1));
  }

  @override
  Future<dynamic> fileChanges(String sessionId,
      {required Map<String, dynamic> target,
      int? baseRevision,
      String? baseLogEpoch}) async {
    reviewRequests.add({
      'sessionId': sessionId,
      'target': target,
      'baseRevision': baseRevision,
      'baseLogEpoch': baseLogEpoch,
    });
    return response;
  }

  @override
  Future<String> createSelectionSideSession(String parentSessionId,
      {Duration timeout = const Duration(seconds: 60)}) {
    sideCreates++;
    return sideCreateHandler?.call(parentSessionId) ??
        Future.value('$parentSessionId-side');
  }
}

class _ScenarioDeviceSession extends DeviceSession {
  _ScenarioDeviceSession(super.params, this.bridge);

  final _ScenarioBridge bridge;

  @override
  bool get connected => true;

  @override
  List<Map<String, dynamic>> get workspaces => const [
        {
          'workspaceIdentity': 'workspace',
          'name': 'ZcodeRemote',
          'workspacePath': 'D:/Project',
        }
      ];

  @override
  Future<void> connect({void Function(String)? onLog}) async {}
}

class _ScenarioMonitor extends WorkspaceMonitor {
  _ScenarioMonitor({
    required super.bridge,
    required super.scope,
    required super.source,
    required super.notifications,
  });

  @override
  bool get ready => true;
}

class _ScenarioSessions extends AppSessions {
  _ScenarioSessions({required super.store, required _ScenarioBridge bridge})
      : bridge = bridge,
        super(
          notifications: TaskNotificationController(
              platform: FakeNotificationPlatform()),
          sessionFactory: (device) =>
              _ScenarioDeviceSession(device.params!, bridge),
        );

  final _ScenarioBridge bridge;
  final monitors = <String, WorkspaceMonitor>{};

  @override
  WorkspaceMonitor? monitorFor(String deviceId, String workspaceKey) =>
      monitors[deviceId];

  @override
  Future<WorkspaceMonitor> openWorkspace(
      Device device, String key, Map<String, dynamic> scope) async {
    final session = sessionFor(device) as _ScenarioDeviceSession;
    await session.connect();
    return monitors.putIfAbsent(
        device.id,
        () => _ScenarioMonitor(
              bridge: bridge,
              scope: scope,
              notifications: notifications,
              source: WorkspaceTaskSource(
                  deviceId: device.id,
                  deviceLabel: device.label,
                  workspaceKey: key),
            ));
  }

  @override
  void dispose() {
    for (final monitor in monitors.values) {
      monitor.dispose();
    }
    super.dispose();
  }
}

ConversationState _stateFor(String sessionId, {required bool side}) {
  final state = ConversationState();
  state.applyFrame({
    'toSeq': 1,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {
        ...composerSnapshotFixture,
        'sessionId': sessionId,
        'revision': 3,
        'logEpoch': 'side-panel-test',
        'rows': {
          'totalCount': side ? 2 : 3,
          'firstRowId': 1,
          'window': [
            {
              'rowId': 1,
              'kind': 'userInput',
              'entityId': 'input-$sessionId',
              'turnId': 'turn-$sessionId',
              'text': 'Inspect this task',
            },
            if (!side)
              {
                'rowId': 2,
                'kind': 'turnHeader',
                'entityId': 'header-$sessionId',
                'turnId': 'turn-$sessionId',
                'state': 'complete',
                'fileChanges': {
                  'files': 1,
                  'additions': 2,
                  'deletions': 1,
                  'state': 'active',
                },
                'actions': {'canRewindFiles': false},
              },
            {
              'rowId': side ? 2 : 3,
              'kind': 'assistantText',
              'entityId': 'answer-$sessionId',
              'turnId': 'turn-$sessionId',
              'state': 'complete',
              'text': 'The task is ready.',
              'feedback': 'like',
              'actions': {'canFork': true},
            },
          ],
        },
      },
    },
  }, onGap: () => fail('unexpected gap'));
  return state;
}

void main() {
  setUpAll(loadReviewCaptureFonts);

  test('turn header zero stats suppress legacy summary without turn ids', () {
    final rows = <Map<String, dynamic>>[
      {'rowId': 1, 'kind': 'userInput', 'text': 'No file changes'},
      {'rowId': 2, 'kind': 'changeSummary', 'count': 4},
      {
        'rowId': 3,
        'kind': 'turnHeader',
        'state': 'complete',
        'fileChanges': {
          'files': 0,
          'additions': 0,
          'deletions': 0,
          'state': 'active',
        },
      },
    ];

    final summaries = conversationFileChangeSummaryRows(rows);
    expect(summaries, isEmpty);
    expect(turnFileChangeStats(rows.last)?.files, 0);
  });

  testWidgets('summary review ignores unrelated revision updates',
      (tester) async {
    final bridge = _ScenarioBridge();
    var revision = 7;
    var headerState = 'active';
    late StateSetter update;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ZInkTheme.light(),
      home: StatefulBuilder(builder: (context, setState) {
        update = setState;
        final row = <String, dynamic>{
          'rowId': 12,
          'kind': 'turnHeader',
          'turnId': 'turn-a',
          'entityId': 'entity-a',
          'state': headerState,
          'fileChanges': {
            'files': 1,
            'additions': 2,
            'deletions': 1,
            'state': headerState,
          },
        };
        return Scaffold(
          body: SingleChildScrollView(
            child: ConversationChangeSummary(
              row: row,
              reviewCacheVersion: 'epoch-a|$headerState|$headerState',
              createReview: (target) => FileChangesReviewController(
                transport: bridge.conversationTransport,
                scope: FileChangesScope(
                  deviceId: 'device-a',
                  workspaceKey: 'workspace-a',
                  sessionId: 'session-a',
                  rowId: target['rowId'] as int,
                  entityId: target['entityId'],
                ),
                revision: () => revision,
                logEpoch: () => 'epoch-a',
              ),
            ),
          ),
        );
      }),
    ));
    await tester.pumpAndSettle();
    expect(find.byType(ConversationChangeSummary), findsOneWidget);
    await tester.tap(find.byType(ConversationChangeSummary));
    await tester.pumpAndSettle();
    expect(bridge.conversationTransport.reviewRequests, hasLength(1));

    // A revision bump alone must retain the loaded review cache.
    update(() => revision = 8);
    await tester.pumpAndSettle();
    expect(bridge.conversationTransport.reviewRequests, hasLength(1));

    // A header state/fileChanges change invalidates and reloads the review.
    update(() => headerState = 'reverted');
    await tester.pumpAndSettle();
    expect(bridge.conversationTransport.reviewRequests, hasLength(2));
    expect(bridge.conversationTransport.reviewRequests.last['baseRevision'], 8);
  });

  testWidgets('side panel uses turn header review data and side-chat gates',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
      'https://zcode.z.ai/remote/v4?sid=synthetic-side-panel&hash=synthetic&t=1',
      label: 'Side panel test',
    );
    final bridge = FakeBridge();
    bridge.conversationTransport.states['task'] =
        _stateFor('task', side: false);
    bridge.conversationTransport.states['task-side'] =
        _stateFor('task-side', side: true);
    final sessions = FakeAppSessions(
      store: store,
      sessionFactory: (d) => FakeDeviceSession(d.params!, bridge),
    );
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    late BuildContext root;
    final boundary = GlobalKey();
    try {
      await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ZcodeRemoteApp(
          preferences: prefs,
          home: Builder(builder: (context) {
            root = context;
            return const Scaffold();
          }),
        ),
      ));
      await openDeviceWorkspace(root, sessions, prefs, device,
          target: TaskTarget(
              deviceId: device.id,
              workspaceKey: 'workspace',
              sessionId: 'task',
              title: 'Main task'));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('工作面板').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('任务状态'));
      await tester.pumpAndSettle();
      expect(find.byType(ConversationChangeSummary), findsWidgets);
      expect(find.text('1 个文件已更改'), findsWidgets);
      await captureReviewBoundary(tester, boundary, 'u12-summary-1180-zh');

      await tester.tap(find.text('辅助对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开辅助对话'));
      await tester.pumpAndSettle();
      final main = find.byWidgetPredicate(
          (widget) => widget is ChatPage && widget.sessionId == 'task');
      final side = find.byWidgetPredicate(
          (widget) => widget is ChatPage && widget.sessionId == 'task-side');
      expect(main, findsOneWidget);
      expect(side, findsOneWidget);
      expect(find.descendant(of: main, matching: find.byIcon(Icons.edit_outlined)),
          findsOneWidget);
      expect(find.descendant(of: side, matching: find.byIcon(Icons.edit_outlined)),
          findsNothing);
      expect(find.descendant(of: side, matching: find.byIcon(Icons.account_tree_outlined)),
          findsNothing);
      expect(find.descendant(of: side, matching: find.byIcon(Icons.thumb_up_alt_outlined)),
          findsNothing);
      expect(find.descendant(of: side, matching: find.byType(TextField)),
          findsOneWidget);
      expect(find.descendant(of: side, matching: find.byKey(const ValueKey('composer-model'))),
          findsOneWidget,
          reason: 'Side chat keeps the model configuration chip.');
      await tester.tap(find.descendant(
          of: side, matching: find.byKey(const ValueKey('composer-model'))));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('composer-manage-models')), findsOneWidget,
          reason: 'Side chat keeps the model management entry.');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await captureReviewBoundary(tester, boundary, 'u12-side-1180-zh');
      tester.view.physicalSize = const Size(344, 820);
      await tester.pumpAndSettle();
      await captureReviewBoundary(tester, boundary, 'u12-side-344-zh');
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled;
      prefs.dispose();
    }
  });

  testWidgets('late A side creation cannot clear pending B operation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final store =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await store.addUrl(
      'https://zcode.z.ai/remote/v4?sid=synthetic-side-race&hash=synthetic&t=1',
      label: 'Side race test',
    );
    final bridge = _ScenarioBridge();
    final aDone = Completer<String>();
    final bDone = Completer<String>();
    bridge.conversationTransport.sideCreateHandler = (parent) =>
        parent == 'task-a' ? aDone.future : bDone.future;
    bridge.states['task-a'] = _stateFor('task-a', side: false);
    bridge.states['task-b'] = _stateFor('task-b', side: false);
    bridge.states['task-a-side'] = _stateFor('task-a-side', side: true);
    bridge.states['task-b-side'] = _stateFor('task-b-side', side: true);
    final sessions = _ScenarioSessions(store: store, bridge: bridge);
    final prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    late BuildContext root;
    try {
      await tester.pumpWidget(ZcodeRemoteApp(
        preferences: prefs,
        home: Builder(builder: (context) {
          root = context;
          return const Scaffold();
        }),
      ));
      await openDeviceWorkspace(root, sessions, prefs, device,
          target: TaskTarget(
              deviceId: device.id,
              workspaceKey: 'workspace',
              sessionId: 'task-a',
              title: 'Task A'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('工作面板').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('辅助对话'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开辅助对话'));
      await tester.pump();

      await openDeviceWorkspace(
          tester.element(find.byType(WorkspaceShell)), sessions, prefs, device,
          target: TaskTarget(
              deviceId: device.id,
              workspaceKey: 'workspace',
              sessionId: 'task-b',
              title: 'Task B'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('打开辅助对话'));
      await tester.pump();
      expect(find.text('正在打开…'), findsOneWidget);

      aDone.complete('task-a-side');
      await tester.pumpAndSettle();
      expect(find.text('正在打开…'), findsOneWidget,
          reason: 'Late A finally must not clear B loading state.');
      expect(bridge.conversationTransport.sideCreates, 2);
      expect(sessions.sideChats[TaskTarget(
              deviceId: device.id,
              workspaceKey: 'workspace',
              sessionId: 'task-a',
              title: '').key],
          'task-a-side');

      bDone.complete('task-b-side');
      await tester.pumpAndSettle();
      expect(find.byWidgetPredicate(
          (widget) => widget is ChatPage && widget.sessionId == 'task-b-side'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      sessions.dispose();
      await sessions.notifications.settled;
      prefs.dispose();
    }
  });
}
