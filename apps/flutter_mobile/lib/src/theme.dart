import 'package:flutter/material.dart';

abstract final class AppColors {
  static const paper = Color(0xFFF4F1E8);
  static const paperStrong = Color(0xFFE8E2D4);
  static const ink = Color(0xFF18211D);
  static const muted = Color(0xFF67716B);
  static const jade = Color(0xFF176B5B);
  static const jadeDark = Color(0xFF0E4B40);
  static const vermilion = Color(0xFFC8573B);
  static const gold = Color(0xFFC49A43);
  static const line = Color(0xFFD4CEC0);
  static const white = Color(0xFFFFFDF8);
}

ThemeData speechMirrorTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: AppColors.jade,
    brightness: Brightness.light,
    surface: AppColors.paper,
    primary: AppColors.jade,
    secondary: AppColors.vermilion,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.paper,
    fontFamily: 'PingFang SC',
    fontFamilyFallback: const ['Noto Sans CJK SC', 'Songti SC'],
    textTheme: const TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Songti SC',
        fontSize: 42,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      headlineLarge: TextStyle(
        fontFamily: 'Songti SC',
        fontSize: 30,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Songti SC',
        fontSize: 23,
        height: 1.25,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      titleLarge: TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      titleMedium: TextStyle(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.55, color: AppColors.ink),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: AppColors.ink),
      labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.paper,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Songti SC',
        fontSize: 21,
        fontWeight: FontWeight.w700,
        color: AppColors.ink,
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      color: AppColors.white,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.line),
        borderRadius: BorderRadius.all(Radius.circular(8)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      filled: true,
      fillColor: AppColors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: AppColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: AppColors.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(6)),
        borderSide: BorderSide(color: AppColors.jade, width: 1.5),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.jade,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
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
    dividerTheme: const DividerThemeData(color: AppColors.line, thickness: 1),
  );
}
