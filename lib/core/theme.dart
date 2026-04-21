// Owner: T3 (UI teammate) maintains; all features/widgets CONSUME this.
// Reference: UI-Brand-decisions.md §3 (color palette) + §4 (fonts).
// Phase 1 produces the full light/dark token extension; downstream widgets
// read via `Theme.of(context).extension<LivebackColors>()!`.

import 'package:flutter/material.dart';

/// Liveback brand color tokens. 17 tokens per theme, synced with
/// UI-Brand-decisions.md §3. Adding/removing a token is a brand amendment.
@immutable
class LivebackColors extends ThemeExtension<LivebackColors> {
  // ---- Surfaces ----
  final Color bg;
  final Color card;
  final Color panel;

  // ---- Ink (text) ----
  final Color ink;
  final Color inkDim;
  final Color inkFaint;

  // ---- Borders ----
  final Color border;
  final Color borderStrong;

  // ---- Accent (CTA) ----
  final Color accent;
  final Color accentSoft;
  final Color accentBorder;

  // ---- Glitch chroma (brand §3 rule 2: restricted usage) ----
  final Color chromaCyan;
  final Color chromaMagenta;

  // ---- Semantic ----
  final Color success;
  final Color warn;
  final Color danger;
  final Color info;

  const LivebackColors({
    required this.bg,
    required this.card,
    required this.panel,
    required this.ink,
    required this.inkDim,
    required this.inkFaint,
    required this.border,
    required this.borderStrong,
    required this.accent,
    required this.accentSoft,
    required this.accentBorder,
    required this.chromaCyan,
    required this.chromaMagenta,
    required this.success,
    required this.warn,
    required this.danger,
    required this.info,
  });

  /// Light palette (UI-Brand-decisions.md §3 Light block).
  static const LivebackColors light = LivebackColors(
    bg:            Color(0xFFF4EEE2),
    card:          Color(0xFFFFFFFF),
    panel:         Color(0xFFEBE3D0),
    ink:           Color(0xFF0B1013),
    inkDim:        Color(0xFF4A4E53),
    inkFaint:      Color(0xFF8F8B80),
    border:        Color(0xFFD8D1BF),
    borderStrong:  Color(0xFFB8B1A0),
    accent:        Color(0xFF0B1013),
    accentSoft:    Color(0x0F0B1013), // rgba(11, 16, 19, 0.06)
    accentBorder:  Color(0x400B1013), // rgba(11, 16, 19, 0.25)
    chromaCyan:    Color(0xFF22D3EE),
    chromaMagenta: Color(0xFFE11D74),
    success:       Color(0xFF0B1013),
    warn:          Color(0xFFB8691A),
    danger:        Color(0xFFB91457),
    info:          Color(0xFF0E8B9E),
  );

  /// Dark palette (UI-Brand-decisions.md §3 Dark block).
  static const LivebackColors dark = LivebackColors(
    bg:            Color(0xFF0B1013),
    card:          Color(0xFF181D24),
    panel:         Color(0xFF141A20),
    ink:           Color(0xFFF4EEE2),
    inkDim:        Color(0xFF9A968A),
    inkFaint:      Color(0xFF5C5A54),
    border:        Color(0xFF252A31),
    borderStrong:  Color(0xFF353B45),
    accent:        Color(0xFFF4EEE2),
    accentSoft:    Color(0x1AF4EEE2), // rgba(244, 238, 226, 0.1)
    accentBorder:  Color(0x59F4EEE2), // rgba(244, 238, 226, 0.35)
    chromaCyan:    Color(0xFF22D3EE),
    chromaMagenta: Color(0xFFE11D74),
    success:       Color(0xFFF4EEE2),
    warn:          Color(0xFFFBBF24),
    danger:        Color(0xFFE11D74),
    info:          Color(0xFF22D3EE),
  );

  @override
  LivebackColors copyWith({
    Color? bg,
    Color? card,
    Color? panel,
    Color? ink,
    Color? inkDim,
    Color? inkFaint,
    Color? border,
    Color? borderStrong,
    Color? accent,
    Color? accentSoft,
    Color? accentBorder,
    Color? chromaCyan,
    Color? chromaMagenta,
    Color? success,
    Color? warn,
    Color? danger,
    Color? info,
  }) {
    return LivebackColors(
      bg: bg ?? this.bg,
      card: card ?? this.card,
      panel: panel ?? this.panel,
      ink: ink ?? this.ink,
      inkDim: inkDim ?? this.inkDim,
      inkFaint: inkFaint ?? this.inkFaint,
      border: border ?? this.border,
      borderStrong: borderStrong ?? this.borderStrong,
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      accentBorder: accentBorder ?? this.accentBorder,
      chromaCyan: chromaCyan ?? this.chromaCyan,
      chromaMagenta: chromaMagenta ?? this.chromaMagenta,
      success: success ?? this.success,
      warn: warn ?? this.warn,
      danger: danger ?? this.danger,
      info: info ?? this.info,
    );
  }

  @override
  LivebackColors lerp(ThemeExtension<LivebackColors>? other, double t) {
    if (other is! LivebackColors) return this;
    return LivebackColors(
      bg:            Color.lerp(bg,            other.bg,            t)!,
      card:          Color.lerp(card,          other.card,          t)!,
      panel:         Color.lerp(panel,         other.panel,         t)!,
      ink:           Color.lerp(ink,           other.ink,           t)!,
      inkDim:        Color.lerp(inkDim,        other.inkDim,        t)!,
      inkFaint:      Color.lerp(inkFaint,      other.inkFaint,      t)!,
      border:        Color.lerp(border,        other.border,        t)!,
      borderStrong:  Color.lerp(borderStrong,  other.borderStrong,  t)!,
      accent:        Color.lerp(accent,        other.accent,        t)!,
      accentSoft:    Color.lerp(accentSoft,    other.accentSoft,    t)!,
      accentBorder:  Color.lerp(accentBorder,  other.accentBorder,  t)!,
      chromaCyan:    Color.lerp(chromaCyan,    other.chromaCyan,    t)!,
      chromaMagenta: Color.lerp(chromaMagenta, other.chromaMagenta, t)!,
      success:       Color.lerp(success,       other.success,       t)!,
      warn:          Color.lerp(warn,          other.warn,          t)!,
      danger:        Color.lerp(danger,        other.danger,        t)!,
      info:          Color.lerp(info,          other.info,          t)!,
    );
  }
}

/// Liveback [ThemeData] builders. Body/title text uses the system default
/// font stack (brand §4 — `-apple-system, PingFang SC, HarmonyOS Sans, ...`)
/// via Flutter's default `Typography.material2021`. The JetBrains Mono
/// family (brand §4 — technical text only) is available as `'JetBrainsMono'`
/// for callers that explicitly opt in — use [LivebackTheme.monoTextStyle]
/// instead of spelling the family name by hand.
abstract class LivebackTheme {
  static const monoFontFamily = 'JetBrainsMono';

  /// Monospace convenience style for file sizes, elapsed ms, hex dumps,
  /// error-code chips. Pass through `style:` to `Text()` or compose with
  /// `.copyWith(...)` on the caller's side.
  static TextStyle monoTextStyle({
    Color? color,
    double fontSize = 13,
    FontWeight fontWeight = FontWeight.w500,
    double letterSpacing = 0,
  }) =>
      TextStyle(
        fontFamily: monoFontFamily,
        color: color,
        fontSize: fontSize,
        fontWeight: fontWeight,
        letterSpacing: letterSpacing,
      );

  static ThemeData light() {
    const colors = LivebackColors.light;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: colors.bg,
      canvasColor: colors.bg,
      cardColor: colors.card,
      dividerColor: colors.border,
      colorScheme: ColorScheme(
        brightness: Brightness.light,
        primary: colors.accent,
        onPrimary: colors.bg,
        secondary: colors.info,
        onSecondary: colors.bg,
        error: colors.danger,
        onError: colors.bg,
        surface: colors.card,
        onSurface: colors.ink,
      ),
      extensions: const <ThemeExtension<dynamic>>[colors],
    );
  }

  static ThemeData dark() {
    const colors = LivebackColors.dark;
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: colors.bg,
      canvasColor: colors.bg,
      cardColor: colors.card,
      dividerColor: colors.border,
      colorScheme: ColorScheme(
        brightness: Brightness.dark,
        primary: colors.accent,
        onPrimary: colors.bg,
        secondary: colors.info,
        onSecondary: colors.bg,
        error: colors.danger,
        onError: colors.bg,
        surface: colors.card,
        onSurface: colors.ink,
      ),
      extensions: const <ThemeExtension<dynamic>>[colors],
    );
  }
}
