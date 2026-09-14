import 'dart:async';

import 'package:flutter/material.dart';

import '../../protocol/channel_client.dart';
import '../../state/app_sessions.dart';
import '../../state/client_preferences.dart';
import '../../state/remote_settings.dart';
import '../theme.dart';
import 'settings_widgets.dart';

/// "常规" settings section (S1). Extracted from `settings_center_page.dart`:
/// the local language preference plus the remote terminal/proxy/behavior/
/// archive cards, and the win32 integrated-shell select with its read-only
/// `systemService.listIntegratedTerminalShells` lifecycle (failures degrade
/// exactly like the official page: select hidden or the auto-only entry).
class GeneralSettingsPage extends StatefulWidget {
  const GeneralSettingsPage({
    super.key,
    required this.preferences,
    required this.remoteSettings,
    required this.remoteMonitor,
  });

  final ClientPreferences preferences;
  final RemoteSettingsController? remoteSettings;

  /// Read-only system info (platform + shells) is keyed to this monitor;
  /// a late response from a previous connection cannot populate the shells
  /// of a new one (generation guard).
  final WorkspaceMonitor? remoteMonitor;

  @override
  State<GeneralSettingsPage> createState() => _GeneralSettingsPageState();
}

class _GeneralSettingsPageState extends State<GeneralSettingsPage> {
  String? _remotePlatform;
  List<Map<String, Object?>> _terminalShells = const [];
  int _systemInfoGeneration = 0;

  @override
  void initState() {
    super.initState();
    _loadSystemInfo(widget.remoteMonitor);
  }

  @override
  void didUpdateWidget(covariant GeneralSettingsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.remoteMonitor, widget.remoteMonitor)) {
      _loadSystemInfo(widget.remoteMonitor);
    }
  }

  /// Remote part of the General section. The official web client writes
  /// `taskAutoArchiveEnabled` via switch and `taskAutoArchiveOlderThanDays`
  /// via select with fixed 3/7/14/30-day options (IntlProvider bundle).
  Future<void> _loadSystemInfo(WorkspaceMonitor? monitor) async {
    if (monitor == null) return;
    final generation = ++_systemInfoGeneration;
    String? platform;
    var shells = const <Map<String, Object?>>[];
    try {
      final info = await monitor.bridge.channels.call(
          Channels.system, 'info', const [],
          timeout: const Duration(seconds: 10));
      if (info is Map && info['platform'] is String) {
        platform = info['platform'] as String;
      }
    } catch (_) {}
    if (platform == 'win32') {
      try {
        final raw = await monitor.bridge.channels.call(
            Channels.system, 'listIntegratedTerminalShells', const [],
            timeout: const Duration(seconds: 10));
        if (raw is List) {
          shells = [
            for (final entry in raw)
              if (entry is Map && entry['id'] is String)
                {
                  'id': entry['id'] as String,
                  'label': entry['label'] is String
                      ? entry['label'] as String
                      : entry['id'] as String,
                  'dialect': entry['dialect'] is String
                      ? entry['dialect'] as String
                      : '',
                  'path':
                      entry['path'] is String ? entry['path'] as String : '',
                },
          ];
        }
      } catch (_) {}
    }
    if (!mounted || generation != _systemInfoGeneration) return;
    setState(() {
      _remotePlatform = platform;
      _terminalShells = shells;
    });
  }

  Map<String, Object?>? _selectedShell(
      List<Map<String, Object?>> options, String id) {
    for (final shell in options) {
      if (shell['id'] == id) return shell;
    }
    return null;
  }

  Widget _integratedShellRow(BuildContext context, InkTokens ink,
      RemoteSettingsController remote) {
    final snapshot = remote.snapshot;
    final mode = snapshot.integratedTerminalShellMode;
    final selectedId = snapshot.integratedTerminalShellId;
    final saving = remote.isSaving('integratedTerminalShell');
    final options = <Map<String, Object?>>[
      // Official behavior: a stored shell that is not in the current system
      // list is still shown, built from the snapshot fields.
      if (mode == 'shell' &&
          selectedId != null &&
          !_terminalShells.any((shell) => shell['id'] == selectedId))
        {
          'id': selectedId,
          'label': snapshot.integratedTerminalShellLabel ?? selectedId,
          'dialect': snapshot.integratedTerminalShellDialect ?? '',
          'path': snapshot.integratedTerminalShellPath ?? '',
        },
      ..._terminalShells,
    ];
    return settingsRow(
        ink,
        uiText(context, '集成终端Shell', 'Integrated terminal shell'),
        uiText(
            context,
            '仅新会话生效。Windows 下 Bash 工具用此 shell；自动优先 Git Bash，找不到回退 cmd.exe。',
            'Applies to new sessions only. Bash tools prefer the selected '
                'shell on Windows; auto prefers Git Bash and falls back to cmd.'),
        saving
            ? remoteSpinner()
            : SizedBox(
                width: 220,
                child: DropdownButton<String>(
                    value: mode == 'shell' &&
                            selectedId != null &&
                            options.any((shell) => shell['id'] == selectedId)
                        ? selectedId
                        : (mode == 'shell' ? null : 'auto'),
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                          value: 'auto',
                          child: Text(uiText(context, '自动选择', 'Auto'))),
                      for (final shell in options)
                        DropdownMenuItem(
                            value: shell['id'] as String?,
                            child: Text((shell['label'] as String?) ??
                                (shell['id'] as String? ?? ''))),
                    ],
                    onChanged: remote.remoteOperationsAvailable
                        ? (id) {
                            if (id == null) return;
                            if (id == 'auto') {
                              unawaited(remote.update(
                                  'integratedTerminalShell', {'mode': 'auto'}));
                              return;
                            }
                            final shell = _selectedShell(options, id);
                            if (shell == null) return;
                            unawaited(remote.update('integratedTerminalShell', {
                              'mode': 'shell',
                              'dialect': shell['dialect'],
                              'id': shell['id'],
                              'label': shell['label'],
                              'path': shell['path'],
                            }));
                          }
                        : null)));
  }

  @override
  Widget build(BuildContext context) {
    final prefs = widget.preferences;
    final remote = widget.remoteSettings;
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final languageLabel = switch (prefs.language) {
      'zh' => '中文简体',
      'en' => 'English',
      _ => uiText(context, '跟随系统', 'System'),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Official yQt locale chip under the section title.
      Align(
          alignment: Alignment.centerLeft,
          child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                  color: ink.hover, borderRadius: BorderRadius.circular(8)),
              child:
                  Text(languageLabel, style: const TextStyle(fontSize: 12.5)))),
      const SizedBox(height: 16),
      settingsCard(ink, [
        settingsRow(
            ink,
            uiText(context, '界面语言', 'Interface language'),
            uiText(context, '选择应用 UI 的显示语言。',
                'Choose the display language of the app UI.'),
            SizedBox(
                width: 220,
                child: DropdownButton<String>(
                    value: prefs.language,
                    isExpanded: true,
                    underline: const SizedBox(),
                    items: [
                      DropdownMenuItem(
                          value: 'system',
                          child: Text(uiText(context, '跟随系统', 'System'))),
                      DropdownMenuItem(
                          value: 'zh',
                          child: Text(
                              uiText(context, '中文简体', 'Simplified Chinese'))),
                      DropdownMenuItem(
                          value: 'en',
                          child: Text(uiText(context, 'English', 'English')))
                    ],
                    onChanged: (value) {
                      if (value != null) unawaited(prefs.setLanguage(value));
                    }))),
      ]),
      if (remote == null) ...[
        const SizedBox(height: 16),
        Text(
            uiText(context, '未连接远端工作区，远端设置不可用。',
                'No remote workspace connected. Remote settings are unavailable.'),
            style: TextStyle(color: ink.subtlest)),
      ] else
        ListenableBuilder(
            listenable: remote,
            builder: (context, _) {
              final snapshot = remote.snapshot;

              // Official card layout: terminal group, proxy group, behavior
              // group and archive group. Rows are kept in separate lists so
              // an optional row (the win32-only shell select) never shifts
              // the group boundaries.
              final terminalRows = <Widget>[];
              final proxyRows = <Widget>[];
              final behaviorRows = <Widget>[];

              // Terminal card: profile inheritance, font override, the
              // win32-only integrated shell select and native search.
              terminalRows.add(remoteToggle(
                  context,
                  ink,
                  remote,
                  'terminalInheritSystemProfile',
                  uiText(context, '继承系统终端 Profile',
                      'Inherit system terminal profile'),
                  snapshot.terminalInheritSystemProfile,
                  officialDefault: true,
                  description: uiText(
                      context,
                      '启动内置终端时尽量继承登录 shell 环境、代理、Kube 变量和本机终端字体。',
                      'When launching the built-in terminal, inherit login '
                          'shell environment, proxy, Kubernetes variables, '
                          'and local terminal font when possible.')));
              terminalRows.add(RemoteTextSetting(
                  controller: remote,
                  settingKey: 'terminalFontFamily',
                  title: uiText(context, '终端字体', 'Terminal font'),
                  description: uiText(
                      context,
                      '留空时自动探测系统终端配置；填写后作为 ZCode 终端的字体覆盖。',
                      'Auto-detect when empty; otherwise overrides the ZCode terminal font.'),
                  placeholder: uiText(
                      context,
                      '留空自动继承，例如 MesloLGS NF, monospace',
                      'Empty to inherit, e.g. MesloLGS NF, monospace'),
                  monospace: true));
              if (_remotePlatform == 'win32') {
                terminalRows.add(_integratedShellRow(context, ink, remote));
              }
              terminalRows.add(remoteToggle(
                  context,
                  ink,
                  remote,
                  'nativeSearchEnhancementsEnabled',
                  uiText(context, '增强 Find 和 Grep', 'Enhanced Find and Grep'),
                  snapshot.nativeSearchEnhancementsEnabled,
                  officialDefault: true,
                  description: uiText(
                      context,
                      '在新建会话或应用重启后恢复的会话中使用增强 Find 和 Grep。当前会话保持现有设置；Windows 的 Find 保持不变。',
                      'Use enhanced Find and Grep in new sessions and sessions '
                          'restored after an app restart. Active sessions keep '
                          'their current setting; Find remains unchanged on '
                          'Windows.')));

              // Proxy card: three independently saved text settings.
              Widget proxyText(String key, String title, String description,
                      String placeholder) =>
                  RemoteTextSetting(
                      controller: remote,
                      settingKey: key,
                      title: title,
                      description: description,
                      placeholder: placeholder,
                      monospace: true);
              proxyRows.add(proxyText(
                  'httpProxy',
                  uiText(context, 'HTTP 代理', 'HTTP proxy'),
                  uiText(
                      context,
                      '模型、MCP、命令工具与应用渲染层的出口流量将经此代理，不读取系统环境变量。留空时这些流量直连，内置浏览器则跟随系统代理设置。修改后需重启应用生效。',
                      'Route model, MCP, command-tool, and app renderer egress '
                          'traffic through this proxy; system environment '
                          'variables are not read. Leave blank and that '
                          'traffic connects directly, while the embedded '
                          'browser follows your system proxy settings. Restart '
                          'the app to take effect.'),
                  uiText(
                      context,
                      '留空则内置浏览器跟随系统代理，例如 http://127.0.0.1:7890',
                      'Blank means the embedded browser follows the system '
                          'proxy, e.g. http://127.0.0.1:7890')));
              proxyRows.add(proxyText(
                  'httpProxyNoProxy',
                  uiText(context, '不使用代理的地址', 'No proxy'),
                  uiText(
                      context,
                      '匹配这些主机的请求将直连，不经过 HTTP 代理。多个规则用英文逗号分隔。修改后需重启应用生效。',
                      'Requests matching these hosts connect directly instead '
                          'of using the HTTP proxy. Separate rules with '
                          'commas. Restart the app to take effect.'),
                  uiText(
                      context,
                      '例如 localhost,127.0.0.1,::1,.example.com,*.corp.com',
                      'e.g. localhost,127.0.0.1,::1,.example.com,*.corp.com')));
              proxyRows.add(proxyText(
                  'httpProxyCaCertPath',
                  uiText(context, '自定义证书', 'Custom certificate'),
                  uiText(
                      context,
                      '可选。填写 PEM 根证书路径后，会作为 NODE_EXTRA_CA_CERTS 注入模型、MCP 与命令工具，并用于渲染层证书校验。修改后需重启应用生效。',
                      'Optional. Set a PEM root certificate path to inject it '
                          'as NODE_EXTRA_CA_CERTS for models, MCP, and command '
                          'tools, and to trust it in renderer certificate '
                          'verification. Restart the app to take effect.'),
                  uiText(context, '例如 /Users/name/certs/root-ca.pem',
                      'e.g. /Users/name/certs/root-ca.pem')));

              // Behavior card (official general page bottom group; the old
              // local “对话” section content lives here per official
              // structure).
              behaviorRows.add(settingsRow(
                  ink,
                  uiText(context, '交互行为', 'Interaction behavior'),
                  uiText(
                      context,
                      '在 ZCode 运行时将后续操作加入队列，或引导至下一轮工具调用后运行。',
                      'While ZCode is running, add follow-up actions to the '
                          'queue or guide them to run after the next tool call.'),
                  remote.isSaving('zcodeInteractionBehavior')
                      ? remoteSpinner()
                      : SizedBox(
                          width: 220,
                          child: DropdownButton<String>(
                              value: const {
                                'queue',
                                'guide'
                              }.contains(snapshot.zcodeInteractionBehavior)
                                  ? snapshot.zcodeInteractionBehavior
                                  : null,
                              isExpanded: true,
                              underline: const SizedBox(),
                              items: [
                                DropdownMenuItem(
                                    value: 'queue',
                                    child:
                                        Text(uiText(context, '队列', 'Queue'))),
                                DropdownMenuItem(
                                    value: 'guide',
                                    child:
                                        Text(uiText(context, '引导', 'Guide'))),
                              ],
                              onChanged: snapshot.zcodeInteractionBehavior ==
                                      null
                                  ? null
                                  : (value) {
                                      if (value != null) {
                                        unawaited(remote.update(
                                            'zcodeInteractionBehavior', value));
                                      }
                                    }))));
              behaviorRows.add(remoteToggle(
                  context,
                  ink,
                  remote,
                  'askUserQuestionAutoResolutionEnabled',
                  uiText(context, '提问自动继续', 'Automatically continue questions'),
                  snapshot.askUserQuestionAutoResolutionEnabled,
                  officialDefault: true,
                  description: uiText(
                      context,
                      '开启后，Agent 提问 5 分钟未回答会自动继续；关闭后，当前和后续提问会一直等待你的回答。',
                      'When enabled, Agent questions automatically continue '
                          'after 5 minutes without an answer. When disabled, '
                          'current and future questions wait for your response.')));
              behaviorRows.add(remoteToggle(
                  context,
                  ink,
                  remote,
                  'modelIoFullRetentionEnabled',
                  uiText(context, '完整保留模型 I/O', 'Keep complete model I/O'),
                  snapshot.modelIoFullRetentionEnabled,
                  officialDefault: false,
                  description: uiText(
                      context,
                      '保留完整的模型请求和响应，不自动压缩、限制大小或删除旧记录。',
                      'Keep complete model requests and responses without '
                          'compression, size limits, or automatic deletion.')));
              behaviorRows.add(remoteToggle(
                  context,
                  ink,
                  remote,
                  'messageStreamShowReasoning',
                  uiText(context, '显示思考过程', 'Show reasoning'),
                  snapshot.messageStreamShowReasoning,
                  officialDefault: true,
                  description: uiText(
                      context,
                      '在消息流中展示完整的模型思考内容；关闭时每轮仍展示第一次思考。',
                      'Show full reasoning inside the message stream. When '
                          'off, the first reasoning item in each turn remains '
                          'visible.')));
              behaviorRows.add(remoteToggle(
                  context,
                  ink,
                  remote,
                  'messageStreamShowTodos',
                  uiText(context, '显示待办', 'Show todos'),
                  snapshot.messageStreamShowTodos,
                  officialDefault: false,
                  description: uiText(context, '在消息流中展示 Todo 工具卡片。',
                      'Show Todo tool cards inside the message stream.')));
              behaviorRows.add(remoteToggle(
                  context,
                  ink,
                  remote,
                  'toolGroupingExploreEnabled',
                  uiText(context, '分组探索工具', 'Group exploration tools'),
                  snapshot.toolGroupingExploreEnabled,
                  officialDefault: true,
                  description: uiText(
                      context,
                      '将连续的读取和搜索工具聚合为 Explore 分组。',
                      'Group consecutive reads and searches into an Explore '
                          'section.')));
              behaviorRows.add(remoteToggle(
                  context,
                  ink,
                  remote,
                  'toolGroupingTerminalEnabled',
                  uiText(context, '分组终端命令', 'Group terminal commands'),
                  snapshot.toolGroupingTerminalEnabled,
                  officialDefault: true,
                  description: uiText(
                      context,
                      '将连续的非只读 Shell 命令聚合为 Terminal 分组。',
                      'Group consecutive non-read-only shell commands into a '
                          'Terminal section.')));
              behaviorRows.add(remoteToggle(
                  context,
                  ink,
                  remote,
                  'toolGroupingChangesEnabled',
                  uiText(context, '分组文件更改', 'Group file changes'),
                  snapshot.toolGroupingChangesEnabled,
                  officialDefault: false,
                  description: uiText(
                      context,
                      '将连续的 Write、Edit 和 ApplyPatch 调用聚合为 Changes 分组。',
                      'Group consecutive Write, Edit, and ApplyPatch calls '
                          'into a Changes section.')));

              // Archive card (existing E1.2 write path).
              final days = snapshot.taskAutoArchiveOlderThanDays;
              final savingDays =
                  remote.isSaving('taskAutoArchiveOlderThanDays');
              const dayOptions = [3, 7, 14, 30];

              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 24),
                    settingsCard(ink, terminalRows),
                    const SizedBox(height: 16),
                    settingsCard(ink, proxyRows),
                    const SizedBox(height: 16),
                    settingsCard(ink, behaviorRows),
                    const SizedBox(height: 16),
                    settingsCard(ink, [
                      remoteToggle(
                          context,
                          ink,
                          remote,
                          'taskAutoArchiveEnabled',
                          uiText(context, '自动归档旧任务', 'Auto-archive old tasks'),
                          snapshot.taskAutoArchiveEnabled,
                          description: uiText(
                              context,
                              '定时扫描最近打开过的工作区，将已完成、无未读、未置顶且超过保留期的任务自动归档。',
                              'Periodically scan recently opened workspaces '
                                  'and automatically archive completed, '
                                  'unread-free, unpinned tasks after the '
                                  'retention window.')),
                      settingsRow(
                          ink,
                          uiText(context, '归档保留时长', 'Archive retention'),
                          uiText(
                              context,
                              '任务最后更新时间早于该时长后，才会进入自动归档候选。',
                              'A task becomes eligible for auto-archive only '
                                  'after its last update is older than this '
                                  'window.'),
                          savingDays
                              ? remoteSpinner()
                              : SizedBox(
                                  width: 220,
                                  child: DropdownButton<int>(
                                      value: days != null &&
                                              dayOptions.contains(days)
                                          ? days
                                          : null,
                                      isExpanded: true,
                                      underline: const SizedBox(),
                                      items: [
                                        for (final d in dayOptions)
                                          DropdownMenuItem(
                                              value: d,
                                              child: Text(uiText(
                                                  context,
                                                  '$d 天后归档',
                                                  'Archive after $d days')))
                                      ],
                                      onChanged: days == null ||
                                              !remote.remoteOperationsAvailable
                                          ? null
                                          : (value) {
                                              if (value != null) {
                                                unawaited(remote.update(
                                                    'taskAutoArchiveOlderThanDays',
                                                    value));
                                              }
                                            }))),
                    ]),
                    saveFailedColumn(
                        context,
                        remote.saveError('taskAutoArchiveOlderThanDays') !=
                            null,
                        savingDays,
                        remote.remoteOperationsAvailable
                            ? () => unawaited(remote.update(
                                'taskAutoArchiveOlderThanDays',
                                remote.lastAttempt(
                                    'taskAutoArchiveOlderThanDays')))
                            : null),
                  ]);
            }),
    ]);
  }
}
