import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;

import 'app_colors.dart';

class AppTheme {
  static ThemeData build(
      {required Brightness brightness,
      bool highContrast = false,
      bool isUrdu = false}) {
    final dark = brightness == Brightness.dark;
    var scheme = ColorScheme.fromSeed(
      seedColor: AppColors.teal,
      brightness: brightness,
      primary: AppColors.teal,
      secondary: AppColors.lavender,
      tertiary: AppColors.amber,
      error: AppColors.coral,
      surface: dark ? AppColors.navy : AppColors.softWhite,
    );
    if (highContrast) {
      scheme = scheme.copyWith(
        primary: dark ? const Color(0xFF5EF2DF) : const Color(0xFF006B60),
        onSurface: dark ? Colors.white : Colors.black,
        outline: dark ? Colors.white : Colors.black,
      );
    }
    final base = ThemeData(
        useMaterial3: true, colorScheme: scheme, brightness: brightness);
    final text = base.typography.englishLike.merge(base.textTheme).apply(
      bodyColor: scheme.onSurface,
      displayColor: scheme.onSurface,
      fontSizeFactor: isUrdu ? 1.06 : 1.0,
    );
    final radius = BorderRadius.circular(16);
    return base.copyWith(
      scaffoldBackgroundColor: dark ? AppColors.navy : AppColors.softWhite,
      textTheme: text.copyWith(
        headlineMedium: text.headlineMedium
            ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.5),
        titleLarge: text.titleLarge?.copyWith(fontWeight: FontWeight.w700),
        titleMedium: text.titleMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        titleTextStyle: text.titleLarge,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: dark ? fade(Colors.white, 0.06) : Colors.white,
        border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: fade(scheme.outline, 0.3))),
        enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(
                color: fade(scheme.outline, highContrast ? 1 : 0.25))),
        focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: BorderSide(color: scheme.primary, width: 2)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 52),
          shape: RoundedRectangleBorder(borderRadius: radius),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(borderRadius: radius)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        backgroundColor:
            dark ? fade(AppColors.navyLight, 0.92) : fade(Colors.white, 0.94),
        indicatorColor: fade(AppColors.teal, 0.18),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      ),
      chipTheme: ChipThemeData(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
      snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: radius)),
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: ZoomPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      }),
    );
  }
}
