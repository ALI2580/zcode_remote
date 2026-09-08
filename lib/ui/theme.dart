import 'package:flutter/material.dart';

/// Official-web ink palette, mirrored from the desktop client's CSS
/// variables (references/official-web-ui.md 主题 CSS 变量表). All colors
/// resolve through [ZInk.of] so light/dark never invert text colors.
class ZInk {
  ZInk._();

  static const bg = Color(0xFF161616); // 深色背景
  static const bgLight = Color(0xFFF8F8F8); // 浅色背景
  static const header = Color(0xFF202020); // 深色 header/panel/sidebar
  static const headerLight = Color(0xFFFFFFFF);
  static const card = Color(0xFF2B2B2B); // 深色 card/popover/input
  static const cardLight = Color(0xFFFFFFFF);
  static const border = Color(0x1AFFFFFF); // 白10%
  static const borderLight = Color(0x1A0D0D0D); // 黑10%
  static const hover = Color(0x0DFFFFFF); // 白5%
  static const hoverLight = Color(0x0D0D0D0D); // 黑5%
  static const text = Color(0xFFDEDEDE); // 深色正文
  static const textLight = Color(0xFF3A3A3A); // 浅色正文
  static const reasoning = Color(0xFFA78BFA); // 思考块紫
  static const warning = Color(0xFFF59E0B); // 警示琥珀
  static const running = Color(0xFF38BDF8); // 运行中天蓝
  static const fullAccess = Color(0xFFE07B00); // 深色 Full Access 橙
  static const fullAccessLight = Color(0xFFFF8A30); // 浅色 Full Access 橙

  static InkTokens of(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark
          ? const DarkInk()
          : const LightInk();
}

/// Theme ink tokens. [ZInk.of] picks the active one so UI code never
/// hardcodes a light/dark color.
abstract class InkTokens {
  const InkTokens();
  Color get background;
  Color get surface;
  Color get card;
  Color get border;
  Color get hover;
  Color get text;
}

class DarkInk extends InkTokens {
  const DarkInk();
  @override
  Color get background => ZInk.bg;
  @override
  Color get surface => ZInk.header;
  @override
  Color get card => ZInk.card;
  @override
  Color get border => ZInk.border;
  @override
  Color get hover => ZInk.hover;
  @override
  Color get text => ZInk.text;
}

class LightInk extends InkTokens {
  const LightInk();
  @override
  Color get background => ZInk.bgLight;
  @override
  Color get surface => ZInk.headerLight;
  @override
  Color get card => ZInk.cardLight;
  @override
  Color get border => ZInk.borderLight;
  @override
  Color get hover => ZInk.hoverLight;
  @override
  Color get text => ZInk.textLight;
}

/// Official radius scale (references: radius 表).
/// xs=2, sm=4, md=6, lg=8, xl=12, 2xl=16.
class ZRadius {
  ZRadius._();
  static const xs = 2.0;
  static const sm = 4.0;
  static const md = 6.0;
  static const lg = 8.0;
  static const xl = 12.0;
  static const twoXl = 16.0;
}

class ZInkTheme {
  ZInkTheme._();

  static ThemeData dark() => _build(Brightness.dark, ZInk.bg, ZInk.text);
  static ThemeData light() =>
      _build(Brightness.light, ZInk.bgLight, ZInk.textLight);

  static ThemeData _build(Brightness brightness, Color bg, Color text) {
    final dark = brightness == Brightness.dark;
    return ThemeData(
      brightness: brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: dark ? ZInk.reasoning : ZInk.fullAccessLight,
        onPrimary: Colors.white,
        secondary: dark ? ZInk.running : ZInk.fullAccess,
        onSecondary: Colors.white,
        error: const Color(0xFFF87171),
        onError: Colors.white,
        surface: dark ? ZInk.header : ZInk.headerLight,
        onSurface: text,
        outline: dark ? ZInk.border : ZInk.borderLight,
        outlineVariant: dark ? ZInk.hover : ZInk.hoverLight,
      ),
      textTheme: ThemeData.light().textTheme.apply(
            bodyColor: text,
            displayColor: text,
          ),
    );
  }
}
