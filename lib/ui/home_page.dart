import 'package:flutter/material.dart';

import '../state/device_store.dart';
import 'theme.dart';

/// Multi-device home: lists connected desktops, add/remove/rename, and a
/// stub entry point into a device workspace.
class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.store});

  final DeviceStore store;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _urlController = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.store.load();
    widget.store.addListener(_onStoreChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStoreChanged);
    _urlController.dispose();
    super.dispose();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _addDevice() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) return;
    try {
      await widget.store.addUrl(url);
      _urlController.clear();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('设备已添加')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('添加失败：$e')),
      );
    }
  }

  Future<void> _confirmRemove(Device device) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除设备'),
        content: Text('确定移除「${device.label}」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (ok == true) await widget.store.remove(device.id);
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final devices = widget.store.devices;
    return Scaffold(
      appBar: AppBar(
        title: const Text('ZcodeRemote'),
        backgroundColor: ink.surface,
        foregroundColor: ink.text,
      ),
      body: devices.isEmpty ? _buildEmpty(ink) : _buildList(devices, ink),
      bottomNavigationBar: _buildAddBar(ink),
    );
  }

  Widget _buildEmpty(InkTokens ink) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.desktop_windows_outlined,
              size: 64, color: ink.text.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text('还没有设备', style: TextStyle(color: ink.text)),
          const SizedBox(height: 8),
          Text(
            '在桌面端 ZCode 打开「远程控制」，把链接粘贴到下方',
            style: TextStyle(color: ink.text.withValues(alpha: 0.6), fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildList(List<Device> devices, InkTokens ink) {
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: devices.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final device = devices[i];
        return Card(
          color: ink.card,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(ZRadius.lg),
            side: BorderSide(color: ink.border),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: ZInk.reasoning.withValues(alpha: 0.15),
              child: const Icon(Icons.computer, color: ZInk.reasoning),
            ),
            title: Text(device.label, style: TextStyle(color: ink.text)),
            subtitle: Text(
              device.params?.deviceSid ?? '未知设备',
              style: TextStyle(
                  color: ink.text.withValues(alpha: 0.6), fontSize: 12),
            ),
            onTap: () {
              widget.store.touch(device.id);
              // TODO(重构): 进入设备工作区（workspace 列表 → 会话）。
            },
            onLongPress: () => _showDeviceMenu(device),
          ),
        );
      },
    );
  }

  void _showDeviceMenu(Device device) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.drive_file_rename_outline),
              title: const Text('重命名'),
              onTap: () {
                Navigator.pop(ctx);
                _renameDevice(device);
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.redAccent),
              title: const Text('移除', style: TextStyle(color: Colors.redAccent)),
              onTap: () {
                Navigator.pop(ctx);
                _confirmRemove(device);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _renameDevice(Device device) async {
    final controller = TextEditingController(text: device.label);
    final label = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名设备'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '设备名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (label != null && label.isNotEmpty) {
      await widget.store.rename(device.id, label);
    }
  }

  Widget _buildAddBar(InkTokens ink) {
    return Container(
      padding: EdgeInsets.only(
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      decoration: BoxDecoration(
        color: ink.surface,
        border: Border(top: BorderSide(color: ink.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _urlController,
              style: TextStyle(color: ink.text),
              decoration: InputDecoration(
                hintText: '粘贴远程控制链接…',
                hintStyle: TextStyle(color: ink.text.withValues(alpha: 0.5)),
                filled: true,
                fillColor: ink.card,
                isDense: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ZRadius.lg),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _addDevice(),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _addDevice,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}
