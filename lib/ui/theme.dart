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
  static const surface = Color(0x0DFFFFFF); // 深色 surface（白5%）
  static const surfaceLight = Color(0x0A000000); // 浅色 surface（黑4%）
  static const text = Color(0xFFDEDEDE); // 深色正文
  static const textLight = Color(0xFF3A3A3A); // 浅色正文
  static const subtlest = Color(0x99D4D4D4); // 深色 foreground-subtlest（60%）
  static const subtlestLight = Color(0x99262626); // 浅色 foreground-subtlest
  static const diffAdded = Color(0xFF46BF72); // 深色 diff 增
  static const diffAddedLight = Color(0xFF1E8A3E); // 浅色 diff 增
  static const diffRemoved = Color(0xFFFF5C5C); // 深色 diff 删
  static const diffRemovedLight = Color(0xFFE03131); // 浅色 diff 删
  static const reasoning = Color(0xFFA78BFA); // 思考块紫
  static const warning = Color(0xFFF59E0B); // 警示琥珀
  static const running = Color(0xFF38BDF8); // 运行中天蓝
  static const fullAccess = Color(0xFFFF8A30); // 深色 Full Access 橙
  static const fullAccessLight = Color(0xFFE07B00); // 浅色 Full Access 橙

  static InkTokens of(ColorScheme scheme) =>
      scheme.brightness == Brightness.dark ? const DarkInk() : const LightInk();
}

/// Theme ink tokens. [ZInk.of] picks the active one so UI code never
/// hardcodes a light/dark color.
abstract class InkTokens {
  const InkTokens();
  Color get background;
  Color get surface;

  /// The CSS translucent --color-surface fill; [surface] is the panel token.
  Color get surfaceFill;
  Color get card;
  Color get border;
  Color get borderHover => border.withValues(alpha: .15);
  Color get hover;
  Color get text;
  Color get subtlest;
  Color get diffAdded;
  Color get diffRemoved;
  Color get confirmationSurface =>
      this is DarkInk ? const Color(0x2946BF72) : const Color(0xFFEAF7EE);
  Color get confirmationText =>
      this is DarkInk ? const Color(0xFF87D9A4) : const Color(0xFF166B32);
  Color get messageSurface;
  Color get messageBorder;
  Color get warning;
  Color get usageChart;
  List<Color> get usageCharts;
}

class DarkInk extends InkTokens {
  const DarkInk();
  @override
  Color get background => ZInk.bg;
  @override
  Color get surface => ZInk.header;
  @override
  Color get surfaceFill => const Color(0x0DFFFFFF);
  @override
  Color get card => ZInk.card;
  @override
  Color get border => ZInk.border;
  @override
  Color get hover => ZInk.hover;
  @override
  Color get text => ZInk.text;
  @override
  Color get subtlest => ZInk.subtlest;
  @override
  Color get diffAdded => ZInk.diffAdded;
  @override
  Color get diffRemoved => ZInk.diffRemoved;
  @override
  Color get messageSurface => ZInk.surface; // 白5%
  @override
  Color get messageBorder => ZInk.border;
  @override
  Color get warning => ZInk.fullAccess;
  @override
  Color get usageChart => const Color(0xFF4099FF);
  @override
  List<Color> get usageCharts => const [
        Color(0xFF4099FF),
        Color(0xFF46BF72),
        Color(0xFF7B5CE5),
        Color(0xFFFF5C5C),
        Color(0xFFFF8A30),
        Color(0xFF42C8C8)
      ];
}

class LightInk extends InkTokens {
  const LightInk();
  @override
  Color get background => ZInk.bgLight;
  @override
  Color get surface => ZInk.headerLight;
  @override
  Color get surfaceFill => const Color(0x080D0D0D);
  @override
  Color get card => ZInk.cardLight;
  @override
  Color get border => ZInk.borderLight;
  @override
  Color get hover => ZInk.hoverLight;
  @override
  Color get text => ZInk.textLight;
  @override
  Color get subtlest => ZInk.subtlestLight;
  @override
  Color get diffAdded => ZInk.diffAddedLight;
  @override
  Color get diffRemoved => ZInk.diffRemovedLight;
  @override
  Color get messageSurface => ZInk.surfaceLight; // 黑4%
  @override
  Color get messageBorder => ZInk.borderLight;
  @override
  Color get warning => ZInk.fullAccessLight;
  @override
  Color get usageChart => const Color(0xFF0B7FFF);
  @override
  List<Color> get usageCharts => const [
        Color(0xFF0B7FFF),
        Color(0xFF1E8A3E),
        Color(0xFF9E77ED),
        Color(0xFFE03131),
        Color(0xFFE07B00),
        Color(0xFF0AA7A7)
      ];
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
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          ...const PageTransitionsTheme().builders,
          TargetPlatform.android: const PredictiveBackPageTransitionsBuilder(),
        },
      ),
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary: dark ? Colors.white : Colors.black,
        onPrimary: dark ? Colors.black : Colors.white,
        secondary: dark ? ZInk.text : ZInk.textLight,
        onSecondary: dark ? Colors.black : Colors.white,
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
      appBarTheme: AppBarTheme(
          backgroundColor: bg,
          foregroundColor: text,
          elevation: 0,
          scrolledUnderElevation: 0,
          titleTextStyle: TextStyle(
              color: text, fontSize: 15, fontWeight: FontWeight.w500)),
      dividerTheme: DividerThemeData(
          color: dark ? ZInk.border : ZInk.borderLight, thickness: 1),
      popupMenuTheme: PopupMenuThemeData(
          color: dark ? ZInk.card : ZInk.cardLight,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: dark ? ZInk.border : ZInk.borderLight))),
      dialogTheme: DialogThemeData(
          backgroundColor: dark ? ZInk.card : ZInk.cardLight,
          surfaceTintColor: Colors.transparent,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
    );
  }
}
