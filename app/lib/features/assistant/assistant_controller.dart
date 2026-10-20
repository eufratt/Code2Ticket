import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/db/chat_store.dart';
import '../../core/json.dart';
import '../auth/auth_controller.dart';
import '../giveaways/giveaway_models.dart';
import 'assistant_models.dart';

/// Percakapan dengan Asisten (POST /chat). Riwayat disimpan per pengguna di SQLite; ke server hanya dikirim
/// [chatHistoryTurns] giliran terakhir yang sudah terjawab. POST /chat TIDAK pernah di-retry otomatis (biaya + dobel pesan):
/// galat menjadi gelembung galat dengan tombol "Kirim ulang" manual.
class AssistantController extends ChangeNotifier {
  AssistantController(this._api, this._auth, this._store) {
    _auth.addListener(_onAuth);
  }

  final AuthedApi _api;
  final AuthController _auth;
  final ChatStore _store;

  List<ChatMessage> messages = const [];
  bool sending = false;
  String? _userId;
  bool _disposed = false;

  /// Tombol "Kirim ulang" hanya untuk galat terakhir, dan hanya bila tidak sedang mengirim.
  bool get canRetry => !sending && messages.length >= 2 && messages.last.isError && messages[messages.length - 2].role == ChatRole.user;

  /// Memuat riwayat pengguna aktif dari SQLite (sekali per pengguna). Gagal baca = percakapan kosong.
  Future<void> load() async {
    final uid = _auth.user?.id;
    if (uid == null || uid == _userId) return;
    _userId = uid;
    try {
      messages = await _store.loadChat(uid);
    } catch (e) {
      debugPrint('riwayat chat gagal dimuat: ${e.runtimeType}');
      messages = const [];
    }
    _notify();
  }

  Future<void> send(String raw) => _submit(raw.trim(), showUser: true);

  Future<void> retry() {
    if (!canRetry) return Future.value();
    final text = messages[messages.length - 2].text;
    messages = messages.sublist(0, messages.length - 1);
    return _submit(text, showUser: false);
  }

  Future<void> clear() async {
    final uid = _userId;
    if (sending || uid == null) return;
    messages = const [];
    notifyListeners();
    try {
      await _store.clearChat(uid);
    } catch (e) {
      debugPrint('riwayat chat gagal dihapus: ${e.runtimeType}');
    }
  }

  Future<void> _submit(String text, {required bool showUser}) async {
    if (sending || text.isEmpty || text.runes.length > chatMaxLength) return;
    sending = true; // sebelum await pertama: ketukan kedua langsung ditolak
    final history = _history();
    if (showUser) messages = [...messages, ChatMessage(role: ChatRole.user, text: text, confirmed: false, createdAt: DateTime.now())];
    notifyListeners();
    final uid = _userId;
    ChatMessage? failure;
    try {
      final r = await _api.post('/chat', body: {'message': text, 'history': history}, retry: false);
      if (_disposed || uid != _userId) return; // logout / ganti pengguna saat menunggu
      final reply = asString(r['reply'])?.trim();
      if (r['ok'] == true && reply != null && reply.isNotEmpty) {
        final at = DateTime.now();
        final bot = ChatMessage(
          role: ChatRole.assistant,
          text: reply,
          related: parseList(r['related'], Giveaway.tryParse).take(chatRelatedMax).toList(),
          createdAt: at,
        );
        final i = messages.lastIndexWhere((m) => m.role == ChatRole.user && !m.confirmed);
        final user = messages[i].confirm();
        messages = [...messages]..[i] = user;
        messages = [...messages, bot];
        if (uid != null) await _persist(uid, [user, bot]);
        return;
      }
      failure = _error(r['ok'] == true ? 'ai_unavailable' : asString(r['error']), r['retry_after_seconds']);
    } on InvalidSessionException {
      return; // AuthedApi sudah menjalankan alur logout
    } on NetworkException catch (e) {
      failure = _errorMessage(e.message);
    } catch (e) {
      debugPrint('chat gagal: ${e.runtimeType}');
      failure = _errorMessage('Terjadi kesalahan. Coba lagi.');
    } finally {
      sending = false;
      if (failure != null && !_disposed && uid == _userId) messages = [...messages, failure];
      _notify();
    }
  }

  /// Giliran terkonfirmasi terakhir untuk server; teks dipotong ke batas 1000 karakter backend.
  List<Map<String, String>> _history() {
    final done = messages.where((m) => m.confirmed && !m.isError).toList();
    return [
      for (final m in done.skip(done.length > chatHistoryTurns ? done.length - chatHistoryTurns : 0))
        {'role': m.role.name, 'content': String.fromCharCodes(m.text.runes.take(chatTurnMaxLength))},
    ];
  }

  Future<void> _persist(String uid, List<ChatMessage> items) async {
    try {
      await _store.appendChat(uid, items);
    } catch (e) {
      debugPrint('riwayat chat gagal disimpan: ${e.runtimeType}');
    }
  }

  ChatMessage _errorMessage(String text) => ChatMessage(role: ChatRole.assistant, text: text, isError: true, createdAt: DateTime.now());

  /// Pesan Indonesia untuk tiap kode galat server; kode mentah tidak ditampilkan.
  ChatMessage _error(String? code, dynamic retryAfter) => _errorMessage(switch (code) {
        'ai_unavailable' => 'Asisten sedang tidak bisa menjawab. Coba lagi sebentar lagi.',
        'rate_limited' => retryAfter is num
            ? 'Terlalu banyak pesan dalam waktu singkat. Coba lagi dalam ${retryAfter.toInt()} detik.'
            : 'Terlalu banyak pesan dalam waktu singkat. Tunggu sebentar lalu coba lagi.',
        'daily_limit' => 'Batas pesan harian ke Asisten sudah tercapai. Coba lagi besok.',
        'global_limit' => 'Asisten sedang ramai hari ini dan batasnya tercapai. Coba lagi besok.',
        'ai_not_configured' => 'Asisten belum diaktifkan di server. Coba lagi nanti.',
        'invalid_input' => 'Pesan tidak valid. Tulis 1 sampai $chatMaxLength karakter.',
        _ => 'Terjadi kesalahan. Coba lagi.',
      });

  void _onAuth() {
    if (_auth.status == AuthStatus.signedOut && (_userId != null || messages.isNotEmpty)) {
      _userId = null;
      messages = const [];
      sending = false;
      _notify();
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
