import 'package:flutter/material.dart';
import '../constants/typography.dart';

class AndroidTheme {
  static const Color fallbackSeed = Color(0xFF006C4C);

  static ThemeData getTheme({
    ColorScheme? dynamicColorScheme,
    Brightness brightness = Brightness.light,
  }) {
    // If Material You dynamic color scheme is provided from Android system, use it;
    // otherwise generate a cohesive Material 3 Expressive ColorScheme from seed.
    final ColorScheme scheme = dynamicColorScheme ??
        ColorScheme.fromSeed(
          seedColor: fallbackSeed,
          brightness: brightness,
        );

    final isDark = scheme.brightness == Brightness.dark;

    // Apply a distinct chromatic tint derived from the theme seed / primary color
    // to give pages and surfaces a signature tinted canvas instead of flat white or plain dark grey.
    final tintedSurfaceLowest = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.05 : 0.025),
      scheme.surfaceContainerLowest,
    );
    final tintedScaffoldBg = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.09 : 0.05),
      scheme.surfaceContainerLow,
    );
    final tintedSurfaceContainer = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.12 : 0.075),
      scheme.surfaceContainer,
    );
    final tintedSurfaceContainerHigh = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.16 : 0.10),
      scheme.surfaceContainerHigh,
    );
    final tintedSurfaceContainerHighest = Color.alphaBlend(
      scheme.primary.withValues(alpha: isDark ? 0.20 : 0.12),
      scheme.surfaceContainerHighest,
    );

    final effectiveScheme = scheme.copyWith(
      surfaceContainerLowest: tintedSurfaceLowest,
      surfaceContainerLow: tintedScaffoldBg,
      surfaceContainer: tintedSurfaceContainer,
      surfaceContainerHigh: tintedSurfaceContainerHigh,
      surfaceContainerHighest: tintedSurfaceContainerHighest,
      surface: tintedScaffoldBg,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: effectiveScheme.brightness,
      colorScheme: effectiveScheme,
      scaffoldBackgroundColor: effectiveScheme.surfaceContainerLow,
      
      // Expressive TextTheme
      textTheme: TextTheme(
        displayLarge: AppTypography.displayLarge.copyWith(color: effectiveScheme.onSurface),
        displayMedium: AppTypography.displayMedium.copyWith(color: effectiveScheme.onSurface),
        displaySmall: AppTypography.displaySmall.copyWith(color: effectiveScheme.onSurface),
        headlineLarge: AppTypography.headlineLarge.copyWith(color: effectiveScheme.onSurface),
        headlineMedium: AppTypography.headlineMedium.copyWith(color: effectiveScheme.onSurface),
        headlineSmall: AppTypography.headlineSmall.copyWith(color: effectiveScheme.onSurface),
        titleLarge: AppTypography.titleLarge.copyWith(color: effectiveScheme.onSurface),
        titleMedium: AppTypography.titleMedium.copyWith(color: effectiveScheme.onSurface),
        titleSmall: AppTypography.titleSmall.copyWith(color: effectiveScheme.onSurface),
        bodyLarge: AppTypography.bodyLarge.copyWith(color: effectiveScheme.onSurface),
        bodyMedium: AppTypography.bodyMedium.copyWith(color: effectiveScheme.onSurface),
        bodySmall: AppTypography.bodySmall.copyWith(color: effectiveScheme.onSurfaceVariant),
        labelLarge: AppTypography.labelLarge.copyWith(color: effectiveScheme.onSurface),
        labelMedium: AppTypography.labelMedium.copyWith(color: effectiveScheme.onSurfaceVariant),
        labelSmall: AppTypography.labelSmall.copyWith(color: effectiveScheme.onSurfaceVariant),
      ),

      // App Bar: Expressive M3 with surface scroll elevation
      appBarTheme: AppBarTheme(
        backgroundColor: effectiveScheme.surfaceContainerLow,
        foregroundColor: effectiveScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 2,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
          color: effectiveScheme.onSurface,
        ),
      ),

      // Card: Expressive 28dp Corner Radius & Elevated Surface Container
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
          side: BorderSide(
            color: effectiveScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
            width: 1,
          ),
        ),
        color: effectiveScheme.surfaceContainer,
        margin: EdgeInsets.zero,
      ),

      // Floating Action Button: Expressive Rounded Squircle (20dp) with M3E Elevation
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: effectiveScheme.primaryContainer,
        foregroundColor: effectiveScheme.onPrimaryContainer,
        elevation: 2,
        focusElevation: 4,
        hoverElevation: 4,
        highlightElevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
      ),

      // Navigation Bar: Expressive 80dp Pill Indicator
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: effectiveScheme.surfaceContainerHigh,
        indicatorColor: effectiveScheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.2,
              color: effectiveScheme.onSurface,
            );
          }
          return TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
            color: effectiveScheme.onSurfaceVariant,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              size: 24,
              color: effectiveScheme.onSecondaryContainer,
            );
          }
          return IconThemeData(
            size: 24,
            color: effectiveScheme.onSurfaceVariant,
          );
        }),
      ),

      // Input Decoration: Expressive Rounded Inputs (24dp)
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: effectiveScheme.surfaceContainerHighest.withValues(alpha: isDark ? 0.35 : 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(
            color: effectiveScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: effectiveScheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(24),
          borderSide: BorderSide(color: effectiveScheme.error, width: 1.5),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        labelStyle: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: effectiveScheme.onSurfaceVariant,
        ),
        floatingLabelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: effectiveScheme.primary,
        ),
      ),

      // Bottom Sheet: Expressive 32dp Top Corners
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Colors.transparent,
        modalBackgroundColor: Colors.transparent,
        showDragHandle: false,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
        ),
      ),

      // Dialog: Expressive 28dp Shape
      dialogTheme: DialogThemeData(
        backgroundColor: effectiveScheme.surfaceContainerHighest,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(28),
        ),
        titleTextStyle: TextStyle(
          fontSize: 20,
          fontWeight: FontWeight.w700,
          color: effectiveScheme.onSurface,
        ),
      ),

      // Buttons: Expressive Pill Shapes (24dp / Stadium)
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          backgroundColor: effectiveScheme.surfaceContainerLow,
          foregroundColor: effectiveScheme.primary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: effectiveScheme.primary,
          foregroundColor: effectiveScheme.onPrimary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: effectiveScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
            width: 1,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),

      // Segmented Button Theme
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      ),

      // Search Bar Theme: Expressive Pill Shape
      searchBarTheme: SearchBarThemeData(
        elevation: WidgetStateProperty.all(0),
        backgroundColor: WidgetStateProperty.all(effectiveScheme.surfaceContainerHigh),
        shape: WidgetStateProperty.all(const StadiumBorder()),
        hintStyle: WidgetStateProperty.all(
          TextStyle(color: effectiveScheme.onSurfaceVariant, fontSize: 14),
        ),
      ),

      // Chip Theme: Expressive Stadium Shape
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        backgroundColor: effectiveScheme.surfaceContainerHighest.withValues(alpha: 0.4),
        side: BorderSide(
          color: effectiveScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
          width: 1,
        ),
        labelStyle: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: effectiveScheme.onSurface,
        ),
      ),

      // SnackBar Theme: Expressive Floating Rounded
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
      ),

      // Divider Theme
      dividerTheme: DividerThemeData(
        color: effectiveScheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.5),
        thickness: 1,
        space: 1,
      ),

      // Page Transitions
      pageTransitionsTheme: PageTransitionsTheme(
        builders: {
          TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  static ThemeData getLight([ColorScheme? dynamicLight]) =>
      getTheme(dynamicColorScheme: dynamicLight, brightness: Brightness.light);

  static ThemeData getDark([ColorScheme? dynamicDark]) =>
      getTheme(dynamicColorScheme: dynamicDark, brightness: Brightness.dark);

  static ThemeData get lightTheme => getLight();
  static ThemeData get darkTheme => getDark();
}

