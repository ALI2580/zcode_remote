import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/state/workspace_search.dart';

import '../ui/fake_workspace.dart';

class _SearchTransport extends FakeConversationTransport {
  _SearchTransport() : super(FakeBridge());

  Object tasks = const {'items': <Object?>[]};
  final filesByRoot = <String, List<Map<String, dynamic>>>{};
  Completer<Map<String, dynamic>>? taskGate;

  @override
  Future<Map<String, dynamic>> listTaskList({
    required List<Map<String, dynamic>> workspaceScopes,
    String? search,
    int limit = 80,
  }) async {
    final gate = taskGate;
    if (gate != null) return gate.future;
    return (tasks as Map).cast<String, dynamic>();
  }

  @override
  Future<List<Map<String, dynamic>>> workspaceFilesForRoot(
          String rootPath) async =>
      filesByRoot[rootPath] ?? const [];
}

void main() {
  test('search uses full task identity and expands distinct snippets',
      () async {
    final transport = _SearchTransport()
      ..tasks = {
        'items': [
          {
            'workspaceIdentity': 'workspace-a',
            'taskId': 'task-1',
            'title': '同一任务',
            'searchSnippets': ['第一段', '第二段'],
          },
          {
            'workspaceIdentity': 'workspace-b',
            'taskId': 'task-1',
            'title': '另一工作区',
            'searchSnippet': '另一段',
          },
        ],
      };
    final controller = WorkspaceSearchController(
        transport: transport,
        currentWorkspaceKey: 'a',
        scopes: const [
          WorkspaceSearchScope(workspaceKey: 'a', title: 'A', scope: {
            'workspaceIdentity': 'workspace-a',
            'workspacePath': 'D:/a'
          }),
          WorkspaceSearchScope(workspaceKey: 'b', title: 'B', scope: {
            'workspaceIdentity': 'workspace-b',
            'workspacePath': 'D:/b'
          }),
        ],
        currentTaskId: 'current');
    await controller.search('#同一任务');
    expect(controller.results, hasLength(3));
    expect(controller.results.map((r) => r.workspaceKey), ['a', 'a', 'b']);
    expect(controller.results[0].snippetIndex, 0);
    expect(controller.results[1].snippetIndex, 1);
  });

  test('file search matches tokenized name and relative path', () async {
    final transport = _SearchTransport()
      ..filesByRoot['D:/a'] = [
        {'type': 'file', 'name': 'main.dart', 'relativePath': 'lib/main.dart'},
        {'type': 'directory', 'name': 'lib', 'relativePath': 'lib'},
        {
          'type': 'file',
          'name': 'other.dart',
          'relativePath': 'test/other.dart'
        },
      ];
    final controller = WorkspaceSearchController(
        transport: transport,
        currentWorkspaceKey: 'a',
        scopes: const [
          WorkspaceSearchScope(
              workspaceKey: 'a', title: 'A', scope: {'workspacePath': 'D:/a'})
        ]);
    await controller.search('@lib main');
    expect(controller.results, hasLength(1));
    expect(controller.results.single.filePath, 'lib/main.dart');
  });

  test('late search response cannot replace a newer query', () async {
    final transport = _SearchTransport();
    final first = Completer<Map<String, dynamic>>();
    transport.taskGate = first;
    final controller = WorkspaceSearchController(
        transport: transport,
        currentWorkspaceKey: 'a',
        scopes: const [
          WorkspaceSearchScope(
              workspaceKey: 'a', title: 'A', scope: {'workspacePath': 'D:/a'})
        ]);
    final pending = controller.search('#old');
    transport.taskGate = null;
    transport.tasks = {
      'items': [
        {
          'workspacePath': 'D:/a',
          'taskId': 'new',
          'title': '新结果',
          'searchSnippet': 'new'
        }
      ]
    };
    await controller.search('#new');
    first.complete({
      'items': [
        {
          'workspacePath': 'D:/a',
          'taskId': 'old',
          'title': '旧结果',
          'searchSnippet': 'old'
        }
      ]
    });
    await pending;
    expect(controller.results.single.title, '新结果');
  });
}
