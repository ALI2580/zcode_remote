import 'dart:async';
import 'package:flutter/material.dart';
import '../state/app_sessions.dart';
import '../state/client_preferences.dart';
import '../state/device_store.dart';
import '../protocol/connection_params.dart';
import 'official_icons.dart';
import 'device_connection_status.dart';
import 'theme.dart';

class DeviceDirectory extends StatefulWidget {
  const DeviceDirectory(
      {super.key,
      required this.store,
      required this.sessions,
      required this.onOpen,
      required this.onSettings});
  final DeviceStore store;
  final AppSessions sessions;
  final Future<void> Function(Device) onOpen;
  final VoidCallback onSettings;
  @override
  State<DeviceDirectory> createState() => _DeviceDirectoryState();
}

class _DeviceDirectoryState extends State<DeviceDirectory> {
  String? _opening;
  bool _adding = false;
  Future<void> _open(Device device) async {
    setState(() => _opening = device.id);
    try {
      await widget.onOpen(device);
    } catch (_) {
      if (mounted) {
        _message(uiText(context, '连接失败，请重试', 'Connection failed. Try again.'));
      }
    } finally {
      if (mounted && _opening == device.id) setState(() => _opening = null);
    }
  }

  void _message(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  Future<void> _add({Device? replacing}) async {
    if (_adding) return;
    setState(() => _adding = true);
    final device = await showDialog<Device>(
        context: context,
        builder: (_) =>
            _DeviceLinkDialog(store: widget.store, replacing: replacing));
    if (!mounted) return;
    setState(() => _adding = false);
    if (device != null) await _open(device);
  }

  Future<void> _rename(Device device) async {
    final controller = TextEditingController(text: device.label);
    final value = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(uiText(context, '重命名设备', 'Rename device')),
                content: TextField(
                    controller: controller,
                    autofocus: true,
                    onSubmitted: (value) => Navigator.pop(context, value)),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(uiText(context, '取消', 'Cancel'))),
                  FilledButton(
                      onPressed: () =>
                          Navigator.pop(context, controller.text.trim()),
                      child: Text(uiText(context, '保存', 'Save')))
                ]));
    // Dispose after the dialog's closing route has finished its transition.
    Future<void>.delayed(const Duration(milliseconds: 350), controller.dispose);
    if (value != null && value.trim().isNotEmpty) {
      await widget.store.rename(device.id, value);
    }
  }

  Future<void> _remove(Device device) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
                title: Text(uiText(context, '移除设备', 'Remove device')),
                content: Text(uiText(context, '移除「${device.label}」的连接记录？',
                    'Remove the saved connection for ${device.label}?')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: Text(uiText(context, '取消', 'Cancel'))),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: Text(uiText(context, '移除', 'Remove')))
                ]));
    if (confirmed == true) await widget.store.remove(device.id);
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: Listenable.merge([widget.store, widget.sessions]),
      builder: (context, _) {
        final ink = ZInk.of(Theme.of(context).colorScheme);
        final devices = widget.store.devices.toList()
          ..sort((a, b) => b.lastUsedAt.compareTo(a.lastUsedAt));
        return Column(children: [
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(children: [
                Text('ZcodeRemote',
                    style: TextStyle(
                        color: ink.text,
                        fontSize: 15,
                        fontWeight: FontWeight.w500)),
              ])),
          Divider(height: 1, color: ink.border),
          Expanded(
              child: Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 760),
                      child: ListView(
                          padding: const EdgeInsets.fromLTRB(24, 36, 24, 24),
                          children: [
                            Row(children: [
                              Expanded(
                                  child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                    Text(
                                        uiText(context, '你的设备', 'Your devices'),
                                        style: TextStyle(
                                            fontSize: 24,
                                            color: ink.text,
                                            fontWeight: FontWeight.w500)),
                                    const SizedBox(height: 6),
                                    Text(
                                        uiText(context, '回到正在进行的工作。',
                                            'Return to the work in progress.'),
                                        style: TextStyle(color: ink.subtlest)),
                                  ])),
                              IconButton(
                                  tooltip:
                                      uiText(context, '添加设备', 'Add device'),
                                  onPressed: _adding ? null : _add,
                                  icon: LucideIcon('plus',
                                      size: 20, color: ink.text))
                            ]),
                            const SizedBox(height: 28),
                            if (!widget.store.loaded)
                              const Center(child: CircularProgressIndicator()),
                            if (widget.store.loaded && devices.isEmpty)
                              Padding(
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 36),
                                  child: Column(children: [
                                    LucideIcon('monitor',
                                        size: 32, color: ink.subtlest),
                                    const SizedBox(height: 20),
                                    Text(
                                        uiText(
                                            context,
                                            '在桌面 ZCode 开启远程控制，然后添加连接链接。',
                                            'Enable remote control in desktop ZCode, then add its connection link.'),
                                        textAlign: TextAlign.center,
                                        style: TextStyle(color: ink.subtlest)),
                                    const SizedBox(height: 20),
                                    FilledButton(
                                        onPressed: _add,
                                        child: Text(uiText(context, '添加第一台设备',
                                            'Add your first device')))
                                  ])),
                            for (final device in devices) ...[
                              Divider(height: 1, color: ink.border),
                              Builder(builder: (context) {
                                final session =
                                    widget.sessions.sessionOf(device.id);
                                final status =
                                    deviceConnectionStatus(context, session);
                                return ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 10),
                                    leading: Container(
                                        width: 38,
                                        height: 38,
                                        decoration: BoxDecoration(
                                            border:
                                                Border.all(color: ink.border),
                                            borderRadius:
                                                BorderRadius.circular(10)),
                                        child: Center(
                                            child: LucideIcon('monitor',
                                                size: 18, color: ink.text))),
                                    title: Text(device.label,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w500)),
                                    subtitle: Text(status,
                                        style: TextStyle(
                                            fontSize: 12,
                                            color: session?.connected == true
                                                ? ink.diffAdded
                                                : ink.subtlest)),
                                    trailing: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          if (_opening == device.id)
                                            const SizedBox(
                                                width: 16,
                                                height: 16,
                                                child:
                                                    CircularProgressIndicator(
                                                        strokeWidth: 2)),
                                          PopupMenuButton<String>(
                                              tooltip: uiText(context, '设备操作',
                                                  'Device actions'),
                                              icon: LucideIcon('ellipsis',
                                                  size: 18,
                                                  color: ink.subtlest),
                                              onSelected: (value) async {
                                                try {
                                                  switch (value) {
                                                    case 'rename':
                                                      await _rename(device);
                                                    case 'link':
                                                      await _add(
                                                          replacing: device);
                                                    case 'disconnect':
                                                      widget.sessions
                                                          .disconnect(
                                                              device.id);
                                                    case 'remove':
                                                      await _remove(device);
                                                  }
                                                } catch (_) {
                                                  if (context.mounted) {
                                                    _message(uiText(
                                                        context,
                                                        '操作失败，请重试',
                                                        'Operation failed. Try again.'));
                                                  }
                                                }
                                              },
                                              itemBuilder: (context) => [
                                                    PopupMenuItem(
                                                        value: 'rename',
                                                        child: Text(uiText(
                                                            context,
                                                            '重命名',
                                                            'Rename'))),
                                                    PopupMenuItem(
                                                        value: 'link',
                                                        child: Text(uiText(
                                                            context,
                                                            '更新连接链接',
                                                            'Update connection link'))),
                                                    if (session != null)
                                                      PopupMenuItem(
                                                          value: 'disconnect',
                                                          child: Text(uiText(
                                                              context,
                                                              '断开连接',
                                                              'Disconnect'))),
                                                    PopupMenuItem(
                                                        value: 'remove',
                                                        child: Text(uiText(
                                                            context,
                                                            '移除',
                                                            'Remove'))),
                                                  ])
                                        ]),
                                    onTap: () => _open(device));
                              }),
                            ],
                          ])))),
          Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: TextButton.icon(
                      onPressed: widget.onSettings,
                      icon:
                          LucideIcon('settings', size: 16, color: ink.subtlest),
                      label: Text(uiText(context, '设置', 'Settings'),
                          style: TextStyle(color: ink.subtlest))))),
        ]);
      });
}

class _DeviceLinkDialog extends StatefulWidget {
  const _DeviceLinkDialog({required this.store, this.replacing});
  final DeviceStore store;
  final Device? replacing;
  @override
  State<_DeviceLinkDialog> createState() => _DeviceLinkDialogState();
}

class _DeviceLinkDialogState extends State<_DeviceLinkDialog> {
  late final _label = TextEditingController(text: widget.replacing?.label);
  final _url = TextEditingController();
  bool _saving = false;
  String? _error;
  @override
  void dispose() {
    _label.dispose();
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    if (ZemoteConnectionParams.parse(_url.text.trim()) == null) {
      setState(() => _error =
          uiText(context, '请粘贴有效的远程控制链接', 'Paste a valid remote-control link'));
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final device = widget.replacing == null
          ? await widget.store.addUrl(_url.text.trim(), label: _label.text)
          : await widget.store.updateLink(
              widget.replacing!.id, _url.text.trim(),
              label: _label.text);
      if (mounted) Navigator.pop(context, device);
    } catch (_) {
      if (mounted) {
        setState(() => _error = uiText(context, '无法保存链接，请确认它属于当前设备',
            'Could not save the link. Check the selected device.'));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
          title: Text(widget.replacing == null
              ? uiText(context, '添加设备', 'Add device')
              : uiText(context, '更新连接链接', 'Update connection link')),
          content: SizedBox(
              width: 400,
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                        controller: _label,
                        decoration: InputDecoration(
                            labelText: uiText(context, '设备名称', 'Device name'))),
                    const SizedBox(height: 16),
                    TextField(
                        controller: _url,
                        autofocus: true,
                        obscureText: true,
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                            labelText: uiText(
                                context, '远程控制链接', 'Remote-control link'),
                            hintText: 'https://zcode.z.ai/remote/v4?...'),
                        onSubmitted: (_) => _save()),
                    if (_error != null)
                      Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_error!,
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error))),
                  ])),
          actions: [
            TextButton(
                onPressed: _saving ? null : () => Navigator.pop(context),
                child: Text(uiText(context, '取消', 'Cancel'))),
            FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving
                    ? uiText(context, '保存中…', 'Saving…')
                    : uiText(context, '连接', 'Connect')))
          ]);
}
