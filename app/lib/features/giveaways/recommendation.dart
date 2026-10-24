import '../discover/discover_filters.dart' show categoryLabel;
import 'giveaway_models.dart';
import 'recommendation_config.dart';

/// Satu rekomendasi: giveaway, skor 0..1, dan alasan (maks. 2) dari faktor berkontribusi terbesar.
class Recommendation {
  const Recommendation(this.giveaway, this.score, this.reasons);
  final Giveaway giveaway;
  final double score;
  final List<String> reasons;
}

typedef _C = RecommendationConfig;

double _clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Linear: 1 pada [full], 0 pada [zero] atau lebih (satuan bebas, harus zero > full).
double _falloff(double v, double full, double zero) => _clamp01(1 - (v - full) / (zero - full));

/// Desimal koma lokal tanpa nol di belakang (mis. 5 atau 2,3).
String _formatKm(double km) {
  if (km < 0.1) return '<0,1';
  final s = km.toStringAsFixed(1).replaceAll('.', ',');
  return s.endsWith(',0') ? s.substring(0, s.length - 2) : s;
}

/// Rekomendasi "Untuk kamu" (fungsi murni, jalan dari data yang sudah dimuat/cache):
/// skor = 0,4*afinitas + 0,3*kedekatan + 0,2*urgensi + 0,1*kebaruan; cold start: afinitas diganti popularitas.
/// Hanya giveaway aktif yang belum lewat end_at. Batas tiket per pengguna tidak ada di data daftar/cache, jadi tidak diperiksa.
/// Daftar kosong bila cold start dengan kandidat < 3. Urutan seri stabil (urutan masukan).
List<Recommendation> recommend(List<Giveaway> items, Map<String, int> affinity, DateTime now) {
  final candidates = [
    for (final g in items)
      if (g.phaseAt(now) == GiveawayPhase.active && (g.endAt == null || g.endAt!.isAfter(now))) g,
  ];
  final total = affinity.values.where((v) => v > 0).fold(0, (a, b) => a + b);
  final coldStart = total == 0;
  if (candidates.isEmpty || (coldStart && candidates.length < _C.minCandidatesForColdStart)) return const [];

  final maxAffinity = affinity.values.fold(0, (m, v) => v > m ? v : m);
  final maxTickets = candidates.fold(0, (m, g) => g.ticketCount > m ? g.ticketCount : m);
  final locationKnown = candidates.any((g) => g.distanceKm != null);

  final wSum = _C.weightAffinity + _C.weightUrgency + _C.weightFreshness + (locationKnown ? _C.weightProximity : 0);
  final wMain = _C.weightAffinity / wSum;
  final wProx = locationKnown ? _C.weightProximity / wSum : 0.0;
  final wUrg = _C.weightUrgency / wSum;
  final wFresh = _C.weightFreshness / wSum;

  final scored = <(int, Recommendation)>[];
  for (var i = 0; i < candidates.length; i++) {
    final g = candidates[i];
    final main = coldStart
        ? (maxTickets == 0 ? 0.0 : g.ticketCount / maxTickets)
        : (maxAffinity == 0 ? 0.0 : _clamp01((affinity[g.category] ?? 0) / maxAffinity));
    final km = g.distanceKm;
    final prox = km == null ? 0.0 : _falloff(km, 0, _C.proximityZeroKm);
    final remaining = g.endAt?.difference(now);
    final urg = remaining == null
        ? 0.0
        : _falloff(remaining.inSeconds.toDouble(), _C.urgencyFullWithin.inSeconds.toDouble(), _C.urgencyZeroAt.inSeconds.toDouble());
    final age = g.startAt == null ? null : now.difference(g.startAt!);
    final fresh = age == null ? 0.0 : _falloff(age.inSeconds.toDouble(), 0, _C.freshnessZeroAfter.inSeconds.toDouble());

    final cMain = wMain * main, cProx = wProx * prox, cUrg = wUrg * urg;
    final label = categoryLabel(g.category);
    // Kontribusi sama -> urutan daftar ini (afinitas, kedekatan, urgensi); kontribusi nol tidak jadi alasan.
    final reasonCandidates = <(double, String)>[
      (cMain, coldStart ? 'Sedang populer' : (affinity[g.category] ?? 0) >= maxAffinity ? 'Karena kamu sering ikut kategori $label' : 'Sesuai minatmu di $label'),
      (cProx, '${_formatKm(km ?? 0)} km dari kamu'),
      (remaining != null && remaining < _C.urgencyFullWithin ? cUrg : 0, 'Batas ikut segera berakhir'),
    ];
    final order = [for (var k = 0; k < reasonCandidates.length; k++) if (reasonCandidates[k].$1 > 0) k]
      ..sort((x, y) {
        final c = reasonCandidates[y].$1.compareTo(reasonCandidates[x].$1);
        return c != 0 ? c : x.compareTo(y);
      });
    final reasons = [for (final k in order.take(_C.maxReasons)) reasonCandidates[k].$2];
    scored.add((i, Recommendation(g, cMain + cProx + cUrg + wFresh * fresh, reasons)));
  }

  scored.sort((a, b) {
    final c = b.$2.score.compareTo(a.$2.score);
    return c != 0 ? c : a.$1.compareTo(b.$1);
  });

  final perCategory = <String, int>{};
  final out = <Recommendation>[];
  for (final (_, r) in scored) {
    if (out.length >= _C.maxTotal) break;
    final n = perCategory[r.giveaway.category] ?? 0;
    if (n >= _C.maxPerCategory) continue;
    perCategory[r.giveaway.category] = n + 1;
    out.add(r);
  }
  return out;
}
