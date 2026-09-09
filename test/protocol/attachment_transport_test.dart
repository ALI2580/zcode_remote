import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/protocol/ipc_codec.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';

class _Bridge implements BridgeSession {
  _Bridge() {
    channels = ChannelClient(sendBody: (body) {
      final reader = ValueReader(body);
      final header = decodeValue(reader);
      final args = decodeValue(reader) as List;
      if (header is! List || header.first != ChannelClient.reqPromise) return;
      final method = header[3] as String;
      final payload = args.isNotEmpty && args.first is Map
          ? Map<String, dynamic>.from(args.first)
          : <String, dynamic>{};
      calls.add((method: method, payload: payload));
      final answer = response?.call(method, payload) ??
          switch (method) {
            'helloConversationV4' => {'connectionId': 'synthetic'},
            'attachmentBeginV4' => {'nextChunkIndex': 0},
            'attachmentChunkV4' => {
                'nextChunkIndex': payload['chunkIndex'] + 1
              },
            'attachmentCommitV4' => {'ref': 'synthetic-attachment'},
            _ => <String, dynamic>{},
          };
      final writer = ValueWriter();
      encodeValue(writer, [ChannelClient.resPromiseSuccess, header[1]]);
      encodeValue(writer, answer);
      channels.handleMessage(writer.toBytes());
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
  final calls = <({String method, Map<String, dynamic> payload})>[];
  dynamic Function(String, Map<String, dynamic>)? response;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('upload encodes scoped begin/chunks/commit and a SHA-256 checksum',
      () async {
    final bridge = _Bridge();
    final transport = ConversationTransport(session: bridge, scope: const {
      'workspaceIdentity': 'work',
      'workspacePath': 'D:/Synthetic'
    });
    final bytes = Uint8List(800000);
    for (var i = 0; i < bytes.length; i++) {
      bytes[i] = i % 251;
    }
    final result = await transport.attachmentPut('same-session',
        fileName: 'draft.bin', mime: 'application/octet-stream', bytes: bytes);
    final commands = bridge.calls
        .where((call) => call.method.startsWith('attachment'))
        .toList();
    final begin = commands.first.payload;
    expect(begin['totalBytes'], bytes.length);
    expect(begin['totalChunks'], 3);
    expect(begin['checksum'], 'sha256:${sha256.convert(bytes)}');
    expect(commands.last.method, 'attachmentCommitV4');
    final rebuilt = BytesBuilder();
    for (final command in commands) {
      expect(command.payload['workspaceIdentity'], 'work');
      expect(command.payload['workspacePath'], 'D:/Synthetic');
      expect(command.payload['sessionId'], 'same-session');
      expect(command.payload['uploadId'], begin['uploadId']);
      if (command.method == 'attachmentChunkV4') {
        rebuilt.add(base64Decode(command.payload['dataBase64']));
      }
    }
    expect(rebuilt.takeBytes(), bytes);
    expect(result, {
      'ref': 'synthetic-attachment',
      'fileName': 'draft.bin',
      'mime': 'application/octet-stream',
      'bytes': bytes.length
    });
  });

  test('cancel after the first chunk aborts the same upload and never commits',
      () async {
    final bridge = _Bridge();
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'A'});
    var cancelled = false;
    await expectLater(
        transport.attachmentPut('same',
            fileName: 'cancel.bin',
            mime: 'application/octet-stream',
            bytes: Uint8List(800000),
            isCancelled: () => cancelled,
            onProgress: (_) => cancelled = true),
        throwsStateError);
    final chunks =
        bridge.calls.where((call) => call.method == 'attachmentChunkV4');
    final abort =
        bridge.calls.singleWhere((call) => call.method == 'attachmentAbortV4');
    expect(chunks, hasLength(1));
    expect(abort.payload['uploadId'], chunks.single.payload['uploadId']);
    expect(bridge.calls.where((call) => call.method == 'attachmentCommitV4'),
        isEmpty);
  });

  test(
      'invalid server progress and missing committed ref abort rather than send',
      () async {
    for (final failure in ['progress', 'ref']) {
      final bridge = _Bridge()
        ..response = (method, payload) {
          if (failure == 'progress' && method == 'attachmentChunkV4') {
            return {'nextChunkIndex': 99};
          }
          if (failure == 'ref' && method == 'attachmentCommitV4') return {};
          return null;
        };
      final transport = ConversationTransport(session: bridge, scope: const {});
      await expectLater(
          transport.attachmentPut('task',
              fileName: 'fail.txt', mime: 'text/plain', bytes: Uint8List(3)),
          throwsStateError);
      expect(bridge.calls.where((call) => call.method == 'attachmentAbortV4'),
          hasLength(1));
      expect(
          bridge.calls
              .where((call) => call.method == 'sendConversationCommandV4'),
          isEmpty);
    }
  });

  test('already committed upload returns its reference without retransferring',
      () async {
    final bridge = _Bridge()
      ..response = (method, payload) => method == 'attachmentBeginV4'
          ? {'state': 'committed', 'ref': 'existing'}
          : null;
    final transport = ConversationTransport(session: bridge, scope: const {});
    expect(
        (await transport.attachmentPut('task',
            fileName: 'same.txt',
            mime: 'text/plain',
            bytes: Uint8List(3)))['ref'],
        'existing');
    expect(bridge.calls.where((call) => call.method.startsWith('attachment')),
        hasLength(1));
  });

  test('oversized file is rejected before handshake or allocation of an upload',
      () async {
    final bridge = _Bridge();
    final transport = ConversationTransport(session: bridge, scope: const {});
    await expectLater(
        transport.attachmentPut('task',
            fileName: 'large',
            mime: 'application/octet-stream',
            bytes: Uint8List(20 * 1024 * 1024 + 1)),
        throwsStateError);
    expect(bridge.calls, isEmpty);
  });
}
