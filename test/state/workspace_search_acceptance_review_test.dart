import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/workspace_search.dart';

import '../ui/fake_workspace.dart';

class _ReviewSearchTransport extends FakeConversationTransport {
  _ReviewSearchTransport() : super(FakeBridge());
  Map<String, dynamic> taskResult = {'items': <Object?>[]};
  Completer<Map<String, dynamic>>? gate;
  int taskCalls = 0;
  final fileRoots = <String>[];
  List<Map<String, dynamic>> fileResult = [];
  @override
  Future<Map<String, dynamic>> listTaskList({
    required List<Map<String, dynamic>> workspaceScopes,
    String? search,
    int limit = 80,
  }) async {
    taskCalls++;
    return gate == null ? taskResult : await gate!.future;
  }
  @override
  Future<List<Map<String, dynamic>>> workspaceFilesForRoot(String rootPath) async {
    fileRoots.add(rootPath);
    return fileResult;
  }
}

const _scopeA = WorkspaceSearchScope(workspaceKey: 'A', title: 'A',
    scope: {'workspaceIdentity': 'A', 'workspacePath': '/a'});
const _scopeB = WorkspaceSearchScope(workspaceKey: 'B', title: 'B',
    scope: {'workspaceIdentity': 'B', 'workspacePath': '/b'});

void main() {
  test('review: a nonempty query retains current IDs across workspace scopes', () async {
    final transport = _ReviewSearchTransport()..taskResult = {'items': [
      {'workspaceIdentity': 'A', 'taskId': 'same-id', 'title': 'Needle A'},
      {'workspaceIdentity': 'B', 'taskId': 'same-id', 'title': 'Needle B'},
    ]};
    final controller = WorkspaceSearchController(transport: transport, currentWorkspaceKey: 'A',
        scopes: [_scopeA, _scopeB], currentTaskId: 'same-id');
    addTearDown(controller.dispose);
    await controller.search('#needle');
    expect(controller.results.map((e) => e.workspaceKey), ['A', 'B']);
  });

  test('review: closing search discards a pending response without notifying disposal', () async {
    final transport = _ReviewSearchTransport()..gate = Completer<Map<String, dynamic>>();
    final controller = WorkspaceSearchController(transport: transport, currentWorkspaceKey: 'A', scopes: [_scopeA]);
    final pending = controller.search('#needle');
    controller.dispose();
    transport.gate!.complete({'items': []});
    await expectLater(pending, completes);
  });

  test('review: scope replacement rejects the result started on the previous scope', () async {
    final transport = _ReviewSearchTransport()..gate = Completer<Map<String, dynamic>>();
    final controller = WorkspaceSearchController(transport: transport, currentWorkspaceKey: 'A', scopes: [_scopeA]);
    addTearDown(controller.dispose);
    final pending = controller.search('#needle');
    controller.updateScopes([_scopeB]);
    transport.gate!.complete({'items': [
      {'workspaceIdentity': 'B', 'taskId': 'unexpected-old', 'title': 'Old transport result'},
    ]});
    await pending;
    expect(controller.results, isEmpty);
  });

  test('review: command-only prefix never reads remote files or conversations', () async {
    final transport = _ReviewSearchTransport();
    final controller = WorkspaceSearchController(transport: transport, currentWorkspaceKey: 'A', scopes: [_scopeA]);
    addTearDown(controller.dispose);
    await controller.search('>settings');
    expect(transport.taskCalls, 0);
    expect(transport.fileRoots, isEmpty);
  });

  test('review: file selection preserves the absolute path returned by the service', () async {
    final transport = _ReviewSearchTransport()..fileResult = [
      {'type': 'file', 'name': 'needle.dart', 'relativePath': 'lib/needle.dart',
        'path': '/a/lib/needle.dart'},
    ];
    final controller = WorkspaceSearchController(transport: transport, currentWorkspaceKey: 'A', scopes: [_scopeA]);
    addTearDown(controller.dispose);
    await controller.search('@needle');
    expect(controller.results.single.filePath, '/a/lib/needle.dart');
  });
}

