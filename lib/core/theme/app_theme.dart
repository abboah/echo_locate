import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_dimens.dart';
import 'app_typography.dart';

/// Light + dark [ThemeData] built from EchoLocate's design tokens.
///
/// One warm accent (Coral), white/ink surfaces, no gradients. Both themes are
/// driven by [AppColors] so the [ThemeCubit] can swap between them at runtime.
class AppTheme {
  AppTheme._();

  static ThemeData get light => _build(
    brightness: Brightness.light,
    background: AppColors.white,
    surface: AppColors.surface,
    onSurface: AppColors.ink,
    muted: AppColors.inkMuted,
    hairline: AppColors.hairline,
  );

  static ThemeData get dark => _build(
    brightness: Brightness.dark,
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    onSurface: AppColors.darkOnSurface,
    muted: AppColors.darkMuted,
    hairline: AppColors.darkHairline,
  );

  static ThemeData _build({
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color onSurface,
    required Color muted,
    required Color hairline,
  }) {
    final isDark = brightness == Brightness.dark;

    // Filled in past the eight roles this used to declare.
    //
    // Material 3 derives every role left unset, and its derivations come from
    // a violet baseline — so a disabled FilledButton, a SnackBar, a Switch
    // track and an elevated Card were each picking up a tint from a palette
    // this app does not use. Naming them costs nothing and is the difference
    // between components that look designed and components that look default.
    final colorScheme = ColorScheme(
      brightness: brightness,
      primary: AppColors.coral,
      onPrimary: Colors.white,
      primaryContainer: isDark
          ? AppColors.coral.withValues(alpha: 0.18)
          : AppColors.coralSoft,
      onPrimaryContainer: isDark ? AppColors.darkOnSurface : AppColors.ink,
      // One accent, so the secondary role *is* the accent rather than a second
      // hue invented to fill the slot.
      secondary: AppColors.coral,
      onSecondary: Colors.white,
      secondaryContainer: isDark
          ? AppColors.coral.withValues(alpha: 0.18)
          : AppColors.coralSoft,
      onSecondaryContainer: isDark ? AppColors.darkOnSurface : AppColors.ink,
      tertiary: AppColors.warning,
      onTertiary: AppColors.ink,
      surface: surface,
      onSurface: onSurface,
      // The muted role every "secondary text on a panel" reads from.
      onSurfaceVariant: muted,
      surfaceContainerLowest: background,
      surfaceContainerLow: background,
      surfaceContainer: surface,
      surfaceContainerHigh: isDark ? AppColors.darkElevated : surface,
      surfaceContainerHighest: isDark ? AppColors.darkElevated : surface,
      error: AppColors.error,
      onError: Colors.white,
      errorContainer: isDark
          ? AppColors.error.withValues(alpha: 0.18)
          : AppColors.errorSoft,
      onErrorContainer: isDark ? AppColors.darkOnSurface : AppColors.ink,
      outline: hairline,
      outlineVariant: hairline,
      // Snackbars and tooltips sit on the inverse ground.
      inverseSurface: isDark ? AppColors.surface : AppColors.ink,
      onInverseSurface: isDark ? AppColors.ink : AppColors.white,
      inversePrimary: AppColors.coral,
      shadow: AppColors.ink,
      scrim: AppColors.ink,
      // "No gradients" in the token sheet means no elevation tint either: M3
      // washes a raised surface with the primary hue, which turns every
      // elevated card faintly coral.
      surfaceTint: Colors.transparent,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: background,
      textTheme: AppTypography.textTheme(onSurface, muted),
      dividerColor: hairline,
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: AppDimens.cardElevation,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.coral.withValues(alpha: 0.4),
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          ),
        ),
      ),
      // Styled to match [ElevatedButton] exactly, because both are used as
      // *the* primary button — ElevatedButton on Home, Explore, auth and the
      // building screen, FilledButton on the mapping hub, the tracer, the plan
      // editor and the walk screen. With no entry here, those four screens
      // drew a primary button at Material's own height, radius and pressed
      // state, so the app had two different primary buttons depending on which
      // half of it you were in.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.coral,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.coral.withValues(alpha: 0.4),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.7),
          elevation: 0,
          minimumSize: const Size.fromHeight(54),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: onSurface,
          minimumSize: const Size.fromHeight(54),
          side: BorderSide(color: hairline),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.coral,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimens.radiusSm),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: onSurface,
          // 48dp is the minimum comfortable touch target, and this app is
          // built for people who cannot see where they are aiming.
          minimumSize: const Size.square(48),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space16,
          vertical: AppDimens.space12,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          borderSide: BorderSide(color: hairline),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          borderSide: BorderSide(color: hairline),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
          borderSide: const BorderSide(color: AppColors.coral),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: brightness == Brightness.dark
            ? AppColors.darkElevated
            : AppColors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusXl),
        ),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor: background,
        selectedItemColor: AppColors.coral,
        unselectedItemColor: muted,
        type: BottomNavigationBarType.fixed,
        elevation: 0,
      ),
      dividerTheme: DividerThemeData(color: hairline, space: 1, thickness: 1),
      listTileTheme: ListTileThemeData(
        iconColor: muted,
        textColor: onSurface,
        subtitleTextStyle: TextStyle(color: muted, fontSize: 15),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppDimens.space16,
          vertical: AppDimens.space4,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusLg),
        ),
      ),
      // Every screen builds its own snackbars, and they were the one surface
      // still rendering at Material's defaults — a floating violet-tinted card
      // in the middle of a coral-and-ink app.
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? AppColors.darkElevated : AppColors.ink,
        contentTextStyle: TextStyle(
          color: isDark ? AppColors.darkOnSurface : AppColors.white,
          fontSize: 15,
        ),
        actionTextColor: AppColors.coral,
        insetPadding: const EdgeInsets.all(AppDimens.space16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusMd),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: isDark ? AppColors.darkSurface : AppColors.white,
        selectedColor: isDark ? AppColors.darkElevated : AppColors.ink,
        side: BorderSide(color: hairline),
        labelStyle: TextStyle(color: onSurface, fontWeight: FontWeight.w600),
        secondaryLabelStyle: const TextStyle(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimens.radiusPill),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.coral
              : (isDark ? AppColors.darkMuted : AppColors.white),
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.coral.withValues(alpha: 0.35)
              : surface,
        ),
        trackOutlineColor: WidgetStateProperty.all(hairline),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.coral,
      ),
      // Selection and the caret follow the accent; without this they stay on
      // Material's own blue, which is the only blue in the app.
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.coral,
        selectionColor: AppColors.coral.withValues(alpha: 0.28),
        selectionHandleColor: AppColors.coral,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.coral,
        foregroundColor: Colors.white,
        elevation: 2,
        shape: CircleBorder(),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: isDark ? AppColors.darkElevated : AppColors.white,
        surfaceTintColor: Colors.transparent,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppDimens.radiusXl),
          ),
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: isDark ? AppColors.darkElevated : AppColors.ink,
          borderRadius: BorderRadius.circular(AppDimens.radiusSm),
        ),
        textStyle: TextStyle(
          color: isDark ? AppColors.darkOnSurface : AppColors.white,
          fontSize: 13,
        ),
      ),
    );
  }
}
