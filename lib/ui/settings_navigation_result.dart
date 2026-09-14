import '../notifications/task_target.dart';

/// Result returned when a settings surface prepared a target task for its
/// caller. Keeping this small value object out of navigation/settings avoids
/// an import cycle while allowing the caller to reopen the exact workspace.
class SettingsNavigationResult {
  const SettingsNavigationResult({required this.target});

  final TaskTarget target;
}
