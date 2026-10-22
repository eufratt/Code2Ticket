import '../../features/draw/draw_models.dart';
import '../../features/giveaways/giveaway_models.dart';
import '../../features/tickets/ticket_models.dart';

/// Cache offline + riwayat pencarian. Diimplementasikan LocalDb (SQLite); tes memakai versi memori.
/// Tidak pernah menyimpan token, password, atau lokasi pengguna.
abstract class CacheStore {
  Future<void> saveGiveaways(List<Giveaway> items);
  Future<List<Giveaway>> loadGiveaways();
  Future<Giveaway?> loadGiveaway(String id);

  /// Waktu terakhir cache giveaway diperbarui dari server (null bila kosong).
  Future<DateTime?> giveawaysUpdatedAt();

  /// Mengganti seluruh tiket milik [userId] (tiket pengguna lain tidak tersentuh).
  Future<void> replaceTickets(String userId, List<Ticket> items);
  Future<List<Ticket>> loadTickets(String userId);
  Future<DateTime?> ticketsUpdatedAt(String userId);

  /// Hasil draw final per pengguna, maksimal 50 giveaway terbaru (yang paling lama dibuang).
  Future<void> saveDrawResult(String userId, CachedDrawResult result);
  Future<CachedDrawResult?> loadDrawResult(String userId, String giveawayId);

  /// Riwayat pencarian terbaru dulu, per pengguna.
  Future<List<String>> recentSearches(String userId, {int limit = 10});
  Future<void> addSearch(String userId, String query);
  Future<void> deleteSearch(String userId, String query);
  Future<void> clearSearches(String userId);

  /// Saat logout: hapus cache giveaway, tiket, dan hasil draw, serta riwayat pencarian [userId] bila diketahui
  /// (null = semua baris riwayat pencarian dan chat ikut dihapus).
  Future<void> clearUserData({String? userId});
}
