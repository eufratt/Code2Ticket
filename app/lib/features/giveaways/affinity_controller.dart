import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../auth/auth_controller.dart';
import 'giveaway_models.dart';
import 'giveaways_controller.dart' show LoadState;

/// Skor minat per kategori dari GET /me/affinity (tiket x3 + dilihat x1, 90 hari; objek polos {kategori: skor}).
/// Dimuat sekali saat Home dibuka; gagal = tanpa rekomendasi (bagian "Untuk kamu" disembunyikan), tidak ada galat di layar.
class AffinityController extends ChangeNotifier {
  AffinityController(this._api, this._auth) {
    _auth.addListener(_onAuth);
  }

  final AuthedApi _api;
  final AuthController _auth;

  Map<String, int> scores = const {};
  LoadState state = LoadState.idle;
  Future<void>? _inflight;

  /// Memuat bila belum pernah (idle). Panggilan berikutnya tidak membuat permintaan baru.
  Future<void> loadOnce() => state == LoadState.idle ? load() : Future.value();

  Future<void> load() => _inflight ??= _load().whenComplete(() => _inflight = null);

  Future<void> _load() async {
    state = LoadState.loading;
    notifyListeners();
    try {
      final r = await _api.get('/me/affinity');
      if (r['ok'] == false) throw NetworkException('affinity ${r['error']}');
      scores = {
        for (final e in r.entries)
          if (e.key != 'ok' && e.value is num && (e.value as num) > 0) e.key: (e.value as num).toInt(),
      };
      state = LoadState.loaded;
    } on InvalidSessionException {
      return;
    } on NetworkException catch (e) {
      debugPrint('affinity gagal: ${e.runtimeType}');
      state = LoadState.error;
    } on ForbiddenException {
      state = LoadState.error;
    }
    notifyListeners();
  }

  void _onAuth() {
    if (_auth.status == AuthStatus.signedOut && (scores.isNotEmpty || state != LoadState.idle)) {
      scores = const {};
      state = LoadState.idle;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}

/// "Untuk kamu": giveaway yang belum diundi dari kategori yang diminati (skor > 0), skor tertinggi dulu, lalu draw terdekat.
/// Hanya mengurutkan/menyaring data yang sudah dimuat. Kosong bila affinity kosong.
List<Giveaway> recommendFor(List<Giveaway> items, Map<String, int> affinity, DateTime now, {int limit = 6}) {
  if (affinity.isEmpty) return const [];
  final picked = [
    for (final g in items)
      if ((affinity[g.category] ?? 0) > 0 && (g.phaseAt(now) == GiveawayPhase.active || g.phaseAt(now) == GiveawayPhase.upcoming)) g,
  ];
  picked.sort((a, b) {
    final byScore = (affinity[b.category] ?? 0).compareTo(affinity[a.category] ?? 0);
    if (byScore != 0) return byScore;
    final da = a.drawAt, db = b.drawAt;
    if (da == null || db == null) return da == null ? (db == null ? 0 : 1) : -1;
    return da.compareTo(db);
  });
  return picked.take(limit).toList();
}
