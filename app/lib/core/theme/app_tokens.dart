import 'package:flutter/material.dart';

import 'app_colors.dart';

/// Jarak (DESIGN.md 3.5): kelipatan 4/8. Padding layar 16, antar kartu 12, antar bagian 24.
abstract final class Spacing {
  static const s4 = 4.0, s8 = 8.0, s12 = 12.0, s16 = 16.0, s24 = 24.0, s32 = 32.0;
  static const screen = s16, cardGap = s12, sectionGap = s24;

  /// Ruang bawah daftar supaya isi terakhir tidak tertutup FAB + bottom navigation.
  static const listBottom = 140.0;
}

/// Radius (DESIGN.md 3.5).
abstract final class Radii {
  static const input = 8.0, button = 12.0, card = 16.0, sheet = 24.0, full = 999.0;
  static const inputAll = BorderRadius.all(Radius.circular(input));
  static const buttonAll = BorderRadius.all(Radius.circular(button));
  static const cardAll = BorderRadius.all(Radius.circular(card));
  static const sheetTop = BorderRadius.vertical(top: Radius.circular(sheet));
}

/// Lapisan di atas gambar/gradien (sama di kedua tema): ikon putih di atas gradien kategori, lapisan gelap agar terbaca.
abstract final class Overlays {
  static const onGradient = Color(0xFFFFFFFF);

  /// Lapisan gelap 20% di atas gradien kategori: ikon putih terbaca juga di atas warna terang (mis. biru muda travel).
  static const dim = Color(0x33000000);

  /// Lapisan gelap di bawah gambar banner supaya yang ditaruh di atasnya terbaca.
  static const imageScrimTop = Color(0x00000000), imageScrimBottom = Color(0x66000000);

  /// Lingkaran dekoratif samar pada banner.
  static const bubble = Color(0x1FFFFFFF);

  /// Bayangan ikon penanda peta di atas peta terang.
  static const markerShadow = Color(0x66000000);
}

/// Target sentuh minimum (dp).
const double kMinTap = 48;

/// Bayangan (DESIGN.md 3.5). Mode gelap tanpa bayangan: beda warna surface sudah cukup.
abstract final class AppShadows {
  static List<BoxShadow> card(AppColors c) => c.isDark
      ? const []
      : const [BoxShadow(color: Color(0x0F0F172A), offset: Offset(0, 2), blurRadius: 8)];

  static List<BoxShadow> raised(AppColors c) => c.isDark
      ? const []
      : const [BoxShadow(color: Color(0x1A0F172A), offset: Offset(0, 6), blurRadius: 16)];

  static List<BoxShadow> fab(AppColors c) => [
        BoxShadow(color: const Color(0xFF4F46E5).withValues(alpha: c.isDark ? 0.2 : 0.35), offset: const Offset(0, 8), blurRadius: 20),
      ];
}

/// Gerak (DESIGN.md 3.5): 150-250 ms, ease-out, hanya bila bermakna. Pengaturan "kurangi animasi" sistem menghapusnya.
abstract final class Motion {
  static const fast = Duration(milliseconds: 150);
  static const normal = Duration(milliseconds: 200);
  static const slow = Duration(milliseconds: 250);
  static const curve = Curves.easeOut;

  static bool reduced(BuildContext context) => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [d], atau nol bila pengguna meminta animasi dikurangi.
  static Duration of(BuildContext context, [Duration d = normal]) => reduced(context) ? Duration.zero : d;
}
