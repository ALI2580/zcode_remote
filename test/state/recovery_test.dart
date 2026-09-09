import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/notifications/task_target.dart';
import 'package:zcode_remote/state/composer_attachments.dart';
import 'package:zcode_remote/state/composer_controller.dart';
import 'package:zcode_remote/state/composer_input.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/state/device_store.dart';
import 'package:zcode_remote/state/recovery_journal.dart';
import 'package:zcode_remote/state/workspace_view_state.dart';
import '../ui/fake_features.dart';
import '../ui/fake_workspace.dart';

class MemoryRecoveryStorage implements RecoveryStorage {
  String? current, previous;
  int writes = 0;
  Future<void> Function(String)? beforeWrite;
  @override
  Future<List<String>> readCandidates() async =>
      [if (current != null) current!, if (previous != null) previous!];
  @override
  Future<void> write(String value, String? backup) async {
    writes++;
    await beforeWrite?.call(value);
    previous = backup;
    current = value;
  }
}

Future<String?> encrypt(String text) async =>
    'enc:${base64Encode(utf8.encode(text))}';
Future<String?> decrypt(String text) async =>
    utf8.decode(base64Decode(text.substring(4)));
RecoveryJournal journal(MemoryRecoveryStorage storage) => RecoveryJournal(
    storage: storage, encrypted: true, encrypt: encrypt, decrypt: decrypt);
Map<String, dynamic> decoded(MemoryRecoveryStorage storage) =>
    jsonDecode(utf8.decode(base64Decode(storage.current!.substring(4))));
PickedAttachment picked(String name) => PickedAttachment(
    name: name,
    mime: 'text/plain',
    size: 4,
    recovery: {'token': 'cache-$name', 'sha256': 'synthetic'},
    read: () async => Uint8List.fromList([1, 2, 3, 4]));
Future<PickedAttachment> restoreFile(Map<String, dynamic> raw) async =>
    PickedAttachment(
        name: raw['name'],
        mime: raw['mime'],
        size: raw['size'],
        recovery: raw,
        read: () async => Uint8List.fromList([1, 2, 3, 4]));
FakeAppSessions app(RecoveryJournal journal, FeatureBridge bridge) =>
    FakeAppSessions(
        store:
            DeviceStore(requireEncryption: false, encrypt: (_) async => null),
        recovery: journal,
        restoreAttachment: restoreFile,
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
Future<void> tick() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
      'restart restores isolated editors, references, attachments, navigation and panels',
      () async {
    final storage = MemoryRecoveryStorage(), bridge = FeatureBridge();
    final first = app(journal(storage), bridge);
    await first.loadRecovery();
    final a = first.composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work',
        sessionId: 'same');
    final b = first.composers.obtain(
        transport: FeatureBridge().conversationTransport,
        deviceId: 'B',
        workspaceKey: 'work',
        sessionId: 'same');
    a.bind((await bridge.conversationTransport.subscribe('same')).state);
    await a.loadOptions();
    a.input.insertReference(
        const TextRange(start: 0, end: 0),
        const ComposerReference(
            id: 'f',
            category: 'files',
            label: 'main.dart',
            value: 'lib/main.dart'));
    a.input.value =
        a.input.value.copyWith(text: '${a.input.text}secret A draft');
    b.input.text = 'B independent';
    a.attachments.add([picked('A.txt')]);
    await tick();
    final draft = first.composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work');
    await draft.loadOptions();
    await draft.selectModel('builtin:bigmodel-coding-plan/GLM-5.2');
    const targetA = TaskTarget(
        deviceId: 'A',
        workspaceKey: 'work',
        sessionId: 'same',
        title: 'Task A');
    const targetB = TaskTarget(
        deviceId: 'B', workspaceKey: 'work', sessionId: '', title: 'Draft B');
    first.lastLocations['A'] = targetA;
    first.lastLocations['B'] = targetB;
    first.conversationViewStates[a.key] = ConversationViewState()
      ..following = false
      ..pixels = 420
      ..anchor = 'row-17'
      ..anchorOffset = -14;
    first.conversationViewStates[a.key]!.expandedTurns[17] = true;
    first.workspaceViewStates[targetA.key] = WorkspaceViewState()
      ..panelOpen = true
      ..panelTab = 'sideChat';
    first.sideChats[targetA.key] = 'side';
    first.sidebarStates['A'] = SidebarViewState()..archived = true;
    first.sidebarStates['A']!.expandedProjects.add('work');
    await first.flushRecovery();
    expect(storage.current, startsWith('enc:'));
    expect(storage.current, isNot(contains('secret A draft')));
    expect(storage.current, isNot(contains('lib/main.dart')));
    first.dispose();
    await first.notifications.settled;
    await tick();

    final nextBridge = FeatureBridge();
    final second = app(journal(storage), nextBridge);
    await second.loadRecovery();
    final restored = second.composers.obtain(
        transport: nextBridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work',
        sessionId: 'same');
    expect(
        restored.input.markdown, '[main.dart](./lib/main.dart) secret A draft');
    expect(restored.input.referenceCount, 1);
    expect(restored.attachments.items.single.phase, AttachmentPhase.ready);
    expect(
        await restored.attachments.preview(restored.attachments.items.single),
        [1, 2, 3, 4]);
    expect(second.drafts[b.key], 'B independent');
    expect(second.lastLocations['A'], targetA);
    expect(second.lastLocations['B'], targetB);
    expect(second.conversationViewStates[a.key]!.anchor, 'row-17');
    expect(second.conversationViewStates[a.key]!.anchorOffset, -14);
    expect(second.conversationViewStates[a.key]!.expandedTurns[17], isTrue);
    expect(second.workspaceViewStates[targetA.key]!.panelTab, 'sideChat');
    expect(second.sideChats[targetA.key], 'side');
    expect(second.sidebarStates['A']!.archived, isTrue);
    expect(second.sidebarStates['A']!.expandedProjects, contains('work'));
    final restoredDraft = second.composers.obtain(
        transport: nextBridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work');
    await restoredDraft.loadOptions();
    expect(restoredDraft.config['provider'], 'builtin:bigmodel-coding-plan');
    expect(nextBridge.conversationTransport.commands, isEmpty);
    second.dispose();
    await second.notifications.settled;
  });

  test(
      'a crash during send restores an uncertainty warning without resubmitting',
      () async {
    final storage = MemoryRecoveryStorage(), bridge = FeatureBridge();
    final first = app(journal(storage), bridge);
    await first.loadRecovery();
    final controller = first.composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work',
        sessionId: 'same');
    controller
        .bind((await bridge.conversationTransport.subscribe('same')).state);
    await controller.loadOptions();
    controller.input.text = 'never automatically repeat';
    final gate = Completer<dynamic>();
    bridge.conversationTransport.commandHandler =
        (id, type, payload) => gate.future;
    final sending = controller.send();
    await tick();
    await first.flushRecovery();
    expect(
        decoded(storage)['composers']['entries'][controller.key]['uncertain'],
        isTrue);
    final persisted = MemoryRecoveryStorage()..current = storage.current;
    first.dispose();
    gate.complete({'status': 'accepted'});
    await sending;
    await first.notifications.settled;
    final restartedBridge = FeatureBridge(),
        second = app(journal(persisted), FeatureBridge());
    await second.loadRecovery();
    final restored = second.composers.obtain(
        transport: restartedBridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work',
        sessionId: 'same');
    restored.bind(
        (await restartedBridge.conversationTransport.subscribe('same')).state);
    await restored.loadOptions();
    expect(restored.failure, ComposerFailure.uncertain);
    expect(restored.input.text, 'never automatically repeat');
    expect(restartedBridge.conversationTransport.sent, isEmpty);
    expect(restartedBridge.conversationTransport.commands, isEmpty);
    second.dispose();
    await second.notifications.settled;
  });

  test(
      'restored attachment draft reuses its provisional session without another creation',
      () async {
    final storage = MemoryRecoveryStorage(), firstBridge = FeatureBridge();
    final first = app(journal(storage), firstBridge);
    await first.loadRecovery();
    final draft = first.composers.obtain(
        transport: firstBridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work');
    await draft.loadOptions();
    draft.input.text = 'first input after restart';
    draft.attachments.add([picked('draft.txt')]);
    await tick();
    await tick();
    await first.flushRecovery();
    expect(
        firstBridge.conversationTransport.commands
            .where((e) => e.type == 'createSession'),
        hasLength(1));
    first.dispose();
    await first.notifications.settled;
    await tick();
    expect(
        firstBridge.conversationTransport.commands
            .where((e) => e.type == 'deleteSession'),
        isEmpty);
    final nextBridge = FeatureBridge(),
        second = app(journal(storage), FeatureBridge());
    await second.loadRecovery();
    final restored = second.composers.obtain(
        transport: nextBridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work');
    await restored.loadOptions();
    expect(nextBridge.conversationTransport.commands, isEmpty);
    expect(restored.attachments.items.single.phase, AttachmentPhase.ready);
    expect(await restored.send(), ComposerSendResult.sent);
    expect(
        nextBridge.conversationTransport.commands
            .where((e) => e.type == 'createSession'),
        isEmpty);
    final sends = nextBridge.conversationTransport.commands
        .where((e) => e.type == 'sendText');
    expect(sends, hasLength(1));
    expect(sends.single.sessionId, 'created-task');
    await second.flushRecovery();
    expect(decoded(storage)['composers']['entries'], isEmpty);
    second.dispose();
    await second.notifications.settled;
  });

  test('writes coalesce during slow storage and the newest edit wins',
      () async {
    final storage = MemoryRecoveryStorage();
    final active = journal(storage);
    var value = 'first';
    active.capture = () => {'schemaVersion': 1, 'text': value};
    await active.load();
    active.activate();
    final gate = Completer<void>();
    storage.beforeWrite =
        (_) => storage.writes == 1 ? gate.future : Future.value();
    final saving = active.flush();
    await tick();
    value = 'middle';
    active.schedule();
    value = 'latest';
    active.schedule();
    gate.complete();
    await saving;
    expect(storage.writes, 2);
    expect(decoded(storage)['text'], 'latest');
    active.dispose();
  });

  test('local save failure blocks submission and retains the previous snapshot',
      () async {
    final storage = MemoryRecoveryStorage(), bridge = FeatureBridge();
    final sessions = app(journal(storage), bridge);
    await sessions.loadRecovery();
    final controller = sessions.composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work');
    await controller.loadOptions();
    controller.input.text = 'first saved';
    await sessions.flushRecovery();
    final previous = storage.current;
    storage.beforeWrite = (_) => Future.error(StateError('disk unavailable'));
    controller.input.text = 'keep unsaved text';
    expect(await controller.send(), ComposerSendResult.failed);
    expect(controller.input.text, 'keep unsaved text');
    expect(storage.current, previous);
    expect(sessions.recovery!.failed, isTrue);
    expect(bridge.conversationTransport.commands, isEmpty);
    storage.beforeWrite = null;
    await sessions.flushRecovery();
    expect(sessions.recovery!.failed, isFalse);
    expect(
        decoded(storage)['composers']['entries'][controller.key]['input']
            ['text'],
        'keep unsaved text');
    sessions.dispose();
    await sessions.notifications.settled;
  });

  test(
      'attachment picker blocks early sends and a late result remains in its original scope',
      () async {
    final store = ComposerStore();
    final bridge = FeatureBridge();
    final a = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work');
    await a.loadOptions();
    a.input.text = 'A text';
    expect(a.beginAttachmentPick(), isTrue);
    expect(await a.send(), ComposerSendResult.blocked);
    final oldKey = a.key;
    store.disconnect('A');
    final b = store.obtain(
        transport: FeatureBridge().conversationTransport,
        deviceId: 'B',
        workspaceKey: 'work');
    b.input.text = 'B text';
    a.finishAttachmentPick([picked('A.txt')]);
    expect(store.attachmentDrafts[oldKey]!.single.name, 'A.txt');
    expect(b.attachments.items, isEmpty);
    expect(b.input.text, 'B text');
    expect(bridge.conversationTransport.sent, isEmpty);
    store.dispose();
  });

  test('missing cached files remain visible and cannot be silently sent',
      () async {
    final store = ComposerStore();
    final key = composerKey('A', 'work', 'same');
    await store.importRecovery(
        {
          'entries': {
            key: {
              'input': {'text': 'keep'},
              'attachments': [
                {
                  'file': {'name': 'lost.txt', 'mime': 'text/plain', 'size': 5},
                  'phase': 'ready',
                  'descriptor': {'ref': 'old'}
                }
              ]
            }
          }
        },
        (raw) async => PickedAttachment(
            name: raw['name'],
            mime: raw['mime'],
            size: raw['size'],
            unavailable: true,
            read: () async => throw const AttachmentUnavailable()));
    final bridge = FeatureBridge();
    final restored = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work',
        sessionId: 'same');
    restored.bind((await bridge.conversationTransport.subscribe('same')).state);
    await restored.loadOptions();
    expect(restored.input.text, 'keep');
    expect(restored.attachments.items.single.unavailable, isTrue);
    expect(restored.canSend, isFalse);
    expect(bridge.conversationTransport.commands, isEmpty);
    store.dispose();
  });

  test(
      'valid backup is recovered and encryption failure never writes plaintext',
      () async {
    final storage = MemoryRecoveryStorage()
      ..current = 'enc:broken'
      ..previous =
          await encrypt(jsonEncode({'schemaVersion': 1, 'composers': {}}));
    final recovering = journal(storage);
    expect((await recovering.load())['schemaVersion'], 1);
    expect(recovering.recoveredBackup, isTrue);
    final rejected = RecoveryJournal(
        storage: storage,
        encrypted: true,
        encrypt: (_) async => null,
        decrypt: decrypt);
    await rejected.load();
    rejected.capture = () => {'schemaVersion': 1, 'text': 'sensitive draft'};
    rejected.activate();
    final before = storage.current;
    await expectLater(rejected.flush(), throwsStateError);
    expect(storage.current, before);
    expect(storage.writes, 0);
    recovering.dispose();
    rejected.dispose();
  });

  test(
      'removing a device prevents late picker results from resurrecting its drafts',
      () async {
    final devices =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final a = await devices.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1');
    final b = await devices.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-B&hash=synthetic&t=1');
    final storage = MemoryRecoveryStorage(), bridge = FeatureBridge();
    final sessions = FakeAppSessions(
        store: devices,
        recovery: journal(storage),
        restoreAttachment: restoreFile,
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
    await sessions.loadRecovery();
    final first = sessions.composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: a.id,
        workspaceKey: 'work');
    final second = sessions.composers.obtain(
        transport: FeatureBridge().conversationTransport,
        deviceId: b.id,
        workspaceKey: 'work');
    first.input.text = 'remove A';
    second.input.text = 'keep B';
    first.beginAttachmentPick();
    await devices.remove(a.id);
    first.finishAttachmentPick([picked('late-A.txt')]);
    await sessions.flushRecovery();
    final entries = decoded(storage)['composers']['entries'] as Map;
    expect(entries.containsKey(first.key), isFalse);
    expect(entries[second.key]['input']['text'], 'keep B');
    expect(sessions.composers.attachmentDrafts.containsKey(first.key), isFalse);
    sessions.dispose();
    await sessions.notifications.settled;
  });

  test('device removal during hydration discards every restored scope',
      () async {
    final devices =
        DeviceStore(requireEncryption: false, encrypt: (_) async => null);
    final device = await devices.addUrl(
        'https://zcode.z.ai/remote/v4?sid=synthetic-A&hash=synthetic&t=1');
    final target = TaskTarget(
        deviceId: device.id,
        workspaceKey: 'work',
        sessionId: 'same',
        title: 'A');
    final key = composerKey(device.id, 'work', 'same');
    final draftKey = composerKey(device.id, 'work', null);
    final gate = Completer<PickedAttachment>();
    final storage = MemoryRecoveryStorage()
      ..current = await encrypt(jsonEncode({
        'schemaVersion': 1,
        'composers': {
          'draftConfigs': {
            draftKey: {'model': 'saved-model'}
          },
          'entries': {
            key: {
              'input': {'text': 'removed device draft'},
              'attachments': [
                {
                  'file': {'name': 'old.txt', 'mime': 'text/plain', 'size': 4}
                }
              ]
            },
            draftKey: {
              'input': {'text': 'another removed draft'}
            }
          }
        },
        'locations': {device.id: target.toJson()},
        'reading': {
          key: {'following': false, 'anchor': 'old'}
        },
        'panels': {
          target.key: {'panelOpen': true, 'panelTab': 'sideChat'}
        },
        'sidebar': {
          device.id: {'archived': true}
        },
        'sideChats': {target.key: 'old-side'}
      }));
    final bridge = FeatureBridge();
    final sessions = FakeAppSessions(
        store: devices,
        recovery: journal(storage),
        restoreAttachment: (_) => gate.future,
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
    final loading = sessions.loadRecovery();
    await tick();
    await devices.remove(device.id);
    gate.complete(picked('old.txt'));
    await loading;
    await sessions.flushRecovery();
    final saved = decoded(storage);
    expect(saved['composers']['entries'], isEmpty);
    expect(saved['composers']['draftConfigs'], isEmpty);
    for (final field in [
      'locations',
      'reading',
      'panels',
      'sidebar',
      'sideChats'
    ]) {
      expect(saved[field], isEmpty, reason: field);
    }
    expect(sessions.composers.retainedAttachmentTokens, isEmpty);
    sessions.dispose();
    await sessions.notifications.settled;
  });

  test('forgotten devices are ignored when hydration starts later', () async {
    final store = ComposerStore();
    final key = composerKey('A', 'work', null);
    store.forgetDevice('A');
    await store.importRecovery({
      'draftConfigs': {
        key: {'model': 'old'}
      },
      'entries': {
        key: {
          'input': {'text': 'old'},
          'attachments': [
            {
              'file': {'name': 'old.txt'}
            }
          ]
        }
      }
    }, (_) async => throw StateError('must not read removed files'));
    expect(store.exportRecovery()['entries'], isEmpty);
    expect(store.exportRecovery()['draftConfigs'], isEmpty);
    store.dispose();
  });

  test('edits during a slow restoration win and are saved after hydration',
      () async {
    final key = composerKey('A', 'work', null),
        gate = Completer<PickedAttachment>();
    final storage = MemoryRecoveryStorage()
      ..current = await encrypt(jsonEncode({
        'schemaVersion': 1,
        'composers': {
          'entries': {
            key: {
              'input': {'text': 'old'},
              'attachments': [
                {
                  'file': {'name': 'old.txt', 'mime': 'text/plain', 'size': 4},
                  'phase': 'ready',
                  'descriptor': {'ref': 'old'}
                }
              ]
            }
          }
        }
      }));
    final bridge = FeatureBridge();
    final sessions = FakeAppSessions(
        store:
            DeviceStore(requireEncryption: false, encrypt: (_) async => null),
        recovery: journal(storage),
        restoreAttachment: (_) => gate.future,
        sessionFactory: (d) => FakeDeviceSession(d.params!, bridge));
    final loading = sessions.loadRecovery();
    await tick();
    final current = sessions.composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'work');
    current.input.text = 'new while loading';
    gate.complete(picked('old.txt'));
    await loading;
    await sessions.flushRecovery();
    expect(current.input.text, 'new while loading');
    expect(current.attachments.items, isEmpty);
    expect(decoded(storage)['composers']['entries'][key]['input']['text'],
        'new while loading');
    sessions.dispose();
    await sessions.notifications.settled;
  });

  test('a newer schema is preserved without falling back and overwriting it',
      () async {
    final storage = MemoryRecoveryStorage()
      ..current =
          await encrypt(jsonEncode({'schemaVersion': 2, 'future': 'data'}))
      ..previous = await encrypt(jsonEncode({'schemaVersion': 1}));
    final recovery = journal(storage), before = storage.current;
    await expectLater(recovery.load(), throwsA(isA<RecoveryVersionMismatch>()));
    expect(recovery.failed, isTrue);
    expect(storage.current, before);
    expect(storage.writes, 0);
    recovery.dispose();
  });
}
