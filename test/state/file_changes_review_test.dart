import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/protocol/ipc_codec.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/file_changes_review.dart';

class _Bridge implements BridgeSession {
  _Bridge() {
    channels = ChannelClient(sendBody: (body) {
      final reader = ValueReader(body);
      final header = decodeValue(reader) as List;
      final args = decodeValue(reader) as List;
      final method = header[3] as String;
      final id = header[1] as int;
      void respond(dynamic value) {
        final writer = ValueWriter();
        encodeValue(writer, [ChannelClient.resPromiseSuccess, id]);
        encodeValue(writer, value);
        channels.handleMessage(writer.toBytes());
      }

      void respondError(dynamic value) {
        final writer = ValueWriter();
        encodeValue(writer, [ChannelClient.resPromiseError, id]);
        encodeValue(writer, value);
        channels.handleMessage(writer.toBytes());
      }

      if (method == 'helloConversationV4') {
        respond({'connectionId': 'synthetic'});
      } else if (method == 'initializeConversationV4') {
        respond({});
      } else if (method == 'conversationFileChangesV4') {
        final request = _PendingRequest(
          (args.single as Map).cast<String, dynamic>(),
          respond,
          respondError,
        );
        requests.add(request);
        if (autoRespond) respond(response);
      } else if (method == 'conversationFileRewindPreviewV4') {
        final request = _PendingRequest(
          (args.single as Map).cast<String, dynamic>(),
          respond,
          respondError,
        );
        previews.add(request);
        if (autoRespond) respond(previewResponse);
      } else if (method == 'sendConversationCommandV4') {
        final packet = (args.single as Map).cast<String, dynamic>();
        final request = _PendingRequest(
          (packet['envelope'] as Map).cast<String, dynamic>(),
          respond,
          respondError,
        );
        commands.add(request);
        if (autoRespond) respond(applyResponse);
      }
    });
    final writer = ValueWriter();
    encodeValue(writer, [ChannelClient.resInitialize]);
    channels.handleMessage(writer.toBytes());
  }

  @override
  late final ChannelClient channels;
  @override
  final degraded = ValueSignal<String?>(null);
  @override
  final recovered = ValueSignal<int>(0);
  @override
  final recoveryStarting = ValueSignal<int>(0);
  dynamic response;
  dynamic previewResponse;
  dynamic applyResponse;
  bool autoRespond = true;
  final requests = <_PendingRequest>[];
  final previews = <_PendingRequest>[];
  final commands = <_PendingRequest>[];

  @override
  Future<void> waitHealthy(
      {Duration timeout = const Duration(seconds: 45)}) async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingRequest {
  final Map<String, dynamic> packet;
  final void Function(dynamic value) respond;
  final void Function(dynamic value) respondError;
  final completer = Completer<dynamic>();

  _PendingRequest(this.packet, this.respond, this.respondError);
}

FileChangesReviewController _controller(ConversationTransport transport) =>
    FileChangesReviewController(
      transport: transport,
      scope: const FileChangesScope(
        deviceId: 'device-a',
        workspaceKey: 'workspace-a',
        sessionId: 'session-a',
        rowId: 12,
        entityId: 'entity-a',
      ),
      revision: () => 7,
      logEpoch: () => 'epoch-a',
    );

void main() {
  test('loads review payload, exposes the first file and can refresh',
      () async {
    final bridge = _Bridge();
    bridge.response = {
      'files': 1,
      'additions': 1,
      'deletions': 0,
      'items': [
        {
          'path': 'lib/a.dart',
          'additions': 1,
          'deletions': 0,
          'writeCount': 1,
          'toolNames': ['edit'],
          'patches': [
            {
              'oldStart': 1,
              'oldLines': 1,
              'newStart': 1,
              'newLines': 1,
              'lines': ['+new'],
            }
          ],
        }
      ],
    };
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'a'});
    final controller = _controller(transport);
    await controller.load();

    final request = bridge.requests.single.packet;
    expect(request['sessionId'], 'session-a');
    expect(request['target'], {'rowId': 12, 'entityId': 'entity-a'});
    expect(request['baseRevision'], 7);
    expect(request['baseLogEpoch'], 'epoch-a');
    expect(controller.status, FileChangesStatus.loaded);
    // U21: no first file is auto-selected; opening a diff is explicit.
    expect(controller.selectedPath, isNull);
    expect(controller.result?.items.single.patches.single.lines, ['+new']);

    await controller.retry();
    expect(bridge.requests, hasLength(2));
    controller.dispose();
    bridge.channels.dispose();
  });

  test('keeps an RPC error visible and does not overwrite it with a stale load',
      () async {
    final bridge = _Bridge();
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'a'});
    final controller = _controller(transport);

    bridge.autoRespond = false;
    final failed = controller.load();
    final newer = controller.load(refresh: true);
    while (bridge.requests.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    final first = bridge.requests.first;
    final second = bridge.requests.last;
    first.respondError({'message': 'old request failed'});
    second.respond({'files': 1, 'items': []});
    await expectLater(failed, throwsA(isA<ChannelRpcError>()));
    await newer;
    expect(controller.status, FileChangesStatus.loaded);
    expect(controller.error, isNull);
    expect(second.packet['sessionId'], 'session-a');
    controller.dispose();
    bridge.channels.dispose();
  });

  test('previews and applies rewind only through synthetic transport',
      () async {
    final bridge = _Bridge();
    bridge.response = {'files': 1, 'items': []};
    bridge.previewResponse = {
      'canApply': true,
      'safeFiles': [
        {
          'action': 'restore',
          'operationCount': 2,
          'path': 'lib/a.dart',
          'toolNames': ['edit'],
        }
      ],
      'unsafeFiles': [],
      'ignoredFiles': [],
    };
    bridge.applyResponse = {
      'status': 'accepted',
      'result': {
        'type': 'applyFileRewind',
        'applied': true,
        'response': 'rewind-response',
        'preview': bridge.previewResponse,
      },
    };
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'a'});
    final controller = _controller(transport);
    await controller.load();

    controller.openRewind();
    await controller.previewRewind();
    expect(controller.rewindOpen, isTrue);
    expect(controller.rewindLoading, isFalse);
    expect(controller.rewindPreview?.canApply, isTrue);
    expect(bridge.previews.single.packet['target'],
        {'rowId': 12, 'entityId': 'entity-a'});

    final result = await controller.applyRewind();
    expect(result.status, 'accepted');
    expect(result.applied, isTrue);
    expect(controller.rewindOpen, isFalse);
    expect(controller.rewindApplyError, isNull);
    expect(bridge.commands.single.packet['type'], 'applyFileRewind');
    expect(bridge.commands.single.packet['payload']['target'],
        {'rowId': 12, 'entityId': 'entity-a'});
    controller.dispose();
    bridge.channels.dispose();
  });

  test('a second apply while one is in flight never duplicates the write',
      () async {
    final bridge = _Bridge();
    bridge.response = {'files': 1, 'items': []};
    bridge.previewResponse = {
      'canApply': true,
      'safeFiles': [
        {
          'action': 'restore',
          'operationCount': 1,
          'path': 'lib/a.dart',
          'toolNames': ['edit'],
        }
      ],
      'unsafeFiles': [],
      'ignoredFiles': [],
    };
    bridge.applyResponse = {
      'status': 'accepted',
      'result': {
        'type': 'applyFileRewind',
        'applied': true,
        'response': 'rewind-response',
        'preview': bridge.previewResponse,
      },
    };
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'a'});
    final controller = _controller(transport);
    await controller.load();
    controller.openRewind();
    await controller.previewRewind();

    final first = controller.applyRewind();
    // A second click while the first apply is pending is rejected locally.
    await expectLater(controller.applyRewind(), throwsStateError);
    final result = await first;
    expect(result.status, 'accepted');
    expect(bridge.commands.where((c) =>
        c.packet['type'] == 'applyFileRewind'), hasLength(1));
    controller.dispose();
    bridge.channels.dispose();
  });

  test('a rejected rewind stays open and preserves the server message',
      () async {
    final bridge = _Bridge();
    bridge.response = {'files': 1, 'items': []};
    bridge.previewResponse = {
      'canApply': true,
      'safeFiles': [],
      'unsafeFiles': [],
      'ignoredFiles': [],
    };
    bridge.applyResponse = {
      'status': 'rejected',
      'message': 'rejected by synthetic server',
      'result': {
        'type': 'applyFileRewind',
        'applied': false,
        'response': 'rewind-response',
      },
    };
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'a'});
    final controller = _controller(transport);
    await controller.load();
    controller.openRewind();
    await controller.previewRewind();

    final result = await controller.applyRewind();
    expect(result.status, 'rejected');
    expect(result.message, 'rejected by synthetic server');
    expect(controller.rewindOpen, isTrue);
    expect(controller.rewindApplyError, isNull);
    controller.dispose();
    bridge.channels.dispose();
  });

  test('discards a stale rewind preview after a newer file-changes refresh',
      () async {
    final bridge = _Bridge();
    bridge.response = {'files': 1, 'items': []};
    bridge.previewResponse = {
      'canApply': true,
      'safeFiles': [],
      'unsafeFiles': [],
      'ignoredFiles': [],
    };
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'a'});
    final controller = _controller(transport);
    await controller.load();

    bridge.autoRespond = false;
    final preview = controller.previewRewind();
    while (bridge.previews.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    final refresh = controller.load(refresh: true);
    while (bridge.requests.length < 2) {
      await Future<void>.delayed(Duration.zero);
    }
    bridge.previews.single.respond(bridge.previewResponse);
    bridge.requests.last.respond({'files': 1, 'items': []});
    await preview;
    await refresh;
    expect(controller.rewindPreview, isNull);
    expect(controller.rewindOpen, isFalse);
    controller.dispose();
    bridge.channels.dispose();
  });

  test('scope keys include device, workspace, session and row identity', () {
    const a = FileChangesScope(
        deviceId: 'a',
        workspaceKey: 'w',
        sessionId: 's',
        rowId: 1,
        entityId: 2);
    final b = FileChangesScope(
        deviceId: 'b',
        workspaceKey: 'w',
        sessionId: 's',
        rowId: 1,
        entityId: 2);
    final c = FileChangesScope(
        deviceId: 'a',
        workspaceKey: 'w',
        sessionId: 's',
        rowId: 1,
        entityId: null);
    expect(a.cacheKey == b.cacheKey, isFalse);
    expect(a.cacheKey == c.cacheKey, isFalse);
    expect(a.target, {'rowId': 1, 'entityId': 2});
    expect(c.target, {'rowId': 1});
  });
}
