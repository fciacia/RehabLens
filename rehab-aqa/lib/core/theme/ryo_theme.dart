// ryo_theme.dart
// "Stealth Wealth" Luxury Design System for RYO.
// Inspired by Apple & Nike — Pitch Black base, surgical Neon Cyan accents.

import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Animation & interaction
// ---------------------------------------------------------------------------

abstract final class RyoMotion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 250);
  static const slow = Duration(milliseconds: 400);
}

// ---------------------------------------------------------------------------
// Design Tokens
// ---------------------------------------------------------------------------

abstract final class RyoColors {
  // Base surfaces
  static const black       = Color(0xFF000000); // pitch black
  static const surface     = Color(0xFF141414); // elevated surface
  static const card        = Color(0xFF1C1C1E); // card background (Apple dark)
  static const divider     = Color(0xFF2C2C2E); // subtle divider

  // Accents
  static const cyan        = Color(0xFF00FFC2); // surgical neon cyan  (primary)
  static const cyanDim     = Color(0x3300FFC2); // 20% cyan for ghosts
  static const cyanGlow    = Color(0x6600FFC2); // 40% for glows
  static const white       = Color(0xFFFFFFFF);
  static const offWhite    = Color(0xFFE8E8E8);

  // Text hierarchy
  static const textPrimary   = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFFCCCCCC); // brighter — readable on dark cards
  static const textMuted     = Color(0xFF6E6E73); // Apple system-grey (visible on #1C1C1E)

  // Status
  static const success = Color(0xFF00FFC2);
  static const warning = Color(0xFFFFB300);
  static const critical= Color(0xFFFF1744);

  // Glass
  static const glassWhite = Color(0x1AFFFFFF); // 10% white for frosted glass
  static const glassBorder = Color(0x33FFFFFF); // 20% white border
}

abstract final class RyoTypography {
  // Use SF Pro on Apple, fall back to Inter → system sans-serif
  static const _fontFamily = 'SF Pro Display';
  static const _fontFallback = ['Inter', 'Helvetica Neue', 'sans-serif'];

  static const brandmark = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    fontSize: 10,
    fontWeight: FontWeight.w300,
    color: RyoColors.textMuted,
    letterSpacing: 4.0,
  );

  static const display = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    fontSize: 36,
    fontWeight: FontWeight.w700,
    color: RyoColors.textPrimary,
    letterSpacing: 2.0,
  );

  static const headline = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    color: RyoColors.textPrimary,
    letterSpacing: 2.0,
  );

  /// Screen titles and card titles — readable for elderly users.
  static const title = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    fontSize: 16,
    fontWeight: FontWeight.w600,
    color: RyoColors.textPrimary,
    letterSpacing: 1.5,
  );

  /// Body text — slightly larger for readability (elderly-friendly).
  static const body = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    fontSize: 15,
    fontWeight: FontWeight.w400,
    color: RyoColors.textSecondary,
    letterSpacing: 0.3,
  );

  /// Labels and captions — minimum 12px for legibility.
  static const dataLabel = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    fontSize: 12,
    fontWeight: FontWeight.w500,
    color: RyoColors.textMuted,
    letterSpacing: 1.2,
  );

  static const hudValue = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: RyoColors.cyan,
    letterSpacing: 1.0,
  );

  /// Small labels (nav, badges) — at least 10px for elderly.
  static const micro = TextStyle(
    fontFamily: _fontFamily,
    fontFamilyFallback: _fontFallback,
    fontSize: 10,
    fontWeight: FontWeight.w400,
    color: RyoColors.textMuted,
    letterSpacing: 1.5,
  );
}

// ---------------------------------------------------------------------------
// Shared Decorations
// ---------------------------------------------------------------------------

abstract final class RyoDecorations {
  /// Frosted glass box — BackdropFilter companion container.
  static BoxDecoration glass({
    double borderRadius = 20,
    Color? border,
  }) =>
      BoxDecoration(
        color: RyoColors.glassWhite,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: border ?? RyoColors.glassBorder,
          width: 0.5,
        ),
      );

  /// Card with subtle border on deep charcoal.
  static BoxDecoration card({double borderRadius = 16}) => BoxDecoration(
        color: RyoColors.card,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: RyoColors.divider, width: 0.5),
      );

  /// Neon cyan glow shadow.
  static List<BoxShadow> cyanGlow({double blurRadius = 20, double spread = 0}) =>
      [
        BoxShadow(
          color: RyoColors.cyanGlow,
          blurRadius: blurRadius,
          spreadRadius: spread,
        ),
      ];
}

// ---------------------------------------------------------------------------
// ThemeData
// ---------------------------------------------------------------------------

ThemeData buildRyoTheme({bool highContrast = false}) {
  final borderWidth = highContrast ? 1.0 : 0.5;
  final dividerColor = highContrast ? RyoColors.textMuted : RyoColors.divider;
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: RyoColors.black,
    colorScheme: const ColorScheme.dark(
      surface: RyoColors.surface,
      primary: RyoColors.cyan,
      secondary: RyoColors.cyanDim,
      error: RyoColors.critical,
      onPrimary: RyoColors.black,
      onSurface: RyoColors.textPrimary,
    ),
    textTheme: const TextTheme(
      displayLarge: RyoTypography.display,
      titleLarge: RyoTypography.headline,
      titleMedium: RyoTypography.title,
      bodyMedium: RyoTypography.body,
      labelSmall: RyoTypography.dataLabel,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: RyoColors.black,
      foregroundColor: RyoColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: RyoTypography.title,
    ),
    cardTheme: CardThemeData(
      color: RyoColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: dividerColor, width: borderWidth),
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    dividerTheme: DividerThemeData(
      color: dividerColor,
      thickness: borderWidth,
      space: 0,
    ),
    navigationBarTheme: const NavigationBarThemeData(
      backgroundColor: Colors.transparent,
      indicatorColor: RyoColors.cyanDim,
      elevation: 0,
      labelTextStyle: WidgetStatePropertyAll(RyoTypography.micro),
    ),
    navigationRailTheme: const NavigationRailThemeData(
      backgroundColor: RyoColors.surface,
      indicatorColor: RyoColors.cyanDim,
      labelType: NavigationRailLabelType.none,
      elevation: 0,
    ),
    // Accessibility: minimum 48dp tap targets
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size(48, 48)),
        padding: WidgetStateProperty.all(const EdgeInsets.all(12)),
      ),
    ),
    // Splash/ripple use primary cyan for consistency
    splashFactory: highContrast ? null : InkRipple.splashFactory,
    highlightColor: RyoColors.cyan.withValues(alpha: 0.08),
    splashColor: RyoColors.cyan.withValues(alpha: 0.12),
  );
}

// ---------------------------------------------------------------------------
// Elderly / Senior Friendly Theme — White background, large text, teal accent
// ---------------------------------------------------------------------------

/// Semantic color tokens for the elderly (light) theme.
/// Named after function, not appearance, so code stays readable.
abstract final class RyoElderlyColors {
  static const background    = Color(0xFFF7F7F7);
  static const surface       = Color(0xFFFFFFFF);
  static const card          = Color(0xFFFFFFFF);
  static const divider       = Color(0xFFDEDEDE);

  // Teal accent — high contrast on white (WCAG AA ≥ 4.5:1)
  static const accent        = Color(0xFF007A90);
  static const accentDim     = Color(0x1C007A90);
  static const accentGlow    = Color(0x40007A90);

  static const textPrimary   = Color(0xFF111111);
  static const textSecondary = Color(0xFF444444);
  static const textMuted     = Color(0xFF888888);

  static const warning       = Color(0xFFAA5500);
  static const critical      = Color(0xFFBB0022);
}

ThemeData buildElderlyTheme() {
  const accent = RyoElderlyColors.accent;
  const bg     = RyoElderlyColors.background;
  const card   = RyoElderlyColors.card;
  const div    = RyoElderlyColors.divider;
  const onBg   = RyoElderlyColors.textPrimary;

  const bodyStyle = TextStyle(
    fontFamily: 'SF Pro Display',
    fontFamilyFallback: ['Inter', 'Helvetica Neue', 'sans-serif'],
    fontSize: 17,
    fontWeight: FontWeight.w400,
    color: RyoElderlyColors.textSecondary,
    letterSpacing: 0.2,
  );
  const titleStyle = TextStyle(
    fontFamily: 'SF Pro Display',
    fontFamilyFallback: ['Inter', 'Helvetica Neue', 'sans-serif'],
    fontSize: 18,
    fontWeight: FontWeight.w600,
    color: RyoElderlyColors.textPrimary,
    letterSpacing: 0.5,
  );
  const headlineStyle = TextStyle(
    fontFamily: 'SF Pro Display',
    fontFamilyFallback: ['Inter', 'Helvetica Neue', 'sans-serif'],
    fontSize: 22,
    fontWeight: FontWeight.w700,
    color: RyoElderlyColors.textPrimary,
    letterSpacing: 0.5,
  );
  const labelStyle = TextStyle(
    fontFamily: 'SF Pro Display',
    fontFamilyFallback: ['Inter', 'Helvetica Neue', 'sans-serif'],
    fontSize: 13,
    fontWeight: FontWeight.w600,
    color: RyoElderlyColors.textMuted,
    letterSpacing: 1.0,
  );
  const microStyle = TextStyle(
    fontFamily: 'SF Pro Display',
    fontFamilyFallback: ['Inter', 'Helvetica Neue', 'sans-serif'],
    fontSize: 12,
    fontWeight: FontWeight.w400,
    color: RyoElderlyColors.textMuted,
    letterSpacing: 1.0,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    scaffoldBackgroundColor: bg,
    colorScheme: const ColorScheme.light(
      surface: card,
      primary: accent,
      secondary: RyoElderlyColors.accentDim,
      error: RyoElderlyColors.critical,
      onPrimary: Colors.white,
      onSurface: onBg,
    ),
    textTheme: TextTheme(
      displayLarge: headlineStyle.copyWith(fontSize: 36),
      titleLarge: headlineStyle,
      titleMedium: titleStyle,
      bodyMedium: bodyStyle,
      labelSmall: labelStyle,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: card,
      foregroundColor: onBg,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      shadowColor: div,
      centerTitle: false,
      titleTextStyle: titleStyle,
    ),
    cardTheme: CardThemeData(
      color: card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        side: const BorderSide(color: div, width: 1),
        borderRadius: BorderRadius.circular(16),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: div,
      thickness: 1,
      space: 0,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      indicatorColor: accent.withValues(alpha: 0.15),
      elevation: 0,
      labelTextStyle: const WidgetStatePropertyAll(microStyle),
    ),
    navigationRailTheme: NavigationRailThemeData(
      backgroundColor: card,
      indicatorColor: accent.withValues(alpha: 0.15),
      labelType: NavigationRailLabelType.none,
      elevation: 0,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize: WidgetStateProperty.all(const Size(52, 52)),
        padding: WidgetStateProperty.all(const EdgeInsets.all(14)),
      ),
    ),
    splashFactory: InkRipple.splashFactory,
    highlightColor: accent.withValues(alpha: 0.08),
    splashColor: accent.withValues(alpha: 0.12),
  );
}

// ---------------------------------------------------------------------------
// Adaptive helpers — use in screens instead of RyoColors.* directly
// ---------------------------------------------------------------------------

/// Returns a set of semantic UI colors appropriate for the current theme
/// (dark RYO theme or elderly white theme).
extension RyoAdaptiveTheme on BuildContext {
  bool get isElderlyMode => Theme.of(this).brightness == Brightness.light;

  Color get ryoBg =>
      isElderlyMode ? RyoElderlyColors.background : RyoColors.black;
  Color get ryoSurface =>
      isElderlyMode ? RyoElderlyColors.surface : RyoColors.surface;
  Color get ryoCard =>
      isElderlyMode ? RyoElderlyColors.card : RyoColors.card;
  Color get ryoDivider =>
      isElderlyMode ? RyoElderlyColors.divider : RyoColors.divider;
  Color get ryoAccent =>
      isElderlyMode ? RyoElderlyColors.accent : RyoColors.cyan;
  Color get ryoAccentDim =>
      isElderlyMode ? RyoElderlyColors.accentDim : RyoColors.cyanDim;
  Color get ryoTextPrimary =>
      isElderlyMode ? RyoElderlyColors.textPrimary : RyoColors.textPrimary;
  Color get ryoTextSecondary =>
      isElderlyMode ? RyoElderlyColors.textSecondary : RyoColors.textSecondary;
  Color get ryoTextMuted =>
      isElderlyMode ? RyoElderlyColors.textMuted : RyoColors.textMuted;
  Color get ryoWarning =>
      isElderlyMode ? RyoElderlyColors.warning : RyoColors.warning;
  Color get ryoCritical =>
      isElderlyMode ? RyoElderlyColors.critical : RyoColors.critical;

  TextStyle get ryoBodyStyle => isElderlyMode
      ? const TextStyle(
          fontFamily: 'SF Pro Display',
          fontFamilyFallback: ['Inter', 'Helvetica Neue', 'sans-serif'],
          fontSize: 17,
          fontWeight: FontWeight.w400,
          color: RyoElderlyColors.textSecondary,
          letterSpacing: 0.2,
        )
      : RyoTypography.body;

  TextStyle get ryoTitleStyle => isElderlyMode
      ? const TextStyle(
          fontFamily: 'SF Pro Display',
          fontFamilyFallback: ['Inter', 'Helvetica Neue', 'sans-serif'],
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: RyoElderlyColors.textPrimary,
          letterSpacing: 0.5,
        )
      : RyoTypography.title;

  TextStyle get ryoLabelStyle => isElderlyMode
      ? const TextStyle(
          fontFamily: 'SF Pro Display',
          fontFamilyFallback: ['Inter', 'Helvetica Neue', 'sans-serif'],
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: RyoElderlyColors.textMuted,
          letterSpacing: 1.0,
        )
      : RyoTypography.dataLabel;
}

