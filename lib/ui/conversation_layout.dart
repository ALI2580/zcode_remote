import 'dart:math' as math;
import 'package:flutter/widgets.dart';

/// Official y5e/g5e: both the timeline and composer use this conversation
/// container width. A side pane is a separate container, not the screen width.
double conversationColumnWidth(double width) {
  if (width >= 1280) return math.min(width - 384, 1152);
  if (width >= 864) return math.min(width - 96, 896);
  return width;
}

class ConversationColumn extends StatelessWidget {
  const ConversationColumn({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
      builder: (context, constraints) => Align(
          alignment: Alignment.topCenter,
          heightFactor: 1,
          child: SizedBox(
              width: conversationColumnWidth(constraints.maxWidth),
              child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: child))));
}
