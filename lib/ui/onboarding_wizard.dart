import 'dart:async';

import 'package:flutter/material.dart';

import '../state/client_preferences.dart';
import '../state/settings_import.dart';
import 'theme.dart';

/// Official onboarding wizard (`L$t` welcome + `A$t` steps + `M$t` step nav,
/// footer `onBackStep`/`onNextStep`/`onBeginMigration`). Replaces the previous
/// behaviour of opening the plain import dialog from the 引导 entry.
///
/// Desktop-only steps (local session history scan, AGENTS.md file copy) render
/// their official gate copy instead of pretending to run on a remote host.
class OnboardingWizard {
  static Future<void> show(
    BuildContext context, {
    required SettingsSyncService service,
    String? workspacePath,
    String? workspaceIdentity,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => OnboardingWizardDialog(
        service: service,
        workspacePath: workspacePath,
        workspaceIdentity: workspaceIdentity,
      ),
    );
  }
}

enum _WizardStep {
  welcome,
  session,
  skillsImport,
  mcpImport,
  pluginsImport,
  commandsImport,
  agentsFile,
  agentSettings,
  migration,
  finish;

  bool get isWelcome => this == welcome;
  bool get isMigration => this == migration;
  bool get isFinish => this == finish;
}

class OnboardingWizardDialog extends StatefulWidget {
  const OnboardingWizardDialog({
    super.key,
    required this.service,
    this.workspacePath,
    this.workspaceIdentity,
  });

  final SettingsSyncService service;
  final String? workspacePath;
  final String? workspaceIdentity;

  @override
  State<OnboardingWizardDialog> createState() => _OnboardingWizardDialogState();
}

class _OnboardingWizardDialogState extends State<OnboardingWizardDialog> {
  late final ExternalAgentImportController _controller;
  _WizardStep _step = _WizardStep.welcome;
  bool _migrationStarted = false;

  static const _categorySteps = <_WizardStep, String>{
    _WizardStep.skillsImport: 'skills',
    _WizardStep.mcpImport: 'mcpServers',
    _WizardStep.pluginsImport: 'plugins',
    _WizardStep.commandsImport: 'commands',
  };

  static const _stepLabels = <_WizardStep, (String, String)>{
    _WizardStep.session: ('会话', 'Sessions'),
    _WizardStep.skillsImport: ('Skills', 'Skills'),
    _WizardStep.mcpImport: ('MCP 服务器', 'MCP servers'),
    _WizardStep.pluginsImport: ('插件', 'Plugins'),
    _WizardStep.commandsImport: ('命令', 'Commands'),
    _WizardStep.agentsFile: ('AGENTS.md', 'AGENTS.md'),
    _WizardStep.agentSettings: ('代理设置', 'Agent settings'),
    _WizardStep.migration: ('迁移', 'Migration'),
  };

  static const _stepDescriptions = <_WizardStep, (String, String)>{
    _WizardStep.skillsImport: (
      '在最终迁移前，从外部 Agent 选择要导入的 Skills。',
      'Import selected skills from external agents before the final migration.'
    ),
    _WizardStep.mcpImport: (
      '从外部 Agent 配置中选择要合并的 MCP 服务器。',
      'Import selected MCP server definitions from external agent configs.'
    ),
    _WizardStep.pluginsImport: (
      '在最终迁移前，从外部 Agent 选择要导入的插件。',
      'Import selected plugins from external agents before the final migration.'
    ),
    _WizardStep.commandsImport: (
      '在最终迁移前，从外部 Agent 选择要导入的命令。',
      'Import selected commands from external agents before the final migration.'
    ),
    _WizardStep.agentSettings: (
      '选择要导入的各 Agent 模型供应商。',
      "Choose which agents' providers to bring in."
    ),
    _WizardStep.migration: (
      '开始迁移并等待 ZCode 完成导入。',
      'Start migration and wait while ZCode imports your selections.'
    ),
  };

  @override
  void initState() {
    super.initState();
    _controller = ExternalAgentImportController(
      service: widget.service,
      category: 'skills',
      categories: _categorySteps.values.toList(),
      workspacePath: widget.workspacePath,
      workspaceIdentity: widget.workspaceIdentity,
    );
    _controller.addListener(_changed);
    unawaited(_controller.scan());
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _next() {
    final steps = _WizardStep.values;
    final index = steps.indexOf(_step);
    if (index < steps.length - 1) {
      setState(() => _step = steps[index + 1]);
    }
  }

  void _back() {
    final steps = _WizardStep.values;
    final index = steps.indexOf(_step);
    if (index > 0) setState(() => _step = steps[index - 1]);
  }

  Future<void> _beginMigration() async {
    if (_controller.selectedCount == 0 || _migrationStarted) return;
    _migrationStarted = true;
    await _controller.importSelected();
    if (mounted) setState(() => _step = _WizardStep.finish);
  }

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Dialog(
      backgroundColor: ink.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 860, maxHeight: 640),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
              child: Row(children: [
                Expanded(
                    child: Text(
                        uiText(context, '欢迎使用 ZCode', 'Welcome to ZCode'),
                        style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w600))),
                IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    onPressed: () => Navigator.of(context).pop()),
              ])),
          if (_step.isMigration && _controller.status ==
              ExternalAgentImportStatus.importing)
            Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
                child: Text(
                    uiText(context, '正在准备迁移计划...',
                        'Preparing migration plan...'),
                    style: TextStyle(fontSize: 13, color: ink.subtlest))),
          const Divider(height: 24),
          Expanded(
              child: _step.isWelcome
                  ? _welcome(context, ink)
                  : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(
                          width: 180,
                          child: ListView(padding: const EdgeInsets.all(12), children: [
                            Text(uiText(context, '迁移向导', 'Migration guide'),
                                style: TextStyle(
                                    fontSize: 12, color: ink.subtlest)),
                            const SizedBox(height: 8),
                            for (final entry in _stepLabels.entries)
                              _stepNavRow(context, ink, entry.key, entry.value),
                          ])),
                      VerticalDivider(width: 1, color: ink.border),
                      Expanded(
                          child: SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: _stepBody(context, ink))),
                    ])),
          _footer(context, ink),
        ]),
      ),
    );
  }

  Widget _stepNavRow(
      BuildContext context, InkTokens ink, _WizardStep step, (String, String) label) {
    final active = _step == step;
    return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: active ? ink.text : ink.border)),
          const SizedBox(width: 8),
          Text(uiText(context, label.$1, label.$2),
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                  color: active ? ink.text : ink.subtlest)),
        ]));
  }

  Widget _welcome(BuildContext context, InkTokens ink) => Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(uiText(context, '首次启动设置', 'First run setup'),
            style: TextStyle(fontSize: 12, color: ink.subtlest)),
        const SizedBox(height: 8),
        Text(uiText(context, '欢迎使用 ZCode', 'Welcome to ZCode'),
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Text(
            uiText(context, '选择如何开始第一次会话。',
                'Choose how to start your first session.'),
            style: TextStyle(fontSize: 14, color: ink.subtlest)),
        const SizedBox(height: 24),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(uiText(context, '开始使用 ZCode', 'Start ZCode'))),
        const SizedBox(height: 12),
        OutlinedButton(
            onPressed: () => setState(() => _step = _WizardStep.session),
            child: Text(uiText(context, '数据迁移向导', 'Migration Guide'))),
        const SizedBox(height: 16),
        Text(
            uiText(
                context,
                '可立即导入旧工具设置，或先跳过，稍后在设置中继续迁移。',
                'Import existing tool settings now, or skip and continue later from Settings.'),
            style: TextStyle(fontSize: 12, color: ink.subtlest)),
      ]));

  Widget _stepBody(BuildContext context, InkTokens ink) {
    final description = _stepDescriptions[_step];
    final body = switch (_step) {
      _WizardStep.session => _gated(
          context,
          ink,
          uiText(
              context,
              '会话迁移需要扫描本地桌面历史，远控会话下不可用。可先跳过，稍后在桌面端继续迁移。',
              'Session migration scans local desktop history and is unavailable over remote control. Skip and resume on the desktop.'),
        ),
      _WizardStep.agentsFile => _gated(
          context,
          ink,
          uiText(
              context,
              'AGENTS.md 迁移需要读取桌面端 ~/.claude/CLAUDE.md，远控会话下不可用。',
              'AGENTS.md migration reads ~/.claude/CLAUDE.md on the desktop and is unavailable over remote control.'),
        ),
      _WizardStep.agentSettings => _gated(
          context,
          ink,
          uiText(context, '暂无可导入项。可重新扫描，或直接继续。',
              'Nothing to import right now. Scan again or continue without migration.'),
        ),
      _WizardStep.migration => _migrationBody(context, ink),
      _WizardStep.finish => _finishBody(context, ink),
      _ => _categoryList(context, ink),
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (description != null) ...[
        Text(uiText(context, description.$1, description.$2),
            style: TextStyle(fontSize: 13, color: ink.subtlest)),
        const SizedBox(height: 16),
      ],
      body,
    ]);
  }

  Widget _gated(BuildContext context, InkTokens ink, String text) => Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
          color: ink.surfaceFill, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: TextStyle(fontSize: 13, color: ink.subtlest)));

  Widget _categoryList(BuildContext context, InkTokens ink) {
    final category = _categorySteps[_step];
    if (category == null) return const SizedBox.shrink();
    final rows = _controller.visibleRoots
        .where((row) => row.category == category)
        .toList();
    if (_controller.status == ExternalAgentImportStatus.scanning) {
      return Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2)),
            const SizedBox(width: 10),
            Text(uiText(context, '正在检测...', 'Checking...'),
                style: TextStyle(fontSize: 13, color: ink.subtlest)),
          ]));
    }
    if (rows.isEmpty) {
      return _gated(context, ink, uiText(context, '暂无可导入项。可重新扫描，或直接继续。',
          'Nothing to import right now. Scan again or continue without migration.'));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (final row in rows)
        // Row selection toggles the row's importable resource keys, matching
        // the controller's resource-level selection model.
        Builder(builder: (context) {
          final keys = _controller.resourceKeysFor(row);
          final allSelected =
              keys.isNotEmpty && keys.every(_controller.isSelected);
          return ListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            leading: Checkbox(
                value: allSelected,
                onChanged: (_) =>
                    _controller.setResourceSelection(keys, !allSelected)),
            title: Text(row.agent.label,
                style: const TextStyle(fontSize: 14)),
            subtitle: Text(row.root.path,
                style: TextStyle(fontSize: 12, color: ink.subtlest)),
            trailing: Text(uiText(context, '${keys.length} 项', '${keys.length} items'),
                style: TextStyle(fontSize: 12, color: ink.subtlest)),
            onTap: () =>
                _controller.setResourceSelection(keys, !allSelected),
          );
        }),
      if (_controller.status == ExternalAgentImportStatus.error)
        Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text('${_controller.error}',
                style: TextStyle(fontSize: 12, color: ink.diffRemoved))),
    ]);
  }

  Widget _migrationBody(BuildContext context, InkTokens ink) {
    switch (_controller.status) {
      case ExternalAgentImportStatus.importing:
        return Row(children: [
          const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2)),
          const SizedBox(width: 10),
          Text(uiText(context, '迁移中...', 'Migrating...'),
              style: TextStyle(fontSize: 13, color: ink.subtlest)),
        ]);
      case ExternalAgentImportStatus.complete:
      case ExternalAgentImportStatus.ready:
        return Text(
            uiText(context, '已选择 ${_controller.selectedCount} 项，可开始迁移。',
                '${_controller.selectedCount} items selected. Begin migration when ready.'),
            style: TextStyle(fontSize: 13, color: ink.subtlest));
      default:
        return Text(
            uiText(context, '可随时跳过引导，稍后在设置中继续迁移。',
                'Skip anytime and resume migration from Settings later.'),
            style: TextStyle(fontSize: 13, color: ink.subtlest));
    }
  }

  Widget _finishBody(BuildContext context, InkTokens ink) {
    final result = _controller.result;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(uiText(context, '迁移完成', 'Migration complete'),
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600)),
      const SizedBox(height: 8),
      Text(uiText(context, '确认已导入的内容，然后继续。',
          'Review what was imported before you continue.'),
          style: TextStyle(fontSize: 13, color: ink.subtlest)),
      const SizedBox(height: 16),
      Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
              color: ink.surfaceFill, borderRadius: BorderRadius.circular(12)),
          child: result == null
              ? Text(uiText(context, '没有可汇总的迁移结果。', 'No migration summary.'),
                  style: TextStyle(fontSize: 13, color: ink.subtlest))
              : Text(
                  uiText(
                      context,
                      '已导入 ${result.successCount} 项，已跳过 ${result.skippedCount} 项，失败 ${result.failedCount} 项。',
                      'Imported ${result.successCount}, skipped ${result.skippedCount}, failed ${result.failedCount}.'),
                  style: const TextStyle(fontSize: 13)),
        ),
      ]);
  }

  Widget _footer(BuildContext context, InkTokens ink) {
    final selected = _controller.selectedCount;
    return Container(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: ink.border))),
        child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 8,
            children: [
              Text(
                  selected > 0
                      ? uiText(context, '已选择 $selected 项', '$selected items selected')
                      : uiText(context, '可随时跳过引导，稍后在设置中继续迁移。',
                          'Skip anytime and resume migration from Settings later.'),
                  style: TextStyle(fontSize: 12, color: ink.subtlest)),
              Wrap(spacing: 8, children: [
                if (!_step.isWelcome && !_step.isFinish)
                  OutlinedButton(
                      onPressed: _back, child: Text(uiText(context, '返回', 'Back'))),
                if (_step.isMigration)
                  FilledButton(
                      onPressed: _controller.selectedCount == 0 ||
                              _migrationStarted ||
                              _controller.status ==
                                  ExternalAgentImportStatus.importing
                          ? null
                          : () => unawaited(_beginMigration()),
                      child: Text(
                          uiText(context, '开始迁移', 'Begin migration'))),
                if (!_step.isWelcome && !_step.isFinish && !_step.isMigration)
                  FilledButton(
                      onPressed: _next, child: Text(uiText(context, '继续', 'Continue'))),
                if (_step.isFinish)
                  FilledButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(uiText(context, '继续', 'Continue'))),
              ]),
            ]));
  }
}



