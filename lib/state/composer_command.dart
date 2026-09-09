enum ComposerCommandKind { plan, compact, goal, resumeGoal, invalid }

class ComposerCommand {
  const ComposerCommand(this.kind, this.text, this.displayText);
  final ComposerCommandKind kind;
  final String text, displayText;
}

/// Official hX: these shortcuts are local protocol actions; all other runtime
/// slash commands remain text. Context/attachments only block /plan.
ComposerCommand? parseComposerCommand(String text, {required bool hasContext}) {
  final raw = text.trim();
  final match = RegExp(r'^/([^\s]+)(?:\s+([\s\S]*))?$').firstMatch(raw);
  if (match == null) return null;
  final name = match.group(1)!.toLowerCase();
  final body = match.group(2)?.trim() ?? '';
  if (name == 'plan') {
    return ComposerCommand(
        hasContext ? ComposerCommandKind.invalid : ComposerCommandKind.plan,
        body,
        raw);
  }
  if (hasContext) return null;
  if (name == 'compact' || name == 'compress') {
    return ComposerCommand(ComposerCommandKind.compact, '', raw);
  }
  if (name != 'goal' && name != 'target') return null;
  final action = body.split(RegExp(r'\s+')).first.toLowerCase();
  if (action == 'resume') {
    return ComposerCommand(ComposerCommandKind.resumeGoal, '', raw);
  }
  if (body.isEmpty || const ['pause', 'clear', 'show'].contains(action)) {
    return ComposerCommand(ComposerCommandKind.invalid, '', raw);
  }
  final objective = action == 'replace'
      ? body
          .replaceFirst(RegExp(r'^replace\s*', caseSensitive: false), '')
          .trim()
      : body;
  return ComposerCommand(
      objective.isEmpty
          ? ComposerCommandKind.invalid
          : ComposerCommandKind.goal,
      objective,
      raw);
}
