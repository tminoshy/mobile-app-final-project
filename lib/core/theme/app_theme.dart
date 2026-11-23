import 'package:flutter/material.dart';

class FTColors {
  static const primary = Color(0xFF111827),
      secondary = Color(0xFF6B7280),
      muted = Color(0xFF9CA3AF),
      border = Color(0xFFE5E7EB),
      fill = Color(0xFFF3F4F6);
  static const success = Color(0xFF15803D),
      successBg = Color(0xFFDCFCE7),
      warning = Color(0xFFB45309),
      warningBg = Color(0xFFFEF3C7),
      danger = Color(0xFFB91C1C),
      dangerBg = Color(0xFFFEE2E2),
      info = Color(0xFF2563EB),
      infoBg = Color(0xFFDBEAFE);
}

ThemeData appTheme() {
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: ColorScheme.fromSeed(
      seedColor: FTColors.primary,
      primary: FTColors.primary,
      surface: Colors.white,
      error: FTColors.danger,
    ),
    scaffoldBackgroundColor: Colors.white,
  );
  final text = base.textTheme
      .apply(fontFamily: 'Inter')
      .apply(bodyColor: FTColors.primary, displayColor: FTColors.primary);
  return base.copyWith(
    textTheme: text.copyWith(
      bodyMedium: text.bodyMedium?.copyWith(fontSize: 14),
      titleLarge: text.titleLarge?.copyWith(
        fontSize: 20,
        fontWeight: FontWeight.w700,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: FTColors.primary,
        fontSize: 16,
        fontWeight: FontWeight.w600,
      ),
      shape: Border(bottom: BorderSide(color: FTColors.border)),
    ),
    dividerTheme: const DividerThemeData(
      color: FTColors.border,
      space: 24,
      thickness: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FTColors.fill,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: FTColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: FTColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 48),
        foregroundColor: FTColors.primary,
        side: const BorderSide(color: FTColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: FTColors.info,
        minimumSize: const Size(44, 44),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: FTColors.primary,
      foregroundColor: Colors.white,
      shape: CircleBorder(),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Colors.transparent,
      height: 72,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => TextStyle(
          fontSize: 10,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w700
              : FontWeight.w400,
          color: s.contains(WidgetState.selected)
              ? FTColors.primary
              : FTColors.muted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 21,
          color: s.contains(WidgetState.selected)
              ? FTColors.primary
              : FTColors.muted,
        ),
      ),
    ),
  );
}
