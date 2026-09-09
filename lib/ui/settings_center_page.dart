import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import '../state/app_sessions.dart';
import '../state/client_preferences.dart';
import '../update/app_version.dart';
import '../update/update_channel.dart';
import '../update/update_checker.dart';
import 'notification_settings_page.dart';
import 'official_icons.dart';
import 'theme.dart';

class SettingsCenterPage extends StatefulWidget {
  const SettingsCenterPage(
      {super.key,
      required this.preferences,
      required this.sessions,
      required this.onManageDevices,
      this.initialSection = 'general'});
  final ClientPreferences preferences;
  final AppSessions sessions;
  final VoidCallback onManageDevices;
  final String initialSection;
  @override
  State<SettingsCenterPage> createState() => _SettingsCenterPageState();
}

class _SettingsCenterPageState extends State<SettingsCenterPage> {
  late String _section;
  bool _checking = false;
  String? _updateError;
  UpdateInfo? _update;
  @override
  void initState() {
    super.initState();
    _section = widget.initialSection;
    unawaited(widget.preferences.load());
    unawaited(updateChannelSettings.load().then((_) {
      if (mounted) setState(() {});
    }));
  }

  Future<void> _checkUpdate() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _updateError = null;
    });
    try {
      final result = await checkForUpdates();
      if (mounted) setState(() => _update = result);
    } catch (_) {
      if (mounted) {
        setState(() => _updateError = uiText(
            context, '检查失败，请稍后重试', 'Could not check for updates. Try again.'));
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
      listenable: widget.preferences,
      builder: (context, _) {
        final ink = ZInk.of(Theme.of(context).colorScheme);
        final labels = <String, (String, String, String)>{
          'general': ('sliders-horizontal', '常规', 'General'),
          'appearance': ('settings', '外观', 'Appearance'),
          'notifications': ('bell', '通知与上岛', 'Task notifications'),
          'devices': ('monitor', '设备', 'Devices'),
          'updates': ('package', '更新与关于', 'Updates and about'),
        };
        Widget item(String key) {
          final value = labels[key]!;
          return Material(
              color: _section == key ? ink.hover : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => setState(() => _section = key),
                  child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        LucideIcon(value.$1, size: 16, color: ink.subtlest),
                        const SizedBox(width: 10),
                        Flexible(
                            child: Text(uiText(context, value.$2, value.$3),
                                style: const TextStyle(fontSize: 14)))
                      ]))));
        }

        return Scaffold(
            appBar: AppBar(title: Text(uiText(context, '设置', 'Settings'))),
            body: SafeArea(
                top: false,
                child: LayoutBuilder(builder: (context, constraints) {
                  final wide = constraints.maxWidth >=
                      224 +
                          400 *
                              (MediaQuery.textScalerOf(context).scale(14) / 14)
                                  .clamp(1, 2);
                  final content = ListView(
                      padding: EdgeInsets.all(wide ? 28 : 20),
                      children: [
                        Text(
                            uiText(context, labels[_section]!.$2,
                                labels[_section]!.$3),
                            style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w500,
                                color: ink.text)),
                        const SizedBox(height: 24),
                        ..._content(context, ink),
                      ]);
                  if (!wide) {
                    return Column(children: [
                      Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 8),
                          child: DropdownButton<String>(
                              isExpanded: true,
                              value: _section,
                              items: [
                                for (final entry in labels.entries)
                                  DropdownMenuItem(
                                      value: entry.key,
                                      child: Text(uiText(context,
                                          entry.value.$2, entry.value.$3)))
                              ],
                              onChanged: (value) {
                                if (value != null) {
                                  setState(() => _section = value);
                                }
                              })),
                      const Divider(height: 1),
                      Expanded(child: content)
                    ]);
                  }
                  return Row(children: [
                    Container(
                        width: 224,
                        color: ink.surface,
                        padding: const EdgeInsets.all(12),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: labels.keys.map(item).toList())),
                    Expanded(
                        child: Align(
                            alignment: Alignment.topLeft,
                            child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 800),
                                child: content)))
                  ]);
                })));
      });

  List<Widget> _content(BuildContext context, InkTokens ink) {
    final prefs = widget.preferences;
    switch (_section) {
      case 'general':
        return [
          _row(
              uiText(context, '界面语言', 'Interface language'),
              DropdownButton<String>(
                  value: prefs.language,
                  underline: const SizedBox(),
                  items: [
                    DropdownMenuItem(
                        value: 'system',
                        child: Text(uiText(context, '跟随系统', 'System'))),
                    const DropdownMenuItem(value: 'zh', child: Text('简体中文')),
                    const DropdownMenuItem(value: 'en', child: Text('English'))
                  ],
                  onChanged: (value) {
                    if (value != null) unawaited(prefs.setLanguage(value));
                  })),
          const SizedBox(height: 16),
          Text(
              uiText(context, '界面语言不改变任务内容或代码。',
                  'Interface language does not translate conversations or code.'),
              style: TextStyle(color: ink.subtlest)),
        ];
      case 'appearance':
        return [
          _row(
              uiText(context, '主题', 'Theme'),
              DropdownButton<ThemeMode>(
                  value: prefs.theme,
                  underline: const SizedBox(),
                  items: [
                    DropdownMenuItem(
                        value: ThemeMode.system,
                        child: Text(uiText(context, '跟随系统', 'System'))),
                    DropdownMenuItem(
                        value: ThemeMode.dark,
                        child: Text(uiText(context, '深色', 'Dark'))),
                    DropdownMenuItem(
                        value: ThemeMode.light,
                        child: Text(uiText(context, '浅色', 'Light')))
                  ],
                  onChanged: (value) {
                    if (value != null) unawaited(prefs.setTheme(value));
                  })),
          const Divider(),
          _row(uiText(context, '文字大小', 'Text size'),
              Text('${(prefs.textScale * 100).round()}%')),
          Slider(
              value: prefs.textScale,
              min: .8,
              max: 1.4,
              divisions: 12,
              label: '${(prefs.textScale * 100).round()}%',
              onChanged: (value) => unawaited(prefs.setTextScale(value))),
          _row(uiText(context, '代码字号', 'Code font size'),
              Text('${prefs.codeFontSize.round()}')),
          Slider(
              value: prefs.codeFontSize,
              min: 10,
              max: 20,
              divisions: 10,
              onChanged: (value) => unawaited(prefs.setCodeFontSize(value))),
          Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                  color: ink.surface,
                  border: Border.all(color: ink.border),
                  borderRadius: BorderRadius.circular(12)),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(uiText(context, '继续专注于正在进行的工作。',
                        'Stay focused on the work in progress.')),
                    const SizedBox(height: 8),
                    Text('const draft = session.draft;',
                        style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: prefs.codeFontSize,
                            color: ink.text))
                  ])),
          Align(
              alignment: Alignment.centerLeft,
              child: TextButton(
                  onPressed: prefs.resetAppearance,
                  child: Text(uiText(context, '恢复默认', 'Reset to defaults')))),
        ];
      case 'notifications':
        return [
          ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(uiText(
                  context, '任务通知与上岛设置', 'Task notifications and Live Updates')),
              subtitle: Text(uiText(context, '管理任务进度、通知权限和系统实时活动。',
                  'Manage task progress, notification permissions and live updates.')),
              trailing:
                  LucideIcon('chevron-right', size: 16, color: ink.subtlest),
              onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => NotificationSettingsPage(
                          controller: widget.sessions.notifications)))),
        ];
      case 'devices':
        return [
          Text(uiText(context, '切换设备时保留连接与当前任务。',
              'Keep connections and tasks when switching devices.')),
          const SizedBox(height: 20),
          Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton(
                  onPressed: widget.onManageDevices,
                  child: Text(uiText(context, '管理设备', 'Manage devices')))),
        ];
      default:
        return [
          Text('ZcodeRemote $appVersion ($appBuildNumber)',
              style: const TextStyle(fontWeight: FontWeight.w500)),
          const SizedBox(height: 20),
          SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title:
                  Text(uiText(context, '接收 Beta 更新', 'Receive beta updates')),
              value: updateChannelSettings.receiveBetaUpdates,
              onChanged: (value) async {
                await updateChannelSettings.setReceiveBetaUpdates(value);
                if (mounted) setState(() {});
              }),
          const SizedBox(height: 12),
          Align(
              alignment: Alignment.centerLeft,
              child: FilledButton(
                  onPressed: _checking ? null : _checkUpdate,
                  child: Text(_checking
                      ? uiText(context, '正在检查…', 'Checking…')
                      : uiText(context, '检查更新', 'Check for updates')))),
          if (_updateError != null)
            Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(_updateError!,
                    style: TextStyle(color: ink.diffRemoved))),
          if (_update != null) ...[
            const SizedBox(height: 20),
            Text(_update!.isNewer
                ? uiText(context, '发现新版本 ${_update!.latestVersion}',
                    'New version ${_update!.latestVersion}')
                : uiText(context, '当前已是最新版本', 'You are up to date')),
            if (_update!.body?.trim().isNotEmpty == true)
              Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: SelectableText(_update!.body!)),
            if (_update!.isNewer)
              Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                      onPressed: () async {
                        await Clipboard.setData(
                            ClipboardData(text: _update!.releaseUrl));
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              content: Text(uiText(context, '下载页面地址已复制',
                                  'Download page copied'))));
                        }
                      },
                      child: Text(
                          uiText(context, '复制下载页面地址', 'Copy download page')))),
          ],
        ];
    }
  }

  Widget _row(String title, Widget trailing) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: LayoutBuilder(builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title),
                const SizedBox(height: 8),
                trailing,
              ]);
        }
        return Row(children: [
          Expanded(child: Text(title)),
          const SizedBox(width: 16),
          Flexible(
              child: Align(alignment: Alignment.centerRight, child: trailing))
        ]);
      }));
}
