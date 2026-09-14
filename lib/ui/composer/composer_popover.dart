import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../theme.dart';

enum ComposerPopoverSide { vertical, right }

/// Measure the actual menu before placing it above the trigger. On a short
/// viewport it flips below, then scrolls within the available safe area.
Future<T?> showComposerPopover<T>(BuildContext context,
    {required Widget child,
    double width = 256,
    double maxHeight = 288,
    double gap = 4,
    double collisionPadding = 8,
    ComposerPopoverSide side = ComposerPopoverSide.vertical}) {
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
                    gap: gap,
                    collisionPadding: collisionPadding,
                    side: side),
                child: RepaintBoundary(
                    child: Material(
                        key: const ValueKey('composer-popover'),
                        color: ink.card,
                        elevation: 4,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: ink.border)),
                        child: SingleChildScrollView(child: child))));
            final routedContent = Shortcuts(
                shortcuts: const <ShortcutActivator, Intent>{
                  SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
                },
                child: Actions(actions: <Type, Action<Intent>>{
                  DismissIntent: CallbackAction<DismissIntent>(onInvoke: (_) {
                    Navigator.of(popupContext).pop();
                    return null;
                  }),
                }, child: content));
            return context.mounted && navigatorContext.mounted
                ? InheritedTheme.capture(from: context, to: navigatorContext)
                    .wrap(routedContent)
                : routedContent;
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
      required this.gap,
      required this.collisionPadding,
      required this.side});
  final Rect anchor;
  final EdgeInsets padding;
  final double keyboard, width, maxHeight, gap;
  final double collisionPadding;
  final ComposerPopoverSide side;
  Rect _safe(Size size) => Rect.fromLTRB(
      padding.left + collisionPadding,
      padding.top + collisionPadding,
      size.width - padding.right - collisionPadding,
      math.max(padding.top + 8,
          size.height - math.max(padding.bottom, keyboard) - collisionPadding));

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final safe = _safe(constraints.biggest);
    if (side == ComposerPopoverSide.right) {
      final fittedWidth = math.min(width, safe.width);
      return BoxConstraints(
          minWidth: fittedWidth,
          maxWidth: fittedWidth,
          maxHeight: math.min(maxHeight, safe.height));
    }
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
    if (side == ComposerPopoverSide.right) {
      final right = anchor.right + gap;
      final left = anchor.left - gap - childSize.width;
      final fitsRight = right + childSize.width <= safe.right;
      final fitsLeft = left >= safe.left;
      final horizontal = fitsRight
          ? right
          : fitsLeft
              ? left
              : right.clamp(safe.left, safe.right - childSize.width);
      final vertical = anchor.top
          .clamp(safe.top, math.max(safe.top, safe.bottom - childSize.height));
      return Offset(horizontal.toDouble(), vertical.toDouble());
    }
    final above = anchor.top - gap - childSize.height;
    final top = above >= safe.top ? above : anchor.bottom + gap;
    return Offset(anchor.left.clamp(safe.left, safe.right - childSize.width),
        top.clamp(safe.top, safe.bottom - childSize.height));
  }

  @override
  bool shouldRelayout(_PopoverPosition old) => true;
}
