import 'package:flutter/material.dart';
import '../official_icons.dart';
import '../theme.dart';

/// Icon button for the compact shell with an explicit touch target of at
/// least 48 logical px (Android accessibility guidance), while the glyph
/// keeps the official visual size. The hit box is a real, non-overlapping
/// box — not a transparent overlay grown over neighbours.
class MobileIconButton extends StatelessWidget {
  const MobileIconButton(
      {super.key,
      required this.icon,
      required this.label,
      required this.onPressed,
      this.selected = false,
      this.visualSize = 18,
      this.hitExtent = 48});
  final String icon;
  final String label;
  final VoidCallback? onPressed;
  final bool selected;

  /// Visual glyph size; kept in the 16–20 range of the desktop shell.
  final double visualSize;

  /// Edge length of the tappable area in logical pixels.
  final double hitExtent;
  @override
  Widget build(BuildContext context) {
    final ink = ZInk.of(Theme.of(context).colorScheme);
    return Tooltip(
        message: label,
        child: SizedBox(
            width: hitExtent,
            height: hitExtent,
            child: IconButton(
                tooltip: label,
                onPressed: onPressed,
                padding: EdgeInsets.zero,
                constraints: BoxConstraints(
                    minWidth: hitExtent, minHeight: hitExtent),
                style: IconButton.styleFrom(
                    backgroundColor: selected ? ink.hover : null,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                icon: LucideIcon(icon,
                    size: visualSize,
                    color:
                        onPressed == null ? ink.subtlest : ink.text))));
  }
}
