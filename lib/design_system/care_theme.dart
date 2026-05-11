import 'package:flutter/material.dart';

import 'care_colors.dart';

/// CareSignal theme factory for CareAgent light and dark modes.
abstract final class CareTheme {
  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: CareColors.brandPrimary,
          brightness: Brightness.light,
        ).copyWith(
          primary: CareColors.brandPrimary,
          onPrimary: Colors.white,
          primaryContainer: CareColors.brandPrimarySoft,
          onPrimaryContainer: CareColors.ink,
          secondary: CareColors.statusInfo,
          onSecondary: Colors.white,
          secondaryContainer: CareColors.surfaceSoft,
          onSecondaryContainer: CareColors.ink,
          tertiary: CareColors.statusSimulation,
          onTertiary: Colors.white,
          error: CareColors.statusUrgent,
          surface: CareColors.surface,
          onSurface: CareColors.textPrimary,
          outline: CareColors.borderSubtle,
        );

    return _base(
      scheme: scheme,
      scaffoldBackground: CareColors.canvas,
      surfaceSoft: CareColors.surfaceSoft,
      subtleBorder: CareColors.borderSubtle,
      textPrimary: CareColors.textPrimary,
      textSecondary: CareColors.textSecondary,
    );
  }

  static ThemeData dark() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: CareColors.brandPrimaryDark,
          brightness: Brightness.dark,
        ).copyWith(
          primary: CareColors.brandPrimaryDark,
          onPrimary: CareColors.canvasDark,
          primaryContainer: CareColors.brandPrimarySoftDark,
          onPrimaryContainer: CareColors.inkDark,
          secondary: CareColors.statusInfoDark,
          onSecondary: CareColors.canvasDark,
          secondaryContainer: CareColors.surfaceSoftDark,
          onSecondaryContainer: CareColors.inkDark,
          tertiary: CareColors.statusSimulationDark,
          onTertiary: CareColors.canvasDark,
          error: CareColors.statusUrgentDark,
          surface: CareColors.surfaceDark,
          onSurface: CareColors.textPrimaryDark,
          outline: CareColors.borderSubtleDark,
        );

    return _base(
      scheme: scheme,
      scaffoldBackground: CareColors.canvasDark,
      surfaceSoft: CareColors.surfaceSoftDark,
      subtleBorder: CareColors.borderSubtleDark,
      textPrimary: CareColors.textPrimaryDark,
      textSecondary: CareColors.textSecondaryDark,
    );
  }

  static ThemeData _base({
    required ColorScheme scheme,
    required Color scaffoldBackground,
    required Color surfaceSoft,
    required Color subtleBorder,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final textTheme = _textTheme(textPrimary, textSecondary);

    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      scaffoldBackgroundColor: scaffoldBackground,
      fontFamily: 'Nunito Sans',
      textTheme: textTheme,
      appBarTheme: AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: scaffoldBackground,
        foregroundColor: textPrimary,
        titleTextStyle: textTheme.titleMedium?.copyWith(
          color: textPrimary,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(8)),
          side: BorderSide(color: subtleBorder),
        ),
      ),
      dividerTheme: DividerThemeData(color: subtleBorder),
      navigationDrawerTheme: NavigationDrawerThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelLarge?.copyWith(
            color: selected ? scheme.primary : textPrimary,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceSoft,
        border: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: subtleBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: subtleBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: const BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(44, 44),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(44, 44),
          side: BorderSide(color: subtleBorder),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(44, 44),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.error,
        foregroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: Colors.white),
      ),
    );
  }

  static TextTheme _textTheme(Color primary, Color secondary) {
    return TextTheme(
      displayLarge: TextStyle(
        fontFamily: 'Sora',
        fontSize: 32,
        height: 1.25,
        color: primary,
        fontWeight: FontWeight.w700,
      ),
      headlineMedium: TextStyle(
        fontFamily: 'Sora',
        fontSize: 28,
        height: 1.28,
        color: primary,
        fontWeight: FontWeight.w700,
      ),
      headlineSmall: TextStyle(
        fontFamily: 'Sora',
        fontSize: 24,
        height: 1.33,
        color: primary,
        fontWeight: FontWeight.w700,
      ),
      titleLarge: TextStyle(
        fontFamily: 'Sora',
        fontSize: 24,
        height: 1.33,
        color: primary,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: TextStyle(
        fontFamily: 'Sora',
        fontSize: 20,
        height: 1.4,
        color: primary,
        fontWeight: FontWeight.w700,
      ),
      titleSmall: TextStyle(
        fontFamily: 'Sora',
        fontSize: 17,
        height: 1.4,
        color: primary,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: TextStyle(fontSize: 16, height: 1.5, color: secondary),
      bodyMedium: TextStyle(fontSize: 14, height: 1.5, color: secondary),
      bodySmall: TextStyle(fontSize: 13, height: 1.38, color: secondary),
      labelLarge: TextStyle(fontSize: 14, height: 1.28, color: primary),
      labelSmall: TextStyle(fontSize: 12, height: 1.33, color: secondary),
    );
  }
}
