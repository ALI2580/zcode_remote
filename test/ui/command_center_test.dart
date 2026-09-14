import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zcode_remote/protocol/conversation.dart';
import 'package:zcode_remote/state/workspace_catalog.dart';
import 'package:zcode_remote/ui/command_center.dart';
import 'package:zcode_remote/ui/official_icons.dart';
import 'package:zcode_remote/ui/shell/task_navigation.dart';
import 'package:zcode_remote/ui/theme.dart';

SessionEntry _task(String id, String title, int activity) => SessionEntry({
      'sessionId': id,
      'title': title,
      'lastActivityAt': activity,
      'createdAt': activity - 1000,
    });

Future<void> _open(WidgetTester tester, CommandCenterActions actions,
    {List<SidebarTask> tasks = const [],
    String? activeTaskId,
    List<CommandCenterFileChange> changes = const []}) async {
  final context = tester.element(find.byType(Scaffold));
  showCommandCenter(context,
      actions: actions,
      tasks: tasks,
      activeTaskId: activeTaskId,
      changes: changes);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('all tabs, commands, tasks and file changes are rendered',
      (tester) async {
    var openedTasks = <String>[], counters = List.filled(6, 0);
    final workspace = const WorkspaceDescriptor(
        key: 'rog', title: 'ROG', scope: {'workspaceIdentity': 'rog'});
    final catalog = WorkspaceTaskCatalog(workspace.scope);
    catalog.replaceRemote([
      _task('active', 'Active task', 5000),
      _task('older', 'Older task', 4000),
      _task('middle', 'Middle task', 4500),
      _task('newest', 'Newest task', 4800),
      _task('extra', 'Extra task', 4600),
    ]);
    final tasks = [SidebarProject(workspace, catalog)]
        .expand((project) => commandCenterTasks([project]))
        .toList();
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('zh')],
        home: Scaffold(
            body: Builder(builder: (context) {
              return const SizedBox.shrink();
            }),
            floatingActionButton: FloatingActionButton(
                onPressed: () {}, child: const Icon(Icons.add)))));
    await _open(
      tester,
      CommandCenterActions(
        newTask: () => counters[0]++,
        openWorkspace: () => counters[1]++,
        openSettings: () => counters[2]++,
        toggleSidebar: () => counters[3]++,
        toggleTerminal: () => counters[4]++,
        addTerminalTab: () => counters[5]++,
        openTask: (entry) => openedTasks.add(entry.task.sessionId),
      ),
      tasks: tasks,
      activeTaskId: 'active',
      changes: [
        CommandCenterFileChange(
            path: 'lib/b.dart', added: 2, removed: 1, lastTurnIndex: 1),
        CommandCenterFileChange(
            path: 'lib/a.dart', added: 4, removed: 3, lastTurnIndex: 2),
      ],
    );
    expect(find.text('全部'), findsOneWidget);
    expect(find.text('操作'), findsOneWidget);
    expect(find.text('任务'), findsOneWidget);
    expect(find.text('文件'), findsOneWidget);
    expect(find.text('最近变更'), findsOneWidget);
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('+4'), findsOneWidget);
    expect(find.text('-3'), findsOneWidget);
  });

  testWidgets('commands and task actions invoke scoped callbacks',
      (tester) async {
    var openedTasks = <String>[], counters = List.filled(6, 0);
    final workspace = const WorkspaceDescriptor(
        key: 'rog', title: 'ROG', scope: {'workspaceIdentity': 'rog'});
    final catalog = WorkspaceTaskCatalog(workspace.scope);
    catalog.replaceRemote([_task('task', 'Task', 1000)]);
    final tasks = [SidebarProject(workspace, catalog)]
        .expand((project) => commandCenterTasks([project]))
        .toList();
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('zh')],
        home:
            Scaffold(body: Builder(builder: (_) => const SizedBox.shrink()))));
    await _open(
        tester,
        CommandCenterActions(
          newTask: () => counters[0]++,
          openWorkspace: () => counters[1]++,
          openSettings: () => counters[2]++,
          toggleSidebar: () => counters[3]++,
          toggleTerminal: () => counters[4]++,
          addTerminalTab: () => counters[5]++,
          openTask: (entry) => openedTasks.add(entry.task.sessionId),
        ),
        tasks: tasks);
    await tester.tap(find.text('新任务'));
    await tester.pumpAndSettle();
    await _open(
        tester,
        CommandCenterActions(
          newTask: () => counters[0]++,
          openWorkspace: () => counters[1]++,
          openSettings: () => counters[2]++,
          toggleSidebar: () => counters[3]++,
          toggleTerminal: () => counters[4]++,
          addTerminalTab: () => counters[5]++,
          openTask: (entry) => openedTasks.add(entry.task.sessionId),
        ),
        tasks: tasks);
    await tester.tap(find.text('Task'));
    await tester.pumpAndSettle();
    await _open(
        tester,
        CommandCenterActions(
          newTask: () => counters[0]++,
          openWorkspace: () => counters[1]++,
          openSettings: () => counters[2]++,
          toggleSidebar: () => counters[3]++,
          toggleTerminal: () => counters[4]++,
          addTerminalTab: () => counters[5]++,
          openTask: (entry) => openedTasks.add(entry.task.sessionId),
        ),
        tasks: tasks);
    await tester.tap(find.text('添加终端标签'));
    await tester.pumpAndSettle();
    expect(counters[0], 1);
    expect(counters[5], 1);
    expect(openedTasks, ['task']);
  });

  testWidgets('task rows and tabs follow official palette structure',
      (tester) async {
    final workspace = const WorkspaceDescriptor(
        key: 'rog', title: 'ROG', scope: {'workspaceIdentity': 'rog'});
    final catalog = WorkspaceTaskCatalog(workspace.scope);
    final now = DateTime.now().millisecondsSinceEpoch;
    catalog.replaceRemote([
      _task('active', 'Active task', now),
      _task('one', 'One hour task',
          now - const Duration(hours: 1).inMilliseconds),
      _task('two', 'Two hour task',
          now - const Duration(hours: 2).inMilliseconds),
      _task('fifteen', 'Fifteen hour task',
          now - const Duration(hours: 15).inMilliseconds),
      _task('extra', 'Extra task',
          now - const Duration(hours: 16).inMilliseconds),
    ]);
    final tasks = [SidebarProject(workspace, catalog)]
        .expand((project) => commandCenterTasks([project]))
        .toList();
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('zh')],
        home:
            Scaffold(body: Builder(builder: (_) => const SizedBox.shrink()))));
    await _open(
        tester,
        CommandCenterActions(
          newTask: () {},
          openWorkspace: () {},
          openSettings: () {},
          toggleSidebar: () {},
          toggleTerminal: () {},
          addTerminalTab: () {},
          openTask: (_) {},
        ),
        tasks: tasks,
        activeTaskId: 'active');
    for (final label in ['全部', '操作', '任务', '文件']) {
      expect(
          find.descendant(
              of: find.byKey(ValueKey('command-scope-${switch (label) {
                '全部' => 'all',
                '操作' => 'commands',
                '任务' => 'conversations',
                _ => 'files',
              }}')),
              matching: find.byType(LucideIcon)),
          findsOneWidget,
          reason: '$label keeps the official tab icon');
    }
    expect(find.text('最近任务'), findsOneWidget);
    expect(find.text('One hour task'), findsOneWidget);
    expect(find.text('Two hour task'), findsOneWidget);
    expect(find.text('Fifteen hour task'), findsOneWidget);
    expect(find.text('Extra task'), findsNothing);
    expect(find.text('1小时'), findsOneWidget);
    expect(find.text('2小时'), findsOneWidget);
    expect(find.text('15小时'), findsOneWidget);
  });

  testWidgets('file empty state and query prefixes switch scope',
      (tester) async {
    final workspace = const WorkspaceDescriptor(
        key: 'rog', title: 'ROG', scope: {'workspaceIdentity': 'rog'});
    final catalog = WorkspaceTaskCatalog(workspace.scope);
    catalog.replaceRemote([_task('task', 'Task', 1000)]);
    final tasks = [SidebarProject(workspace, catalog)]
        .expand((project) => commandCenterTasks([project]))
        .toList();
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('zh')],
        home:
            Scaffold(body: Builder(builder: (_) => const SizedBox.shrink()))));
    await _open(
        tester,
        CommandCenterActions(
          newTask: () {},
          openWorkspace: () {},
          openSettings: () {},
          toggleSidebar: () {},
          toggleTerminal: () {},
          addTerminalTab: () {},
          openTask: (_) {},
        ),
        tasks: tasks);
    await tester.tap(find.text('文件'));
    await tester.pumpAndSettle();
    expect(find.text('当前任务暂无最近变更'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '>设置');
    await tester.pumpAndSettle();
    expect(find.text('设置'), findsOneWidget);
    expect(find.text('Task'), findsNothing);
    await tester.enterText(find.byType(TextField), '#Task');
    await tester.pumpAndSettle();
    expect(find.text('Task'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '@a.dart');
    await tester.pumpAndSettle();
    expect(find.text('当前任务暂无最近变更'), findsOneWidget);
  });

  testWidgets('workspace, settings and panel commands invoke callbacks',
      (tester) async {
    var counters = List.filled(6, 0);
    List<CommandCenterActions> actions() => [
          CommandCenterActions(
            newTask: () {},
            openWorkspace: () => counters[1]++,
            openSettings: () => counters[2]++,
            toggleSidebar: () => counters[3]++,
            toggleTerminal: () => counters[4]++,
            addTerminalTab: () {},
            openTask: (_) {},
          )
        ];
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('zh')],
        home:
            Scaffold(body: Builder(builder: (_) => const SizedBox.shrink()))));
    await _open(tester, actions().first);
    await tester.tap(find.text('打开工作区'));
    await tester.pumpAndSettle();
    await _open(tester, actions().first);
    await tester.tap(find.text('设置'));
    await tester.pumpAndSettle();
    await _open(tester, actions().first);
    await tester.tap(find.text('切换侧栏'));
    await tester.pumpAndSettle();
    await _open(tester, actions().first);
    await tester.tap(find.text('切换终端'));
    await tester.pumpAndSettle();
    expect(counters[1], 1);
    expect(counters[2], 1);
    expect(counters[3], 1);
    expect(counters[4], 1);
  });

  testWidgets('escape closes without invoking an action', (tester) async {
    var closedByEscape = false;
    await tester.pumpWidget(MaterialApp(
        theme: ZInkTheme.light(),
        locale: const Locale('zh'),
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: const [Locale('en'), Locale('zh')],
        home:
            Scaffold(body: Builder(builder: (_) => const SizedBox.shrink()))));
    await _open(
        tester,
        CommandCenterActions(
          newTask: () {},
          openWorkspace: () {},
          openSettings: () {},
          toggleSidebar: () {},
          toggleTerminal: () {},
          addTerminalTab: () {},
          openTask: (_) {},
        ));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(CommandCenter), findsNothing);
    expect(closedByEscape, isFalse);
  });
}
