import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:gbt_fluent2_ui/theme_data.dart' as fluent_theme;
import 'package:gbt_fluent2_ui/gbt_fluent2_ui.dart';

import 'services/preferences.dart';

ThemeData applicationTheme(AppThemeMode mode) {
  final brightness = mode == AppThemeMode.light
      ? Brightness.light
      : Brightness.dark;
  final base = brightness == Brightness.light
      ? fluent_theme.theme
      : fluent_theme.darkTheme;
  var colors = base.colorScheme;
  colors = colors.copyWith(
    primary: brightness == Brightness.light
        ? const Color(0xff0f6cbd)
        : const Color(0xff479ef5),
    surface: brightness == Brightness.light
        ? Colors.white
        : const Color(0xff292929),
    surfaceContainer: brightness == Brightness.light
        ? Colors.white
        : const Color(0xff292929),
    onSurface: brightness == Brightness.light
        ? const Color(0xff242424)
        : const Color(0xfff5f5f5),
    onSurfaceVariant: brightness == Brightness.light
        ? const Color(0xff616161)
        : const Color(0xffd6d6d6),
    surfaceContainerLowest: brightness == Brightness.light
        ? Colors.white
        : const Color(0xff141414),
    surfaceContainerLow: brightness == Brightness.light
        ? const Color(0xfffafafa)
        : const Color(0xff1f1f1f),
    surfaceContainerHigh: brightness == Brightness.light
        ? const Color(0xfff5f5f5)
        : const Color(0xff333333),
    surfaceContainerHighest: brightness == Brightness.light
        ? const Color(0xffebebeb)
        : const Color(0xff3d3d3d),
    surfaceTint: Colors.transparent,
    outlineVariant: brightness == Brightness.light
        ? const Color(0xffe4e4e4)
        : const Color(0xff414141),
  );
  if (mode == AppThemeMode.oledBlack) {
    // Removing surface tint keeps large OLED backgrounds completely black.
    colors = colors.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Colors.black,
      surfaceContainer: Colors.black,
      surfaceContainerHigh: Colors.black,
      surfaceContainerHighest: Colors.black,
      surfaceTint: Colors.transparent,
    );
  }
  final mac = defaultTargetPlatform == TargetPlatform.macOS;
  final fontFamily = switch (defaultTargetPlatform) {
    TargetPlatform.macOS || TargetPlatform.iOS => '.AppleSystemUIFont',
    TargetPlatform.windows => 'Segoe UI',
    TargetPlatform.android => 'Roboto',
    _ => 'sans-serif',
  };
  final bodySize = mac ? 13.0 : 14.0;
  final captionSize = mac ? 10.0 : 12.0;
  final titleSize = mac ? 17.0 : 20.0;
  TextStyle text(
    double size,
    double lineHeight, {
    FontWeight weight = FontWeight.w400,
  }) => TextStyle(
    fontFamily: fontFamily,
    fontSize: size,
    height: lineHeight / size,
    fontWeight: weight,
    color: colors.onSurface,
  );
  final textTheme = base.textTheme.copyWith(
    bodyMedium: text(bodySize, mac ? 16 : 20),
    bodyLarge: text(mac ? 15 : 18, mac ? 20 : 24),
    bodySmall: text(captionSize, mac ? 13 : 16),
    labelSmall: text(captionSize, mac ? 13 : 16),
    labelMedium: text(captionSize, mac ? 13 : 16, weight: FontWeight.w600),
    labelLarge: text(bodySize, mac ? 16 : 20, weight: FontWeight.w600),
    titleSmall: text(bodySize, mac ? 16 : 20, weight: FontWeight.w600),
    titleMedium: text(mac ? 15 : 16, mac ? 20 : 22, weight: FontWeight.w600),
    titleLarge: text(titleSize, mac ? 22 : 26, weight: FontWeight.w600),
    headlineSmall: text(mac ? 22 : 24, mac ? 26 : 32, weight: FontWeight.w600),
  );
  MixedFluentTextStyle fluentText(
    double size,
    double lineHeight, {
    bool strong = false,
  }) => MixedFluentTextStyle(
    fluentSize: size,
    fluentLineHeight: lineHeight / size,
    fluentWeight: strong
        ? MixedFluentFontWeight.semibold
        : MixedFluentFontWeight.regular,
  );
  return base.copyWith(
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    fluentTextTheme: MixedFluentTextTheme(
      caption2: fluentText(captionSize, mac ? 13 : 16),
      caption1: fluentText(captionSize, mac ? 13 : 16),
      caption1Strong: fluentText(captionSize, mac ? 13 : 16, strong: true),
      body2: fluentText(bodySize, mac ? 16 : 20),
      body2Strong: fluentText(bodySize, mac ? 16 : 20, strong: true),
      body1: fluentText(mac ? 15 : 18, mac ? 20 : 24),
      body1Strong: fluentText(mac ? 15 : 18, mac ? 20 : 24, strong: true),
      title3: fluentText(mac ? 15 : 16, mac ? 20 : 22, strong: true),
      title2: fluentText(titleSize, mac ? 22 : 26, strong: true),
      title1: fluentText(mac ? 22 : 28, mac ? 26 : 36, strong: true),
      largeTitle: fluentText(mac ? 26 : 40, mac ? 32 : 52, strong: true),
      display: fluentText(mac ? 30 : 68, mac ? 40 : 92, strong: true),
    ),
    platform: defaultTargetPlatform,
    brightness: brightness,
    colorScheme: colors,
    splashFactory: NoSplash.splashFactory,
    scaffoldBackgroundColor: mode == AppThemeMode.oledBlack
        ? Colors.black
        : brightness == Brightness.light
        ? const Color(0xfffafafa)
        : const Color(0xff1f1f1f),
    tooltipTheme: const TooltipThemeData(
      waitDuration: Duration(milliseconds: 400),
    ),
  );
}

Color providerAccent(BuildContext context, int index) =>
    Theme.of(context).colorScheme.primary;

Color warningColor(BuildContext context) =>
    Theme.of(context).brightness == Brightness.light
    ? const Color(0xff805600)
    : Colors.amber;
