import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Tipografi (DESIGN.md 3.4): Plus Jakarta Sans lewat google_fonts.
/// Bila font belum terunduh (mis. offline pertama kali), google_fonts memakai font bawaan sistem tanpa melempar galat;
/// semua tata letak memakai Flexible/Wrap sehingga perbedaan lebar huruf tidak merusak tampilan.
abstract final class AppTypography {
  static TextStyle _s(double size, FontWeight w, {double? height}) =>
      GoogleFonts.plusJakartaSans(fontSize: size, fontWeight: w, height: height);

  // Enam gaya DESIGN.md.
  static final display = _s(28, FontWeight.w700, height: 1.2);
  static final title = _s(20, FontWeight.w700, height: 1.3);
  static final subtitle = _s(16, FontWeight.w600, height: 1.35);
  static final body = _s(14, FontWeight.w400, height: 1.45);
  static final label = _s(12, FontWeight.w600, height: 1.3);
  static final caption = _s(12, FontWeight.w400, height: 1.4);

  /// Angka sama lebar: nomor tiket, kurs, hitung mundur.
  static TextStyle tabular(TextStyle s) => s.copyWith(fontFeatures: const [FontFeature.tabularFigures()]);

  /// Kode di Input Code: monospace sistem (tanpa unduhan font tambahan).
  static TextStyle mono(TextStyle s) => s.copyWith(fontFamily: 'monospace', fontFeatures: const [FontFeature.tabularFigures()]);

  /// Skala Material dipetakan ke enam gaya di atas; gaya Material yang tidak punya padanan memakai yang terdekat.
  static TextTheme textTheme({required Color color}) {
    TextStyle c(TextStyle s) => s.copyWith(color: color);
    return TextTheme(
      displayLarge: c(display),
      displayMedium: c(display),
      displaySmall: c(display),
      headlineLarge: c(title),
      headlineMedium: c(title),
      headlineSmall: c(title),
      titleLarge: c(title),
      titleMedium: c(subtitle),
      titleSmall: c(subtitle.copyWith(fontSize: 14)),
      bodyLarge: c(body.copyWith(fontSize: 16)),
      bodyMedium: c(body),
      bodySmall: c(caption),
      labelLarge: c(subtitle.copyWith(fontSize: 14)),
      labelMedium: c(label),
      labelSmall: c(label),
    );
  }
}
