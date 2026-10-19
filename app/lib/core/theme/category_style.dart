import 'package:flutter/material.dart';

/// Gaya per kategori (DESIGN.md 3.3): gradien dua warna + ikon. Konsisten di seluruh aplikasi.
@immutable
class CategoryStyle {
  const CategoryStyle(this.key, this.from, this.to, this.icon);
  final String key;
  final Color from, to;
  final IconData icon;

  LinearGradient get gradient =>
      LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [from, to]);

  static const gaming = CategoryStyle('gaming', Color(0xFF4F46E5), Color(0xFF7C3AED), Icons.sports_esports);
  static const travel = CategoryStyle('travel', Color(0xFF0EA5E9), Color(0xFF22D3EE), Icons.flight);
  static const electronics = CategoryStyle('elektronik', Color(0xFF334155), Color(0xFF64748B), Icons.laptop_mac);
  static const fashion = CategoryStyle('fashion', Color(0xFFDB2777), Color(0xFFF472B6), Icons.checkroom);
  static const food = CategoryStyle('makanan', Color(0xFFEA580C), Color(0xFFFB923C), Icons.restaurant);
  static const other = CategoryStyle('lainnya', Color(0xFF4F46E5), Color(0xFF818CF8), Icons.card_giftcard);

  /// Kode kategori dari backend (tech, gaming, travel, fashion, food, lifestyle, other) ke gaya.
  /// Nama DESIGN.md (elektronik, makanan) juga diterima. Yang tidak dikenal = lainnya.
  static CategoryStyle of(String? category) => switch (category?.toLowerCase().trim()) {
        'gaming' => gaming,
        'travel' => travel,
        'tech' || 'elektronik' || 'electronics' => electronics,
        'fashion' => fashion,
        'food' || 'makanan' => food,
        _ => other,
      };
}
