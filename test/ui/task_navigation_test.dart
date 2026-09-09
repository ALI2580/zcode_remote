import 'dart:async';
import 'dart:ui' show SemanticsAction;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zcode_remote/state/client_preferences.dart';
import 'package:zcode_remote/state/workspace_catalog.dart';
import 'package:zcode_remote/state/workspace_view_state.dart';
import 'package:zcode_remote/ui/app.dart';
import 'package:zcode_remote/ui/shell/task_navigation.dart';

void main() {
  late ClientPreferences prefs;
  late List<SidebarProject> projects;
  late SidebarViewState view;
  final opened = <String>[];
  final actions =
      <({String workspace, String task, SidebarTaskAction action})>[];
  Future<void> Function(SidebarTask, SidebarTaskAction)? mutation;
  Future<void> Function(SidebarTask)? opening;
  String query = '';
  String? active;
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = ClientPreferences();
    await prefs.setLanguage('zh');
    view = SidebarViewState()..expandedProjects.add('A');
    opened.clear();
    actions.clear();
    mutation = null;
    opening = null;
    query = '';
    active = null;
    projects = [
      for (final id in ['A', 'B'])
        SidebarProject(
            WorkspaceDescriptor(key: id, title: 'Project $id', scope: {
              'workspaceIdentity': id,
              'workspacePath': '/projects/$id'
            }),
            WorkspaceTaskCatalog({'workspaceIdentity': id}))
    ];
    projects[0].catalog.replaceRemote(projects[0].catalog.parseChannel([
          {
            'taskId': 'pinned',
            'title': 'Pinned task',
            'pinned': true,
            'updatedAt': 200
          },
          {
            'taskId': 'shared',
            'title': 'Task A',
            'createdAt': 50,
            'updatedAt': 100
          },
          {
            'taskId': 'archived',
            'title': 'Archived task',
            'archived': true,
            'updatedAt': 300
          },
        ]));
    projects[1].catalog.replaceRemote(projects[1].catalog.parseChannel([
          {
            'taskId': 'shared',
            'title': 'Task B',
            'unreadAt': 1,
            'createdAt': 10,
            'updatedAt': 400
          },
        ]));
  });
  tearDown(() => prefs.dispose());
  Widget app() => ZcodeRemoteApp(
      preferences: prefs,
      home: Scaffold(
          body: SizedBox(
              width: 264,
              child: TaskNavigation(
                projects: projects,
                view: view,
                preferences: prefs,
                query: query,
                activeWorkspace: 'A',
                activeTask: active,
                onExpand: (project) {},
                onOpen: (task) async {
                  opened.add(task.key);
                  await opening?.call(task);
                },
                onAction: (task, action) async {
                  actions.add((
                    workspace: task.project.workspace.key,
                    task: task.task.sessionId,
                    action: action
                  ));
                  await mutation?.call(task, action);
                },
              ))));

  testWidgets(
      'pinned section is independent and collapsed projects show unread',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Pinned task'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Pinned task')).dy,
        lessThan(tester.getTopLeft(find.text('Project A')).dy));
    expect(find.text('Task B'), findsNothing);
    expect(
        find.byKey(const ValueKey('sidebar-project-unread-B')), findsOneWidget);
    await tester.tap(find.text('Project B'));
    await tester.pumpAndSettle();
    expect(find.text('Task B'), findsOneWidget);
    expect(
        find.byKey(const ValueKey('sidebar-project-unread-B')), findsNothing);
    await tester.tap(find.byTooltip('全部折叠'));
    await tester.pumpAndSettle();
    expect(find.text('Task A'), findsNothing);
    expect(find.text('Pinned task'), findsOneWidget);
    query = '/projects/B';
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(find.text('Task B'), findsOneWidget);
    expect(find.text('Task A'), findsNothing);
    expect(find.text('Pinned task'), findsNothing);
  });

  testWidgets('timeline sorting preserves scope for identical task IDs',
      (tester) async {
    await tester.runAsync(() => prefs.setTaskView('timeline'));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Task B')).dy,
        lessThan(tester.getTopLeft(find.text('Task A')).dy));
    await tester.runAsync(() => prefs.setTaskSort('created'));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(find.text('Task A')).dy,
        lessThan(tester.getTopLeft(find.text('Task B')).dy));
    await tester.longPress(find.text('Task B'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('标记为未读'));
    await tester.pumpAndSettle();
    expect(actions.single.workspace, 'B');
    expect(actions.single.task, 'shared');
    expect(actions.single.action, SidebarTaskAction.unread);
    expect(opened, isEmpty);
  });

  testWidgets(
      'archive requires confirmation and failure keeps the task visible',
      (tester) async {
    active = 'shared';
    mutation = (task, action) => Future.error(StateError('synthetic rejected'));
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('归档任务'));
    await tester.pumpAndSettle();
    expect(actions, isEmpty);
    expect(find.text('确认'), findsOneWidget);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(actions.single.action, SidebarTaskAction.archive);
    expect(find.text('Task A'), findsOneWidget);
    expect(find.text('任务操作失败，请重试'), findsOneWidget);
    expect(projects[0].catalog.isArchived('shared'), isFalse);
  });

  testWidgets(
      'only archived tasks expose delete and cancellation never mutates',
      (tester) async {
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Task A'));
    await tester.pumpAndSettle();
    expect(find.text('删除任务'), findsNothing);
    await tester.tapAt(const Offset(700, 500));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('归档'));
    await tester.pumpAndSettle();
    expect(find.text('Archived task'), findsOneWidget);
    await tester.longPress(find.text('Archived task'));
    await tester.pumpAndSettle();
    expect(find.text('取消归档任务'), findsOneWidget);
    await tester.tap(find.text('删除任务'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(actions, isEmpty);
    await tester.longPress(find.text('Archived task'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('取消归档任务'));
    await tester.pumpAndSettle();
    expect(actions.single.action, SidebarTaskAction.unarchive);
  });

  testWidgets('pending task open has a status and cannot dispatch twice',
      (tester) async {
    final gate = Completer<void>();
    opening = (task) => gate.future;
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Task A'));
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.tap(find.text('Task A'));
    await tester.pump();
    expect(opened, hasLength(1));
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets(
      'pin then unpin menus follow acknowledged membership after moving rows',
      (tester) async {
    mutation = (entry, action) async {
      if (action == SidebarTaskAction.pin) {
        final catalog = entry.project.catalog;
        catalog.setPinned(entry.task.sessionId, !entry.pinned);
        catalog.replacePinned(catalog.visible
            .where((task) => catalog.isPinned(task.sessionId))
            .toList());
      }
    };
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    await tester.longPress(find.text('Task A'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('置顶任务'));
    await tester.pumpAndSettle();
    expect(projects.first.catalog.isPinned('shared'), isTrue);
    await tester.longPress(find.text('Task A'));
    await tester.pumpAndSettle();
    expect(find.text('取消置顶'), findsOneWidget);
    await tester.tap(find.text('取消置顶'));
    await tester.pumpAndSettle();
    expect(projects.first.catalog.isPinned('shared'), isFalse);
  });

  testWidgets('assistive long-press opens the same scoped task actions',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    final node = tester.getSemantics(find.text('Task A'));
    expect(
        node.getSemanticsData().hasAction(SemanticsAction.longPress), isTrue);
    tester
        .renderObject(find.text('Task A'))
        .owner!
        .semanticsOwner!
        .performAction(node.id, SemanticsAction.longPress);
    await tester.pumpAndSettle();
    expect(find.text('置顶任务'), findsOneWidget);
    expect(find.text('重命名任务'), findsOneWidget);
    expect(actions, isEmpty);
    semantics.dispose();
  });
}
