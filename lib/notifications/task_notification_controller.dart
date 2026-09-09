import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../protocol/conversation.dart';
import 'notification_platform.dart';
import 'task_progress.dart';
import 'task_target.dart';

class TaskNotificationController extends ChangeNotifier {
  TaskNotificationController({TaskNotificationPlatform? platform})
      : platform = platform ?? AndroidTaskNotifications();

  static const preferenceKey = 'task_progress_notifications_enabled';
  final TaskNotificationPlatform platform;
  final _reducer = TaskProgressReducer();
  Future<void>? _initializing;
  Future<void> _operations = Future.value();
  SharedPreferences? _preferences;
  Timer? _timer;
  bool _enabled = false;
  bool _foreground = true;
  bool _disposed = false;
  int _revision = 0;
  int _toggleRevision = 0;
  TaskTarget? _pendingTarget;
  void Function(TaskTarget)? _onTap;
  NotificationCapabilities _capabilities = const NotificationCapabilities();
  String? _error;

  bool get enabled => _enabled;
  NotificationCapabilities get capabilities => _capabilities;
  String? get error => _error;
  List<ProgressTask> get activeTasks => _reducer.active;
  Future<void> get settled => _operations;

  set onTap(void Function(TaskTarget)? handler) {
    _onTap = handler;
    if (handler != null && _pendingTarget != null) {
      final target = _pendingTarget!;
      _pendingTarget = null;
      handler(target);
    }
  }

  Future<void> initialize() => _initializing ??= _initialize();
  Future<void> _initialize() async {
    _preferences = await SharedPreferences.getInstance();
    if (_disposed) return;
    _enabled = _preferences!.getBool(preferenceKey) ?? false;
    try {
      await platform.initialize((target) {
        if (_disposed) return;
        if (_onTap == null) {
          _pendingTarget = target;
        } else {
          _onTap!(target);
        }
      }, () {
        // A dismissal is a user decision. Persist it instead of reposting.
        unawaited(setEnabled(false));
      });
      await refreshCapabilities();
    } catch (_) {
      _error = '暂时无法读取系统通知状态';
    }
    if (!_disposed) {
      _schedule(immediate: true);
      notifyListeners();
    }
  }

  Future<void> refreshCapabilities() async {
    final result = await platform.capabilities();
    if (_disposed) return;
    _capabilities = result;
    if (result.dismissed) {
      _enabled = false;
      await _preferences?.setBool(preferenceKey, false);
    }
    if (!_disposed) notifyListeners();
  }

  Future<bool> setEnabled(bool value) async {
    final toggle = ++_toggleRevision;
    await initialize();
    if (_disposed || toggle != _toggleRevision) return false;
    if (value && !await platform.requestPermission()) {
      if (!_disposed && toggle == _toggleRevision) {
        _error = '未获得通知权限，可在系统设置中开启';
        notifyListeners();
      }
      return false;
    }
    if (_disposed || toggle != _toggleRevision) return false;
    _enabled = value;
    _error = null;
    await _preferences!.setBool(preferenceKey, value);
    if (_disposed || toggle != _toggleRevision) return false;
    await refreshCapabilities();
    _schedule(immediate: true);
    if (!_disposed) notifyListeners();
    return _enabled == value;
  }

  void setForeground(bool value) {
    _foreground = value;
    if (value) _schedule(immediate: true);
  }

  void update(WorkspaceTaskSource source, List<SessionEntry> entries) {
    if (_disposed) return;
    final notices = _reducer.update(source, entries);
    if (_enabled) {
      for (final notice in notices) {
        _enqueue(() async {
          if (_enabled && !_disposed) {
            await platform.showFinished(
                notice.title,
                '${source.deviceLabel} · ${notice.target.title}',
                notice.target);
          }
        });
      }
    }
    _schedule(immediate: _reducer.active.isEmpty);
    notifyListeners();
  }

  void remove(String sourceKey) {
    _reducer.remove(sourceKey);
    _schedule(immediate: true);
  }

  void _schedule({bool immediate = false}) {
    if (_disposed) return;
    _revision++;
    if (immediate) {
      _timer?.cancel();
      _timer = null;
      _publish();
    } else {
      _timer ??= Timer(const Duration(milliseconds: 900), () {
        _timer = null;
        _publish();
      });
    }
  }

  void _publish() {
    final revision = _revision;
    _enqueue(() async {
      if (_disposed || revision != _revision) return;
      final tasks = _reducer.active;
      if (!_enabled || tasks.isEmpty) {
        await platform.stopProgress();
        return;
      }
      final primary = tasks.first;
      final waiting = tasks.where((task) => task.needsAttention).length;
      final title = waiting > 0 ? '$waiting 个任务等待处理' : '${tasks.length} 个任务运行中';
      var text = tasks
          .take(3)
          .map((task) => '${task.deviceLabel} · ${task.target.title}')
          .join('\n');
      if (text.length > 500) text = '${text.substring(0, 497)}…';
      await platform.showProgress(
        title: title,
        text: text,
        shortText: waiting > 0 ? '待确认' : '${tasks.length}项任务',
        target: primary.target,
        allowStart: _foreground,
      );
    });
  }

  void _enqueue(Future<void> Function() operation) {
    _operations =
        _operations.then((_) => operation()).catchError((Object error) {
      if (!_disposed) {
        _error = '任务通知暂时不可用，请检查系统通知设置';
        notifyListeners();
      }
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _revision++;
    _toggleRevision++;
    _timer?.cancel();
    _onTap = null;
    _operations =
        _operations.then((_) => platform.stopProgress()).catchError((_) {});
    platform.dispose();
    super.dispose();
  }
}
