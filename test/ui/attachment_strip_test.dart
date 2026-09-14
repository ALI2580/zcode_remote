import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/composer_attachments.dart';
import 'package:zcode_remote/state/composer_store.dart';
import 'package:zcode_remote/state/conversation_view_state.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/composer/attachment_strip.dart';

import 'fake_workspace.dart';
import 'fake_features.dart';

PickedAttachment _file(String name,
        {String mime = 'text/plain', String text = 'synthetic'}) =>
    PickedAttachment(
        name: name,
        mime: mime,
        size: text.codeUnits.length,
        read: () async => Uint8List.fromList(text.codeUnits));

void main() {
  testWidgets('attachment strip renders progress, retry and preview states',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1180, 820);
    addTearDown(tester.view.reset);
    final capture = Platform.environment['ZCODE_UI_CAPTURE_DIR'];
    final font = Platform.environment['ZCODE_TEST_FONT'];
    final boundary = GlobalKey();
    if (font != null) {
      await tester.runAsync(() async {
        final bytes = await File(font).readAsBytes();
        await (FontLoader('Roboto')
              ..addFont(Future.value(ByteData.sublistView(bytes))))
            .load();
      });
    }
    final bridge = FeatureBridge();
    final gate = Completer<void>();
    final attachments = ComposerAttachments(
        transport: bridge.conversationTransport,
        ensureSession: () async => 'task');
    addTearDown(attachments.dispose);

    attachments.add([
      _file('ready.txt'),
    ]);
    await tester.pumpAndSettle();
    bridge.conversationTransport.uploadHandler = () => gate.future;
    attachments.add([_file('slow.txt')]);
    await tester.pump();
    bridge.conversationTransport.uploadHandler =
        () => Future.error(StateError('upload'));
    attachments.add([_file('known_audio.wav', mime: 'audio/wav')]);
    await tester.pumpWidget(ZcodeRemoteApp(
        home: RepaintBoundary(
            key: boundary,
            child: Theme(
                data: ThemeData.dark(),
                child: Material(
                    child: AttachmentStrip(attachments: attachments))))));
    await tester.pump();

    expect(find.text('ready.txt'), findsOneWidget);
    expect(find.text('9 B'), findsNWidgets(3));
    expect(find.text('slow.txt'), findsOneWidget);
    expect(find.text('Uploading 50%'), findsOneWidget);
    expect(find.text('known_audio.wav'), findsOneWidget);
    expect(find.textContaining('Upload failed'), findsOneWidget);
    expect(find.byTooltip('Retry upload'), findsOneWidget);
    expect(find.byTooltip('Remove attachment ready.txt'), findsOneWidget);

    if (capture != null) {
      await tester.runAsync(() async {
        final image = await (boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
        final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
        await Directory(capture).create(recursive: true);
        await File('$capture/b2.3-local-attachment-states.png')
            .writeAsBytes(bytes!.buffer.asUint8List());
        image.dispose();
      });
    }

    gate.complete();
    await tester.pumpAndSettle();

    await tester.tap(find.text('ready.txt'));
    await tester.pumpAndSettle();
    expect(find.text('ready.txt'), findsNWidgets(2));
    expect(find.text('synthetic'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
  });

  testWidgets('sent user attachments render official read-only pills',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 820);
    addTearDown(tester.view.reset);
    final bridge = FakeBridge();
    bridge.conversationTransport.states['task'] = ConversationState()
      ..applyFrame({
        'toSeq': 20,
        'payload': {
          'kind': 'snapshot',
          'snapshot': {
            ...composerSnapshotFixture,
            'logEpoch': 'attachment-pill-fixture',
            'rows': {
              'window': [
                {
                  'rowId': 1,
                  'kind': 'userInput',
                  'text': 'With attachment',
                  'attachments': [
                    {
                      'ref': 'sent-ref',
                      'fileName': 'report.pdf',
                      'mime': 'application/pdf',
                      'bytes': 2048,
                    }
                  ],
                }
              ],
              'firstRowId': 1,
              'totalCount': 1,
            },
          },
        },
      }, onGap: () {});

    await tester.pumpWidget(ZcodeRemoteApp(
        home: ChatPage(
            session: bridge,
            scope: const {},
            workspaceKey: 'work',
            deviceId: 'A',
            sessionId: 'task',
            title: 'Attachments',
            embedded: true,
            viewStates: {
              composerKey('A', 'work', 'task'): ConversationViewState()
            })));
    await tester.pumpAndSettle();

    expect(find.text('With attachment'), findsOneWidget);
    expect(find.text('report.pdf'), findsOneWidget);
    expect(find.text('2.0 KB'), findsOneWidget);
    final pill = tester.renderObject<RenderBox>(
        find.byKey(const ValueKey('sent-attachment-sent-ref')));
    expect(pill.size.height, 48);
    expect(tester.takeException(), isNull);
  });
}
