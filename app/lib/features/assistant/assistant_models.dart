import 'dart:convert';

import '../../core/json.dart';
import '../giveaways/giveaway_models.dart';

/// Batas yang sama dengan backend (POST /chat): pesan 1-500 karakter, tiap giliran riwayat <= 1000, riwayat dipakai 6 giliran.
const chatMaxLength = 500, chatTurnMaxLength = 1000, chatHistoryTurns = 6, chatRelatedMax = 3;

enum ChatRole { user, assistant }

/// Satu gelembung percakapan. [confirmed] false = pesan pengguna yang belum dijawab server; [isError] = pesan galat
/// dari app (bukan dari server), tidak pernah disimpan maupun dikirim sebagai riwayat.
class ChatMessage {
  const ChatMessage({
    required this.role,
    required this.text,
    this.related = const [],
    this.isError = false,
    this.confirmed = true,
    required this.createdAt,
  });

  final ChatRole role;
  final String text;
  final List<Giveaway> related;
  final bool isError, confirmed;
  final DateTime createdAt;

  ChatMessage confirm() => ChatMessage(role: role, text: text, related: related, createdAt: createdAt);

  /// Baris tabel chat_messages. Hanya teks dan ringkasan giveaway publik; tidak ada token atau kunci.
  Map<String, Object?> toRow(String userId) => {
        'user_id': userId,
        'role': role.name,
        'content': text,
        'related_json': related.isEmpty ? null : jsonEncode([for (final g in related) g.toRow(createdAt)]),
        'created_at': createdAt.toUtc().toIso8601String(),
      };

  static ChatMessage? tryParse(Map<String, Object?> row) {
    final role = ChatRole.values.where((r) => r.name == row['role']).firstOrNull;
    final text = asString(row['content']);
    if (role == null || text == null || text.isEmpty) return null;
    var related = <Giveaway>[];
    try {
      related = parseList(jsonDecode(asString(row['related_json']) ?? 'null'), Giveaway.tryParse);
    } catch (_) {/* kartu rusak dilewati, teks tetap tampil */}
    return ChatMessage(role: role, text: text, related: related, createdAt: asDate(row['created_at']) ?? DateTime.now());
  }
}
