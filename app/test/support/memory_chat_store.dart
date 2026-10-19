import 'package:code2ticket/core/db/chat_store.dart';
import 'package:code2ticket/features/assistant/assistant_models.dart';

/// ChatStore di memori untuk tes controller/widget (tanpa SQLite).
class MemoryChatStore implements ChatStore {
  final Map<String, List<ChatMessage>> rows = {};
  bool failing = false;

  void _check() {
    if (failing) throw StateError('riwayat rusak');
  }

  @override
  Future<List<ChatMessage>> loadChat(String userId, {int limit = 200}) async {
    _check();
    return List.of(rows[userId] ?? const []);
  }

  @override
  Future<void> appendChat(String userId, List<ChatMessage> items) async {
    _check();
    (rows[userId] ??= []).addAll(items);
  }

  @override
  Future<void> clearChat(String userId) async {
    _check();
    rows.remove(userId);
  }
}
