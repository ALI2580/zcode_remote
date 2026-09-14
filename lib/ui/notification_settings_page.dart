import 'package:flutter/material.dart';

import '../notifications/task_notification_controller.dart';
import '../state/client_preferences.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage(
      {super.key, required this.controller, this.embedded = false});

  final TaskNotificationController controller;

  /// When true the body renders without its own Scaffold/AppBar so a host
  /// (settings center right pane) can embed it directly.
  final bool embedded;
  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _busy = false;

  String _errorText(BuildContext context, String value) => switch (value) {
        '暂时无法读取系统通知状态' =>
          uiText(context, value, 'Unable to read system notification status.'),
        '未获得通知权限，可在系统设置中开启' => uiText(context, value,
            'Notification permission is unavailable. Enable it in system settings.'),
        '任务通知暂时不可用，请检查系统通知设置' => uiText(context, value,
            'Task notifications are temporarily unavailable. Check system notification settings.'),
        _ => value,
      };

  @override
  void initState() {
    super.initState();
    widget.controller.initialize();
  }

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    try {
      await widget.controller.setEnabled(value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final capabilities = widget.controller.capabilities;
        final liveStatus = !capabilities.promotedSupported
            ? uiText(context, '使用普通任务通知', 'Uses standard task notifications')
            : capabilities.promotedAllowed == false
                ? uiText(context, '已被系统关闭', 'Disabled by the system')
                : capabilities.promotedAllowed == true
                    ? uiText(context, '系统允许，按厂商条件显示',
                        'Allowed by the system; shown according to vendor rules')
                    : uiText(context, '由系统决定显示方式',
                        'Display is decided by the system');
        final controls = <Widget>[
          SwitchListTile.adaptive(
            title:
                Text(uiText(context, '任务进度通知', 'Task progress notifications')),
            subtitle: Text(uiText(context, '持续显示任务进展；ColorOS 16 支持时可上岛',
                'Keep task progress visible; Live Updates appear when supported.')),
            value: widget.controller.enabled,
            onChanged: _busy || !capabilities.supported ? null : _toggle,
          ),
          ListTile(
              title:
                  Text(uiText(context, '通知权限', 'Notification permission')),
              subtitle: Text(uiText(
                  context,
                  capabilities.allowed ? '已允许' : '未允许',
                  capabilities.allowed ? 'Allowed' : 'Not allowed'))),
          ListTile(
              title: Text(uiText(context, '实时活动', 'Live Updates')),
              subtitle: Text(liveStatus)),
          ListTile(
              title: Text(uiText(
                  context, '系统通知设置', 'System notification settings')),
              subtitle: Text(uiText(context, '管理通知权限与实时活动显示',
                  'Manage notification permission and Live Updates.')),
              trailing: const Icon(Icons.chevron_right),
              onTap: capabilities.supported
                  ? () => widget.controller.platform.openSettings()
                  : null),
          Padding(
              padding: EdgeInsets.all(16),
              child: Text(uiText(
                  context,
                  '通知只展示正在进行的任务。点击可回到对应设备和任务；“停止显示”不会停止桌面任务。',
                  'Notifications show active tasks only. Tap one to return to its device and task; “Stop showing” does not stop the desktop task.'))),
          if (widget.controller.error != null)
            Padding(
                padding: const EdgeInsets.all(16),
                child: Text(_errorText(context, widget.controller.error!),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.error))),
        ];
        // Embedded hosts (settings right pane) already scroll; a nested
        // ListView would be unbounded inside their outer ListView.
        if (widget.embedded) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: controls);
        }
        return Scaffold(
          appBar: AppBar(
              title: Text(uiText(context, '任务通知与上岛', 'Task notifications'))),
          body: ListView(padding: const EdgeInsets.symmetric(vertical: 12), children: controls),
        );
      });
}
