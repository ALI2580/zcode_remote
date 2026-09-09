import 'dart:async';
import 'package:flutter/material.dart';

import '../notifications/task_target.dart';
import '../state/app_sessions.dart';
import '../state/client_preferences.dart';
import '../state/device_store.dart';
import '../state/recovery_journal.dart';
import 'device_directory.dart';
import 'navigation.dart';

/// The root owns device runtimes; workspace routes only choose what to show.
class HomePage extends StatefulWidget {
  const HomePage(
      {super.key, required this.store, this.preferences, this.recovery});
  final DeviceStore store;
  final ClientPreferences? preferences;
  final RecoveryJournal? recovery;
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  late final AppSessions _sessions;
  late final ClientPreferences _preferences;
  int _notificationRevision = 0;

  @override
  void initState() {
    super.initState();
    _preferences = widget.preferences ?? ClientPreferences();
    _sessions = AppSessions(store: widget.store, recovery: widget.recovery);
    _sessions.notifications.onTap = _openNotification;
    unawaited(_sessions.notifications.initialize());
    unawaited(_load());
  }

  Future<void> _load() async {
    final navigation = _sessions.beginNavigation();
    try {
      await Future.wait([widget.store.load(), _preferences.load()]);
      await _sessions.loadRecovery();
      if (!mounted || !_sessions.navigationIsCurrent(navigation)) return;
      if (widget.recovery?.recoveredBackup == true) {
        _message(uiText(context, '已恢复上一次保存的草稿，请核对内容。',
            'Restored the previous saved draft. Please review it.'));
      }
      final device = widget.store.lastUsed;
      if (device != null && device.params != null) await _open(device);
    } catch (_) {
      if (mounted) {
        _message(widget.recovery?.failed == true
            ? uiText(context, '无法恢复上次草稿，本地记录已保留。请重试。',
                'Could not restore drafts. Saved data has been preserved. Retry.')
            : uiText(
                context, '设备加载失败，请重试', 'Could not load devices. Try again.'));
      }
    }
  }

  @override
  void dispose() {
    _sessions.dispose();
    if (widget.preferences == null) _preferences.dispose();
    super.dispose();
  }

  void _message(String text) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _open(Device device, {TaskTarget? target}) async {
    try {
      await openDeviceWorkspace(context, _sessions, _preferences, device,
          target: target);
    } catch (_) {
      if (mounted) {
        _message(widget.recovery?.failed == true
            ? uiText(context, '无法恢复草稿，本地记录已保留，请重试。',
                'Could not restore drafts. Saved data is preserved. Retry.')
            : uiText(context, '连接失败，请检查桌面后重试',
                'Connection failed. Check the desktop and try again.'));
      }
    }
  }

  void _openNotification(TaskTarget target) {
    final revision = ++_notificationRevision;
    _sessions.beginNavigation();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await widget.store.load();
      } catch (_) {
        if (mounted) {
          _message(uiText(
              context, '设备加载失败，请重试', 'Could not load devices. Try again.'));
        }
        return;
      }
      if (!mounted || revision != _notificationRevision) return;
      final device = widget.store.devices
          .where((d) => d.id == target.deviceId)
          .firstOrNull;
      if (device == null || device.params == null) {
        _message(uiText(context, '对应设备不可用，请重新添加连接链接',
            'Device unavailable. Add its connection link again.'));
        return;
      }
      Navigator.of(context).popUntil((route) => route.isFirst);
      await _open(device, target: target);
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
            child: DeviceDirectory(
                store: widget.store,
                sessions: _sessions,
                onOpen: _open,
                onSettings: () =>
                    showSettingsCenter(context, _sessions, _preferences))),
      );
}
