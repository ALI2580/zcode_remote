import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/composer_attachments.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_store.dart';
import '../ui/fake_features.dart';

PickedAttachment file(String name, {int size = 4}) => PickedAttachment(
    name: name,
    mime: 'text/plain',
    size: size,
    read: () async => Uint8List.fromList([1, 2, 3, 4]));
Future<void> settle() => Future<void>.delayed(Duration.zero);

void main() {
  late ComposerStore store;
  late FeatureBridge bridge;
  late ComposerController draft;
  setUp(() async {
    store = ComposerStore();
    bridge = FeatureBridge();
    draft = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'same-workspace');
    await draft.loadOptions();
  });
  tearDown(() => store.dispose());

  test(
      'explicit re-preparation retains input and never retries an uncertain submission',
      () async {
    draft.input.text = 'retain draft';
    draft.attachments.add([file('retry.txt')]);
    await settle();
    bridge.conversationTransport.response = {'status': 'rejected'};
    expect(await draft.send(), ComposerSendResult.failed);
    expect(draft.canReprepareAttachments, isTrue);
    expect(await draft.reprepareAttachments(), isTrue);
    await settle();
    expect(draft.input.text, 'retain draft');
    expect(bridge.conversationTransport.sent, hasLength(1));
    expect(bridge.conversationTransport.uploads, hasLength(2));
    bridge.conversationTransport.commandHandler =
        (id, type, payload) => Future.error(TimeoutException('uncertain'));
    expect(await draft.send(), ComposerSendResult.failed);
    expect(draft.canReprepareAttachments, isFalse);
    final count = bridge.conversationTransport.commands.length;
    expect(await draft.reprepareAttachments(), isFalse);
    expect(bridge.conversationTransport.commands, hasLength(count));
  });

  test('attachment first input creates once, uploads before one send, promotes',
      () async {
    draft.input.text = 'first input';
    final gate = Completer<void>();
    bridge.conversationTransport.uploadHandler = () => gate.future;
    draft.attachments.add([file('one.txt'), file('two.txt')]);
    await settle();
    expect(draft.sessionId, isNull);
    expect(draft.canSend, isFalse);
    expect(await draft.send(), ComposerSendResult.blocked);
    final creates = bridge.conversationTransport.commands
        .where((command) => command.type == 'createSession');
    expect(creates, hasLength(1));
    expect(creates.single.payload.containsKey('firstInput'), isFalse);
    gate.complete();
    await settle();
    expect(draft.canSend, isTrue);
    expect(await draft.send(), ComposerSendResult.sent);
    final sends = bridge.conversationTransport.commands
        .where((command) => command.type == 'sendText');
    expect(sends, hasLength(1));
    expect(sends.single.sessionId, 'created-task');
    expect(sends.single.payload['attachments'], hasLength(2));
    expect(sends.single.payload['text'], 'first input');
    expect(draft.sessionId, 'created-task');
    expect(draft.attachments.items, isEmpty);
    expect(draft.input.text, isEmpty);
    expect(store.attachmentDrafts, isEmpty);
  });

  test('rejected first input preserves text and files, retry uses same session',
      () async {
    draft.input.text = 'preserve me';
    draft.attachments.add([file('one.txt')]);
    await settle();
    bridge.conversationTransport.response = {'status': 'rejected'};
    expect(await draft.send(), ComposerSendResult.failed);
    expect(draft.input.text, 'preserve me');
    expect(draft.attachments.items.single.phase, AttachmentPhase.ready);
    expect(draft.sessionId, isNull);
    bridge.conversationTransport.response = {'status': 'accepted'};
    expect(await draft.send(), ComposerSendResult.sent);
    expect(
        bridge.conversationTransport.commands
            .where((command) => command.type == 'createSession'),
        hasLength(1));
    expect(bridge.conversationTransport.uploads, hasLength(1));
  });

  test('uncertain first input never retries or deletes a potentially sent task',
      () async {
    draft.input.text = 'uncertain';
    draft.attachments.add([file('one.txt')]);
    await settle();
    bridge.conversationTransport.commandHandler = (id, type, payload) =>
        Future.error(TimeoutException('synthetic receipt timeout'));
    expect(await draft.send(), ComposerSendResult.failed);
    expect(draft.failure, ComposerFailure.uncertain);
    expect(draft.input.text, 'uncertain');
    expect(draft.attachments.items, hasLength(1));
    await settle();
    store.disconnect('A');
    await settle();
    expect(
        bridge.conversationTransport.commands
            .where((command) => command.type == 'sendText'),
        hasLength(1));
    expect(
        bridge.conversationTransport.commands
            .where((command) => command.type == 'deleteSession'),
        isEmpty);
  });

  test('cancelled upload cannot reappear when the response arrives', () async {
    final gate = Completer<void>();
    bridge.conversationTransport.uploadHandler = () => gate.future;
    draft.attachments.add([file('cancel.txt')]);
    await settle();
    draft.attachments.remove(draft.attachments.items.single);
    gate.complete();
    await settle();
    expect(draft.attachments.items, isEmpty);
    expect(draft.attachments.descriptors, isEmpty);
    expect(store.attachmentDrafts, isEmpty);
    expect(bridge.conversationTransport.sent, isEmpty);
  });

  test('oversized files do not create sessions, upload failures can be retried',
      () async {
    draft.attachments.add([file('large.txt', size: 21 * 1024 * 1024)]);
    await settle();
    expect(draft.attachments.items.single.tooLarge, isTrue);
    expect(bridge.conversationTransport.commands, isEmpty);
    draft.attachments.remove(draft.attachments.items.single);
    bridge.conversationTransport.uploadHandler =
        () => Future.error(StateError('upload'));
    draft.attachments.add([file('retry.txt')]);
    await settle();
    final item = draft.attachments.items.single;
    expect(item.phase, AttachmentPhase.failed);
    bridge.conversationTransport.uploadHandler = null;
    draft.attachments.retry(item);
    await settle();
    expect(item.phase, AttachmentPhase.ready);
    expect(bridge.conversationTransport.uploads, hasLength(2));
    expect(
        bridge.conversationTransport.commands
            .where((command) => command.type == 'createSession'),
        hasLength(1));
  });

  test('same task IDs keep device attachments and late sends isolated',
      () async {
    final otherBridge = FeatureBridge();
    final b = store.obtain(
        transport: otherBridge.conversationTransport,
        deviceId: 'B',
        workspaceKey: 'same-workspace');
    await b.loadOptions();
    draft.attachments.add([file('A.txt')]);
    b.attachments.add([file('B.txt')]);
    await settle();
    final gate = Completer<dynamic>();
    bridge.conversationTransport.commandHandler =
        (id, type, payload) => gate.future;
    final sent = draft.send();
    await settle();
    b.input.text = 'B stays';
    draft.input.text = 'A newer text';
    gate.complete({'status': 'accepted'});
    expect(await sent, ComposerSendResult.sent);
    expect(draft.input.text, 'A newer text');
    expect(b.input.text, 'B stays');
    expect(b.attachments.items.single.file.name, 'B.txt');
    expect(otherBridge.conversationTransport.sent, isEmpty);
    expect(store.attachmentDrafts[b.key]!.single.name, 'B.txt');
  });

  test('configuration changed after upload is applied before first input',
      () async {
    draft.attachments.add([file('config.txt')]);
    await settle();
    await draft.selectModel('builtin:bigmodel-coding-plan/GLM-5.2');
    expect(await draft.send(), ComposerSendResult.sent);
    final commands = bridge.conversationTransport.commands;
    final configIndex =
        commands.indexWhere((e) => e.type == 'switchModelConfig');
    final sendIndex = commands.indexWhere((e) => e.type == 'sendText');
    expect(configIndex, greaterThanOrEqualTo(0));
    expect(sendIndex, greaterThan(configIndex));
    expect(commands[configIndex].payload['provider'],
        'builtin:bigmodel-coding-plan');
  });
}
