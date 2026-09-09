import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/workspace_catalog.dart';

void main() {
  test('workspace descriptors use stable identity and normalize display name',
      () {
    final project = WorkspaceDescriptor.parse(
        {'workspaceIdentity': 'stable', 'workspacePath': r'D:\Projects\Demo\'});
    expect(project!.key, 'stable');
    expect(project.title, 'Demo');
    expect(WorkspaceDescriptor.parse({}), isNull);
    expect(
        belongsToWorkspace({'workspacePath': r'd:\Projects\Demo\'},
            {'workspacePath': 'D:/Projects/Demo'}),
        isTrue);
    expect(belongsToWorkspace({'workspaceIdentity': 'other'}, project.scope),
        isFalse);
  });

  test(
      'empty snapshots and late channel responses preserve the independent source',
      () {
    final catalog =
        WorkspaceTaskCatalog(const {'workspaceIdentity': 'workspace'});
    catalog.channel = catalog.parseChannel([
      {
        'taskId': 'a',
        'title': 'Channel task',
        'workspaceIdentity': 'workspace',
        'updatedAt': 20
      },
      {
        'taskId': 'wrong',
        'title': 'Other project',
        'workspaceIdentity': 'other'
      },
    ]);
    catalog.index = [
      SessionEntry(
          {'sessionId': 'b', 'title': 'Live task', 'lastActivityAt': 30})
    ];
    expect(catalog.visible.map((e) => e.sessionId), ['b', 'a']);
    catalog.index = [];
    expect(catalog.visible.map((e) => e.sessionId), ['a']);
    catalog.index = [
      SessionEntry({'sessionId': 'b', 'title': 'Live task'})
    ];
    catalog.channel = [];
    expect(catalog.visible.map((e) => e.sessionId), ['b']);
  });

  test('pin, rename and archive apply within the selected workspace', () {
    final first = WorkspaceTaskCatalog(const {'workspaceIdentity': 'first'});
    final second = WorkspaceTaskCatalog(const {'workspaceIdentity': 'second'});
    for (final catalog in [first, second]) {
      catalog.index = [
        SessionEntry({'sessionId': 'shared-id', 'title': 'Original'})
      ];
    }
    first.setPinned('shared-id', true);
    first.setTitle('shared-id', 'Renamed');
    first.setArchived('shared-id', true);
    expect(first.visible, isEmpty);
    expect(first.archiveList.single.title, 'Renamed');
    expect(
        first.isPinned('shared-id'), isFalse); // Official archive clears pin.
    expect(second.visible.single.title, 'Original');
    expect(second.isPinned('shared-id'), isFalse);
  });

  test('full remote index omission removes previous pin, archive and unread',
      () {
    final catalog = WorkspaceTaskCatalog(const {});
    catalog.replaceRemote(catalog.parseChannel([
      {
        'taskId': 'a',
        'pinned': true,
        'archived': true,
        'unreadAt': 20,
        'updatedAt': 20
      }
    ]));
    catalog.replaceRemote(catalog.parseChannel([
      {'taskId': 'a', 'updatedAt': 30}
    ]));
    expect(catalog.isPinned('a'), isFalse);
    expect(catalog.isArchived('a'), isFalse);
    expect(catalog.visible.single.raw['unreadAt'], isNull);
  });

  test('new remote metadata survives older channel and local index snapshots',
      () {
    final catalog = WorkspaceTaskCatalog(const {});
    final older = catalog.parseChannel([
      {'taskId': 'a', 'title': 'Old title', 'unreadAt': 10, 'updatedAt': 10}
    ]);
    catalog.channel = older;
    catalog.pinned = older;
    catalog.index = older;
    catalog.replaceRemote(catalog.parseChannel([
      {'taskId': 'a', 'title': 'New title', 'updatedAt': 20}
    ]));
    expect(catalog.visible.single.title, 'New title');
    expect(catalog.visible.single.raw['unreadAt'], isNull);
    catalog.index = [
      SessionEntry({
        'sessionId': 'a',
        'title': '',
        'lastActivityAt': 30,
        'phase': 'running'
      })
    ];
    expect(catalog.visible.single.title, 'New title');
    expect(catalog.visible.single.phase, 'running');
  });

  test('late pinned/archive list cannot undo newer full remote membership', () {
    final catalog = WorkspaceTaskCatalog(const {});
    final pinRevision = catalog.pinRevision;
    final archiveRevision = catalog.archiveRevision;
    catalog.replaceRemote(catalog.parseChannel([
      {'taskId': 'a', 'pinned': true, 'updatedAt': 20},
      {'taskId': 'b', 'archived': true, 'updatedAt': 20}
    ]));
    catalog.replacePinned([], requestRevision: pinRevision);
    catalog.replaceArchived([], requestRevision: archiveRevision);
    expect(catalog.isPinned('a'), isTrue);
    expect(catalog.isArchived('b'), isTrue);
  });

  test(
      'fresh list acknowledges a pin without reverting to the older remote flag',
      () {
    final catalog = WorkspaceTaskCatalog(const {});
    final task = catalog.parseChannel([
      {'taskId': 'a', 'updatedAt': 10}
    ]).single;
    catalog.replaceRemote([task]);
    catalog.setPinned('a', true);
    catalog.replacePinned([task]);
    expect(catalog.isPinned('a'), isTrue);
    catalog.setArchived('a', true);
    catalog.replaceArchived([task]);
    expect(catalog.isArchived('a'), isTrue);
    expect(catalog.visible, isEmpty);
  });
}
