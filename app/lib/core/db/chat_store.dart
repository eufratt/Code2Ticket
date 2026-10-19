import '../../features/assistant/assistant_models.dart';

/// Riwayat percakapan Asisten per pengguna. Diimplementasikan LocalDb (SQLite); tes memakai versi memori.
/// Hanya teks dan ringkasan giveaway publik: tidak pernah token, kunci, atau lokasi.
abstract class ChatStore {
  /// Terlama dulu; paling banyak [limit] pesan terakhir.
  Future<List<ChatMessage>> loadChat(String userId, {int limit = 200});
  Future<void> appendChat(String userId, List<ChatMessage> items);
  Future<void> clearChat(String userId);
}
