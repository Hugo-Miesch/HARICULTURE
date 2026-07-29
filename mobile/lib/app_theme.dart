import 'package:flutter/material.dart';

@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceSoft,
    required this.navigation,
    required this.border,
    required this.foreground,
    required this.muted,
    required this.accent,
  });

  static const dark = AppColors(
    background: Color(0xff111715),
    surface: Color(0xff18211e),
    surfaceSoft: Color(0xff202a26),
    navigation: Color(0xff151d1a),
    border: Color(0xff2a3731),
    foreground: Color(0xfff2f5f3),
    muted: Color(0xff95a19b),
    accent: Color(0xff68e2bd),
  );

  static const light = AppColors(
    background: Color(0xffedf4ef),
    surface: Color(0xfff8fbf8),
    surfaceSoft: Color(0xffe2ece5),
    navigation: Color(0xfff3f8f4),
    border: Color(0xffceddd2),
    foreground: Color(0xff17211d),
    muted: Color(0xff6d7771),
    accent: Color(0xff2f8067),
  );

  final Color background;
  final Color surface;
  final Color surfaceSoft;
  final Color navigation;
  final Color border;
  final Color foreground;
  final Color muted;
  final Color accent;

  @override
  AppColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceSoft,
    Color? navigation,
    Color? border,
    Color? foreground,
    Color? muted,
    Color? accent,
  }) =>
      AppColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        surfaceSoft: surfaceSoft ?? this.surfaceSoft,
        navigation: navigation ?? this.navigation,
        border: border ?? this.border,
        foreground: foreground ?? this.foreground,
        muted: muted ?? this.muted,
        accent: accent ?? this.accent,
      );

  @override
  AppColors lerp(covariant AppColors? other, double t) {
    if (other == null) return this;
    return AppColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      navigation: Color.lerp(navigation, other.navigation, t)!,
      border: Color.lerp(border, other.border, t)!,
      foreground: Color.lerp(foreground, other.foreground, t)!,
      muted: Color.lerp(muted, other.muted, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

extension AppColorsContext on BuildContext {
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;
}

Color appOnAccent(AppColors colors) =>
    ThemeData.estimateBrightnessForColor(colors.accent) == Brightness.dark
        ? const Color(0xfff7fbf9)
        : const Color(0xff10201b);

ButtonStyle appPrimaryButtonStyle(
  BuildContext context, {
  double height = 54,
  double radius = 18,
}) {
  final colors = context.appColors;
  final foreground = appOnAccent(colors);
  return FilledButton.styleFrom(
    minimumSize: Size.fromHeight(height),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    backgroundColor: colors.accent,
    foregroundColor: foreground,
    disabledBackgroundColor: Color.alphaBlend(
      colors.accent.withValues(alpha: 0.08),
      colors.surfaceSoft,
    ),
    disabledForegroundColor: colors.muted.withValues(alpha: 0.78),
    overlayColor: foreground.withValues(alpha: 0.1),
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

ButtonStyle appTonalButtonStyle(
  BuildContext context, {
  double height = 48,
  double radius = 16,
}) {
  final colors = context.appColors;
  return TextButton.styleFrom(
    minimumSize: Size.fromHeight(height),
    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
    foregroundColor: colors.accent,
    backgroundColor: colors.accent.withValues(alpha: 0.09),
    disabledForegroundColor: colors.muted.withValues(alpha: 0.78),
    disabledBackgroundColor: colors.surfaceSoft.withValues(alpha: 0.72),
    overlayColor: colors.accent.withValues(alpha: 0.1),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}

ButtonStyle appOutlineButtonStyle(
  BuildContext context, {
  double height = 56,
  double radius = 18,
}) {
  final colors = context.appColors;
  return OutlinedButton.styleFrom(
    minimumSize: Size.fromHeight(height),
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
    foregroundColor: colors.accent,
    backgroundColor: colors.accent.withValues(alpha: 0.07),
    disabledForegroundColor: colors.muted.withValues(alpha: 0.78),
    disabledBackgroundColor: colors.surfaceSoft.withValues(alpha: 0.72),
    overlayColor: colors.accent.withValues(alpha: 0.1),
    side: BorderSide(
      color: colors.accent.withValues(alpha: 0.42),
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
    ),
  );
}
