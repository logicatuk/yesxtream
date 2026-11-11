import 'package:flutter/material.dart';

typedef ClubTiviTheme = YesXtreamTheme;

/// YesXtream dark theme — optimized for TV & desktop viewing (OLED-friendly, high contrast).
class YesXtreamTheme {
  static const _accent = Color(0xFF6C5CE7);
  static const _surface = Color(0xFF0A0A0F);
  static const _card = Color(0xFF1A1A2E);

  /// Returns a TV-scaled ThemeData for LG webOS, Samsung Tizen, and Android TV.
  /// All font sizes, icon sizes, and minimum touch targets are multiplied by [scale].
  static ThemeData scaled(double scale) => _buildTheme(scale);

  static ThemeData get dark => _buildTheme(1.0);

  static ThemeData _buildTheme(double scale) {
    // Helper to scale a size, keeping it ≥ original
    double s(double v) => scale > 1.0 ? (v * scale).roundToDouble() : v;

    return ThemeData(
      brightness: Brightness.dark,
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _accent,
        brightness: Brightness.dark,
        surface: _surface,
        onSurface: Colors.white,
      ),
      scaffoldBackgroundColor: _surface,
      cardTheme: const CardThemeData(
        color: _card,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
      ),
      // Focus highlight for D-pad / remote navigation
      focusColor: _accent.withValues(alpha: 0.45),
      hoverColor: _accent.withValues(alpha: 0.1),
      // ListTile focus/hover styling
      listTileTheme: ListTileThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        selectedTileColor: _accent.withValues(alpha: 0.2),
        minVerticalPadding: scale > 1.0 ? 16 : 4,
      ),
      // Filled button focus styling — larger minimum size on TV
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: Size(s(64), s(48)),
          backgroundColor: _accent,
          foregroundColor: Colors.white,
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: Colors.white, width: scale > 1.0 ? 3 : 2);
            }
            return null;
          }),
        ),
      ),
      // Text button focus styling
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: Size(s(64), s(48)),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: _accent, width: scale > 1.0 ? 3 : 2);
            }
            return null;
          }),
        ),
      ),
      // Icon button focus styling
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: Size(s(48), s(48)),
        ).copyWith(
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return BorderSide(color: _accent, width: scale > 1.0 ? 3 : 2);
            }
            return null;
          }),
        ),
      ),
      // FloatingActionButton styling
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        focusColor: _accent.withValues(alpha: 0.8),
        focusElevation: 8,
      ),
      // Switch styling for settings
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return _accent;
          return Colors.white54;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return _accent.withValues(alpha: 0.4);
          }
          return Colors.white12;
        }),
        overlayColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.focused)) {
            return _accent.withValues(alpha: 0.2);
          }
          return null;
        }),
      ),
      // Input decoration for text fields
      inputDecorationTheme: InputDecorationTheme(
        border: const OutlineInputBorder(),
        focusedBorder: OutlineInputBorder(
          borderSide: BorderSide(color: _accent, width: scale > 1.0 ? 3 : 2),
          borderRadius: BorderRadius.circular(8),
        ),
        contentPadding: EdgeInsets.symmetric(
          horizontal: s(16),
          vertical: s(14),
        ),
      ),
      // Tab bar styling
      tabBarTheme: const TabBarThemeData(
        indicatorColor: _accent,
        labelColor: _accent,
        unselectedLabelColor: Colors.white54,
      ),
      textTheme: TextTheme(
        headlineLarge: TextStyle(
          fontSize: s(28),
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
        headlineMedium: TextStyle(
          fontSize: s(22),
          fontWeight: FontWeight.w600,
          color: Colors.white,
        ),
        bodyLarge: TextStyle(
          fontSize: s(16),
          color: Colors.white70,
        ),
        bodyMedium: TextStyle(
          fontSize: s(14),
          color: Colors.white60,
        ),
      ),
    );
  }
}
