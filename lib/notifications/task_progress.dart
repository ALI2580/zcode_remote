import 'dart:convert';

import '../protocol/conversation.dart';
import 'task_target.dart';

class WorkspaceTaskSource {
  const WorkspaceTaskSource({
    required this.deviceId,
    required this.deviceLabel,
    required this.workspaceKey,
    this.workspacePath,
  });
  final String deviceId;
  final String deviceLabel;
  final String workspaceKey;
  final String? workspacePath;
  String get key => jsonEncode([deviceId, workspaceKey]);
  TaskTarget target(SessionEntry entry) => TaskTarget(
        deviceId: deviceId,
        workspaceKey: workspaceKey,
        workspacePath: workspacePath,
        sessionId: entry.sessionId,
        title: entry.title.isEmpty ? '任务' : entry.title,
      );
}

class ProgressTask {
  const ProgressTask(this.target, this.deviceLabel, this.phase,
      {this.needsAttention = false});
  final TaskTarget target;
  final String deviceLabel;
  final String phase;
  final bool needsAttention;
}

class TaskNotice {
  const TaskNotice(this.title, this.target);
  final String title;
  final TaskTarget target;
}

const _working = {'running', 'prewarming', 'inputStreaming'};
const _finished = {
  'completed',
  'completedSuccess',
  'completedInterrupted',
  'cancelled',
  'interrupted',
  'failed',
  'error',
};

/// Derives transitions per device/workspace; loading a completed history is
/// not a completion event and losing a snapshot is not task completion.
class TaskProgressReducer {
  final _tasks = <String, List<ProgressTask>>{};
  final _previous = <String, Map<String, SessionEntry>>{};
  final _attention = <String, Set<String>>{};

  List<ProgressTask> get active =>
      _tasks.values.expand((entries) => entries).toList()
        ..sort((a, b) =>
            (b.needsAttention ? 1 : 0).compareTo(a.needsAttention ? 1 : 0));

  List<TaskNotice> update(
      WorkspaceTaskSource source, List<SessionEntry> entries) {
    final previous = _previous[source.key] ?? const <String, SessionEntry>{};
    final notices = <TaskNotice>[];
    final working = <ProgressTask>[];
    final attention = _attention.putIfAbsent(source.key, () => {});
    for (final entry in entries) {
      final target = source.target(entry);
      final pending = entry.pendingInteraction;
      final interaction = pending?['interactionId'];
      if (interaction is String &&
          interaction.isNotEmpty &&
          attention.add(jsonEncode([entry.sessionId, interaction]))) {
        notices.add(TaskNotice('需要你的处理', target));
      }
      if (_working.contains(entry.phase) ||
          entry.hasBackgroundWork ||
          pending != null) {
        working.add(ProgressTask(target, source.deviceLabel, entry.phase,
            needsAttention: pending != null));
      }
      final before = previous[entry.sessionId];
      if (before != null &&
          (_working.contains(before.phase) ||
              before.hasBackgroundWork ||
              before.pendingInteraction != null) &&
          _finished.contains(entry.phase) &&
          !entry.hasBackgroundWork &&
          pending == null) {
        final title = switch (entry.phase) {
          'error' || 'failed' => '任务失败',
          'completedInterrupted' || 'cancelled' || 'interrupted' => '任务已停止',
          _ => '任务完成',
        };
        notices.add(TaskNotice(title, target));
      }
    }
    _previous[source.key] = {
      for (final entry in entries) entry.sessionId: entry
    };
    _tasks[source.key] = working;
    return notices;
  }

  void remove(String sourceKey) {
    _tasks.remove(sourceKey);
    _previous.remove(sourceKey);
    _attention.remove(sourceKey);
  }
}
