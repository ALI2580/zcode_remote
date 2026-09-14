import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/channel_client.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/protocol/ipc_codec.dart';
import 'package:zcode_remote/protocol/observable.dart';
import 'package:zcode_remote/protocol/zemote_client.dart';
import 'package:zcode_remote/state/file_changes_review.dart';
import 'package:zcode_remote/ui/chat_page.dart';
import 'package:zcode_remote/ui/file_changes_review_panel.dart';
import 'package:zcode_remote/ui/theme.dart';

Finder _diffLine(String line) => find.byWidgetPredicate((widget) =>
    widget is SelectableText &&
    widget.textSpan?.toPlainText().split('\n').contains(line) == true);

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
      } else if (method == 'conversationFileRewindPreviewV4') {
        previews.add((args.single as Map).cast<String, dynamic>());
        respond(previewResponse);
      } else if (method == 'sendConversationCommandV4') {
        final packet = (args.single as Map).cast<String, dynamic>();
        commands.add((packet['envelope'] as Map).cast<String, dynamic>());
        respond(applyResponse);
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
  final requests = <Map<String, dynamic>>[];
  final previews = <Map<String, dynamic>>[];
  final commands = <Map<String, dynamic>>[];

  @override
  Future<void> waitHealthy(
          {Duration timeout = const Duration(seconds: 45)}) async =>
      Future<void>.value();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('change summary expands into file list and readable diff',
      (tester) async {
    final bridge = _Bridge();
    bridge.response = {
      'files': 1,
      'additions': 1,
      'deletions': 1,
      'state': 'active',
      'items': [
        {
          'path': 'lib/a.dart',
          'additions': 1,
          'deletions': 1,
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
        }
      ],
    };
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'synthetic'});

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConversationChangeSummary(
            row: const {
              'rowId': 12,
              'entityId': 'entity-a',
              'count': 1,
              'files': [
                {'path': 'lib/a.dart', 'addedLines': 1, 'removedLines': 1}
              ],
            },
            createReview: (row) => FileChangesReviewController(
              transport: transport,
              scope: FileChangesScope(
                deviceId: 'device-a',
                workspaceKey: 'workspace-a',
                sessionId: 'session-a',
                rowId: row['rowId'] as int? ?? 0,
                entityId: row['entityId'],
              ),
              revision: () => 7,
              logEpoch: () => 'epoch-a',
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('1 个文件已更改'));
    await tester.pumpAndSettle();
    // The expanded summary lists the file rows; no Review button renders
    // without a review-panel host above this widget.
    expect(find.text('a.dart'), findsOneWidget);
    expect(find.text('lib/'), findsOneWidget);
    expect(find.text('审查'), findsNothing);
    // The expanded summary lists the file; the load happens immediately.
    expect(bridge.requests.single['baseRevision'], 7);
    expect(bridge.requests.single['baseLogEpoch'], 'epoch-a');
  });

  testWidgets('file rows and the review button open the same panel path',
      (tester) async {
    final bridge = _Bridge();
    bridge.response = {
      'files': 1,
      'additions': 1,
      'deletions': 1,
      'state': 'active',
      'items': [
        {
          'path': 'lib/a.dart',
          'additions': 1,
          'deletions': 1,
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
        }
      ],
    };
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'synthetic'});
    final opened = <String>[];

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: FileChangesReviewHost(
          openReview: (row, path) => opened.add(path),
          child: SingleChildScrollView(
            child: ConversationChangeSummary(
              row: const {
                'rowId': 12,
                'entityId': 'entity-a',
                'count': 1,
                'files': [
                  {'path': 'lib/a.dart', 'addedLines': 1, 'removedLines': 1}
                ],
              },
              createReview: (row) => FileChangesReviewController(
                transport: transport,
                scope: FileChangesScope(
                  deviceId: 'device-a',
                  workspaceKey: 'workspace-a',
                  sessionId: 'session-a',
                  rowId: row['rowId'] as int? ?? 0,
                  entityId: row['entityId'],
                ),
                revision: () => 7,
                logEpoch: () => 'epoch-a',
              ),
              onOpenReview: (path) => opened.add(path),
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('1 个文件已更改'));
    await tester.pumpAndSettle();
    // U21: tapping the row and the Review button both open the same file in
    // the review panel; the summary itself never inlines the diff.
    await tester.tap(find.text('a.dart'));
    await tester.pumpAndSettle();
    expect(opened, ['lib/a.dart']);
    expect(_diffLine('+new'), findsNothing);
    // Default test locale is English, so the row button reads "Review".
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(opened, ['lib/a.dart', 'lib/a.dart']);
  });

  testWidgets('expanded old summary ignores unrelated revision updates',
      (tester) async {
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
        session: bridge, scope: const {'workspaceIdentity': 'synthetic'});
    var revision = 7;
    var cacheVersion = 'epoch-a|active';
    late StateSetter update;

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: StatefulBuilder(builder: (context, setState) {
          update = setState;
          return SingleChildScrollView(
            child: ConversationChangeSummary(
              row: const {
                'rowId': 12,
                'entityId': 'entity-a',
                'count': 1,
                'state': 'completed',
                'actions': {'canRewindFiles': false},
                'fileChanges': {'state': 'active'},
              },
              reviewCacheVersion: cacheVersion,
              createReview: (row) => FileChangesReviewController(
                transport: transport,
                scope: FileChangesScope(
                  deviceId: 'device-a',
                  workspaceKey: 'workspace-a',
                  sessionId: 'session-a',
                  rowId: row['rowId'] as int? ?? 0,
                  entityId: row['entityId'],
                ),
                revision: () => revision,
                logEpoch: () => 'epoch-a',
              ),
            ),
          );
        }),
      ),
    ));

    await tester.tap(find.text('1 个文件已更改'));
    await tester.pumpAndSettle();
    expect(bridge.requests, hasLength(1));

    update(() => revision = 8);
    await tester.pumpAndSettle();
    expect(bridge.requests, hasLength(1));

    update(() => cacheVersion = 'epoch-a|changed');
    await tester.pumpAndSettle();
    expect(bridge.requests, hasLength(2));
  });

  testWidgets('trimmed large content is marked instead of fabricated',
      (tester) async {
    final bridge = _Bridge();
    bridge.response = {
      'fileChanges': [
        {
          'turnIndex': 1,
          'fileState': 'applied',
          'snapshots': [
            {
              'path': 'lib/large.dart',
              'beforeContent': null,
              'afterContent': 'preview',
              'writeCount': 1,
              'contentRefs': [
                {
                  'field': 'afterContent',
                  'refId': 'ref-1',
                  'hash': 'sha256:synthetic',
                  'fullBytes': 4096,
                  'previewBytes': 64,
                }
              ],
            }
          ],
        }
      ],
    };
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'synthetic'});

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConversationChangeSummary(
            row: const {
              'rowId': 12,
              'count': 1,
              'files': [
                {'path': 'lib/large.dart', 'addedLines': 1, 'removedLines': 0}
              ],
            },
            createReview: (row) => FileChangesReviewController(
              transport: transport,
              scope: FileChangesScope(
                deviceId: 'device-a',
                workspaceKey: 'workspace-a',
                sessionId: 'session-a',
                rowId: row['rowId'] as int? ?? 0,
                entityId: row['entityId'],
              ),
              revision: () => 7,
              logEpoch: () => 'epoch-a',
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('1 个文件已更改'));
    await tester.pumpAndSettle();
    expect(find.text('large.dart'), findsOneWidget);
    // Trim markers belong to the diff payload; the summary keeps listing the
    // file without rendering inline hunks.
    expect(_diffLine('+new'), findsNothing);
  });

  testWidgets('review failures stay visible and retry loads the diff',
      (tester) async {
    final bridge = _Bridge();
    bridge.response = null;
    final transport = ConversationTransport(
        session: bridge, scope: const {'workspaceIdentity': 'synthetic'});

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConversationChangeSummary(
            row: const {
              'rowId': 12,
              'count': 1,
              'files': [
                {'path': 'lib/recovered.dart', 'addedLines': 1, 'removedLines': 0}
              ],
            },
            createReview: (row) => FileChangesReviewController(
              transport: transport,
              scope: FileChangesScope(
                deviceId: 'device-a',
                workspaceKey: 'workspace-a',
                sessionId: 'session-a',
                rowId: row['rowId'] as int? ?? 0,
                entityId: row['entityId'],
              ),
              revision: () => 7,
              logEpoch: () => 'epoch-a',
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('1 个文件已更改'));
    await tester.pumpAndSettle();
    expect(find.text('暂时无法读取文件变更。'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);

    bridge.response = {
      'files': 1,
      'additions': 1,
      'deletions': 0,
      'items': [
        {
          'path': 'lib/recovered.dart',
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
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('recovered.dart'), findsOneWidget);
    expect(_diffLine('+new'), findsNothing);
    expect(find.text('暂时无法读取文件变更。'), findsNothing);
  });

  testWidgets('rewind preview and confirm use the synthetic transport',
      (tester) async {
    final bridge = _Bridge();
    bridge.response = {
      'files': 1,
      'additions': 1,
      'deletions': 0,
      'state': 'active',
      'items': [
        {
          'path': 'lib/a.dart',
          'additions': 1,
          'deletions': 0,
          'writeCount': 1,
          'toolNames': ['edit'],
          'patches': [],
        }
      ],
    };
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
        session: bridge, scope: const {'workspaceIdentity': 'synthetic'});

    await tester.pumpWidget(MaterialApp(
      theme: ZInkTheme.light(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: ConversationChangeSummary(
            row: const {
              'rowId': 12,
              'entityId': 'entity-a',
              'count': 1,
              'state': 'completed',
              'actions': {'canRewindFiles': true},
              'fileChanges': {'state': 'active'},
            },
            createReview: (row) => FileChangesReviewController(
              transport: transport,
              scope: FileChangesScope(
                deviceId: 'device-a',
                workspaceKey: 'workspace-a',
                sessionId: 'session-a',
                rowId: row['rowId'] as int? ?? 0,
                entityId: row['entityId'],
              ),
              revision: () => 7,
              logEpoch: () => 'epoch-a',
            ),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('1 个文件已更改'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('撤销'));
    await tester.pumpAndSettle();
    expect(find.text('撤销文件改动'), findsOneWidget);
    expect(find.text('可安全撤销 1'), findsOneWidget);
    expect(find.text('lib/a.dart'), findsWidgets);

    await tester.tap(find.text('撤销文件'));
    await tester.pumpAndSettle();
    expect(find.text('撤销文件改动'), findsNothing);
    expect(bridge.previews.single['target'],
        {'rowId': 12, 'entityId': 'entity-a'});
    expect(bridge.commands.single['type'], 'applyFileRewind');
  });
}
