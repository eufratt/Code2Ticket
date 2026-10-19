/// Satu baris tabel exchange_rate_cache.
class CachedRate {
  const CachedRate({required this.target, required this.rate, this.rateDate, required this.fetchedAt});
  final String target;
  final double rate;

  /// Tanggal kurs dari Frankfurter (YYYY-MM-DD); bisa berbeda antar mata uang.
  final String? rateDate;

  /// Kapan aplikasi mengambil kurs ini dari server.
  final DateTime fetchedAt;
}

/// Cache kurs (tabel exchange_rate_cache). Diimplementasikan LocalDb.
abstract class RateCache {
  Future<void> saveRates(String base, List<CachedRate> rates);
  Future<List<CachedRate>> loadRates(String base);
}

/// Pengaturan per perangkat (tabel app_settings, user_id kosong). Diimplementasikan LocalDb.
abstract class SettingsStore {
  Future<String?> getSetting(String key, {String userId = ''});
  Future<void> setSetting(String key, String? value, {String userId = ''});
}
