import 'package:flutter/material.dart';
import '../constants/typography.dart';
import '../utils/adaptive_page_route.dart';

/// Material Design 3 (MD3) Android Theme
///
/// Implements Google's Material 3 & M3 Expressive design tokens, adaptive tonal surfaces,
/// 15-scale typography, standard/expressive corner radii, and comprehensive component theming.
class AndroidTheme {
  /// Default seed color for Material You ColorScheme generation
  static const Color fallbackSeed = Color(0xFF006C4C);

  /// MD3 Shape Tokens
  static const double shapeCornerNone = 0.0;
  static const double shapeCornerExtraSmall = 4.0;
  static const double shapeCornerSmall = 8.0;
  static const double shapeCornerMedium = 12.0;
  static const double shapeCornerLarge = 16.0;
  static const double shapeCornerLargeIncreased = 20.0;
  static const double shapeCornerExtraLarge = 28.0;
  static const double shapeCornerExtraLargeIncreased = 32.0;
  static const double shapeCornerExtraExtraLarge = 48.0;
  static const double shapeCornerFull = 9999.0;

  /// Returns the configured [ThemeData] matching MD3 specifications.
  static ThemeData getTheme({
    ColorScheme? dynamicColorScheme,
    Brightness brightness = Brightness.light,
  }) {
    // Generate base color scheme from dynamic Wallpaper seed or fallback seed
    final ColorScheme rawScheme = dynamicColorScheme ??
        ColorScheme.fromSeed(
          seedColor: fallbackSeed,
          brightness: brightness,
        );

    final bool isDark = rawScheme.brightness == Brightness.dark;

    final ColorScheme scheme;
    if (!isDark) {
      // Light Mode: Apply chromatic subtle tonal elevation to surface container levels
      // with adaptive colors (looks rich, warm, and adaptive).
      final Color tintedSurfaceLowest = Color.alphaBlend(
        rawScheme.primary.withValues(alpha: 0.02),
        rawScheme.surfaceContainerLowest,
      );
      final Color tintedSurfaceLow = Color.alphaBlend(
        rawScheme.primary.withValues(alpha: 0.04),
        rawScheme.surfaceContainerLow,
      );
      final Color tintedSurfaceContainer = Color.alphaBlend(
        rawScheme.primary.withValues(alpha: 0.06),
        rawScheme.surfaceContainer,
      );
      final Color tintedSurfaceContainerHigh = Color.alphaBlend(
        rawScheme.primary.withValues(alpha: 0.08),
        rawScheme.surfaceContainerHigh,
      );
      final Color tintedSurfaceContainerHighest = Color.alphaBlend(
        rawScheme.primary.withValues(alpha: 0.10),
        rawScheme.surfaceContainerHighest,
      );

      scheme = rawScheme.copyWith(
        surfaceContainerLowest: tintedSurfaceLowest,
        surfaceContainerLow: tintedSurfaceLow,
        surfaceContainer: tintedSurfaceContainer,
        surfaceContainerHigh: tintedSurfaceContainerHigh,
        surfaceContainerHighest: tintedSurfaceContainerHighest,
        surface: tintedSurfaceLow,
      );
    } else {
      // Dark Mode: Pure black background (true dark / AMOLED) with clean neutral dark surfaces.
      // Retains the themed color (primary, secondary, indicators, pills, accents) where needed,
      // without dark adaptive tinted background.
      scheme = rawScheme.copyWith(
        surface: const Color(0xFF000000),
        surfaceDim: const Color(0xFF000000),
        surfaceContainerLowest: const Color(0xFF000000),
        surfaceContainerLow: const Color(0xFF0A0A0A),
        surfaceContainer: const Color(0xFF141414),
        surfaceContainerHigh: const Color(0xFF1E1E1E),
        surfaceContainerHighest: const Color(0xFF282828),
        surfaceBright: const Color(0xFF323232),
        secondaryContainer: const Color(0xFF242424),
        onSecondaryContainer: const Color(0xFFF4F4F5),
        outlineVariant: const Color(0xFF27272A),
        onSurface: const Color(0xFFF4F4F5),
        onSurfaceVariant: const Color(0xFFA1A1AA),
      );
    }

    return ThemeData(
      useMaterial3: true,
      brightness: scheme.brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: isDark ? const Color(0xFF000000) : scheme.surfaceContainerLow,
      canvasColor: isDark ? const Color(0xFF000000) : scheme.surfaceContainerLow,

      // --- MD3 15-Scale Typography ---
      textTheme: TextTheme(
        displayLarge: AppTypography.displayLarge.copyWith(color: scheme.onSurface),
        displayMedium: AppTypography.displayMedium.copyWith(color: scheme.onSurface),
        displaySmall: AppTypography.displaySmall.copyWith(color: scheme.onSurface),
        headlineLarge: AppTypography.headlineLarge.copyWith(color: scheme.onSurface),
        headlineMedium: AppTypography.headlineMedium.copyWith(color: scheme.onSurface),
        headlineSmall: AppTypography.headlineSmall.copyWith(color: scheme.onSurface),
        titleLarge: AppTypography.titleLarge.copyWith(color: scheme.onSurface),
        titleMedium: AppTypography.titleMedium.copyWith(color: scheme.onSurface),
        titleSmall: AppTypography.titleSmall.copyWith(color: scheme.onSurface),
        bodyLarge: AppTypography.bodyLarge.copyWith(color: scheme.onSurface),
        bodyMedium: AppTypography.bodyMedium.copyWith(color: scheme.onSurface),
        bodySmall: AppTypography.bodySmall.copyWith(color: scheme.onSurfaceVariant),
        labelLarge: AppTypography.labelLarge.copyWith(color: scheme.onSurface),
        labelMedium: AppTypography.labelMedium.copyWith(color: scheme.onSurfaceVariant),
        labelSmall: AppTypography.labelSmall.copyWith(color: scheme.onSurfaceVariant),
      ),

      // --- Icon Themes: MD3 Adaptive Scheme ---
      iconTheme: IconThemeData(
        color: scheme.onSurface,
        size: 24,
      ),
      primaryIconTheme: IconThemeData(
        color: scheme.primary,
        size: 24,
      ),

      // --- App Bar: MD3 Tonal Surface (Level 0 resting, Level 2 scrolled) ---
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? const Color(0xFF000000) : scheme.surfaceContainerLow,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: isDark ? 0.0 : 2.0,
        surfaceTintColor: isDark ? Colors.transparent : scheme.surfaceTint,
        centerTitle: false,
        titleTextStyle: AppTypography.titleLarge.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 24),
        actionsIconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 24),
      ),

      // --- Card Theme: MD3 Outlined & Tonal Container (Level 0/1) ---
      cardTheme: CardThemeData(
        elevation: isDark ? 0 : 2,
        shadowColor: isDark ? Colors.transparent : Colors.black.withValues(alpha: 0.08),
        color: scheme.surfaceContainer,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeCornerExtraLarge),
          side: BorderSide(
            color: isDark ? const Color(0xFF27272A) : scheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
      ),

      // --- Floating Action Button: MD3 Large (16dp) / Expressive (20dp) ---
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primaryContainer,
        foregroundColor: scheme.onPrimaryContainer,
        elevation: 2,
        focusElevation: 6,
        hoverElevation: 6,
        highlightElevation: 6,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeCornerLargeIncreased),
        ),
      ),

      // --- Buttons: MD3 Full Stadium / Expressive Shapes ---
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          elevation: 0,
          backgroundColor: scheme.primary,
          foregroundColor: scheme.onPrimary,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
          minimumSize: const Size(64, 44),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 1,
          backgroundColor: scheme.surfaceContainerLow,
          foregroundColor: scheme.primary,
          surfaceTintColor: scheme.surfaceTint,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          textStyle: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
          minimumSize: const Size(64, 44),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: isDark ? 0.5 : 0.8),
            width: 1,
          ),
          foregroundColor: scheme.primary,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          textStyle: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
          minimumSize: const Size(64, 44),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.primary,
          shape: const StadiumBorder(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          textStyle: AppTypography.labelLarge.copyWith(fontWeight: FontWeight.w600),
          minimumSize: const Size(48, 40),
        ),
      ),

      // --- Navigation Bar: MD3 Height 80dp, Pill Indicator ---
      navigationBarTheme: NavigationBarThemeData(
        height: 80,
        backgroundColor: isDark ? const Color(0xFF000000) : scheme.surfaceContainer,
        surfaceTintColor: isDark ? Colors.transparent : scheme.surfaceTint,
        elevation: 0,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppTypography.labelMedium.copyWith(
              color: isDark ? scheme.primary : scheme.onSurface,
              fontWeight: FontWeight.w700,
            );
          }
          return AppTypography.labelMedium.copyWith(
            color: scheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(
              size: 24,
              color: scheme.onSecondaryContainer,
            );
          }
          return IconThemeData(
            size: 24,
            color: scheme.onSurfaceVariant,
          );
        }),
      ),

      // --- Navigation Drawer ---
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: isDark ? const Color(0xFF000000) : scheme.surfaceContainerLow,
        surfaceTintColor: isDark ? Colors.transparent : scheme.surfaceTint,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        elevation: 0,
      ),

      // --- Navigation Rail ---
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: isDark ? const Color(0xFF000000) : scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        indicatorShape: const StadiumBorder(),
        elevation: 0,
        labelType: NavigationRailLabelType.all,
        unselectedLabelTextStyle: AppTypography.labelMedium.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        selectedLabelTextStyle: AppTypography.labelMedium.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w700,
        ),
      ),

      // --- Input Decoration: MD3 Form Inputs ---
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? const Color(0xFF161616) : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeCornerMedium),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF27272A) : scheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeCornerMedium),
          borderSide: BorderSide(
            color: isDark ? const Color(0xFF27272A) : scheme.outlineVariant.withValues(alpha: 0.6),
            width: 1,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeCornerMedium),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeCornerMedium),
          borderSide: BorderSide(color: scheme.error, width: 1.5),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(shapeCornerMedium),
          borderSide: BorderSide(color: scheme.error, width: 2),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        labelStyle: AppTypography.bodyMedium.copyWith(color: scheme.onSurfaceVariant),
        floatingLabelStyle: AppTypography.bodySmall.copyWith(
          color: scheme.primary,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: AppTypography.bodyMedium.copyWith(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
      ),

      // --- Dialog Theme: MD3 Extra-Large (28dp) ---
      dialogTheme: DialogThemeData(
        backgroundColor: isDark ? const Color(0xFF161616) : scheme.surfaceContainerHigh,
        surfaceTintColor: isDark ? Colors.transparent : scheme.surfaceTint,
        elevation: isDark ? 0 : 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeCornerExtraLarge),
          side: isDark
              ? const BorderSide(
                  color: Color(0xFF27272A),
                  width: 1,
                )
              : BorderSide.none,
        ),
        titleTextStyle: AppTypography.headlineSmall.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w600,
        ),
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: scheme.onSurfaceVariant,
        ),
      ),

      // --- Bottom Sheet Theme: MD3 Extra-Large Top Corners (28dp / 32dp) ---
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? const Color(0xFF141414) : scheme.surfaceContainerLow,
        modalBackgroundColor: isDark ? const Color(0xFF141414) : scheme.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        showDragHandle: false,
        dragHandleColor: scheme.onSurfaceVariant.withValues(alpha: 0.4),
        dragHandleSize: const Size(32, 4),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(shapeCornerExtraLarge),
          ),
        ),
      ),

      // --- Search Bar Theme: MD3 Stadium Shape ---
      searchBarTheme: SearchBarThemeData(
        elevation: WidgetStateProperty.all(0),
        backgroundColor: WidgetStateProperty.all(
          isDark ? const Color(0xFF161616) : scheme.surfaceContainerHigh,
        ),
        surfaceTintColor: WidgetStateProperty.all(isDark ? Colors.transparent : scheme.surfaceTint),
        shape: WidgetStateProperty.all(const StadiumBorder()),
        hintStyle: WidgetStateProperty.all(
          AppTypography.bodyMedium.copyWith(color: scheme.onSurfaceVariant),
        ),
        textStyle: WidgetStateProperty.all(
          AppTypography.bodyMedium.copyWith(color: scheme.onSurface),
        ),
      ),

      // --- Segmented Button Theme ---
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: ButtonStyle(
          shape: WidgetStateProperty.all(const StadiumBorder()),
          side: WidgetStateProperty.resolveWith((states) {
            return BorderSide(
              color: scheme.outlineVariant.withValues(alpha: isDark ? 0.35 : 0.6),
              width: 1,
            );
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.secondaryContainer;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return scheme.onSecondaryContainer;
            }
            return scheme.onSurface;
          }),
        ),
      ),

      // --- Chip Theme: MD3 Shape & State Fills ---
      chipTheme: ChipThemeData(
        shape: const StadiumBorder(),
        backgroundColor: isDark ? const Color(0xFF141414) : scheme.surfaceContainerLow,
        selectedColor: scheme.secondaryContainer,
        disabledColor: scheme.onSurface.withValues(alpha: 0.12),
        surfaceTintColor: Colors.transparent,
        side: BorderSide(
          color: isDark ? const Color(0xFF27272A) : scheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
        labelStyle: AppTypography.labelLarge.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: AppTypography.labelLarge.copyWith(
          color: scheme.onSecondaryContainer,
        ),
        iconTheme: IconThemeData(color: scheme.primary, size: 18),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),

      // --- SnackBar Theme: MD3 Floating Inverted Surface ---
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: AppTypography.bodyMedium.copyWith(
          color: scheme.onInverseSurface,
        ),
        actionTextColor: scheme.inversePrimary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeCornerSmall),
        ),
        elevation: 3,
      ),

      // --- Checkbox Theme ---
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeCornerExtraSmall),
        ),
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return Colors.transparent;
        }),
        checkColor: WidgetStateProperty.all(scheme.onPrimary),
        side: BorderSide(color: scheme.outline, width: 2),
      ),

      // --- Radio Theme ---
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return scheme.onSurfaceVariant;
        }),
      ),

      // --- Switch Theme: MD3 Specification ---
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.onPrimary;
          }
          return scheme.outline;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return scheme.primary;
          }
          return scheme.surfaceContainerHighest;
        }),
        trackOutlineColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return Colors.transparent;
          }
          return scheme.outline;
        }),
      ),

      // --- Progress Indicator Theme ---
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHighest,
        circularTrackColor: scheme.surfaceContainerHighest,
      ),

      // --- Slider Theme ---
      sliderTheme: SliderThemeData(
        activeTrackColor: scheme.primary,
        inactiveTrackColor: scheme.surfaceContainerHighest,
        thumbColor: scheme.primary,
        overlayColor: scheme.primary.withValues(alpha: 0.12),
        trackHeight: 4,
      ),

      // --- Menu Theme & PopupMenuTheme ---
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStateProperty.all(
            isDark ? const Color(0xFF161616) : scheme.surfaceContainer,
          ),
          surfaceTintColor: WidgetStateProperty.all(isDark ? Colors.transparent : scheme.surfaceTint),
          elevation: WidgetStateProperty.all(2),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(shapeCornerMedium),
              side: isDark
                  ? const BorderSide(
                      color: Color(0xFF27272A),
                      width: 1,
                    )
                  : BorderSide.none,
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: isDark ? const Color(0xFF161616) : scheme.surfaceContainer,
        surfaceTintColor: isDark ? Colors.transparent : scheme.surfaceTint,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeCornerMedium),
          side: isDark
              ? const BorderSide(
                  color: Color(0xFF27272A),
                  width: 1,
                )
              : BorderSide.none,
        ),
        textStyle: AppTypography.bodyLarge.copyWith(color: scheme.onSurface),
      ),

      // --- List Tile Theme ---
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        titleTextStyle: AppTypography.bodyLarge.copyWith(
          color: scheme.onSurface,
          fontWeight: FontWeight.w500,
        ),
        subtitleTextStyle: AppTypography.bodyMedium.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        leadingAndTrailingTextStyle: AppTypography.labelMedium.copyWith(
          color: scheme.onSurfaceVariant,
        ),
        iconColor: scheme.onSurfaceVariant,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(shapeCornerMedium),
        ),
      ),

      // --- Divider Theme: Uses outlineVariant strictly ---
      dividerTheme: DividerThemeData(
        color: isDark ? const Color(0xFF27272A) : scheme.outlineVariant.withValues(alpha: 0.6),
        thickness: 1,
        space: 1,
      ),

      // --- Modern Android Predictive Back & Platform Transitions ---
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: EnhancedPredictiveBackPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: ZoomPageTransitionsBuilder(),
          TargetPlatform.linux: ZoomPageTransitionsBuilder(),
        },
      ),
    );
  }

  /// Convenience getters for light and dark themes
  static ThemeData getLight([ColorScheme? dynamicLight]) =>
      getTheme(dynamicColorScheme: dynamicLight, brightness: Brightness.light);

  static ThemeData getDark([ColorScheme? dynamicDark]) =>
      getTheme(dynamicColorScheme: dynamicDark, brightness: Brightness.dark);

  static ThemeData get lightTheme => getLight();
  static ThemeData get darkTheme => getDark();
}
