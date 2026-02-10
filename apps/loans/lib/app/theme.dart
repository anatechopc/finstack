import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loooans/utils/screen_helpers.dart';

/// Builds the app theme with all design tokens properly defined.
///
/// See DESIGN.md for full design system documentation.
ThemeData buildAppTheme() {
  final textTheme = _buildTextTheme();

  return ThemeData(
    useMaterial3: true,
    colorScheme: _buildColorScheme(),
    textTheme: textTheme,
    scaffoldBackgroundColor: AppColors.green1,
    appBarTheme: _buildAppBarTheme(textTheme),
    inputDecorationTheme: _buildInputDecorationTheme(),
    filledButtonTheme: _buildFilledButtonTheme(),
    outlinedButtonTheme: _buildOutlinedButtonTheme(),
    dialogTheme: _buildDialogThemeData(),
    cardTheme: _buildCardThemeData(),
    chipTheme: _buildChipTheme(textTheme),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.green1,
    ),
  );
}

/// Color scheme based on the app's brand colors.
ColorScheme _buildColorScheme() {
  return const ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.green1,
    onPrimary: AppColors.black,
    primaryContainer: AppColors.green1_5,
    onPrimaryContainer: AppColors.white,
    secondary: AppColors.green2,
    onSecondary: AppColors.black,
    secondaryContainer: AppColors.green2,
    onSecondaryContainer: AppColors.black,
    tertiary: AppColors.ubOrange,
    onTertiary: AppColors.black,
    error: AppColors.red,
    onError: AppColors.white,
    errorContainer: AppColors.red2,
    onErrorContainer: AppColors.white,
    surface: AppColors.white,
    onSurface: AppColors.black,
    surfaceContainerHighest: AppColors.lightBlack,
    onSurfaceVariant: AppColors.lightBlack,
    outline: AppColors.black,
    outlineVariant: AppColors.lightBlack,
  );
}

/// Text theme using Urbanist font with explicit sizes.
TextTheme _buildTextTheme() {
  return GoogleFonts.urbanistTextTheme().copyWith(
    // Logo title - 64px
    displayLarge: GoogleFonts.urbanist(
      fontSize: AppTypography.displayLarge,
      fontWeight: FontWeight.w600,
      color: AppColors.black,
    ),
    // Section headers, dialog titles - 24px
    headlineLarge: GoogleFonts.urbanist(
      fontSize: AppTypography.headlineLarge,
      fontWeight: FontWeight.w600,
      color: AppColors.black,
    ),
    // Amount displays (whole number) - 20px
    headlineMedium: GoogleFonts.urbanist(
      fontSize: AppTypography.headlineMedium,
      fontWeight: FontWeight.w600,
      color: AppColors.black,
    ),
    // Tagline/subtitle - 18px
    titleLarge: GoogleFonts.urbanist(
      fontSize: AppTypography.titleLarge,
      fontWeight: FontWeight.w500,
      color: AppColors.black,
    ),
    // Body emphasis - 16px
    titleMedium: GoogleFonts.urbanist(
      fontSize: AppTypography.bodyLarge,
      fontWeight: FontWeight.w500,
      color: AppColors.black,
    ),
    // Body text, welcome text, buttons - 16px
    bodyLarge: GoogleFonts.urbanist(
      fontSize: AppTypography.bodyLarge,
      fontWeight: FontWeight.w400,
      color: AppColors.black,
    ),
    // Card titles, notification text - 14px
    bodyMedium: GoogleFonts.urbanist(
      fontSize: AppTypography.bodyMedium,
      fontWeight: FontWeight.w400,
      color: AppColors.black,
    ),
    // Helper text, chips, currency symbols, decimals - 12px
    bodySmall: GoogleFonts.urbanist(
      fontSize: AppTypography.bodySmall,
      fontWeight: FontWeight.w400,
      color: AppColors.black,
    ),
    // Labels - 12px
    labelLarge: GoogleFonts.urbanist(
      fontSize: AppTypography.bodySmall,
      fontWeight: FontWeight.w500,
      color: AppColors.black,
    ),
    // Timestamps, tertiary text - 10px
    labelSmall: GoogleFonts.urbanist(
      fontSize: AppTypography.labelSmall,
      fontWeight: FontWeight.w400,
      color: AppColors.black,
    ),
  );
}

/// App bar theme with green background.
AppBarTheme _buildAppBarTheme(TextTheme textTheme) {
  return AppBarTheme(
    backgroundColor: AppColors.green1,
    foregroundColor: AppColors.black,
    elevation: 0,
    centerTitle: true,
    titleTextStyle: textTheme.headlineLarge,
  );
}

/// Input decoration theme matching form_widgets.dart patterns.
InputDecorationTheme _buildInputDecorationTheme() {
  return InputDecorationTheme(
    contentPadding: const EdgeInsets.all(defaultPaddingSize),
    floatingLabelBehavior: FloatingLabelBehavior.always,
    border: OutlineInputBorder(
      borderRadius: defaultBorderRadius,
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: defaultBorderRadius,
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: defaultBorderRadius,
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: defaultBorderRadius,
      borderSide: BorderSide(color: AppColors.black.withValues(alpha: 0.6)),
    ),
    errorBorder: OutlineInputBorder(
      borderRadius: defaultBorderRadius,
      borderSide: const BorderSide(color: AppColors.red),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderRadius: defaultBorderRadius,
      borderSide: const BorderSide(color: AppColors.red),
    ),
    errorStyle: const TextStyle(color: AppColors.red),
    labelStyle: GoogleFonts.urbanist(color: AppColors.black),
    helperStyle: TextStyle(color: AppColors.black.withValues(alpha: 0.6)),
    helperMaxLines: 4,
    errorMaxLines: 4,
  );
}

/// Filled button theme (primary actions).
FilledButtonThemeData _buildFilledButtonTheme() {
  return FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: AppColors.black,
      foregroundColor: AppColors.white,
      padding: defaultButtonPadding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(defaultRadiusSize),
      ),
      textStyle: GoogleFonts.urbanist(
        fontSize: AppTypography.bodyLarge,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

/// Outlined button theme (secondary actions).
OutlinedButtonThemeData _buildOutlinedButtonTheme() {
  return OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: AppColors.black,
      padding: defaultButtonPadding,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(defaultRadiusSize),
      ),
      textStyle: GoogleFonts.urbanist(
        fontSize: AppTypography.bodyLarge,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

/// Dialog theme with green background.
DialogThemeData _buildDialogThemeData() {
  return DialogThemeData(
    backgroundColor: AppColors.green1,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(defaultRadiusSize),
    ),
    contentTextStyle: GoogleFonts.urbanist(
      fontSize: AppTypography.bodyLarge,
      color: AppColors.black,
    ),
    titleTextStyle: GoogleFonts.urbanist(
      fontSize: AppTypography.headlineLarge,
      fontWeight: FontWeight.w600,
      color: AppColors.black,
    ),
  );
}

/// Card theme with white background.
CardThemeData _buildCardThemeData() {
  return CardThemeData(
    color: AppColors.white,
    elevation: 0,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(defaultRadiusSize),
    ),
  );
}

/// Chip theme with pill shape.
ChipThemeData _buildChipTheme(TextTheme textTheme) {
  return ChipThemeData(
    backgroundColor: AppColors.white,
    labelStyle: textTheme.bodySmall,
    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
    shape: const StadiumBorder(),
  );
}
