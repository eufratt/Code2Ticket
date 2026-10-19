import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/json.dart';

/// Satu kiriman Saran & Kesan (GET /feedback: id, suggestion, impression, created_at).
class FeedbackEntry {
  const FeedbackEntry({required this.id, required this.suggestion, required this.impression, this.createdAt});
  final int id;
  final String suggestion, impression;
  final DateTime? createdAt;

  static FeedbackEntry? tryParse(dynamic raw) {
    final j = asMap(raw);
    final suggestion = asString(j?['suggestion']);
    final impression = asString(j?['impression']);
    if (j == null || suggestion == null || impression == null) return null;
    return FeedbackEntry(id: asInt(j['id']), suggestion: suggestion, impression: impression, createdAt: asDate(j['created_at']));
  }
}

const feedbackMaxLength = 1000;

/// Kirim (POST /feedback) dan riwayat milik pengguna (GET /feedback).
class FeedbackController extends ChangeNotifier {
  FeedbackController(this._api);
  final AuthedApi _api;

  List<FeedbackEntry> history = const [];
  bool loadingHistory = false, sending = false;
  String? historyError;

  Future<void> loadHistory() async {
    loadingHistory = true;
    historyError = null;
    notifyListeners();
    try {
      final r = await _api.get('/feedback');
      if (r['ok'] == false) throw NetworkException('Gagal memuat riwayat (${r['error']}).');
      history = parseList(r['data'], FeedbackEntry.tryParse);
    } on InvalidSessionException {
      return;
    } on NetworkException catch (e) {
      historyError = e.message;
    } finally {
      loadingHistory = false;
      notifyListeners();
    }
  }

  /// Mengembalikan pesan galat siap tampil, atau null bila terkirim. Validasi lokal sama dengan backend
  /// (tidak kosong setelah dipangkas, maks. 1000 karakter per kolom).
  Future<String?> submit(String suggestion, String impression) async {
    final s = suggestion.trim(), i = impression.trim();
    if (s.isEmpty) return 'Saran wajib diisi.';
    if (i.isEmpty) return 'Kesan wajib diisi.';
    if (s.runes.length > feedbackMaxLength) return 'Saran maksimal $feedbackMaxLength karakter.';
    if (i.runes.length > feedbackMaxLength) return 'Kesan maksimal $feedbackMaxLength karakter.';
    if (sending) return 'Sedang mengirim, tunggu sebentar.';
    sending = true;
    notifyListeners();
    try {
      final r = await _api.post('/feedback', body: {'suggestion': s, 'impression': i}, retry: false);
      if (r['ok'] == true) {
        await loadHistory();
        return null;
      }
      return switch (r['error']) {
        'invalid_input' when r['field'] == 'suggestion' => 'Saran tidak valid (wajib diisi, maks. $feedbackMaxLength karakter).',
        'invalid_input' when r['field'] == 'impression' => 'Kesan tidak valid (wajib diisi, maks. $feedbackMaxLength karakter).',
        'too_many_requests' => 'Terlalu banyak permintaan. Coba lagi sebentar.',
        _ => 'Gagal mengirim (${r['error']}). Coba lagi.',
      };
    } on InvalidSessionException {
      return null;
    } on NetworkException catch (e) {
      return e.message;
    } finally {
      sending = false;
      notifyListeners();
    }
  }
}
