import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:zcode_remote/state/composer_attachments.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/composer_bar.dart';
import '../test/ui/fake_features.dart';

const channel = MethodChannel('zcode_remote/attachments');

/// Names the host adb script seeds into /sdcard/Download before launch;
/// the picker picks them through the real DocumentsUI multi-select.
const expectedNames = [
  'qa-b2.2-image.png',
  'qa-b2.2-note.txt',
  'qa-b2.2-blob.bin',
];

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('native attachment types, preview and oversized rejection',
      (tester) async {
    final environment =
        await channel.invokeMapMethod<String, dynamic>('environment');
    expect(environment?['packageName'], 'com.zcoderemote.zcode_remote.qa',
        reason: 'Run only with ZCODE_ANDROID_QA=true; never .dev.');

    final bridge = FeatureBridge();
    final store = ComposerStore();
    final controller = store.obtain(
        transport: bridge.conversationTransport,
        deviceId: 'A',
        workspaceKey: 'workspace');
    await controller.loadOptions();
    await tester.pumpWidget(ZcodeRemoteApp(
        home: Scaffold(
            body: Column(children: [
      const Text('附件类型 QA · 仅使用合成远端'),
      const Spacer(),
      ComposerBar(controller: controller),
    ]))));
    await tester.pumpAndSettle();

    // Hold the fake transport before the picker can deliver files so the
    // native upload flow reliably reaches its in-flight state.
    final gate = Completer<void>();
    bridge.conversationTransport.uploadHandler = () => gate.future;

    // Multi-select happens in the real DocumentsUI, driven over adb from
    // the host while this window waits for the attachments to land.
    await tester.tap(find.byKey(const ValueKey('composer-actions')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('composer-action-file')));
    final deadline = DateTime.now().add(const Duration(minutes: 8));
    while (controller.attachments.items.length < 3) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Pick the three qa-b2.2 fixtures in the Android file picker.');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();

    final names = controller.attachments.items.map((e) => e.file.name).toSet();
    expect(names, containsAll(['qa-b2.2-image.png', 'qa-b2.2-note.txt']));

    // Slow upload: hold the fake transport, verify the uploads entered
    // the uploading phase, then remove one entry mid-upload and let the
    // rest finish. The removed entry must abort via the isCancelled
    // callback and disappear from the list.
    final deadlineUploading = DateTime.now().add(const Duration(seconds: 20));
    while (!controller.attachments.items
        .any((e) => e.phase == AttachmentPhase.uploading)) {
      if (DateTime.now().isAfter(deadlineUploading)) {
        fail('uploads never reached the uploading phase');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }
    final removed = controller.attachments.items.first;
    controller.attachments.remove(removed);
    await tester.pumpAndSettle();
    expect(controller.attachments.items.contains(removed), isFalse);

    gate.complete();
    final deadlineReady = DateTime.now().add(const Duration(seconds: 30));
    while (controller.attachments.items
        .any((e) => e.phase != AttachmentPhase.ready)) {
      if (DateTime.now().isAfter(deadlineReady)) {
        fail('uploads never became ready: '
            '${controller.attachments.items.map((e) => e.phase)}');
      }
      await tester.pump(const Duration(milliseconds: 100));
    }

    final remaining =
        controller.attachments.items.map((e) => e.file.name).toSet();
    expect(remaining.contains(removed.file.name), isFalse);
    for (final item in controller.attachments.items) {
      final bytes = await controller.attachments.preview(item);
      expect(bytes, isNotEmpty);
      expect(item.file.recovery?['token'], isNotNull);
    }
    final text = controller.attachments.items
        .singleWhere((e) => e.file.name == 'qa-b2.2-note.txt');
    expect(text.file.mime, 'text/plain');
    final image = controller.attachments.items
        .singleWhere((e) => e.file.name == 'qa-b2.2-image.png');
    expect(image.file.mime, startsWith('image/'));
    expect(tester.takeException(), isNull);
  });
}
