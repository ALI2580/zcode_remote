import 'dart:async';

import 'package:flutter/material.dart';

import '../../state/client_preferences.dart';
import '../../state/remote_settings.dart';
import '../theme.dart';

/// Shared display components for the settings center sections (S1). These
/// were private helpers inside `settings_center_page.dart`; they are the
/// official vQt general-page row language: bordered cards whose rows carry a
/// title + description on the left and the control on the right.
///
/// Remote mutations stay owned by [RemoteSettingsController] — these helpers
/// never buffer state, so a failed `setting.update` keeps the previous
/// stored value visible and offers the official retry row.

Widget settingsCard(InkTokens ink, List<Widget> rows) => Container(
    decoration: BoxDecoration(
        color: ink.card,
        border: Border.all(color: ink.border),
        borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      for (final (index, row) in rows.indexed) ...[
        if (index > 0) const Divider(height: 1),
        row,
      ]
    ]));

Widget settingsRow(
        InkTokens ink, String title, String? description, Widget control) =>
    Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: LayoutBuilder(builder: (context, constraints) {
          final label =
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title),
            if (description != null) ...[
              const SizedBox(height: 4),
              Text(description,
                  style: TextStyle(fontSize: 12.5, color: ink.subtlest)),
            ],
          ]);
          if (constraints.maxWidth < 420) {
            return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  label,
                  const SizedBox(height: 8),
                  control,
                ]);
          }
          return Row(children: [
            Expanded(child: label),
            const SizedBox(width: 12),
            control,
          ]);
        }));

Widget remoteSpinner() => const SizedBox(
    width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2));

/// Keep the compact switch paint while retaining a 48px hit area.
Widget settingsSwitch({
  Key? key,
  required bool value,
  required ValueChanged<bool>? onChanged,
}) =>
    SizedBox(
        width: 48,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onTap: onChanged == null ? null : () => onChanged(!value),
              ),
            ),
            Transform.scale(
              scale: .62,
              child: Switch(
                key: key,
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
          ],
        ));

Widget remoteToggle(
    BuildContext context,
    InkTokens ink,
    RemoteSettingsController controller,
    String key,
    String title,
    bool? value,
    {bool? officialDefault,
    String? description}) {
  final saving = controller.isSaving(key);
  final failed = controller.saveError(key) != null;
  Widget trailing;
  if (value == null && officialDefault == null) {
    trailing = Text('--', style: TextStyle(color: ink.subtlest));
  } else if (saving) {
    trailing = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2));
  } else {
    // A missing key falls back to the official component default
    // (`?? true` / `?? false` in the bundle); toggling it stores the
    // explicit value.
    trailing = settingsSwitch(
        key: ValueKey('remote-toggle-$key'),
        value: value ?? officialDefault!,
        onChanged: controller.remoteOperationsAvailable
            ? (next) => unawaited(controller.update(key, next))
            : null);
  }
  return Column(children: [
    settingsRow(ink, title, description, trailing),
    saveFailedColumn(
        context,
        failed,
        saving,
        controller.remoteOperationsAvailable
            ? () => unawaited(controller.updatePatch(
                (controller.lastAttempt(key) ?? const {})
                    as Map<String, Object?>))
            : null),
  ]);
}

/// Toggle variant for multi-key official patches (e.g. the indexing
/// switch also stamps its user-configured flag in the same call).
Widget remoteTogglePatch(
    BuildContext context,
    InkTokens ink,
    RemoteSettingsController controller,
    Map<String, Object?> patch,
    String patchKey,
    String title,
    bool? value,
    {String? description}) {
  final saving = controller.isSaving(patchKey);
  final failed = controller.saveError(patchKey) != null;
  Widget trailing;
  if (value == null) {
    trailing = Text('--', style: TextStyle(color: ink.subtlest));
  } else if (saving) {
    trailing = const SizedBox(
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2));
  } else {
    trailing = settingsSwitch(
        key: ValueKey('remote-toggle-$patchKey'),
        value: value,
        onChanged: controller.remoteOperationsAvailable
            ? (_) => unawaited(controller.updatePatch(patch))
            : null);
  }
  return Column(children: [
    settingsRow(ink, title, description, trailing),
    saveFailedColumn(
        context,
        failed,
        saving,
        controller.remoteOperationsAvailable
            ? () => unawaited(controller.updatePatch(
                (controller.lastAttempt(patchKey) ?? const {})
                    as Map<String, Object?>))
            : null),
  ]);
}

Widget saveFailedColumn(
    BuildContext context, bool failed, bool saving, VoidCallback? onRetry) {
  if (!failed) return const SizedBox.shrink();
  return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(children: [
        Text(
            uiText(context, '保存失败，已保留原设置。',
                'Save failed. The previous value is kept.'),
            style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(width: 12),
        OutlinedButton(
            onPressed: saving ? null : onRetry,
            child: Text(uiText(context, '重试', 'Retry'))),
      ]));
}

/// Remote text setting with the official save semantics: a pending user
/// edit is never overwritten by a background refresh, a successful save
/// shows the stored trimmed value, and a failed save keeps the user text
/// for retry.
class RemoteTextSetting extends StatefulWidget {
  const RemoteTextSetting({
    super.key,
    required this.controller,
    required this.settingKey,
    required this.title,
    this.description,
    this.placeholder,
    this.monospace = false,
  });

  final RemoteSettingsController controller;
  final String settingKey;
  final String title;
  final String? description;
  final String? placeholder;
  final bool monospace;

  @override
  State<RemoteTextSetting> createState() => _RemoteTextSettingState();
}

class _RemoteTextSettingState extends State<RemoteTextSetting> {
  final TextEditingController _text = TextEditingController();
  String? _lastSynced;

  @override
  void initState() {
    super.initState();
    _syncFromSnapshot();
    widget.controller.addListener(_onRemoteChanged);
  }

  @override
  void didUpdateWidget(covariant RemoteTextSetting oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.controller, widget.controller)) {
      oldWidget.controller.removeListener(_onRemoteChanged);
      widget.controller.addListener(_onRemoteChanged);
      _lastSynced = null;
      _syncFromSnapshot();
    }
  }

  String _snapshotText() {
    final value = widget.controller.snapshot.values[widget.settingKey];
    if (value == null) return '';
    return value is String ? value : '$value';
  }

  // A pending user edit (text differs from the last synced snapshot) is
  // never overwritten by a refresh; the official page re-syncs
  // unconditionally, but that would erase typing mid-save.
  void _syncFromSnapshot() {
    final current = _snapshotText();
    if (_lastSynced == current) return;
    final dirty = _lastSynced != null && _text.text.trim() != _lastSynced;
    _lastSynced = current;
    if (!dirty && _text.text != current) {
      _text.text = current;
    }
  }

  void _onRemoteChanged() {
    if (!mounted) return;
    setState(_syncFromSnapshot);
  }

  bool get _dirty => _text.text.trim() != _lastSynced;

  Future<void> _save() async {
    if (!_dirty) return;
    await widget.controller.update(widget.settingKey, _text.text.trim());
    // Official behavior: after a successful save the input shows the stored
    // (trimmed) value. A failed save keeps the user text for retry.
    if (!mounted) return;
    if (widget.controller.saveError(widget.settingKey) == null) {
      final stored = _snapshotText();
      _text.text = stored;
      _lastSynced = stored;
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onRemoteChanged);
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saving = widget.controller.isSaving(widget.settingKey);
    final failed = widget.controller.saveError(widget.settingKey) != null;
    final saveButton = OutlinedButton(
        onPressed:
            _dirty && !saving && widget.controller.remoteOperationsAvailable
                ? () => unawaited(_save())
                : null,
        child: Text(
            saving
                ? uiText(context, '保存中…', 'Saving…')
                : uiText(context, '保存', 'Save'),
            style: const TextStyle(fontSize: 13)));
    return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          LayoutBuilder(builder: (context, constraints) {
            final label =
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.title),
              if (widget.description != null) ...[
                const SizedBox(height: 4),
                Text(widget.description!,
                    style: TextStyle(
                        fontSize: 12.5,
                        color:
                            ZInk.of(Theme.of(context).colorScheme).subtlest)),
              ],
            ]);
            if (constraints.maxWidth < 420) {
              return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [label, const SizedBox(height: 8), saveButton]);
            }
            return Row(children: [
              Expanded(child: label),
              const SizedBox(width: 12),
              saveButton,
            ]);
          }),
          const SizedBox(height: 8),
          TextField(
              controller: _text,
              enabled: widget.controller.remoteOperationsAvailable,
              onSubmitted: (_) => widget.controller.remoteOperationsAvailable
                  ? unawaited(_save())
                  : null,
              style: widget.monospace
                  ? const TextStyle(fontFamily: 'monospace', fontSize: 13)
                  : null,
              decoration: InputDecoration(
                  isDense: true,
                  hintText: widget.placeholder,
                  border: const OutlineInputBorder())),
          saveFailedColumn(
              context,
              failed,
              saving,
              widget.controller.remoteOperationsAvailable
                  ? () => unawaited(widget.controller.update(
                      widget.settingKey,
                      (widget.controller.lastAttempt(widget.settingKey)
                              as Map<String, Object?>?)?[widget.settingKey] ??
                          _text.text.trim()))
                  : null),
        ]));
  }
}
