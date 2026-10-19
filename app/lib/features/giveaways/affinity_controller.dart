import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../auth/auth_controller.dart';
import '../discover/discover_filters.dart' show categoryLabel;
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

/// Format jarak untuk alasan rekomendasi: desimal koma lokal, tanpa desimal nol (mis. 5 atau 2,3).
String _formatKmReason(double km) {
  if (km < 0.1) return '<0,1';
  final s = km.toStringAsFixed(1).replaceAll('.', ',');
  return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
}

/// Menghitung alasan rekomendasi per giveaway (PRD FR-AI-01 AC4):
/// 1. Afinitas:
///    - Kategori dengan skor tertinggi: "Karena kamu sering ikut kategori {kategori}"
///    - Skor > 0 tetapi bukan teratas: "Sesuai minatmu di {kategori}"
///    - Afinitas kosong / skor <= 0: tidak ada alasan afinitas
/// 2. Alasan kedua (opsional, jika ada):
///    - draw < 24 jam: "Draw segera"
///    - jarak diketahui: "{n} km dari kamu"
/// Maksimal 2 alasan per kartu, urutan: afinitas dulu.
List<String> recommendationReasons(
  Giveaway giveaway,
  Map<String, int> affinity,
  DateTime now,
) {
  if (affinity.isEmpty) return const [];
  final score = affinity[giveaway.category] ?? 0;
  if (score <= 0) return const [];

  final reasons = <String>[];

  // 1. Alasan utama: afinitas
  final maxScore = affinity.values.fold(0, (max, v) => v > max ? v : max);
  final label = categoryLabel(giveaway.category);
  if (score >= maxScore) {
    reasons.add('Karena kamu sering ikut kategori $label');
  } else {
    reasons.add('Sesuai minatmu di $label');
  }

  // 2. Alasan kedua: draw < 24 jam
  final da = giveaway.drawAt;
  if (da != null) {
    final diff = da.difference(now);
    if (!diff.isNegative && diff < const Duration(hours: 24)) {
      reasons.add('Draw segera');
    }
  }

  // 3. Alasan kedua: jarak diketahui (jika masih kurang dari 2 alasan)
  final dist = giveaway.distanceKm;
  if (dist != null) {
    reasons.add('${_formatKmReason(dist)} km dari kamu');
  }

  return reasons.take(2).toList();
}
