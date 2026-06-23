import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Deep indigo + warm gold: a premium, gift-giving feel without leaning on
/// literal Christmas red/green. Playfair Display for headings keeps things
/// elegant; Inter for body text keeps it readable at small sizes.
class AppTheme {
  static const _indigo = Color(0xFF1B1F3B);
  static const _gold = Color(0xFFC9A24B);
  static const _cream = Color(0xFFFBF7EF);

  static ThemeData get light {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _indigo,
      primary: _indigo,
      secondary: _gold,
      surface: _cream,
      brightness: Brightness.light,
    );

    final base = ThemeData(colorScheme: colorScheme, useMaterial3: true);
    final headingFont = GoogleFonts.playfairDisplayTextTheme(base.textTheme);
    final bodyFont = GoogleFonts.interTextTheme(base.textTheme);

    final textTheme = bodyFont.copyWith(
      displayLarge: headingFont.displayLarge,
      displayMedium: headingFont.displayMedium,
      displaySmall: headingFont.displaySmall,
      headlineLarge: headingFont.headlineLarge,
      headlineMedium: headingFont.headlineMedium,
      headlineSmall: headingFont.headlineSmall,
      titleLarge: headingFont.titleLarge,
    );

    return base.copyWith(
      scaffoldBackgroundColor: _cream,
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        backgroundColor: _cream,
        foregroundColor: _indigo,
        elevation: 0,
        titleTextStyle: headingFont.titleLarge?.copyWith(color: _indigo),
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: Color(0x22C9A24B)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: _indigo,
          foregroundColor: _gold,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _indigo,
          side: const BorderSide(color: _gold, width: 1.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        focusedBorder: const UnderlineInputBorder(
          borderSide: BorderSide(color: _gold, width: 2),
        ),
        labelStyle: const TextStyle(color: _indigo),
      ),
      iconTheme: const IconThemeData(color: _gold),
      colorScheme: colorScheme,
    );
  }
}
