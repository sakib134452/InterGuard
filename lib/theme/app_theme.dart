import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppColors {
  // Primary palette — dark midnight blue + cyan
  static const Color background = Color(0xFF050D1A);
  static const Color surface = Color(0xFF0D1E35);
  static const Color surfaceElevated = Color(0xFF132840);
  static const Color card = Color(0xFF0F2238);
  static const Color cardBorder = Color(0xFF1A3A5C);

  static const Color cyan = Color(0xFF00D4FF);
  static const Color cyanDim = Color(0xFF0097B5);
  static const Color cyanGlow = Color(0x3300D4FF);
  static const Color cyanFaint = Color(0x1100D4FF);

  static const Color green = Color(0xFF00E676);
  static const Color greenGlow = Color(0x3300E676);
  static const Color greenDim = Color(0xFF00994F);

  static const Color red = Color(0xFFFF4D6D);
  static const Color redGlow = Color(0x33FF4D6D);
  static const Color redDim = Color(0xFFB5354F);

  static const Color textPrimary = Color(0xFFE8F0FE);
  static const Color textSecondary = Color(0xFF7B9BC0);
  static const Color textMuted = Color(0xFF3D5875);
  static const Color textOnAccent = Color(0xFF050D1A);

  static const Color divider = Color(0xFF1A3A5C);
  static const Color toggleTrackOff = Color(0xFF1A2E47);
  static const Color navBar = Color(0xFF0A1929);
  static const Color navBarBorder = Color(0xFF1A3A5C);
}

class AppTheme {
  static ThemeData get dark {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.cyan,
        secondary: AppColors.cyanDim,
        surface: AppColors.surface,
        error: AppColors.red,
        onPrimary: AppColors.textOnAccent,
        onSurface: AppColors.textPrimary,
      ),
      textTheme: GoogleFonts.interTextTheme(
        const TextTheme(
          displayLarge: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          displayMedium: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          headlineLarge: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w700),
          headlineMedium: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          headlineSmall: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          titleLarge: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600),
          titleMedium: TextStyle(
              color: AppColors.textSecondary, fontWeight: FontWeight.w500),
          bodyLarge: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w400),
          bodyMedium: TextStyle(
              color: AppColors.textSecondary, fontWeight: FontWeight.w400),
          labelLarge: TextStyle(
              color: AppColors.textPrimary, fontWeight: FontWeight.w600),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.background,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: GoogleFonts.inter(
          color: AppColors.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.navBar,
        indicatorColor: AppColors.cyanFaint,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: AppColors.cyan, size: 24);
          }
          return const IconThemeData(color: AppColors.textMuted, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return GoogleFonts.inter(
                color: AppColors.cyan,
                fontSize: 11,
                fontWeight: FontWeight.w600);
          }
          return GoogleFonts.inter(
              color: AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w400);
        }),
      ),
      cardTheme: CardThemeData(
        color: AppColors.card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.cardBorder, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceElevated,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cardBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.cyan, width: 1.5),
        ),
        labelStyle:
            GoogleFonts.inter(color: AppColors.textSecondary, fontSize: 14),
        hintStyle:
            GoogleFonts.inter(color: AppColors.textMuted, fontSize: 14),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.cyan;
          return AppColors.textMuted;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.cyanDim.withOpacity(0.4);
          }
          return AppColors.toggleTrackOff;
        }),
      ),
      dividerTheme: const DividerThemeData(
        color: AppColors.divider,
        thickness: 1,
        space: 1,
      ),
    );
  }
}
