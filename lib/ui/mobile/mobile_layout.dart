import 'package:flutter/material.dart';

/// Compact-shell decision helpers. Every input comes from real layout
/// constraints and MediaQuery (width, text scale) — never from device
/// names, `Platform.isAndroid` or orientation alone.
class MobileLayout {
  MobileLayout._();

  /// Compact candidate threshold: usable width under 600 logical px scaled
  /// by the current text scale, using the same scaling algorithm as the
  /// shell header (`WorkspaceShellLayout.build`). This is a candidate
  /// default; per-component overrides must be recorded in
  /// references/mobile/mobile-design-decisions.md with evidence.
  ///
  /// Composer keeps its own container-width breakpoints (384/576/672);
  /// window width must not replace the composer container width.
  static bool isCompact(double width, TextScaler textScaler) {
    final scale = (textScaler.scale(14) / 14).clamp(1.0, 2.0);
    return width < 600 * scale;
  }
}
