import 'package:flutter/material.dart';

/// Pasangan latar + teks untuk chip status (DESIGN.md 3.1). Semua pasangan di atas 6:1.
@immutable
class StatusColors {
  const StatusColors(this.bg, this.fg);
  final Color bg, fg;
  static StatusColors lerp(StatusColors a, StatusColors b, double t) =>
      StatusColors(Color.lerp(a.bg, b.bg, t)!, Color.lerp(a.fg, b.fg, t)!);
}

/// Token warna (DESIGN.md 3.1 dan 3.2). Setiap token punya padanan terang dan gelap.
/// Dibaca lewat `context.colors`; warna literal di widget tidak boleh dipakai.
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.background,
    required this.surface,
    required this.surfaceVariant,
    required this.onBackground,
    required this.muted,
    required this.mutedOnVariant,
    required this.outline,
    required this.primary,
    required this.onPrimary,
    required this.primaryContainer,
    required this.onPrimaryContainer,
    required this.accent,
    required this.onAccent,
    required this.accentText,
    required this.success,
    required this.successText,
    required this.error,
    required this.onError,
    required this.errorContainer,
    required this.onErrorContainer,
    required this.statusSuccess,
    required this.statusWarning,
    required this.statusError,
    required this.statusInfo,
    required this.statusNeutral,
    required this.isDark,
  });

  final Color background, surface, surfaceVariant, onBackground;

  /// Teks sekunder di atas background/surface.
  final Color muted;

  /// Teks sekunder di atas surfaceVariant (kolom input): di tema gelap muted hanya 4,0:1 di sana, jadi dipakai yang lebih terang.
  final Color mutedOnVariant;
  final Color outline;
  final Color primary, onPrimary, primaryContainer, onPrimaryContainer;

  /// Amber: HANYA isi/ikon besar. Teks amber kecil memakai [accentText].
  final Color accent, onAccent, accentText;

  /// Hijau: HANYA isi/ikon besar. Teks hijau memakai [successText].
  final Color success, successText;
  final Color error, onError, errorContainer, onErrorContainer;
  final StatusColors statusSuccess, statusWarning, statusError, statusInfo, statusNeutral;
  final bool isDark;

  static const light = AppColors(
    background: Color(0xFFF8FAFC),
    surface: Color(0xFFFFFFFF),
    surfaceVariant: Color(0xFFF1F5F9),
    onBackground: Color(0xFF0F172A),
    muted: Color(0xFF475569),
    mutedOnVariant: Color(0xFF475569),
    outline: Color(0xFF64748B),
    primary: Color(0xFF4F46E5),
    onPrimary: Color(0xFFFFFFFF),
    primaryContainer: Color(0xFFEEF2FF),
    onPrimaryContainer: Color(0xFF3730A3),
    accent: Color(0xFFF59E0B),
    onAccent: Color(0xFF1F2937),
    accentText: Color(0xFFB45309),
    success: Color(0xFF16A34A),
    successText: Color(0xFF15803D),
    error: Color(0xFFDC2626),
    onError: Color(0xFFFFFFFF),
    errorContainer: Color(0xFFFEE2E2),
    onErrorContainer: Color(0xFF991B1B),
    statusSuccess: StatusColors(Color(0xFFDCFCE7), Color(0xFF166534)),
    statusWarning: StatusColors(Color(0xFFFEF3C7), Color(0xFF92400E)),
    statusError: StatusColors(Color(0xFFFEE2E2), Color(0xFF991B1B)),
    statusInfo: StatusColors(Color(0xFFEEF2FF), Color(0xFF3730A3)),
    statusNeutral: StatusColors(Color(0xFFF1F5F9), Color(0xFF475569)),
    isDark: false,
  );

  static const dark = AppColors(
    background: Color(0xFF0F172A),
    surface: Color(0xFF1E293B),
    surfaceVariant: Color(0xFF334155),
    onBackground: Color(0xFFE2E8F0),
    muted: Color(0xFF94A3B8),
    mutedOnVariant: Color(0xFFCBD5E1),
    outline: Color(0xFF94A3B8),
    primary: Color(0xFF818CF8),
    onPrimary: Color(0xFF0F172A),
    primaryContainer: Color(0xFF312E81),
    onPrimaryContainer: Color(0xFFE0E7FF),
    accent: Color(0xFFFBBF24),
    onAccent: Color(0xFF0F172A),
    accentText: Color(0xFFFBBF24),
    success: Color(0xFF4ADE80),
    successText: Color(0xFF4ADE80),
    error: Color(0xFFF87171),
    onError: Color(0xFF0F172A),
    errorContainer: Color(0xFF7F1D1D),
    onErrorContainer: Color(0xFFFECACA),
    statusSuccess: StatusColors(Color(0xFF14532D), Color(0xFFBBF7D0)),
    statusWarning: StatusColors(Color(0xFF78350F), Color(0xFFFDE68A)),
    statusError: StatusColors(Color(0xFF7F1D1D), Color(0xFFFECACA)),
    statusInfo: StatusColors(Color(0xFF312E81), Color(0xFFC7D2FE)),
    statusNeutral: StatusColors(Color(0xFF334155), Color(0xFFCBD5E1)),
    isDark: true,
  );

  @override
  AppColors copyWith() => this;

  @override
  AppColors lerp(ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    StatusColors s(StatusColors a, StatusColors b) => StatusColors.lerp(a, b, t);
    return AppColors(
      background: c(background, other.background),
      surface: c(surface, other.surface),
      surfaceVariant: c(surfaceVariant, other.surfaceVariant),
      onBackground: c(onBackground, other.onBackground),
      muted: c(muted, other.muted),
      mutedOnVariant: c(mutedOnVariant, other.mutedOnVariant),
      outline: c(outline, other.outline),
      primary: c(primary, other.primary),
      onPrimary: c(onPrimary, other.onPrimary),
      primaryContainer: c(primaryContainer, other.primaryContainer),
      onPrimaryContainer: c(onPrimaryContainer, other.onPrimaryContainer),
      accent: c(accent, other.accent),
      onAccent: c(onAccent, other.onAccent),
      accentText: c(accentText, other.accentText),
      success: c(success, other.success),
      successText: c(successText, other.successText),
      error: c(error, other.error),
      onError: c(onError, other.onError),
      errorContainer: c(errorContainer, other.errorContainer),
      onErrorContainer: c(onErrorContainer, other.onErrorContainer),
      statusSuccess: s(statusSuccess, other.statusSuccess),
      statusWarning: s(statusWarning, other.statusWarning),
      statusError: s(statusError, other.statusError),
      statusInfo: s(statusInfo, other.statusInfo),
      statusNeutral: s(statusNeutral, other.statusNeutral),
      isDark: t < 0.5 ? isDark : other.isDark,
    );
  }
}

extension AppColorsContext on BuildContext {
  /// Token warna tema aktif. Jatuh ke tema terang bila dipakai di luar [AppTheme] (mis. MaterialApp polos di tes).
  AppColors get colors => Theme.of(this).extension<AppColors>() ?? AppColors.light;
}
