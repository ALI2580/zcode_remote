import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme.dart';

/// Measure the actual menu before placing it above the trigger. On a short
/// viewport it flips below, then scrolls within the available safe area.
Future<T?> showComposerPopover<T>(BuildContext context,
    {required Widget child,
    double width = 256,
    double maxHeight = 288,
    double gap = 4}) {
  final overlay =
      Navigator.of(context).overlay!.context.findRenderObject()! as RenderBox;
  final navigatorContext = Navigator.of(context).context;
  final box = context.findRenderObject()! as RenderBox;
  final anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  return showGeneralDialog<T>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: true,
      barrierColor: Colors.transparent,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      transitionDuration: const Duration(milliseconds: 100),
      pageBuilder: (routeContext, animation, secondary) =>
          Builder(builder: (popupContext) {
            // Subscribe inside the route: colors, safe area and anchor may change
            // while this popup remains open (system theme, IME, rotation).
            final routeTheme = Theme.of(popupContext);
            final routeMedia = MediaQuery.of(popupContext);
            final theme = context.mounted ? Theme.of(context) : routeTheme;
            final media = context.mounted ? MediaQuery.of(context) : routeMedia;
            final ink = ZInk.of(theme.colorScheme);
            final currentAnchor = box.attached && box.hasSize
                ? box.localToGlobal(Offset.zero, ancestor: overlay) & box.size
                : anchor;
            final content = CustomSingleChildLayout(
                delegate: _PopoverPosition(
                    anchor: currentAnchor,
                    padding: EdgeInsets.fromLTRB(
                        math.max(media.padding.left, routeMedia.padding.left),
                        math.max(media.padding.top, routeMedia.padding.top),
                        math.max(media.padding.right, routeMedia.padding.right),
                        math.max(
                            media.padding.bottom, routeMedia.padding.bottom)),
                    // Scaffold consumes the IME inset for its own children; the
                    // overlay still needs the full route inset for placement.
                    keyboard: math.max(
                        media.viewInsets.bottom, routeMedia.viewInsets.bottom),
                    width: width,
                    maxHeight: maxHeight,
                    gap: gap),
                child: Material(
                    key: const ValueKey('composer-popover'),
                    color: ink.card,
                    elevation: 4,
                    clipBehavior: Clip.antiAlias,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: ink.border)),
                    child: SingleChildScrollView(child: child)));
            return context.mounted && navigatorContext.mounted
                ? InheritedTheme.capture(from: context, to: navigatorContext)
                    .wrap(content)
                : content;
          }),
      transitionBuilder: (context, animation, secondary, child) =>
          FadeTransition(opacity: animation, child: child));
}

class _PopoverPosition extends SingleChildLayoutDelegate {
  const _PopoverPosition(
      {required this.anchor,
      required this.padding,
      required this.keyboard,
      required this.width,
      required this.maxHeight,
      required this.gap});
  final Rect anchor;
  final EdgeInsets padding;
  final double keyboard, width, maxHeight, gap;
  Rect _safe(Size size) => Rect.fromLTRB(
      padding.left + 8,
      padding.top + 8,
      size.width - padding.right - 8,
      math.max(padding.top + 8,
          size.height - math.max(padding.bottom, keyboard) - 8));

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final safe = _safe(constraints.biggest);
    final height = math
        .max(anchor.top - safe.top - gap, safe.bottom - anchor.bottom - gap)
        .clamp(0.0, safe.height);
    final fittedWidth = math.min(width, safe.width);
    return BoxConstraints(
        minWidth: fittedWidth,
        maxWidth: fittedWidth,
        maxHeight: math.min(maxHeight, height));
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final safe = _safe(size);
    final above = anchor.top - gap - childSize.height;
    final top = above >= safe.top ? above : anchor.bottom + gap;
    return Offset(anchor.left.clamp(safe.left, safe.right - childSize.width),
        top.clamp(safe.top, safe.bottom - childSize.height));
  }

  @override
  bool shouldRelayout(_PopoverPosition old) => true;
}
