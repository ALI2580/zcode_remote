import 'dart:convert';

/// Device, workspace and task ids are all needed: session ids alone are not
/// globally unique. Pairing credentials never enter a notification payload.
class TaskTarget {
  const TaskTarget({
    required this.deviceId,
    required this.workspaceKey,
    required this.sessionId,
    required this.title,
    this.workspacePath,
  });

  final String deviceId;
  final String workspaceKey;
  final String sessionId;
  final String title;
  final String? workspacePath;

  @override
  bool operator ==(Object other) =>
      other is TaskTarget &&
      other.deviceId == deviceId &&
      other.workspaceKey == workspaceKey &&
      other.sessionId == sessionId &&
      other.title == title &&
      other.workspacePath == workspacePath;
  @override
  int get hashCode =>
      Object.hash(deviceId, workspaceKey, sessionId, title, workspacePath);

  String get key => jsonEncode([deviceId, workspaceKey, sessionId]);
  Map<String, dynamic> get scope => {
        'workspaceIdentity': workspaceKey,
        if (workspacePath != null) 'workspacePath': workspacePath,
      };
  Map<String, dynamic> toJson() => {
        'deviceId': deviceId,
        'workspaceKey': workspaceKey,
        'sessionId': sessionId,
        'title': title,
        if (workspacePath != null) 'workspacePath': workspacePath,
      };

  static TaskTarget? parse(Object? raw, {bool allowDraft = false}) {
    try {
      final map = raw is String ? jsonDecode(raw) : raw;
      if (map is! Map) return null;
      for (final key in ['deviceId', 'workspaceKey', 'sessionId']) {
        if (map[key] is! String ||
            (map[key] as String).trim().isEmpty &&
                !(allowDraft && key == 'sessionId')) {
          return null;
        }
      }
      return TaskTarget(
        deviceId: map['deviceId'] as String,
        workspaceKey: map['workspaceKey'] as String,
        sessionId: map['sessionId'] as String,
        title: map['title'] is String ? map['title'] as String : '任务',
        workspacePath: map['workspacePath'] as String?,
      );
    } catch (_) {
      return null;
    }
  }
}
