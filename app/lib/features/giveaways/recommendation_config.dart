/// Konstanta skor rekomendasi "Untuk kamu" (recommendation.dart). Semua bobot/batas ada di sini, tidak tersebar.
abstract final class RecommendationConfig {
  // Bobot faktor (total 1). Faktor kedekatan dibuang bila lokasi pengguna tidak diketahui; sisanya dinormalkan.
  static const double weightAffinity = 0.4; // saat cold start dipakai untuk popularitas
  static const double weightProximity = 0.3;
  static const double weightUrgency = 0.2;
  static const double weightFreshness = 0.1;

  /// Kedekatan: 1 pada 0 km, turun linear ke 0 pada jarak ini atau lebih.
  static const double proximityZeroKm = 50;

  /// Urgensi: 1 bila sisa waktu ikut <= [urgencyFullWithin], turun linear ke 0 pada [urgencyZeroAt].
  static const Duration urgencyFullWithin = Duration(hours: 24);
  static const Duration urgencyZeroAt = Duration(days: 14);

  /// Kebaruan: 1 saat baru mulai, turun linear ke 0 setelah durasi ini sejak start_at.
  static const Duration freshnessZeroAfter = Duration(days: 30);

  /// Keragaman dan ukuran daftar.
  static const int maxPerCategory = 3;
  static const int maxTotal = 10;
  static const int minCandidatesForColdStart = 3;

  /// Alasan kartu.
  static const int maxReasons = 2;
}
