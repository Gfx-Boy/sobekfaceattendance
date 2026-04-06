import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class AppTheme {
  // ── Dark palette ──────────────────────────────────────────────
  static const Color scaffoldBg = Color(0xFF0D1117);
  static const Color cardBg = Color(0xFF161B22);
  static const Color cardBgLighter = Color(0xFF1C2333);
  static const Color surfaceBorder = Color(0xFF2A3140);

  // Accent colours
  static const Color primaryBlue = Color(0xFF3B82F6);
  static const Color primaryBlueDark = Color(0xFF2563EB);
  static const Color accentGreen = Color(0xFF10B981);
  static const Color checkOutRed = Color(0xFFEF4444);
  static const Color checkOutPink = Color(0xFFF87171);
  static const Color warningAmber = Color(0xFFF59E0B);

  // Text
  static const Color textPrimary = Color(0xFFE6EDF3);
  static const Color textSecondary = Color(0xFF8B949E);
  static const Color textMuted = Color(0xFF545D68);

  // Nav
  static const Color navBg = Color(0xFF0D1117);
  static const Color navActive = Color(0xFFE6EDF3);
  static const Color navInactive = Color(0xFF545D68);

  // Elevated home button
  static const Color homeButtonBg = Color(0xFF21262D);

  // ── Light palette ────────────────────────────────────────────
  static const Color lightScaffoldBg = Color(0xFFF1F5F9);
  static const Color lightCardBg = Color(0xFFFFFFFF);
  static const Color lightCardBgLighter = Color(0xFFF8FAFC);
  static const Color lightSurfaceBorder = Color(0xFFE2E8F0);
  static const Color lightTextPrimary = Color(0xFF0F172A);
  static const Color lightTextSecondary = Color(0xFF475569);
  static const Color lightTextMuted = Color(0xFF94A3B8);
  static const Color lightNavBg = Color(0xFFFFFFFF);
  static const Color lightHomeButtonBg = Color(0xFFF1F5F9);

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: scaffoldBg,
      colorScheme: const ColorScheme.dark(
        primary: primaryBlue,
        secondary: accentGreen,
        surface: cardBg,
        error: checkOutRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: textPrimary,
        onError: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: scaffoldBg,
        foregroundColor: textPrimary,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        titleTextStyle: TextStyle(
          color: textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: textPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: textPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: surfaceBorder),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: surfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: surfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: textMuted),
        labelStyle: const TextStyle(color: textSecondary),
      ),
      cardTheme: CardThemeData(
        color: cardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: surfaceBorder, width: 0.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: surfaceBorder,
        thickness: 0.5,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: navBg,
        selectedItemColor: navActive,
        unselectedItemColor: navInactive,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        elevation: 0,
      ),
    );
  }

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightScaffoldBg,
      colorScheme: const ColorScheme.light(
        primary: primaryBlue,
        secondary: accentGreen,
        surface: lightCardBg,
        error: checkOutRed,
        onPrimary: Colors.white,
        onSecondary: Colors.white,
        onSurface: lightTextPrimary,
        onError: Colors.white,
        outline: lightSurfaceBorder,
        outlineVariant: lightSurfaceBorder,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: lightScaffoldBg,
        foregroundColor: lightTextPrimary,
        elevation: 0,
        centerTitle: true,
        systemOverlayStyle: SystemUiOverlayStyle.dark,
        titleTextStyle: TextStyle(
          color: lightTextPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: lightTextPrimary),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primaryBlue,
          foregroundColor: Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          elevation: 0,
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: lightTextPrimary,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          side: const BorderSide(color: lightSurfaceBorder),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightCardBg,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightSurfaceBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: lightSurfaceBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: primaryBlue, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 16,
        ),
        hintStyle: const TextStyle(color: lightTextMuted),
        labelStyle: const TextStyle(color: lightTextSecondary),
      ),
      cardTheme: CardThemeData(
        color: lightCardBg,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: lightSurfaceBorder, width: 0.5),
        ),
      ),
      dividerTheme: const DividerThemeData(
        color: lightSurfaceBorder,
        thickness: 0.5,
      ),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: lightNavBg,
        selectedItemColor: lightTextPrimary,
        unselectedItemColor: lightTextMuted,
        type: BottomNavigationBarType.fixed,
        showSelectedLabels: false,
        showUnselectedLabels: false,
        elevation: 0,
      ),
    );
  }
}

/// A set of theme-aware colors derived from the current [BuildContext].
/// Usage: `context.colors.textPrimary`, `context.colors.cardBg`, etc.
class AppColors {
  final bool isDark;
  const AppColors(this.isDark);

  Color get textPrimary => isDark ? AppTheme.textPrimary : AppTheme.lightTextPrimary;
  Color get textSecondary => isDark ? AppTheme.textSecondary : AppTheme.lightTextSecondary;
  Color get textMuted => isDark ? AppTheme.textMuted : AppTheme.lightTextMuted;
  Color get cardBg => isDark ? AppTheme.cardBg : AppTheme.lightCardBg;
  Color get cardBgLighter => isDark ? AppTheme.cardBgLighter : AppTheme.lightCardBgLighter;
  Color get surfaceBorder => isDark ? AppTheme.surfaceBorder : AppTheme.lightSurfaceBorder;
  Color get scaffoldBg => isDark ? AppTheme.scaffoldBg : AppTheme.lightScaffoldBg;
  Color get homeButtonBg => isDark ? AppTheme.homeButtonBg : AppTheme.lightHomeButtonBg;
  Color get navBg => isDark ? AppTheme.navBg : AppTheme.lightNavBg;

  // Brand colours stay the same in both modes
  Color get primaryBlue => AppTheme.primaryBlue;
  Color get accentGreen => AppTheme.accentGreen;
  Color get checkOutRed => AppTheme.checkOutRed;
  Color get warningAmber => AppTheme.warningAmber;
}

extension AppColorsContext on BuildContext {
  AppColors get colors => AppColors(Theme.of(this).brightness == Brightness.dark);
}
