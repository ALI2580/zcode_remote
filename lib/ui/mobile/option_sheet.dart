import 'package:flutter/material.dart';
import '../../state/client_preferences.dart';
import '../official_icons.dart';
import '../theme.dart';
import 'touch_target.dart';

/// One selectable row of [showMobileOptionSheet].
class MobileSheetOption<T> {
  const MobileSheetOption(
      {required this.value,
      required this.label,
      this.subtitle,
      this.icon,
      this.selected = false,
      this.enabled = true,
      this.trailingIcon,
      this.sectionHeader = false});
  final T value;
  final String label;
  final String? subtitle;
  final String? icon;
  final bool selected;
  final bool enabled;

  /// Extra glyph after the label (e.g. a capability badge icon).
  final String? trailingIcon;

  /// Renders as a non-interactive group heading; [value] is still required
  /// to keep the generic row contract.
  final bool sectionHeader;
}

/// Bottom option sheet for the compact shell. Complex single-choice
/// selections (models, modes, references, settings sections, terminal
/// tabs) move here instead of anchor popovers; wide layouts keep the
/// existing anchored popovers untouched.
///
/// Presentation only: callers pass their existing controller/callbacks so
/// no second business state is created. The modal route closes on one
/// Back; dismissal produces no navigation side effects.
Future<T?> showMobileOptionSheet<T>(
    {required BuildContext context,
    required String title,
    List<MobileSheetOption<T>> options = const [],
    bool searchable = false,
    String? searchHint,
    List<MobileSheetOption<T>> Function(BuildContext context)?
        optionsBuilder}) {
  return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => MobileOptionSheet<T>(
          title: title,
          options: options,
          searchable: searchable,
          searchHint: searchHint,
          optionsBuilder: optionsBuilder));
}

class MobileOptionSheet<T> extends StatefulWidget {
  const MobileOptionSheet(
      {super.key,
      required this.title,
      this.options = const [],
      this.searchable = false,
      this.searchHint,
      this.optionsBuilder});
  final String title;
  final List<MobileSheetOption<T>> options;
  final bool searchable;
  final String? searchHint;

  /// Evaluated on every build so callers can project live controller state
  /// into rows without keeping a second business copy.
  final List<MobileSheetOption<T>> Function(BuildContext context)?
      optionsBuilder;
  @override
  State<MobileOptionSheet<T>> createState() => _MobileOptionSheetState<T>();
}

class _MobileOptionSheetState<T> extends State<MobileOptionSheet<T>> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    final query = _query.trim().toLowerCase();
    final allRows =
        widget.optionsBuilder?.call(context) ?? widget.options;
    final visible = query.isEmpty
        ? allRows
        : allRows
            .where((option) =>
                option.sectionHeader ||
                option.label.toLowerCase().contains(query) ||
                (option.subtitle ?? '').toLowerCase().contains(query))
            .toList();
    // The keyboard inset is applied once via viewInsets; SafeArea already
    // consumed the system padding (useSafeArea), so no double shrink.
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: Container(
            decoration: BoxDecoration(
                color: ink.surface,
                border: Border(top: BorderSide(color: ink.border))),
            constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.8),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Header stays visible above the keyboard: title plus a
                  // full-target close button.
                  Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 4, 0),
                      child: Row(children: [
                        Expanded(
                            child: Text(widget.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context)
                                    .textTheme
                                    .titleSmall)),
                        MobileIconButton(
                            icon: 'x',
                            label: uiText(
                                context, '关闭', 'Close'),
                            onPressed: () =>
                                Navigator.of(context).pop()),
                      ])),
                  if (widget.searchable)
                    Padding(
                        padding:
                            const EdgeInsets.fromLTRB(16, 8, 16, 0),
                        child: TextField(
                            autofocus: true,
                            onChanged: (value) =>
                                setState(() => _query = value),
                            decoration: InputDecoration(
                                isDense: true,
                                prefixIcon: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: LucideIcon('search',
                                        size: 16,
                                        color: ink.subtlest)),
                                hintText: widget.searchHint ??
                                    uiText(context, '搜索', 'Search')))),
                  Flexible(
                      child: visible.isEmpty
                          ? Padding(
                              padding: const EdgeInsets.all(24),
                              child: Text(
                                  uiText(context, '无匹配结果',
                                      'No matches'),
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodyMedium
                                      ?.copyWith(color: ink.subtlest)))
                          : ListView.builder(
                              shrinkWrap: true,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 4),
                              itemCount: visible.length,
                              itemBuilder: (context, index) =>
                                  _optionRow(context, ink, visible[index]))),
                  SafeArea(
                      top: false,
                      child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: SizedBox(
                              height: 48,
                              width: double.infinity,
                              child: TextButton(
                                  onPressed: () =>
                                      Navigator.of(context).pop(),
                                  style: TextButton.styleFrom(
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(8))),
                                  child: Text(
                                      uiText(context, '取消', 'Cancel'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelLarge))))),
                ])));
  }

  Widget _optionRow(
      BuildContext context, InkTokens ink, MobileSheetOption<T> option) {
    if (option.sectionHeader) {
      return Container(
          key: ValueKey('mobile-sheet-header-${option.label}'),
          constraints: const BoxConstraints(minHeight: 36),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          alignment: Alignment.centerLeft,
          child: Text(option.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: ink.subtlest)));
    }
    final title = Theme.of(context).textTheme.bodyMedium;
    // Screen readers announce the row as a button with its selection and
    // enabled state; InkWell alone only registers the tap action.
    return Semantics(
        button: true,
        selected: option.selected,
        enabled: option.enabled,
        child: InkWell(
            key: ValueKey('mobile-sheet-option-${option.value}'),
            onTap: option.enabled
                ? () => Navigator.of(context).pop(option.value)
                : null,
        child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(children: [
              if (option.icon != null) ...[
                LucideIcon(option.icon!,
                    size: 16,
                    color: option.enabled ? ink.text : ink.subtlest),
                const SizedBox(width: 12)
              ],
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                    Text(option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: title?.copyWith(
                            color: option.enabled
                                ? ink.text
                                : ink.subtlest)),
                    if (option.subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(option.subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(color: ink.subtlest))
                    ]
                  ])),
              if (option.trailingIcon != null &&
                  option.trailingIcon != 'check') ...[
                const SizedBox(width: 6),
                LucideIcon(option.trailingIcon!,
                    size: 14, color: ink.subtlest)
              ],
              if (option.selected) ...[
                const SizedBox(width: 8),
                LucideIcon('check', size: 16, color: ink.text),
                const SizedBox(width: 16)
              ]
            ]))));
  }
}
