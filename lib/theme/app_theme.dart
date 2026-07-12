// lib/theme/app_theme.dart
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Nipino.com brand — crisp white + bold red
  static const Color red        = Color(0xFFCC0000);
  static const Color redDark    = Color(0xFFAA0000);
  static const Color redLight   = Color(0xFFFFF0F0);

  static const Color ink        = Color(0xFF111111);
  static const Color ink2       = Color(0xFF333333);
  static const Color muted      = Color(0xFF666666);
  static const Color muted2     = Color(0xFF999999);

  static const Color border     = Color(0xFFE5E5E5);
  static const Color bg         = Color(0xFFFFFFFF);
  static const Color bg2        = Color(0xFFF8F8F8);
  static const Color bg3        = Color(0xFFF2F2F2);

  static const Color gold       = Color(0xFFD4920A);
  static const Color goldLight  = Color(0xFFFFF8E6);
  static const Color green      = Color(0xFF1A7A3C);
  static const Color greenLight = Color(0xFFEEF8F2);
  
  static const Color blue       = Color(0xFF1053A0);
  
  static const Color blueLight  = Color(0xFFEEF3FC);

  // Level colors
  static const Color n5Color    = Color(0xFF10B981);
  static const Color n4Color    = Color(0xFF3B82F6);
  static const Color n3Color    = Color(0xFFF59E0B);
  static const Color n2Color    = Color(0xFFEF4444);
  static const Color n1Color    = Color(0xFF7C3AED);
}

class AppTheme {
  static ThemeData get theme => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppColors.red,
      primary: AppColors.red,
      secondary: AppColors.gold,
      background: AppColors.bg,
      surface: AppColors.bg,
      onPrimary: Colors.white,
      onBackground: AppColors.ink,
      onSurface: AppColors.ink,
    ),
    scaffoldBackgroundColor: AppColors.bg,
    textTheme: GoogleFonts.interTextTheme().copyWith(
      headlineLarge: GoogleFonts.inter(
        fontSize: 24, fontWeight: FontWeight.w700, color: AppColors.ink,
      ),
      headlineMedium: GoogleFonts.inter(
        fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.ink,
      ),
      titleLarge: GoogleFonts.inter(
        fontSize: 16, fontWeight: FontWeight.w700, color: AppColors.ink,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 14, fontWeight: FontWeight.w600, color: AppColors.ink2,
      ),
      bodyMedium: GoogleFonts.inter(
        fontSize: 13, fontWeight: FontWeight.w400, color: AppColors.ink2,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 11, fontWeight: FontWeight.w400, color: AppColors.muted,
      ),
      labelSmall: GoogleFonts.inter(
        fontSize: 10, fontWeight: FontWeight.w600,
        color: AppColors.muted, letterSpacing: 0.5,
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.bg,
      foregroundColor: AppColors.ink,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.red,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.ink,
        side: const BorderSide(color: AppColors.border, width: 1.5),
        minimumSize: const Size(double.infinity, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
        textStyle: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.bg2,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: const BorderSide(color: AppColors.red, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    cardTheme: CardThemeData(
      color: AppColors.bg,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, thickness: 1),
    bottomNavigationBarTheme: const BottomNavigationBarThemeData(
      backgroundColor: AppColors.bg,
      selectedItemColor: AppColors.red,
      unselectedItemColor: AppColors.muted,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
  );

  static Color levelColor(String level) {
    switch (level.toUpperCase()) {
      case 'N5': return AppColors.n5Color;
      case 'N4': return AppColors.n4Color;
      case 'N3': return AppColors.n3Color;
      case 'N2': return AppColors.n2Color;
      case 'N1': return AppColors.n1Color;
      default:   return AppColors.red;
    }
  }
}
