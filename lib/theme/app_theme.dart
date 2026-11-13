import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppPalette {
  static const Color ink = Color(0xFF13273D);
  static const Color deepBlue = Color(0xFF1E5E9D);
  static const Color aqua = Color(0xFF19C5B6);
  static const Color sand = Color(0xFFFFF8EE);
  static const Color rose = Color(0xFFFF6B6B);
}

class AppTheme {
  static ThemeData light() {
    final textTheme = TextTheme(
      displayLarge: GoogleFonts.sora(fontWeight: FontWeight.w700),
      displayMedium: GoogleFonts.sora(fontWeight: FontWeight.w700),
      displaySmall: GoogleFonts.sora(fontWeight: FontWeight.w700),
      headlineMedium: GoogleFonts.sora(fontWeight: FontWeight.w700),
      titleLarge: GoogleFonts.sora(fontWeight: FontWeight.w600),
      bodyLarge: GoogleFonts.dmSans(fontWeight: FontWeight.w500),
      bodyMedium: GoogleFonts.dmSans(fontWeight: FontWeight.w500),
      labelLarge: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
    );

    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: AppPalette.sand,
      textTheme: textTheme,
      colorScheme: const ColorScheme.light(
        primary: AppPalette.deepBlue,
        secondary: AppPalette.aqua,
        surface: Colors.white,
        error: AppPalette.rose,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD9E2EC)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: Color(0xFFD9E2EC)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: AppPalette.deepBlue, width: 1.5),
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
        color: Colors.white,
      ),
    );
  }
}
