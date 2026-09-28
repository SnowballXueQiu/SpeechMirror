import 'package:flutter/material.dart';

abstract final class AppColors {
  static const paper = Color(0xFFF4F5F2);
  static const paperStrong = Color(0xFFE9EBE6);
  static const ink = Color(0xFF111412);
  static const muted = Color(0xFF6B716C);
  static const jade = Color(0xFF246BFE);
  static const jadeDark = Color(0xFF174EC4);
  static const signal = Color(0xFFC9F463);
  static const vermilion = Color(0xFFDF493D);
  static const gold = Color(0xFFAA7618);
  static const line = Color(0xFFD9DDD7);
  static const white = Color(0xFFFFFFFF);
  static const success = Color(0xFF19845D);
  static const softBlue = Color(0xFFE8F0FF);
  static const softRed = Color(0xFFFFE9E5);
  static const night = Color(0xFF111512);
  static const nightSoft = Color(0xFF1D231F);
}

ThemeData speechMirrorTheme() {
  const scheme = ColorScheme.light(
    primary: AppColors.jade,
    onPrimary: Colors.white,
    secondary: AppColors.success,
    onSecondary: Colors.white,
    error: AppColors.vermilion,
    surface: AppColors.white,
    onSurface: AppColors.ink,
    outline: AppColors.line,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    fontFamily: 'PingFang SC',
    fontFamilyFallback: const ['Noto Sans CJK SC', 'Helvetica Neue'],
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontSize: 38,
        height: 1.18,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      headlineLarge: TextStyle(
        fontSize: 26,
        height: 1.22,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      headlineMedium: TextStyle(
        fontSize: 21,
        height: 1.28,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: AppColors.ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.45, color: AppColors.ink),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.paper,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w800,
        color: AppColors.ink,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: AppColors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(8)),
        borderSide: BorderSide(color: AppColors.jade, width: 1.6),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        minimumSize: const Size(0, 48),
        side: const BorderSide(color: AppColors.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.jade,
      foregroundColor: Colors.white,
      elevation: 0,
      focusElevation: 0,
      hoverElevation: 0,
      highlightElevation: 0,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.jade,
      linearTrackColor: AppColors.paperStrong,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
  );
}
