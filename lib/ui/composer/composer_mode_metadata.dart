import 'package:flutter/material.dart';

import '../../protocol/conversation.dart';
import '../../state/client_preferences.dart';

/// The official toolbar uses one icon mapping for both the trigger and rows.
String modeIconForValue(String? value) => switch (value) {
      'bypassPermissions' ||
      'fullAccess' ||
      'full-access' ||
      'agent-full-access' ||
      'yolo' =>
        'shield-alert',
      'default' || 'build' => 'hand',
      'plan' => 'notepad-text',
      'auto' ||
      'acceptEdits' ||
      'agent' ||
      'autoEdit' ||
      'dontAsk' ||
      'edit' =>
        'shield-check',
      _ => 'hand',
    };

String _modeFamily(String? provider) {
  final value = provider?.toLowerCase() ?? '';
  if (value.contains('claude')) return 'claude';
  if (value.contains('codex')) return 'codex';
  if (value.contains('gemini')) return 'gemini';
  if (value.contains('opencode')) return 'opencode';
  if (value.contains('glm') ||
      value.contains('zai') ||
      value.contains('bigmodel')) {
    return 'glm';
  }
  return '';
}

/// Resolves the Agent family from the set of mode values the remote agent
/// actually exposes (the `mode` select's options). Official `FYe`/`IYe` are
/// keyed by agent family, and the agent — not the model provider id — decides
/// which mode vocabulary exists. A set contained in exactly one family
/// dictionary identifies that family; ambiguous or unknown sets return null so
/// the server labels stay untouched.
String? familyForModeValues(Iterable<String> values) {
  final set = values.toSet();
  if (set.isEmpty) return null;
  final hits = _knownModes.entries
      .where((entry) => entry.value.containsAll(set))
      .map((entry) => entry.key)
      .toList();
  return hits.length == 1 ? hits.single : null;
}

const _knownModes = <String, Set<String>>{
  'claude': {
    'auto',
    'default',
    'acceptEdits',
    'plan',
    'dontAsk',
    'bypassPermissions'
  },
  'codex': {
    'read-only',
    'auto',
    'agent',
    'fullAccess',
    'full-access',
    'agent-full-access'
  },
  'gemini': {'default', 'autoEdit', 'yolo', 'plan'},
  'opencode': {'build', 'plan'},
  'glm': {'default', 'build', 'edit', 'plan', 'yolo'},
};

class _ModeCopy {
  const _ModeCopy(this.zh, this.en, this.descriptionZh, this.descriptionEn);

  final String zh;
  final String en;
  final String descriptionZh;
  final String descriptionEn;
}

// Values extracted from build/visual-audit/ui-global-20260912/
// u09-official-mode-translations.txt; keep family-specific wording intact.
const _modeCopies = <String, Map<String, _ModeCopy>>{
  'claude': {
    'auto': _ModeCopy(
        '自动模式', 'Auto', '自动选择权限模式。', 'Choose permissions automatically.'),
    'default': _ModeCopy('默认模式', 'Default', '编辑和高风险操作前询问。',
        'Ask before edits and risky actions.'),
    'acceptEdits': _ModeCopy('自动接受编辑', 'Accept edits', '自动接受文件编辑。',
        'Accept file edits automatically.'),
    'plan': _ModeCopy(
        '计划模式', 'Plan', '先计划，确认后执行。', 'Plan first, edit after approval.'),
    'dontAsk': _ModeCopy(
        '静默模式', "Don't ask", '跳过常规确认。', 'Skip routine confirmations.'),
    'bypassPermissions': _ModeCopy('跳过权限检查', 'Bypass permissions', '跳过权限检查。',
        'Run without permission checks.'),
  },
  'codex': {
    'read-only': _ModeCopy(
        '只读模式', 'Read only', '只读代码，不修改文件。', 'Read code without editing.'),
    'auto': _ModeCopy(
        '自动编辑模式', 'Auto edit', '在常规保护下编辑。', 'Edit with normal safeguards.'),
    'agent': _ModeCopy(
        'Agent 模式', 'Agent', '编辑和运行命令前保留确认。', 'Edit and run with approvals.'),
    'full-access': _ModeCopy('全权限模式', 'Full access', '无需确认地访问和执行。',
        'Full access without confirmation.'),
    'fullAccess': _ModeCopy('全权限模式', 'Full access', '无需确认地访问和执行。',
        'Full access without confirmation.'),
    'agent-full-access': _ModeCopy('全权限模式', 'Agent (full access)', '完整文件和网络访问。',
        'Full file and network access.'),
  },
  'gemini': {
    'default':
        _ModeCopy('默认模式', 'Default', '使用默认确认策略。', 'Use default confirmations.'),
    'autoEdit': _ModeCopy(
        '自动编辑模式', 'Auto edit', '自动应用编辑。', 'Apply edits automatically.'),
    'yolo':
        _ModeCopy('全自动模式', 'Yolo', '减少确认次数。', 'Run with fewer confirmations.'),
    'plan': _ModeCopy(
        '计划模式', 'Plan', '先计划，确认后执行。', 'Plan first, edit after approval.'),
  },
  'opencode': {
    'build':
        _ModeCopy('构建模式', 'Build', '实施并修改文件。', 'Implement and modify files.'),
    'plan': _ModeCopy(
        '计划模式', 'Plan', '先计划，确认后执行。', 'Plan first, edit after approval.'),
  },
  'glm': {
    'default':
        _ModeCopy('默认模式', 'Default', '使用默认确认策略。', 'Use default confirmations.'),
    'build': _ModeCopy(
        '变更前确认', 'Ask before changes', '改文件前先问我。', 'Ask before file changes.'),
    'edit': _ModeCopy(
        '自动编辑', 'Edit automatically', '自动编辑文件。', 'Edit files automatically.'),
    'plan': _ModeCopy('计划模式', 'Plan mode', '编辑前先出计划。', 'Plan before editing.'),
    'yolo': _ModeCopy(
        '完全访问', 'Full access', '减少确认次数。', 'Run with fewer confirmations.'),
  },
};

/// Candidate labels follow the confirmed family/value mapping from FYe.
/// Unknown provider metadata keeps the server label instead of inventing a
/// translation or collapsing all providers into one mode vocabulary. An
/// explicit [family] (resolved from the exposed mode set) wins over the
/// provider-name heuristic.
String modeLabel(BuildContext context, String value,
    [String? fallback, String? provider, String? family]) {
  final resolved = family ?? _modeFamily(provider);
  if (resolved.isEmpty || !_knownModes[resolved]!.contains(value)) {
    return fallback ?? value;
  }
  final copy = _modeCopies[resolved]?[value];
  return copy == null ? fallback ?? value : uiText(context, copy.zh, copy.en);
}

/// Candidate descriptions follow IYe. A missing confirmed mapping preserves
/// the remote description, which is safer than making up a provider-specific
/// explanation.
String? modeDescription(BuildContext context, ConfigOptionValue option,
    [String? provider, String? family]) {
  final resolved = family ?? _modeFamily(provider);
  if (resolved.isEmpty || !_knownModes[resolved]!.contains(option.value)) {
    return option.description;
  }
  final copy = _modeCopies[resolved]?[option.value];
  return copy == null
      ? option.description
      : uiText(context, copy.descriptionZh, copy.descriptionEn);
}
