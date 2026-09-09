import 'package:flutter/material.dart';

import '../notifications/task_notification_controller.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key, required this.controller});
  final TaskNotificationController controller;
  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
  bool _busy = false;
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
            ? '使用普通任务通知'
            : capabilities.promotedAllowed == false
                ? '已被系统关闭'
                : capabilities.promotedAllowed == true
                    ? '系统允许，按厂商条件显示'
                    : '由系统决定显示方式';
        return Scaffold(
          appBar: AppBar(title: const Text('任务通知与上岛')),
          body: ListView(
              padding: const EdgeInsets.symmetric(vertical: 12),
              children: [
                SwitchListTile.adaptive(
                  title: const Text('任务进度通知'),
                  subtitle: const Text('持续显示任务进展；ColorOS 16 支持时可上岛'),
                  value: widget.controller.enabled,
                  onChanged: _busy || !capabilities.supported ? null : _toggle,
                ),
                ListTile(
                    title: const Text('通知权限'),
                    subtitle: Text(capabilities.allowed ? '已允许' : '未允许')),
                ListTile(
                    title: const Text('Live Updates'),
                    subtitle: Text(liveStatus)),
                ListTile(
                    title: const Text('系统通知设置'),
                    subtitle: const Text('管理通知权限与实时活动显示'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: capabilities.supported
                        ? () => widget.controller.platform.openSettings()
                        : null),
                const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text('通知只展示正在进行的任务。点击可回到对应设备和任务；“停止显示”不会停止桌面任务。')),
                if (widget.controller.error != null)
                  Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(widget.controller.error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error))),
              ]),
        );
      });
}
