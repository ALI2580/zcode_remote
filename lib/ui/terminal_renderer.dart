import 'dart:async';

import 'package:flutter/material.dart';
import 'package:xterm/xterm.dart';

import '../state/terminal_session.dart';

/// Bridges a protocol terminal controller to xterm's terminal emulator.
class TerminalOutputRenderer {
  TerminalOutputRenderer(
    this.controller, {
    Terminal? terminal,
  }) : terminal = terminal ?? Terminal(maxLines: 5000) {
    if (controller.output.isNotEmpty) {
      this.terminal.write(controller.output);
    }
    this.terminal.onOutput = (data) {
      unawaited(controller.write(data).then((_) {}, onError: (Object _) {}));
    };
    this.terminal.onResize = (cols, rows, _, __) {
      // Keep the latest viewport dimensions on the workspace-owned session so
      // a recovery or reopen creates the PTY with the same geometry.
      controller.cols = cols;
      controller.rows = rows;
      unawaited(controller
          .resize(newCols: cols, newRows: rows)
          .then((_) {}, onError: (Object _) {}));
    };
    _outputSubscription = controller.outputStream.listen(this.terminal.write);
    _resetSubscription = controller.resetStream.listen((_) {
      this.terminal.buffer.clear();
      this.terminal.buffer.setCursor(0, 0);
    });
  }

  final TerminalSessionController controller;
  final Terminal terminal;
  StreamSubscription<String>? _outputSubscription;
  StreamSubscription<void>? _resetSubscription;

  void dispose() {
    unawaited(_outputSubscription?.cancel());
    unawaited(_resetSubscription?.cancel());
    terminal.onOutput = null;
    terminal.onResize = null;
  }
}

const _terminalFontFallback = [
  'SFMono-Regular',
  'SF Mono',
  'Menlo',
  'Monaco',
  'Consolas',
  'Cascadia Mono',
  'JetBrains Mono',
  'MesloLGS NF',
  'Hack Nerd Font',
  'monospace',
];

TerminalStyle terminalStyleFor({String? fontFamily, double? fontSize}) =>
    TerminalStyle(
      fontFamily: fontFamily ?? 'monospace',
      fontFamilyFallback: _terminalFontFallback,
      fontSize: fontSize ?? 13,
      height: 1.2,
    );

Color? _cssColor(Object? value) {
  if (value is int) return Color(value);
  if (value is! String) return null;
  final raw = value.trim().toLowerCase();
  if (raw.startsWith('#')) {
    final hex = raw.substring(1);
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return null;
    return switch (hex.length) {
      6 => Color(0xFF000000 | parsed),
      8 => Color(
          ((parsed & 0xFF) << 24) | ((parsed & 0xFFFFFF00) >> 8),
        ),
      _ => null,
    };
  }
  final rgba = RegExp(r'^rgba?\(([^)]+)\)$').firstMatch(raw);
  if (rgba == null) return null;
  final channels = rgba
      .group(1)!
      .split(',')
      .map((part) => double.tryParse(part.trim()))
      .toList();
  if (channels.length < 3 ||
      channels.take(3).any((channel) => channel == null)) {
    return null;
  }
  final alpha = (channels.length > 3 ? channels[3] ?? 1 : 1).clamp(0.0, 1.0);
  return Color.fromARGB(
    (alpha * 255).round(),
    (channels[0]!.round()).clamp(0, 255),
    (channels[1]!.round()).clamp(0, 255),
    (channels[2]!.round()).clamp(0, 255),
  );
}

/// Mirrors the official terminal CSS palette and xterm profile overrides.
TerminalTheme terminalThemeFor(
  Brightness brightness,
  Map<String, dynamic>? profileTheme,
) {
  final dark = brightness == Brightness.dark;
  var cursor = dark ? const Color(0xFFF8F8F8) : const Color(0xFF0D0D0D);
  var selection = dark ? const Color(0x474099FF) : const Color(0x380B7FFF);
  var black = dark ? const Color(0xFF363636) : const Color(0xFF5C5C5C);
  var red = dark ? const Color(0xFFFF5C5C) : const Color(0xFFE03131);
  var green = dark ? const Color(0xFF46BF72) : const Color(0xFF1E8A3E);
  var yellow = dark ? const Color(0xFFFF8A30) : const Color(0xFFE07B00);
  var blue = dark ? const Color(0xFF4099FF) : const Color(0xFF0B7FFF);
  var magenta = dark ? const Color(0xFF7B5CE5) : const Color(0xFF9E77ED);
  var cyan = dark ? const Color(0xFF42C8C8) : const Color(0xFF0AA7A7);
  var white = const Color(0xFFADADAD);
  var brightBlack = dark ? const Color(0xFF747474) : const Color(0xFF888888);
  var brightRed = dark ? const Color(0xFFFF9999) : const Color(0xFFE03131);
  var brightGreen = dark ? const Color(0xFF87D9A4) : const Color(0xFF1E8A3E);
  var brightYellow = dark ? const Color(0xFFFFB26B) : const Color(0xFFE07B00);
  var brightBlue = dark ? const Color(0xFF80BEFF) : const Color(0xFF0066DD);
  var brightMagenta = dark ? const Color(0xFFA888F2) : const Color(0xFF9E77ED);
  var brightCyan = dark ? const Color(0xFF8EE5E5) : const Color(0xFF0AA7A7);
  var brightWhite = dark ? const Color(0xFFF8F8F8) : const Color(0xFF0D0D0D);

  Color? override(String key) => _cssColor(profileTheme?[key]);
  selection = override('selectionBackground') ?? selection;
  black = override('black') ?? black;
  red = override('red') ?? red;
  green = override('green') ?? green;
  yellow = override('yellow') ?? yellow;
  blue = override('blue') ?? blue;
  magenta = override('magenta') ?? magenta;
  cyan = override('cyan') ?? cyan;
  white = override('white') ?? white;
  brightBlack = override('brightBlack') ?? brightBlack;
  brightRed = override('brightRed') ?? brightRed;
  brightGreen = override('brightGreen') ?? brightGreen;
  brightYellow = override('brightYellow') ?? brightYellow;
  brightBlue = override('brightBlue') ?? brightBlue;
  brightMagenta = override('brightMagenta') ?? brightMagenta;
  brightCyan = override('brightCyan') ?? brightCyan;
  brightWhite = override('brightWhite') ?? brightWhite;

  return TerminalTheme(
    cursor: cursor,
    selection: selection,
    foreground: dark ? const Color(0xFFDEDEDE) : const Color(0xFF3A3A3A),
    background: dark ? const Color(0xFF161616) : const Color(0xFFF8F8F8),
    black: black,
    red: red,
    green: green,
    yellow: yellow,
    blue: blue,
    magenta: magenta,
    cyan: cyan,
    white: white,
    brightBlack: brightBlack,
    brightRed: brightRed,
    brightGreen: brightGreen,
    brightYellow: brightYellow,
    brightBlue: brightBlue,
    brightMagenta: brightMagenta,
    brightCyan: brightCyan,
    brightWhite: brightWhite,
    searchHitBackground:
        dark ? const Color(0xFF542500) : const Color(0xFFFFF4EB),
    searchHitBackgroundCurrent:
        dark ? const Color(0xFFFF8A30) : const Color(0xFFFFB26B),
    searchHitForeground:
        dark ? const Color(0xFF161616) : const Color(0xFF0D0D0D),
  );
}
