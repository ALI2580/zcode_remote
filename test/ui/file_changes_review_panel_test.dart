import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/protocol/ipc_codec.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/file_changes_review.dart';
import 'package:zcode_remote/ui/file_changes_review_panel.dart';
import 'package:zcode_remote/ui/theme.dart';

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

      if (method == 'helloConversationV4') {
        respond({'connectionId': 'synthetic'});
      } else if (method == 'initializeConversationV4') {
        respond({});
      } else if (method == 'conversationFileChangesV4') {
        requests.add((args.single as Map).cast<String, dynamic>());
        respond(response);
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
  final requests = <Map<String, dynamic>>[];

  @override
  Future<void> waitHealthy(
          {Duration timeout = const Duration(seconds: 45)}) async =>
      Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

FileChangesReviewController _controller(_Bridge bridge) {
  final transport = ConversationTransport(
      session: bridge, scope: const {'workspaceIdentity': 'synthetic'});
  return FileChangesReviewController(
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
}

Map<String, dynamic> get twoFileResponse => {
      'files': 2,
      'additions': 4,
      'deletions': 3,
      'state': 'active',
      'items': [
        {
          'path': 'lib/a.dart',
          'additions': 3,
          'deletions': 2,
          'writeCount': 2,
          'toolNames': ['edit'],
          'patches': [
            {
              'oldStart': 1,
              'oldLines': 2,
              'newStart': 1,
              'newLines': 2,
              'lines': [' one', '-old', '+new', ' two'],
            }
          ],
        },
        {
          'path': 'lib/deep/b.dart',
          'additions': 1,
          'deletions': 1,
          'writeCount': 1,
          'toolNames': ['write'],
          'patches': [
            {
              'oldStart': 4,
              'oldLines': 1,
              'newStart': 4,
              'newLines': 1,
              'lines': ['-gone', '+here'],
            }
          ],
        },
      ],
    };

void main() {
  setUp(() {});

  testWidgets('review panel renders tabs, breadcrumb and selected hunks',
      (tester) async {
    final bridge = _Bridge();
    bridge.response = twoFileResponse;
    final controller = _controller(bridge);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: FileChangesReviewPanel(
          controller: controller,
          initialPath: 'lib/a.dart',
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // Tab bar shows the opened file; breadcrumb splits name and directory.
    expect(find.text('a.dart'), findsNWidgets(2));
    expect(find.text('lib/'), findsOneWidget);
    expect(bridge.requests.single['baseRevision'], 7);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText().contains('+new') == true),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText().contains('-old') == true),
        findsOneWidget);
    // The other file stays hidden until opened.
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText().contains('+here') == true),
        findsNothing);
  });

  testWidgets('opening another file adds a tab and switches hunks',
      (tester) async {
    final bridge = _Bridge();
    bridge.response = twoFileResponse;
    final controller = _controller(bridge);
    addTearDown(controller.dispose);

    var initial = 'lib/a.dart';
    late StateSetter setRoot;
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          setRoot = setState;
          return FileChangesReviewPanel(
            controller: controller,
            initialPath: initial,
          );
        }),
      ),
    ));
    await tester.pumpAndSettle();
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText().contains('+new') == true),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText().contains('+here') == true),
        findsNothing);

    setRoot(() => initial = 'lib/deep/b.dart');
    await tester.pumpAndSettle();
    // Both tabs stay open; the active tab shows b.dart hunks.
    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('b.dart'), findsNWidgets(2));
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText().contains('+here') == true),
        findsOneWidget);
    expect(
        find.byWidgetPredicate((widget) =>
            widget is SelectableText &&
            widget.textSpan?.toPlainText().contains('+new') == true),
        findsNothing);
  });

  testWidgets('closing the last tab closes the panel', (tester) async {
    final bridge = _Bridge();
    bridge.response = twoFileResponse;
    final controller = _controller(bridge);
    addTearDown(controller.dispose);
    var closed = false;

    await tester.pumpWidget(MaterialApp(
      locale: const Locale('zh'),
      supportedLocales: const [Locale('zh'), Locale('en')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: FileChangesReviewPanel(
          controller: controller,
          initialPath: 'lib/a.dart',
          onLastTabClosed: () => closed = true,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('关闭文件标签'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
  });
}
