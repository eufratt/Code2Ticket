import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_colors.dart';
import 'app_tokens.dart';
import 'app_typography.dart';

/// Tema terang dan gelap (ThemeMode mengikuti sistem). Semua komponen Material distel di sini sehingga layar
/// tidak perlu gaya inline.
abstract final class AppTheme {
  static ThemeData light() => _build(AppColors.light);
  static ThemeData dark() => _build(AppColors.dark);

  /// Tema tanpa animasi pindah layar, dipasang saat pengguna meminta animasi dikurangi.
  static ThemeData withoutPageTransitions(ThemeData t) => t.copyWith(
        pageTransitionsTheme: const PageTransitionsTheme(builders: {
          TargetPlatform.android: _NoTransitions(),
          TargetPlatform.iOS: _NoTransitions(),
          TargetPlatform.windows: _NoTransitions(),
          TargetPlatform.linux: _NoTransitions(),
          TargetPlatform.macOS: _NoTransitions(),
          TargetPlatform.fuchsia: _NoTransitions(),
        }),
      );

  static ThemeData _build(AppColors c) {
    final brightness = c.isDark ? Brightness.dark : Brightness.light;
    final scheme = ColorScheme(
      brightness: brightness,
      primary: c.primary,
      onPrimary: c.onPrimary,
      primaryContainer: c.primaryContainer,
      onPrimaryContainer: c.onPrimaryContainer,
      secondary: c.primary,
      onSecondary: c.onPrimary,
      secondaryContainer: c.primaryContainer,
      onSecondaryContainer: c.onPrimaryContainer,
      tertiary: c.accent,
      onTertiary: c.onAccent,
      error: c.error,
      onError: c.onError,
      errorContainer: c.errorContainer,
      onErrorContainer: c.onErrorContainer,
      surface: c.surface,
      onSurface: c.onBackground,
      onSurfaceVariant: c.muted,
      surfaceContainerLowest: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainer: c.surface,
      surfaceContainerHigh: c.surface,
      surfaceContainerHighest: c.surfaceVariant,
      // Garis komponen (radio, kotak centang, tepi tombol) perlu kontras 3:1; pembatas halus memakai outlineVariant.
      outline: c.outline,
      outlineVariant: c.isDark ? const Color(0xFF475569) : const Color(0xFFE2E8F0),
      shadow: const Color(0xFF0F172A),
      scrim: const Color(0xFF0F172A),
      surfaceTint: Colors.transparent,
      inverseSurface: c.isDark ? const Color(0xFFE2E8F0) : const Color(0xFF0F172A),
      onInverseSurface: c.isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      inversePrimary: c.isDark ? const Color(0xFF4F46E5) : const Color(0xFF818CF8),
    );

    final text = AppTypography.textTheme(color: c.onBackground);
    const buttonShape = RoundedRectangleBorder(borderRadius: Radii.buttonAll);
    final buttonText = AppTypography.subtitle;

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      extensions: [c],
      scaffoldBackgroundColor: c.background,
      canvasColor: c.background,
      textTheme: text,
      primaryTextTheme: text,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: c.background,
        foregroundColor: c.onBackground,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
        systemOverlayStyle: c.isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      ),
      cardTheme: CardThemeData(
        color: c.surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: Radii.cardAll, side: BorderSide(color: c.outline)),
      ),
      dividerTheme: DividerThemeData(color: c.outline, space: 1, thickness: 1),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: c.surfaceVariant,
        contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.s16, vertical: Spacing.s16),
        labelStyle: text.bodyMedium?.copyWith(color: c.mutedOnVariant),
        floatingLabelStyle: text.bodyMedium?.copyWith(color: c.primary),
        hintStyle: text.bodyMedium?.copyWith(color: c.mutedOnVariant),
        helperStyle: text.bodySmall?.copyWith(color: c.muted),
        errorStyle: text.bodySmall?.copyWith(color: c.error),
        errorMaxLines: 3,
        prefixIconColor: c.isDark ? c.mutedOnVariant : c.muted,
        suffixIconColor: c.isDark ? c.mutedOnVariant : c.muted,
        border: OutlineInputBorder(borderRadius: Radii.inputAll, borderSide: BorderSide(color: c.outline, width: 1)),
        enabledBorder: OutlineInputBorder(borderRadius: Radii.inputAll, borderSide: BorderSide(color: c.outline, width: 1)),
        focusedBorder: OutlineInputBorder(borderRadius: Radii.inputAll, borderSide: BorderSide(color: c.primary, width: 2)),
        errorBorder: OutlineInputBorder(borderRadius: Radii.inputAll, borderSide: BorderSide(color: c.error, width: 1.5)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: Radii.inputAll, borderSide: BorderSide(color: c.error, width: 2)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: buttonShape,
          backgroundColor: c.primary,
          foregroundColor: c.onPrimary,
          disabledBackgroundColor: c.surfaceVariant,
          disabledForegroundColor: c.muted,
          textStyle: buttonText,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(64, 52),
          shape: buttonShape,
          foregroundColor: c.primary,
          disabledForegroundColor: c.muted,
          side: BorderSide(color: c.primary, width: 1.5),
          textStyle: buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(64, kMinTap),
          shape: buttonShape,
          foregroundColor: c.primary,
          disabledForegroundColor: c.muted,
          textStyle: text.labelLarge,
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(kMinTap, kMinTap), foregroundColor: c.onBackground),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: c.primary,
        foregroundColor: c.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: const CircleBorder(),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: c.surface,
        selectedColor: c.primaryContainer,
        disabledColor: c.surfaceVariant,
        labelStyle: text.labelMedium?.copyWith(color: c.onBackground),
        secondaryLabelStyle: text.labelMedium?.copyWith(color: c.onPrimaryContainer),
        checkmarkColor: c.onPrimaryContainer,
        deleteIconColor: c.muted,
        iconTheme: IconThemeData(color: c.muted, size: 18),
        side: BorderSide(color: c.outline),
        shape: const StadiumBorder(),
        padding: const EdgeInsets.symmetric(horizontal: Spacing.s4),
        showCheckmark: false,
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: c.primary,
        unselectedLabelColor: c.muted,
        labelStyle: text.labelLarge,
        unselectedLabelStyle: text.labelLarge,
        indicatorColor: c.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: c.outline,
        overlayColor: WidgetStatePropertyAll(c.primary.withValues(alpha: 0.08)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.muted,
        textColor: c.onBackground,
        titleTextStyle: text.bodyLarge,
        subtitleTextStyle: text.bodySmall?.copyWith(color: c.muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: Spacing.s16),
        minVerticalPadding: Spacing.s8,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: c.outline,
        shape: const RoundedRectangleBorder(borderRadius: Radii.sheetTop),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        shape: const RoundedRectangleBorder(borderRadius: Radii.cardAll),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        surfaceTintColor: Colors.transparent,
        textStyle: text.bodyMedium,
        shape: const RoundedRectangleBorder(borderRadius: Radii.inputAll),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: text.bodyMedium?.copyWith(color: scheme.onInverseSurface),
        actionTextColor: scheme.inversePrimary,
        shape: const RoundedRectangleBorder(borderRadius: Radii.buttonAll),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: c.primary, circularTrackColor: c.surfaceVariant),
      badgeTheme: BadgeThemeData(backgroundColor: c.error, textColor: c.onError, textStyle: text.labelMedium),
      expansionTileTheme: ExpansionTileThemeData(
        shape: const Border(),
        collapsedShape: const Border(),
        iconColor: c.primary,
        collapsedIconColor: c.muted,
        textColor: c.onBackground,
        collapsedTextColor: c.onBackground,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: scheme.inverseSurface, borderRadius: Radii.inputAll),
        textStyle: text.bodySmall?.copyWith(color: scheme.onInverseSurface),
      ),
    );
  }
}

class _NoTransitions extends PageTransitionsBuilder {
  const _NoTransitions();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      child;
}
