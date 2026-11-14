import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'status.dart';

/// Fleet Geeks design tokens, mirrored from `design/tokens.json` (the single source; change it there first).
/// Raw palette: teal is the brand, orange is the only action colour, neutrals for text and surfaces.
class FgColors {
  const FgColors._();

  static const teal50 = Color(0xFFE8F5F4);
  static const teal100 = Color(0xFFC8E8E5);
  static const teal200 = Color(0xFF93D1CB);
  static const teal300 = Color(0xFF5CB6AE);
  static const teal400 = Color(0xFF2F9A92);
  static const teal500 = Color(0xFF127F78);
  static const teal600 = Color(0xFF0E6B67);
  static const teal700 = Color(0xFF0B5554);
  static const teal800 = Color(0xFF094443);
  static const teal900 = Color(0xFF062F2F);

  static const orange50 = Color(0xFFFFF3EB);
  static const orange100 = Color(0xFFFFE1CC);
  static const orange200 = Color(0xFFFFC099);
  static const orange300 = Color(0xFFFF9A5C);
  static const orange400 = Color(0xFFF47A30);
  static const orange500 = Color(0xFFE0601A);
  static const orange600 = Color(0xFFC2410C);
  static const orange700 = Color(0xFF9F350B);
  static const orange800 = Color(0xFF7C2A0A);
  static const orange900 = Color(0xFF5A1F08);

  static const n0 = Color(0xFFFFFFFF);
  static const n50 = Color(0xFFF6F8F7);
  static const n100 = Color(0xFFEEF2F1);
  static const n200 = Color(0xFFDFE6E4);
  static const n300 = Color(0xFFC6D1CE);
  static const n400 = Color(0xFF9FB1B8);
  static const n500 = Color(0xFF7A8B92);
  static const n600 = Color(0xFF5B6B72);
  static const n700 = Color(0xFF3D4B51);
  static const n800 = Color(0xFF26343A);
  static const n900 = Color(0xFF162125);
  static const n950 = Color(0xFF0F171A);

  /// Chart palette (design/tokens.json, validated for colour-blind separation): 7 categorical series, sequential
  /// (teal) and diverging (danger ↔ teal); `chartOther` for de-emphasised series.
  static const chartCategorical = <Color>[
    Color(0xFF008E80), Color(0xFFE0601A), Color(0xFF1D6FA5), Color(0xFF5A9E2F),
    Color(0xFF8A5CC2), Color(0xFFB08900), Color(0xFFC2417A),
  ];
  static const chartOther = Color(0xFF9FB1B8);
  static const chartSequential = <Color>[teal50, teal100, teal200, teal300, teal400, teal500, teal700, teal900];
  static const chartDiverging = <Color>[
    Color(0xFFB8352A), Color(0xFFE58A7F), Color(0xFFF3D2CD), n100, teal100, teal300, teal600,
  ];

  /// Light-mode shortcuts kept for older call sites; prefer `context.fg` (brightness aware).
  static const petrol = teal700;
  static const orange = orange600;
  static const graphite = n900;
  static const success = Color(0xFF18794A);
  static const warning = Color(0xFF8F5F00);
  static const error = Color(0xFFB8352A);
  static const info = Color(0xFF1D6FA5);
}

/// Spacing scale (tokens.json → space; 4 dp grid).
class FgSpace {
  const FgSpace._();
  static const double s1 = 4;
  static const double s2 = 8;
  static const double s3 = 12;
  static const double s4 = 16;
  static const double s5 = 20;
  static const double s6 = 24;
  static const double s8 = 32;
  static const double s10 = 40;
  static const double s12 = 48;
  static const double s16 = 64;

  /// Side gutter of every screen.
  static const double gutter = s4;

  /// Minimum touch target (Material / WCAG).
  static const double touch = 48;
}

/// Corner radius (tokens.json → radius).
class FgRadius {
  const FgRadius._();
  static const double sm = 6;
  static const double md = 10;
  static const double lg = 14;
  static const double xl = 20;
  static const double pill = 999;

  static final BorderRadius brSm = BorderRadius.circular(sm);
  static final BorderRadius brMd = BorderRadius.circular(md);
  static final BorderRadius brLg = BorderRadius.circular(lg);
  static final BorderRadius brXl = BorderRadius.circular(xl);
  static final BorderRadius brPill = BorderRadius.circular(pill);
}

/// Motion (tokens.json → motion). Respect `MediaQuery.disableAnimationsOf` for anything decorative.
class FgMotion {
  const FgMotion._();
  static const fast = Duration(milliseconds: 120);
  static const base = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 320);
  static const easeOut = Cubic(0.2, 0.8, 0.2, 1);
  static const easeInOut = Cubic(0.4, 0, 0.2, 1);
}

/// Elevation as soft shadows (tokens.json → shadow). Dark mode uses deeper, neutral shadows.
class FgShadows {
  const FgShadows._();
  static const sm = [BoxShadow(color: Color(0x0F162125), offset: Offset(0, 1), blurRadius: 2)];
  static const md = [
    BoxShadow(color: Color(0x0F162125), offset: Offset(0, 1), blurRadius: 2),
    BoxShadow(color: Color(0x14162125), offset: Offset(0, 4), blurRadius: 16),
  ];
  static const lg = [BoxShadow(color: Color(0x24162125), offset: Offset(0, 8), blurRadius: 32)];
  static const darkMd = [BoxShadow(color: Color(0x66000000), offset: Offset(0, 4), blurRadius: 16)];

  static List<BoxShadow> card(Brightness b) => b == Brightness.dark ? darkMd : md;
}

/// Bundled fonts (see pubspec `flutter: fonts:`). Package fonts are addressed as `packages/<package>/<family>`.
class FgFonts {
  const FgFonts._();
  static const latin = 'packages/fg_core/Inter';
  static const arabic = 'packages/fg_core/IBMPlexSansArabic';

  /// Tabular figures for money, odometers, counts and times (columns line up).
  static const tabular = <FontFeature>[FontFeature.tabularFigures()];
}

/// Semantic colours of one brightness (tokens.json → color.light / color.dark), available as `context.fg`.
@immutable
class FgTokens extends ThemeExtension<FgTokens> {
  const FgTokens({
    required this.canvas,
    required this.surface,
    required this.surface2,
    required this.border,
    required this.text,
    required this.textMuted,
    required this.primary,
    required this.primaryStrong,
    required this.onPrimary,
    required this.primaryBg,
    required this.action,
    required this.actionHover,
    required this.onAction,
    required this.actionBg,
    required this.focus,
    required this.success,
    required this.successBg,
    required this.warning,
    required this.warningBg,
    required this.danger,
    required this.dangerBg,
    required this.info,
    required this.infoBg,
    required this.heroStart,
    required this.heroEnd,
  });

  final Color canvas, surface, surface2, border, text, textMuted;
  final Color primary, primaryStrong, onPrimary, primaryBg;
  final Color action, actionHover, onAction, actionBg, focus;
  final Color success, successBg, warning, warningBg, danger, dangerBg, info, infoBg;

  /// Gradient of hero headers (dashboard, sign-in, vehicle 360).
  final Color heroStart, heroEnd;

  static const light = FgTokens(
    canvas: Color(0xFFF6F8F7),
    surface: Color(0xFFFFFFFF),
    surface2: Color(0xFFEEF2F1),
    border: Color(0xFFDFE6E4),
    text: Color(0xFF162125),
    textMuted: Color(0xFF5B6B72),
    primary: Color(0xFF0E6B67),
    primaryStrong: Color(0xFF0B5554),
    onPrimary: Color(0xFFFFFFFF),
    primaryBg: FgColors.teal50,
    action: Color(0xFFC2410C),
    actionHover: Color(0xFF9F350B),
    onAction: Color(0xFFFFFFFF),
    actionBg: FgColors.orange50,
    focus: Color(0xFFC2410C),
    success: Color(0xFF18794A),
    successBg: Color(0xFFE3F1E9),
    warning: Color(0xFF8F5F00),
    warningBg: Color(0xFFF7EED8),
    danger: Color(0xFFB8352A),
    dangerBg: Color(0xFFF9E4E1),
    info: Color(0xFF1D6FA5),
    infoBg: Color(0xFFE1EEF7),
    heroStart: FgColors.teal700,
    heroEnd: FgColors.teal900,
  );

  static const dark = FgTokens(
    canvas: Color(0xFF0F171A),
    surface: Color(0xFF162125),
    surface2: Color(0xFF1F2D33),
    border: Color(0xFF2C3C43),
    text: Color(0xFFE8EEEC),
    textMuted: Color(0xFF9FB1B8),
    primary: Color(0xFF4FC1B8),
    primaryStrong: Color(0xFF93D1CB),
    onPrimary: Color(0xFF062F2F),
    primaryBg: Color(0xFF0E3533),
    action: Color(0xFFF08A4B),
    actionHover: Color(0xFFFF9A5C),
    onAction: Color(0xFF1A0D05),
    actionBg: Color(0xFF3A2112),
    focus: Color(0xFFF08A4B),
    success: Color(0xFF5CC48B),
    successBg: Color(0xFF173526),
    warning: Color(0xFFE0B04A),
    warningBg: Color(0xFF3A2F12),
    danger: Color(0xFFEF7A7A),
    dangerBg: Color(0xFF3D1B1B),
    info: Color(0xFF6CB9DB),
    infoBg: Color(0xFF15303D),
    heroStart: FgColors.teal800,
    heroEnd: Color(0xFF07211F),
  );

  /// Foreground and background colour of a status tone (pills, notices, icons).
  ({Color fg, Color bg}) tone(FgTone tone) => switch (tone) {
        FgTone.neutral => (fg: textMuted, bg: surface2),
        FgTone.info => (fg: info, bg: infoBg),
        FgTone.progress => (fg: primary, bg: primaryBg),
        FgTone.attention => (fg: warning, bg: warningBg),
        FgTone.good => (fg: success, bg: successBg),
        FgTone.bad => (fg: danger, bg: dangerBg),
      };

  @override
  FgTokens copyWith({Color? canvas, Color? surface, Color? primary, Color? action, Color? heroStart, Color? heroEnd}) => FgTokens(
        canvas: canvas ?? this.canvas,
        surface: surface ?? this.surface,
        surface2: surface2,
        border: border,
        text: text,
        textMuted: textMuted,
        primary: primary ?? this.primary,
        primaryStrong: primaryStrong,
        onPrimary: onPrimary,
        primaryBg: primaryBg,
        action: action ?? this.action,
        actionHover: actionHover,
        onAction: onAction,
        actionBg: actionBg,
        focus: focus,
        success: success,
        successBg: successBg,
        warning: warning,
        warningBg: warningBg,
        danger: danger,
        dangerBg: dangerBg,
        info: info,
        infoBg: infoBg,
        heroStart: heroStart ?? this.heroStart,
        heroEnd: heroEnd ?? this.heroEnd,
      );

  @override
  FgTokens lerp(ThemeExtension<FgTokens>? other, double t) {
    if (other is! FgTokens) return this;
    Color l(Color a, Color b) => Color.lerp(a, b, t)!;
    return FgTokens(
      canvas: l(canvas, other.canvas),
      surface: l(surface, other.surface),
      surface2: l(surface2, other.surface2),
      border: l(border, other.border),
      text: l(text, other.text),
      textMuted: l(textMuted, other.textMuted),
      primary: l(primary, other.primary),
      primaryStrong: l(primaryStrong, other.primaryStrong),
      onPrimary: l(onPrimary, other.onPrimary),
      primaryBg: l(primaryBg, other.primaryBg),
      action: l(action, other.action),
      actionHover: l(actionHover, other.actionHover),
      onAction: l(onAction, other.onAction),
      actionBg: l(actionBg, other.actionBg),
      focus: l(focus, other.focus),
      success: l(success, other.success),
      successBg: l(successBg, other.successBg),
      warning: l(warning, other.warning),
      warningBg: l(warningBg, other.warningBg),
      danger: l(danger, other.danger),
      dangerBg: l(dangerBg, other.dangerBg),
      info: l(info, other.info),
      infoBg: l(infoBg, other.infoBg),
      heroStart: l(heroStart, other.heroStart),
      heroEnd: l(heroEnd, other.heroEnd),
    );
  }
}

/// Short access to the design system from any widget: `context.fg.action`, `context.tt.titleMedium`, `context.cs.primary`.
extension FgContext on BuildContext {
  FgTokens get fg => Theme.of(this).extension<FgTokens>() ?? FgTokens.light;
  TextTheme get tt => Theme.of(this).textTheme;
  ColorScheme get cs => Theme.of(this).colorScheme;
  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// Material 3 theme built from the tokens. [lang] picks the primary font (Inter for Latin, IBM Plex Sans Arabic for
/// Arabic); the other one is the fallback so mixed text (plates, codes) always renders.
ThemeData fgTheme(Brightness brightness, {String lang = 'en'}) {
  final dark = brightness == Brightness.dark;
  final t = dark ? FgTokens.dark : FgTokens.light;
  final arabic = lang == 'ar';
  final family = arabic ? FgFonts.arabic : FgFonts.latin;
  final fallback = <String>[arabic ? FgFonts.latin : FgFonts.arabic];

  final cs = ColorScheme(
    brightness: brightness,
    primary: t.primary,
    onPrimary: t.onPrimary,
    primaryContainer: t.primaryBg,
    onPrimaryContainer: dark ? FgColors.teal100 : FgColors.teal900,
    secondary: t.action,
    onSecondary: t.onAction,
    secondaryContainer: t.actionBg,
    onSecondaryContainer: dark ? FgColors.orange100 : FgColors.orange800,
    tertiary: t.info,
    onTertiary: dark ? FgColors.n950 : FgColors.n0,
    tertiaryContainer: t.infoBg,
    onTertiaryContainer: t.info,
    error: t.danger,
    onError: dark ? FgColors.n950 : FgColors.n0,
    errorContainer: t.dangerBg,
    onErrorContainer: t.danger,
    surface: t.surface,
    onSurface: t.text,
    onSurfaceVariant: t.textMuted,
    surfaceDim: dark ? FgColors.n950 : FgColors.n100,
    surfaceBright: dark ? FgColors.n800 : FgColors.n0,
    surfaceContainerLowest: dark ? FgColors.n950 : FgColors.n0,
    surfaceContainerLow: dark ? const Color(0xFF131D21) : FgColors.n50,
    surfaceContainer: t.surface2,
    surfaceContainerHigh: dark ? FgColors.n800 : const Color(0xFFE7ECEB),
    surfaceContainerHighest: dark ? t.border : FgColors.n200,
    outline: dark ? FgColors.n700 : FgColors.n300,
    outlineVariant: t.border,
    shadow: FgColors.n900,
    scrim: Colors.black,
    inverseSurface: dark ? FgColors.n100 : FgColors.n900,
    onInverseSurface: dark ? FgColors.n900 : FgColors.n50,
    inversePrimary: dark ? FgColors.teal600 : FgColors.teal200,
    surfaceTint: Colors.transparent,
  );

  // Type scale (tokens.json → font.scale): 12 / 13 / 15 / 17 / 20 / 24 / 30 / 38. Letter spacing stays 0 in Arabic.
  TextStyle st(double size, FontWeight weight, double height, {Color? color, double spacing = 0}) => TextStyle(
        fontFamily: family,
        fontFamilyFallback: fallback,
        fontSize: size,
        fontWeight: weight,
        height: height,
        letterSpacing: arabic ? 0 : spacing,
        color: color ?? t.text,
      );
  final text = TextTheme(
    displayLarge: st(38, FontWeight.w700, 1.2, spacing: -0.6),
    displayMedium: st(30, FontWeight.w700, 1.2, spacing: -0.4),
    displaySmall: st(24, FontWeight.w700, 1.2, spacing: -0.2),
    headlineLarge: st(30, FontWeight.w600, 1.2, spacing: -0.4),
    headlineMedium: st(24, FontWeight.w600, 1.2, spacing: -0.2),
    headlineSmall: st(20, FontWeight.w600, 1.25),
    titleLarge: st(20, FontWeight.w600, 1.25),
    titleMedium: st(17, FontWeight.w600, 1.3),
    titleSmall: st(15, FontWeight.w600, 1.3),
    bodyLarge: st(17, FontWeight.w400, 1.5),
    bodyMedium: st(15, FontWeight.w400, 1.5),
    bodySmall: st(13, FontWeight.w400, 1.45, color: t.textMuted),
    labelLarge: st(15, FontWeight.w600, 1.2),
    labelMedium: st(13, FontWeight.w500, 1.2),
    labelSmall: st(12, FontWeight.w500, 1.2, color: t.textMuted, spacing: 0.2),
  );

  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(borderRadius: FgRadius.brMd, borderSide: BorderSide(color: color, width: width));
  final buttonShape = RoundedRectangleBorder(borderRadius: FgRadius.brMd);
  bool selected(Set<WidgetState> states) => states.contains(WidgetState.selected);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: cs,
    fontFamily: family,
    fontFamilyFallback: fallback,
    textTheme: text,
    scaffoldBackgroundColor: t.canvas,
    canvasColor: t.surface,
    dividerColor: t.border,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    extensions: <ThemeExtension<dynamic>>[t],
    appBarTheme: AppBarThemeData(
      backgroundColor: t.canvas,
      foregroundColor: t.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleSpacing: FgSpace.s4,
      titleTextStyle: text.titleLarge,
      iconTheme: IconThemeData(color: t.text, size: 24),
      actionsIconTheme: IconThemeData(color: t.text, size: 24),
      systemOverlayStyle: dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: t.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: FgRadius.brLg, side: BorderSide(color: t.border)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: t.action,
        foregroundColor: t.onAction,
        disabledBackgroundColor: t.surface2,
        disabledForegroundColor: t.textMuted,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: FgSpace.s5, vertical: FgSpace.s3),
        shape: buttonShape,
        textStyle: text.labelLarge,
        elevation: 0,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: t.surface,
        foregroundColor: dark ? t.primary : t.primaryStrong,
        minimumSize: const Size(64, 48),
        shape: buttonShape,
        textStyle: text.labelLarge,
        elevation: 0,
        side: BorderSide(color: cs.outline),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: dark ? t.primary : t.primaryStrong,
        disabledForegroundColor: t.textMuted,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: FgSpace.s5, vertical: FgSpace.s3),
        shape: buttonShape,
        side: BorderSide(color: cs.outline),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: t.primary,
        minimumSize: const Size(48, 44),
        shape: buttonShape,
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(style: IconButton.styleFrom(foregroundColor: t.text)),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: t.action,
      foregroundColor: t.onAction,
      elevation: 2,
      focusElevation: 3,
      hoverElevation: 3,
      highlightElevation: 4,
      shape: RoundedRectangleBorder(borderRadius: FgRadius.brLg),
      extendedTextStyle: text.labelLarge,
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((s) => selected(s) ? t.primaryBg : t.surface),
        foregroundColor: WidgetStateProperty.resolveWith((s) => selected(s) ? (dark ? t.primary : t.primaryStrong) : t.text),
        iconColor: WidgetStateProperty.resolveWith((s) => selected(s) ? (dark ? t.primary : t.primaryStrong) : t.textMuted),
        side: WidgetStatePropertyAll(BorderSide(color: cs.outline)),
        shape: WidgetStatePropertyAll(buttonShape),
        minimumSize: const WidgetStatePropertyAll(Size(48, 48)),
        textStyle: WidgetStatePropertyAll(text.labelLarge),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: t.surface,
      floatingLabelBehavior: FloatingLabelBehavior.auto,
      contentPadding: const EdgeInsets.symmetric(horizontal: FgSpace.s4, vertical: 14),
      border: inputBorder(cs.outline),
      enabledBorder: inputBorder(cs.outline),
      disabledBorder: inputBorder(t.border),
      focusedBorder: inputBorder(t.focus, 2),
      errorBorder: inputBorder(t.danger),
      focusedErrorBorder: inputBorder(t.danger, 2),
      labelStyle: text.bodyMedium?.copyWith(color: t.textMuted),
      floatingLabelStyle: WidgetStateTextStyle.resolveWith(
        (states) => (text.bodyMedium ?? const TextStyle()).copyWith(
          color: states.contains(WidgetState.error) ? t.danger : (states.contains(WidgetState.focused) ? t.focus : t.textMuted),
          fontWeight: FontWeight.w500,
        ),
      ),
      hintStyle: text.bodyMedium?.copyWith(color: t.textMuted),
      helperStyle: text.bodySmall,
      errorStyle: text.bodySmall?.copyWith(color: t.danger),
      prefixIconColor: t.textMuted,
      suffixIconColor: t.textMuted,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: t.surface,
      selectedColor: t.primaryBg,
      disabledColor: t.surface2,
      checkmarkColor: dark ? t.primary : t.primaryStrong,
      side: BorderSide(color: cs.outline),
      shape: RoundedRectangleBorder(borderRadius: FgRadius.brPill),
      labelStyle: text.labelMedium,
      secondaryLabelStyle: text.labelMedium?.copyWith(color: dark ? t.primary : t.primaryStrong),
      padding: const EdgeInsets.symmetric(horizontal: FgSpace.s2, vertical: 6),
      iconTheme: IconThemeData(color: t.textMuted, size: 18),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      height: 68,
      indicatorColor: t.primaryBg,
      indicatorShape: const StadiumBorder(),
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => (text.labelMedium ?? const TextStyle()).copyWith(
          color: selected(s) ? (dark ? t.primary : t.primaryStrong) : t.textMuted,
          fontWeight: selected(s) ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(size: 24, color: selected(s) ? (dark ? t.primary : t.primaryStrong) : t.textMuted),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: t.surface,
      modalBackgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: cs.outline,
      clipBehavior: Clip.antiAlias,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(FgRadius.xl))),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: t.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: FgRadius.brXl),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: cs.inverseSurface,
      contentTextStyle: text.bodyMedium?.copyWith(color: cs.onInverseSurface),
      actionTextColor: dark ? FgColors.orange600 : FgColors.orange300,
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: FgRadius.brMd),
    ),
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: FgSpace.s4),
      minVerticalPadding: 10,
      minLeadingWidth: 24,
      horizontalTitleGap: FgSpace.s3,
      iconColor: t.textMuted,
      textColor: t.text,
      titleTextStyle: text.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
      subtitleTextStyle: text.bodySmall,
      leadingAndTrailingTextStyle: text.labelMedium,
      shape: RoundedRectangleBorder(borderRadius: FgRadius.brMd),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: dark ? t.primary : t.primaryStrong,
      unselectedLabelColor: t.textMuted,
      indicatorColor: t.action,
      indicatorSize: TabBarIndicatorSize.label,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      dividerColor: t.border,
      overlayColor: WidgetStatePropertyAll(t.primary.withValues(alpha: 0.08)),
    ),
    dividerTheme: DividerThemeData(color: t.border, thickness: 1, space: 1),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: t.primary, linearTrackColor: t.surface2, circularTrackColor: Colors.transparent),
    badgeTheme: BadgeThemeData(backgroundColor: t.action, textColor: t.onAction, textStyle: text.labelSmall),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: t.focus,
      selectionHandleColor: t.focus,
      selectionColor: t.focus.withValues(alpha: 0.25),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: cs.inverseSurface, borderRadius: FgRadius.brSm),
      textStyle: text.labelMedium?.copyWith(color: cs.onInverseSurface),
    ),
  );
}

/// Colour of a status symbol (foreground of its tone) for call sites without a BuildContext.
Color statusColor(String symbol, [Brightness brightness = Brightness.light]) =>
    (brightness == Brightness.dark ? FgTokens.dark : FgTokens.light).tone(toneOf(symbol)).fg;
