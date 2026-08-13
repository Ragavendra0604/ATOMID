import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  // Premium Dark Colors
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color primaryDark = Color(0xFFD4AF37); // Premium Gold
  static const Color onPrimaryDark = Colors.black;

  // Premium Light Colors
  static const Color backgroundLight = Color(0xFFF5F5F7);
  static const Color surfaceLight = Colors.white;
  static const Color primaryLight = Color(0xFFD4AF37); // Premium Gold
  static const Color onPrimaryLight = Colors.black;

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      // Seeded from the brand gold so the roles this app never sets by hand —
      // containers, tertiary, outline — are derived from it too. Setting only
      // four roles left the rest on Material's purple-derived baseline, which
      // is why accents read as off-brand. The anchors below are pinned so the
      // established surface and primary are unchanged.
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: primaryDark,
            brightness: Brightness.dark,
          ).copyWith(
            surface: surfaceDark,
            primary: primaryDark,
            onPrimary: onPrimaryDark,
          ),
      scaffoldBackgroundColor: backgroundDark,
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundDark,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      cardTheme: CardThemeData(
        color: surfaceDark,
        elevation: 4,
        shadowColor: Colors.black45,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.dark().textTheme),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryDark,
          foregroundColor: onPrimaryDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceDark,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryDark, width: 2),
        ),
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: primaryLight,
            brightness: Brightness.light,
          ).copyWith(
            surface: surfaceLight,
            primary: primaryLight,
            onPrimary: onPrimaryLight,
          ),
      scaffoldBackgroundColor: backgroundLight,
      appBarTheme: AppBarTheme(
        backgroundColor: backgroundLight,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.outfit(
          fontSize: 20,
          fontWeight: FontWeight.w600,
          color: Colors.black,
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      cardTheme: CardThemeData(
        color: surfaceLight,
        elevation: 4,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryLight,
          foregroundColor: onPrimaryLight,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceLight,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryLight, width: 2),
        ),
      ),
    );
  }
}
