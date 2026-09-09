import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
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
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import '../test/ui/fake_features.dart';
import '../test/ui/fake_workspace.dart';

const phase = String.fromEnvironment('RECOVERY_QA_PHASE', defaultValue: 'seed');
const fixtureName = 'zcode-goal-recovery-20260909.txt';
const fixtureText = 'ZcodeRemote recovery fixture\nalpha beta gamma\n';
const channel = MethodChannel('zcode_remote/attachments');

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native attachment and durable recovery ($phase)',
      (tester) async {
    final environment =
        await channel.invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa',
        reason:
            'Run only with ZCODE_ANDROID_QA=true; never use production data.');
    final prefs = await SharedPreferences.getInstance();
    if (phase == 'seed') {
      await prefs.remove(PreferencesRecoveryStorage.key);
      await prefs.remove(PreferencesRecoveryStorage.backupKey);
    }
    final bridge = FeatureBridge();
    final apps = FakeAppSessions(
        store:
            DeviceStore(requireEncryption: false, encrypt: (_) async => null),
        sessionFactory: (device) => FakeDeviceSession(device.params!, bridge),
        recovery: RecoveryJournal.production());
    await apps.loadRecovery();
    final controller = apps.composers.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'same-workspace');
    await controller.loadOptions();
    final keyboardDone = Completer<void>();
    final boundary = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: boundary,
        child: ZcodeRemoteApp(
            home: Scaffold(
                body: Column(children: [
          SafeArea(
              child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text('附件与恢复 QA · $phase\n仅使用合成远端'))),
          if (phase == 'keyboard')
            TextButton(
                onPressed: () {
                  if (!keyboardDone.isCompleted) keyboardDone.complete();
                },
                child: const Text('结束键盘检查')),
          const Spacer(),
          ComposerBar(controller: controller),
        ])))));
    Future<void> capture(String name) async {
      await tester.pumpAndSettle();
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage(pixelRatio: 1);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${environment!['cacheDirectory']}/qa-$name.png').writeAsBytes(
          data!.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
      image.dispose();
    }

    await tester.pumpAndSettle();
    const target = TaskTarget(
        deviceId: 'A',
        workspaceKey: 'same-workspace',
        sessionId: '',
        title: 'QA draft');
    if (phase == 'seed') {
      controller.input.insertReference(
          const TextRange(start: 0, end: 0),
          const ComposerReference(
              id: 'synthetic-ref',
              category: 'files',
              label: 'note.txt',
              value: 'notes/note.txt'));
      controller.input.value = controller.input.value
          .copyWith(text: '${controller.input.text}Native saved draft');
      final b = apps.composers.obtain(
          transport: FeatureBridge().conversationTransport,
          deviceId: 'B',
          workspaceKey: 'same-workspace',
          sessionId: 'same-session');
      b.input.text = 'B stays separate';
      apps.lastLocations['A'] = target;
      apps.workspaceViewStates[target.key] = WorkspaceViewState()
        ..panelOpen = true
        ..panelTab = 'sideChat';
      apps.conversationViewStates[controller.key] = ConversationViewState()
        ..following = false
        ..anchor = 'synthetic-anchor'
        ..anchorOffset = -9
        ..pixels = 120;
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-actions')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('composer-action-file')));
      // The agent chooses the named fixture in Android DocumentsUI. This is
      // the actual picker/cache/read path; the remote transport stays fake.
      final deadline = DateTime.now().add(const Duration(minutes: 2));
      while (controller.attachments.items.isEmpty ||
          controller.attachments.pending) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Choose $fixtureName in the Android file picker.');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.attachments.items.single.file.name, fixtureName);
      final bytes = await controller.attachments
          .preview(controller.attachments.items.single);
      expect(utf8.decode(bytes), fixtureText);
      expect(controller.attachments.items.single.file.recovery?['token'],
          isNotNull);
      expect(bridge.conversationTransport.uploads.single['bytes'],
          utf8.encode(fixtureText).length);
      bridge.conversationTransport.response = {'status': 'rejected'};
      expect(await controller.send(), ComposerSendResult.failed);
      expect(controller.input.markdown,
          '[note.txt](./notes/note.txt) Native saved draft');
      await apps.flushRecovery();
      expect(
          prefs.getString(PreferencesRecoveryStorage.key), startsWith('enc:'));
      expect(prefs.getString(PreferencesRecoveryStorage.key),
          isNot(contains('Native saved draft')));
      debugPrint(
          'QA seed: native picker, bytes, fake rejected send and encrypted recovery saved.');
    } else if (phase == 'keyboard') {
      controller.input.clear();
      controller.dismissFailure();
      final deadline = DateTime.now().add(const Duration(minutes: 3));
      while (!keyboardDone.isCompleted) {
        if (DateTime.now().isAfter(deadline)) {
          fail('Complete the real IME check in the QA editor.');
        }
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(controller.input.text, contains('你好'));
      expect(controller.input.text, contains('\n'));
      expect(bridge.conversationTransport.sent, isEmpty);
      await capture('keyboard');
      debugPrint(
          'QA keyboard: Chinese text and newline retained without sending.');
    } else {
      expect(controller.input.referenceCount, 1);
      expect(controller.input.markdown,
          '[note.txt](./notes/note.txt) Native saved draft');
      expect(controller.failure, ComposerFailure.send);
      expect(controller.attachments.items.single.phase, AttachmentPhase.ready);
      expect(
          utf8.decode(await controller.attachments
              .preview(controller.attachments.items.single)),
          fixtureText);
      expect(apps.lastLocations['A'], target);
      expect(apps.workspaceViewStates[target.key]!.panelTab, 'sideChat');
      expect(apps.conversationViewStates[controller.key]!.anchor,
          'synthetic-anchor');
      expect(apps.drafts[composerKey('B', 'same-workspace', 'same-session')],
          'B stays separate');
      expect(bridge.conversationTransport.sent, isEmpty);
      expect(bridge.conversationTransport.commands, isEmpty);
      await tester.pumpAndSettle();
      await tester.tap(find.text(fixtureName));
      await tester.pumpAndSettle();
      expect(find.text(fixtureText), findsOneWidget);
      await capture('restored-preview');
      await tester.tap(find.text('关闭'));
      await tester.pumpAndSettle();
      expect(await controller.send(), ComposerSendResult.sent);
      expect(
          bridge.conversationTransport.commands
              .where((e) => e.type == 'createSession'),
          isEmpty);
      expect(bridge.conversationTransport.sent, hasLength(1));
      await apps.flushRecovery();
      debugPrint(
          'QA verify: cold-start reference/file/navigation recovered; no automatic send; one explicit fake send.');
    }
    await tester.pumpWidget(const SizedBox.shrink());
    apps.dispose();
    await apps.notifications.settled;
  }, timeout: const Timeout(Duration(minutes: 4)));
}
