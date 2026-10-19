/// Premium agricultural design system.
library;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  static const Color forest = Color(0xFF12382A);
  static const Color pine = Color(0xFF1F6B4A);
  static const Color leaf = Color(0xFF5FBF8A);
  static const Color leafLight = Color(0xFF9DDEC0);
  static const Color sage = Color(0xFFD7EDE2);
  static const Color cream = Color(0xFFF4F1E8);
  static const Color parchment = Color(0xFFFAF8F2);
  static const Color soil = Color(0xFF8A6A52);
  static const Color sky = Color(0xFF3B82C4);
  static const Color ai = Color(0xFF2F6FED);
  static const Color amber = Color(0xFFD4922A);
  static const Color danger = Color(0xFFB42318);
  static const Color ink = Color(0xFF1C2A24);
  static const Color muted = Color(0xFF6B7A73);
  static const Color line = Color(0xFFE4E8E3);

  static Color riskColor(String level) {
    switch (level.toUpperCase()) {
      case 'LOW':
      case 'NONE':
      case 'NORMAL':
      case 'GOOD':
        return pine;
      case 'MEDIUM':
      case 'MODERATE':
      case 'FAIR':
      case 'ATTENTION':
        return amber;
      case 'HIGH':
      case 'AT RISK':
        return const Color(0xFFC45C12);
      case 'CRITICAL':
        return danger;
      default:
        return muted;
    }
  }

  static String riskWord(String level) {
    switch (level.toUpperCase()) {
      case 'LOW':
        return 'LOW';
      case 'MEDIUM':
        return 'MODERATE';
      case 'HIGH':
        return 'HIGH';
      case 'CRITICAL':
        return 'CRITICAL';
      default:
        return level.toUpperCase();
    }
  }
}

class Spacing {
  static const double xs = 6, sm = 10, md = 16, lg = 24, xl = 32;
  /// One corner system: 16 for cards/surfaces, 8 for small badges.
  static const double radius = 16;
  static const double badge = 8;
  static EdgeInsets get page => const EdgeInsets.fromLTRB(16, 8, 16, 24);
}

class AppShadows {
  static List<BoxShadow> get card => const [
        BoxShadow(
          color: Color(0x140F241C),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ];
}

class AppTheme {
  /// Manrope covers Latin only; Hindi/Telugu text falls back through these
  /// system fonts so glyphs render natively instead of silently switching
  /// widgets to the default font (mixed look in HI/TE).
  static const _multilingualFallbacks = <String>[
    'Noto Sans Telugu',
    'Noto Sans Devanagari',
    'sans-serif',
  ];

  static ThemeData get light {
    final base = ThemeData.light(useMaterial3: true);
    final text = GoogleFonts.manropeTextTheme(base.textTheme).apply(
      bodyColor: AppColors.ink,
      displayColor: AppColors.forest,
      fontFamilyFallback: _multilingualFallbacks,
    );
    return base.copyWith(
      scaffoldBackgroundColor: AppColors.cream,
      textTheme: text,
      colorScheme: const ColorScheme.light(
        primary: AppColors.pine,
        secondary: AppColors.leaf,
        surface: Colors.white,
        error: AppColors.danger,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.cream,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: AppColors.forest),
        titleTextStyle: GoogleFonts.manrope(
          color: AppColors.forest,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ).apply(fontFamilyFallback: _multilingualFallbacks),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        indicatorColor: AppColors.sage,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (s) => TextStyle(
            fontWeight:
                s.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
            fontSize: 12,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.forest,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(54),
          elevation: 0,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.forest,
          minimumSize: const Size.fromHeight(48),
          side: const BorderSide(color: AppColors.line),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    );
  }
}
