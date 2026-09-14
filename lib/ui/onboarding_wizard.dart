import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../state/client_preferences.dart';
import '../state/settings_import.dart';
import 'official_icons.dart';
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
    // Official dialog shell (Bn): `max-w-4xl max-h-168 rounded-2xl p-0
    // overflow-hidden` with the built-in close button. Welcome renders the
    // two-column hero layout; wizard steps keep the nav/content/footer flow.
    return Dialog(
      backgroundColor: ink.surface,
      insetPadding:
          const EdgeInsets.symmetric(horizontal: 40, vertical: 48),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 896, maxHeight: 672),
        child: LayoutBuilder(builder: (context, constraints) {
          final width = constraints.maxWidth.isFinite
              ? math.min(constraints.maxWidth, 896.0)
              : 896.0;
          final height = constraints.maxHeight.isFinite
              ? math.min(constraints.maxHeight, 672.0)
              : 672.0;
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              width: width,
              height: height,
              child: _step.isWelcome
                  ? OnboardingWelcomePage(
                      onStart: () => Navigator.of(context).pop(),
                      onOpenMigration: () =>
                          setState(() => _step = _WizardStep.session),
                      onClose: () => Navigator.of(context).pop(),
                    )
                  : _wizardScaffold(context, ink),
            ),
          );
        }),
      ),
    );
  }

  Widget _wizardScaffold(BuildContext context, InkTokens ink) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
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
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
    ]);
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

/// Official welcome step (`L$t`): left column with the eyebrow pill, Z logo
/// badge, title, full-width actions and bottom helper; right column is the
/// hero panel (`n4` + `I$t`). The close button is the dialog shell's
/// built-in one, absolutely positioned over the panel.
class OnboardingWelcomePage extends StatelessWidget {
  const OnboardingWelcomePage({
    super.key,
    required this.onStart,
    required this.onOpenMigration,
    required this.onClose,
  });

  final VoidCallback onStart;
  final VoidCallback onOpenMigration;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final bright = Theme.of(context).brightness;
    // Light values sampled from the official zai-light scope; dark mirrors
    // the default dark scope tokens.
    final heading =
        bright == Brightness.light ? const Color(0xFF262626) : const Color(0xFFE5E5E5);
    return Stack(children: [
      Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Expanded(
            child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: ink.border),
                              color: bright == Brightness.light
                                  ? const Color(0x99F5F5F5)
                                  : const Color(0x99262626)),
                          child: Text(uiText(context, '首次启动设置', 'First run setup'),
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 20 / 14,
                                  color: ink.subtlest))),
                      const SizedBox(height: 24),
                      _zLogoBadge(),
                      const SizedBox(height: 8),
                      Text(uiText(context, '欢迎使用 ZCode', 'Welcome to ZCode'),
                          style: TextStyle(
                              fontSize: 36,
                              height: 40 / 36,
                              fontWeight: FontWeight.w700,
                              letterSpacing: -0.9,
                              color: heading)),
                      Expanded(
                          child: Center(
                              child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                            _welcomeButton(context, ink,
                                label: uiText(context, '开始使用 ZCode',
                                    'Start using ZCode'),
                                primary: true,
                                labelColor: heading,
                                onTap: onStart),
                            const SizedBox(height: 16),
                            _welcomeButton(context, ink,
                                label: uiText(
                                    context, '数据迁移向导', 'Migration Guide'),
                                primary: false,
                                labelColor: heading,
                                onTap: onOpenMigration),
                          ]))),
                      Padding(
                          padding: const EdgeInsets.only(top: 24),
                          child: Text(
                              uiText(
                                  context,
                                  '可立即导入旧工具设置，或先跳过，稍后在设置中继续迁移。',
                                  'Import existing tool settings now, or skip and continue later from Settings.'),
                              style: TextStyle(
                                  fontSize: 14,
                                  height: 24 / 14,
                                  color: ink.subtlest))),
                    ]))),
        Expanded(
            child: Padding(
                padding: const EdgeInsets.only(top: 8, right: 8, bottom: 8),
                child: _HeroPanel(brightness: bright))),
      ]),
      Positioned(top: 16, right: 16, child: _closeButton(context, ink)),
    ]);
  }

  Widget _welcomeButton(
      BuildContext context,
      InkTokens ink, {
        required String label,
        required bool primary,
        required Color labelColor,
        required VoidCallback onTap,
      }) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
        color: primary ? scheme.primary : Colors.transparent,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: primary ? BorderSide.none : BorderSide(color: ink.border)),
        child: InkWell(
            onTap: onTap,
            child: SizedBox(
                height: 40,
                child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(children: [
                      Expanded(
                          child: Text(label,
                              style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w500,
                                  color: primary
                                      ? scheme.onPrimary
                                      : labelColor))),
                      LucideIcon('arrow-right',
                          size: 16,
                          color:
                              primary ? scheme.onPrimary : labelColor),
                    ])))));
  }

  Widget _closeButton(BuildContext context, InkTokens ink) {
    final color = Theme.of(context).brightness == Brightness.light
        ? const Color(0xFF737373)
        : const Color(0xFFA3A3A3);
    return Semantics(
        button: true,
        label: uiText(context, '关闭', 'Close'),
        child: Material(
            color: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            shape: const CircleBorder(),
            child: InkWell(
                onTap: onClose,
                child: SizedBox(
                    width: 32,
                    height: 32,
                    child: Center(
                        child: LucideIcon('x', size: 20, color: color))))));
  }
}

/// 56x56 gradient Z badge from the official welcome markup:
/// `size-14 rounded-xl bg-[linear-gradient(180deg,#000000_0%,#151718_100%)]`
/// with a white 10% inner border and the official Z logo SVG (256x218).
Widget _zLogoBadge() {
  return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF000000), Color(0xFF151718)]),
          border: Border.all(color: const Color(0x1AFFFFFF)),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33000000),
                offset: Offset(0, 10),
                blurRadius: 15,
                spreadRadius: -3),
            BoxShadow(
                color: Color(0x33000000),
                offset: Offset(0, 4),
                blurRadius: 6,
                spreadRadius: -4),
          ]),
      child: const Center(
          child: SizedBox(
              width: 32,
              height: 27.25,
              child: CustomPaint(painter: _ZLogoPainter()))));
}

class _ZLogoPainter extends CustomPainter {
  const _ZLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 256, size.height / 218);
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white;
    // Official g3 logo paths (assets/official/index.js), viewBox 256x218.
    canvas.drawPath(
        Path()
          ..moveTo(134.4, 0.13)
          ..lineTo(116.48, 25.602)
          ..cubicTo(113.665, 29.57, 109.054, 32.002, 104.064, 32.002)
          ..lineTo(6.4, 32.002)
          ..lineTo(6.4, 0)
          ..close(),
        paint);
    canvas.drawPath(
        Path()
          ..moveTo(256, 0.13)
          ..lineTo(102.401, 217.732)
          ..lineTo(0, 217.732)
          ..lineTo(153.599, 0.13)
          ..close(),
        paint);
    canvas.drawPath(
        Path()
          ..moveTo(121.601, 217.732)
          ..lineTo(139.65, 192.134)
          ..cubicTo(142.465, 188.166, 147.076, 185.734, 152.067, 185.734)
          ..lineTo(249.604, 185.734)
          ..lineTo(249.604, 217.736)
          ..lineTo(121.601, 217.736)
          ..close(),
        paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Official hero panel (`n4`): base gradient, three radial "before" overlays
/// and two huge blurred glow circles composited with screen/multiply blend
/// modes. Geometry (672/576px circles at 64px blur) matches the official
/// fixed pixel values used inside the 896px dialog.
class _HeroPanel extends StatelessWidget {
  const _HeroPanel({required this.brightness});

  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final light = brightness == Brightness.light;
    return ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: CustomPaint(
            painter: _HeroPanelPainter(brightness),
            child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(uiText(context, '快速打开，专注工作。', 'Open fast, stay focused.'),
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 30,
                      height: 1.2,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.75,
                      color: light
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF8FAFC))),
              const SizedBox(height: 8),
              Text(
                  uiText(
                      context,
                      '选择一个工作区，继续上次的进度，保持界面干净清爽。',
                      'Pick a workspace to pick up where you left off, keeping the interface clean.'),
                  maxLines: 1,
                  softWrap: false,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 14,
                      height: 24 / 14,
                      color: light
                          ? const Color(0xCC334155)
                          : const Color(0xB8E2E8F0))),
            ]))));
  }
}

class _HeroPanelPainter extends CustomPainter {
  const _HeroPanelPainter(this.brightness);

  final Brightness brightness;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.clipRect(rect);
    if (brightness == Brightness.light) {
      _paintBase(canvas, rect, const [
        Color(0xFFEFF6FF),
        Color(0xFFDBEAFE),
        Color(0xFFBFDBFE),
      ], const [
        0.0,
        0.34,
        1.0
      ]);
      _paintCornerGlow(
          canvas, rect, const Offset(0.18, 0.18), 0.24, const Color(0xE6FFFFFF));
      _paintCornerGlow(
          canvas, rect, const Offset(0.82, 0.16), 0.26, const Color(0x6B7DD3FC));
      _paintCornerGlow(
          canvas, rect, const Offset(0.68, 0.80), 0.28, const Color(0x3D60A5FA));
      _paintGlowCircle(canvas, rect,
          dx: -0.12,
          dy: 0.18,
          diameter: 672,
          color: const Color(0xB3BAE6FD),
          screen: true);
      _paintGlowCircle(canvas, rect,
          dx: 1.18,
          dy: 1.14,
          diameter: 576,
          color: const Color(0xB3BFDBFE),
          screen: false);
    } else {
      _paintBase(canvas, rect, const [
        Color(0xFF060816),
        Color(0xFF0B1333),
        Color(0xFF12245A),
        Color(0xFF173474),
      ], const [
        0.0,
        0.38,
        0.72,
        1.0
      ]);
      _paintCornerGlow(
          canvas, rect, const Offset(0.16, 0.20), 0.22, const Color(0x24A5F3FC));
      _paintCornerGlow(
          canvas, rect, const Offset(0.82, 0.14), 0.24, const Color(0x2E60A5FA));
      _paintCornerGlow(
          canvas, rect, const Offset(0.68, 0.84), 0.28, const Color(0x2438BDF8));
      canvas.drawRect(
          rect,
          Paint()
            ..shader = const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x0AFFFFFF), Color(0x00FFFFFF)])
                .createShader(rect));
      _paintGlowCircle(canvas, rect,
          dx: -0.12,
          dy: 0.18,
          diameter: 672,
          color: const Color(0x3867E8F9),
          screen: true);
      _paintGlowCircle(canvas, rect,
          dx: 1.18,
          dy: 1.14,
          diameter: 576,
          color: const Color(0x2E60A5FA),
          screen: true);
    }
  }

  void _paintBase(
      Canvas canvas, Rect rect, List<Color> colors, List<double> stops) {
    canvas.drawRect(
        rect,
        Paint()
          ..shader = LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: colors,
                  stops: stops)
              .createShader(rect));
  }

  // CSS `radial-gradient(circle at X% Y%, color, transparent R%)` with the
  // default farthest-corner sizing.
  void _paintCornerGlow(
      Canvas canvas, Rect rect, Offset rel, double stop, Color color) {
    final center = Offset(rect.width * rel.dx, rect.height * rel.dy);
    var farthest = 0.0;
    for (final corner in [
      rect.topLeft,
      rect.topRight,
      rect.bottomLeft,
      rect.bottomRight
    ]) {
      farthest = math.max(farthest, (corner - center).distance);
    }
    canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
                  center: Alignment(rel.dx * 2 - 1, rel.dy * 2 - 1),
                  radius: stop * farthest / rect.shortestSide,
                  colors: [color, color.withValues(alpha: 0)])
              .createShader(rect));
  }

  // CSS glow div: absolute circle with blur-3xl and a mix-blend mode.
  void _paintGlowCircle(
      Canvas canvas,
      Rect rect, {
        required double dx,
        required double dy,
        required double diameter,
        required Color color,
        required bool screen,
      }) {
    final radius = diameter / 2;
    final cx = dx <= 0 ? rect.width * dx + radius : rect.width * dx - radius;
    final cy = dy <= 1 ? rect.height * dy + radius : rect.height * dy - radius;
    final center = Offset(cx, cy);
    final inner = math.max(0.0, (radius - 64) / radius);
    canvas.drawRect(
        rect,
        Paint()
          ..blendMode = screen ? BlendMode.screen : BlendMode.multiply
          ..shader = RadialGradient(
                  center: Alignment(
                      (center.dx / rect.width) * 2 - 1,
                      (center.dy / rect.height) * 2 - 1),
                  radius: radius / rect.shortestSide,
                  colors: [
                    color,
                    color,
                    color.withValues(alpha: 0),
                  ],
                  stops: [
                    0,
                    inner,
                    1
                  ])
              .createShader(rect));
  }

  @override
  bool shouldRepaint(covariant _HeroPanelPainter oldDelegate) =>
      oldDelegate.brightness != brightness;
}



