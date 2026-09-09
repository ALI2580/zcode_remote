import 'package:flutter/foundation.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/app_sessions.dart';
import 'package:zcode_remote/state/device_session.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/notifications/task_notification_controller.dart';
import 'package:zcode_remote/notifications/task_progress.dart';
import '../notifications/fake_notification_platform.dart';

class FakeDeviceSession extends DeviceSession {
  FakeDeviceSession(super.params, this.bridge, {this.gate});
  final FakeBridge bridge;
  final Future<void>? gate;
  int closes = 0;
  @override
  bool get connected => true;
  @override
  List<Map<String, dynamic>> get workspaces => const [
        {
          'workspaceIdentity': 'workspace',
          'name': 'ZcodeRemote',
          'workspacePath': 'D:/Project'
        }
      ];
  @override
  Future<void> connect({void Function(String)? onLog}) async {
    await gate;
  }

  @override
  void dispose() {
    closes++;
    super.dispose();
  }
}

class FakeAppSessions extends AppSessions {
  FakeAppSessions(
      {required super.store,
      required super.sessionFactory,
      super.recovery,
      super.restoreAttachment})
      : super(
            notifications: TaskNotificationController(
                platform: FakeNotificationPlatform()));
  final monitors = <String, WorkspaceMonitor>{};
  @override
  WorkspaceMonitor? monitorFor(String deviceId, String workspaceKey) =>
      monitors[deviceId];
  @override
  Future<WorkspaceMonitor> openWorkspace(
      Device device, String key, Map<String, dynamic> scope) async {
    final session = sessionFor(device) as FakeDeviceSession;
    await session.connect();
    return monitors.putIfAbsent(
        device.id,
        () => FakeWorkspaceMonitor(
            bridge: session.bridge,
            scope: scope,
            notifications: notifications,
            source: WorkspaceTaskSource(
                deviceId: device.id,
                deviceLabel: device.label,
                workspaceKey: key)));
  }

  @override
  void dispose() {
    for (final monitor in monitors.values) {
      monitor.dispose();
    }
    super.dispose();
  }
}

class FakeWorkspaceMonitor extends WorkspaceMonitor {
  FakeWorkspaceMonitor(
      {required super.bridge,
      required super.scope,
      required super.source,
      required super.notifications});
  @override
  bool get ready => true;
}

class FakeBridge implements BridgeSession {
  @override
  final recovered = ValueSignal<int>(0);
  @override
  final degraded = ValueSignal<String?>(null);
  late final conversationTransport = FakeConversationTransport(this);
  @override
  ConversationTransport conversation(Map<String, dynamic> scope,
          {void Function(String)? onLog}) =>
      conversationTransport;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeConversationTransport extends ConversationTransport {
  FakeConversationTransport(BridgeSession session)
      : super(session: session, scope: const {});
  final states = <String, ConversationState>{};
  final subscriptions = <String, int>{};
  final disposals = <String, int>{};
  final sent = <String>[];
  Object response = const {'status': 'accepted'};
  Object history = const {'rows': [], 'hasMore': false};
  Future<dynamic> Function(String sessionId, int? beforeRowId, int limit)?
      historyHandler;
  final historyRequests = <({String sessionId, int? beforeRowId, int limit})>[];
  int sideCreates = 0;
  final commands =
      <({String? sessionId, String type, Map<String, dynamic> payload})>[];
  Future<dynamic> Function(String?, String, Map<String, dynamic>)?
      commandHandler;
  Future<WorkspacePrep> Function()? prepHandler;
  @override
  Future<WorkspacePrep> prepareWorkspace({bool refresh = false}) async =>
      prepHandler == null
          ? WorkspacePrep.fromRaw(composerPrepFixture)
          : await prepHandler!();
  @override
  Future<dynamic> sendCommand(
      String? sessionId, String type, Map<String, dynamic> payload,
      {Duration timeout = const Duration(seconds: 30)}) async {
    commands.add((sessionId: sessionId, type: type, payload: payload));
    if (commandHandler != null) {
      return await commandHandler!(sessionId, type, payload);
    }
    if (type == 'createSession') {
      return {
        'status': 'accepted',
        'result': {'sessionId': 'created-task'}
      };
    }
    return response;
  }

  @override
  Future<ConversationSubscription> subscribe(String sessionId) async {
    subscriptions.update(sessionId, (v) => v + 1, ifAbsent: () => 1);
    return FakeConversationSubscription(
        states.putIfAbsent(
            sessionId,
            () => ConversationState()
              ..applyFrame({
                'payload': {
                  'kind': 'snapshot',
                  'snapshot': composerSnapshotFixture
                },
                'toSeq': 1,
              }, onGap: () {})),
        () => disposals.update(sessionId, (v) => v + 1, ifAbsent: () => 1));
  }

  @override
  Future<dynamic> sendText(String sessionId, String text,
      {List<Map<String, dynamic>>? attachments,
      String? heldQueueDisposition,
      List<String>? expectedHeldQueueItemIds,
      String? automationId,
      String? offPeakTaskId,
      String? offPeakRunType,
      String? botDeliveryTarget,
      List<String>? toolDisallowlist}) async {
    sent.add(text);
    return sendCommand(sessionId, 'sendText', {
      'text': text,
      if (attachments != null && attachments.isNotEmpty)
        'attachments': attachments,
      if (heldQueueDisposition != null)
        'heldQueueDisposition': heldQueueDisposition,
      if (expectedHeldQueueItemIds != null)
        'expectedHeldQueueItemIds': expectedHeldQueueItemIds,
    });
  }

  @override
  Future<String> createSelectionSideSession(String parentSessionId,
      {Duration timeout = const Duration(seconds: 60)}) async {
    sideCreates++;
    return '$parentSessionId-side';
  }

  @override
  Future<dynamic> rowsRange(String sessionId,
      {int? beforeRowId, int limit = 60}) async {
    historyRequests
        .add((sessionId: sessionId, beforeRowId: beforeRowId, limit: limit));
    return historyHandler == null
        ? history
        : await historyHandler!(sessionId, beforeRowId, limit);
  }
}

class FakeConversationSubscription implements ConversationSubscription {
  FakeConversationSubscription(this.state, this.onDispose);
  @override
  final ConversationState state;
  final VoidCallback onDispose;
  @override
  Future<void> dispose() async {
    onDispose();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void seedConversation(ConversationState state, {int count = 12}) {
  state.applyFrame({
    'toSeq': 1,
    'payload': {
      'kind': 'snapshot',
      'snapshot': {
        ...composerSnapshotFixture,
        'revision': 1,
        'logEpoch': 'test',
        'control': {'phase': 'idle'},
        'rows': {
          'totalCount': count * 2,
          'firstRowId': 1,
          'window': [
            for (var i = 0; i < count; i++) ...[
              {
                'kind': 'userInput',
                'rowId': i * 2 + 1,
                'text': '检查第 ${i + 1} 项布局和状态恢复'
              },
              {
                'kind': 'assistantText',
                'rowId': i * 2 + 2,
                'text': '已检查当前任务的布局。\n\n折叠、旋转和切换设备后，草稿与阅读位置会继续保留。'
              },
            ],
          ]
        },
      }
    }
  }, onGap: () {});
}

const composerPrepFixture = {
  'configOptions': [
    {
      'id': 'model',
      'category': 'model',
      'type': 'select',
      'currentValue': 'builtin:zai/GLM-5.2',
      'options': [
        {
          'value': 'builtin:zai/GLM-5.2',
          'name': 'GLM-5.2',
          'modelProviderId': 'builtin:zai',
          'modelProviderName': 'Z.ai',
          'modelThoughtLevels': ['nothink', 'high', 'max'],
          'modelDefaultThoughtLevel': 'max'
        },
        {
          'value': 'custom:provider-b:second-model',
          'name': 'Second model',
          'modelProviderId': 'provider-b',
          'modelProviderName': 'Provider B',
          'modelThoughtLevels': ['off', 'enabled'],
          'modelDefaultThoughtLevel': 'enabled'
        },
        {
          'value': 'provider-b/fixed-model',
          'name': 'Fixed model',
          'modelProviderId': 'provider-b',
          'modelProviderName': 'Provider B',
          'modelThoughtLevels': []
        },
      ]
    },
    {
      'id': 'mode',
      'category': 'mode',
      'type': 'select',
      'currentValue': 'build',
      'options': [
        {
          'value': 'build',
          'name': 'Build',
          'description': 'Confirm before changing files'
        },
        {
          'value': 'plan',
          'name': 'Plan',
          'description': 'Plan the task before implementation'
        },
        {'value': 'edit', 'name': 'Edit'},
        {'value': 'yolo', 'name': 'Full access'},
      ]
    },
    {
      'id': 'thought_level',
      'category': 'thought_level',
      'type': 'select',
      'currentValue': 'max',
      'options': [
        {'value': 'nothink', 'name': 'Off'},
        {'value': 'high', 'name': 'High'},
        {'value': 'max', 'name': 'Max'},
      ]
    },
  ],
};

const composerSnapshotFixture = {
  'sessionId': 'task',
  'revision': 1,
  'logEpoch': 'synthetic-epoch',
  'config': {
    'provider': 'builtin:zai',
    'model': 'GLM-5.2',
    'thought': 'max',
    'thoughtLevels': ['nothink', 'high', 'max'],
    'mode': 'build',
    'followupMode': 'queue'
  },
  'control': {
    'phase': 'idle',
    'canStop': false,
    'stopState': 'idle',
    'activeWorks': []
  },
  'inputRouting': {'mode': 'startNow'},
  'availability': {
    'switchModelConfig': {'allowed': true},
    'setFollowupMode': {'allowed': true},
    'queueEdit': {'allowed': true},
    'sendQueuedNow': {'allowed': true}
  },
  'queue': {'items': [], 'autoDrain': true},
};
