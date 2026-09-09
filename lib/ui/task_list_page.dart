import 'package:flutter/material.dart';

import '../state/app_sessions.dart';
import 'chat_page.dart';

class TaskListPage extends StatelessWidget {
  const TaskListPage(
      {super.key,
      required this.monitor,
      required this.sessions,
      required this.title});
  final WorkspaceMonitor monitor;
  final AppSessions sessions;
  final String title;

  void _open(BuildContext context, {String? sessionId, String? taskTitle}) {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (_) => ChatPage(
                  session: monitor.bridge,
                  scope: monitor.scope,
                  workspaceKey: monitor.source.workspaceKey,
                  deviceId: monitor.source.deviceId,
                  drafts: sessions.drafts,
                  sessionId: sessionId,
                  title: taskTitle ?? '新建任务',
                  workspaceName: title,
                )));
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: monitor,
      builder: (context, _) => Scaffold(
            appBar: AppBar(title: Text(title)),
            floatingActionButton: FloatingActionButton.extended(
                onPressed: () => _open(context),
                icon: const Icon(Icons.add),
                label: const Text('新建任务')),
            body: !monitor.ready
                ? Center(
                    child: monitor.error == null
                        ? const CircularProgressIndicator()
                        : Text(monitor.error!))
                : monitor.tasks.isEmpty
                    ? const Center(child: Text('还没有任务'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: monitor.tasks.length,
                        itemBuilder: (context, index) {
                          final task = monitor.tasks[index];
                          return ListTile(
                              title: Text(
                                  task.title.isEmpty ? '未命名任务' : task.title),
                              subtitle: Text(
                                  task.pendingInteraction != null
                                      ? '等待处理'
                                      : task.phase == 'running'
                                          ? '运行中'
                                          : task.lastAssistantPreview ?? '',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              onTap: () => _open(context,
                                  sessionId: task.sessionId,
                                  taskTitle: task.title));
                        }),
          ));
}
