import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/giveaways/recommendation.dart';
import 'package:flutter_test/flutter_test.dart';

final now = DateTime.utc(2026, 1, 1, 12);

Giveaway g(String id, {String cat = 'tech', Duration endIn = const Duration(days: 7), Duration startedAgo = const Duration(days: 30), double? km, int tickets = 0, String status = 'active'}) =>
    Giveaway(id: id, title: id, category: cat, startAt: now.subtract(startedAgo), endAt: now.add(endIn), drawAt: now.add(endIn), ticketCount: tickets, distanceKm: km, status: status);

double score(Giveaway x, Map<String, int> aff) => recommend([x], aff, now).single.score;

void main() {
  const aff = {'tech': 4};

  test('kedekatan: 0 km = penuh, 50 km = 0', () {
    expect(score(g('a', km: 0), aff) - score(g('b', km: 50), aff), closeTo(0.3, 1e-9));
    expect(score(g('c', km: 80), aff), closeTo(score(g('b', km: 50), aff), 1e-9));
  });

  test('urgensi: <=24 jam penuh, 14 hari nol, lewat end_at dikecualikan', () {
    final d = score(g('a', endIn: const Duration(hours: 24)), aff) - score(g('b', endIn: const Duration(days: 14)), aff);
    expect(d, closeTo(0.2 / 0.7, 1e-9)); // lokasi tidak diketahui -> bobot dinormalkan (total 0,7)
    expect(score(g('c', endIn: const Duration(hours: 1)), aff), closeTo(score(g('a', endIn: const Duration(hours: 24)), aff), 1e-9));
    expect(recommend([g('x', endIn: const Duration(seconds: -1))], aff, now), isEmpty);
  });

  test('lokasi tidak diketahui: bobot dinormalkan sehingga skor maks = 1', () {
    expect(score(g('a', endIn: const Duration(hours: 1), startedAgo: Duration.zero), aff), closeTo(1, 1e-9));
    expect(score(g('a', km: 0, endIn: const Duration(hours: 1), startedAgo: Duration.zero), aff), closeTo(1, 1e-9));
  });

  test('kebaruan: 0 setelah 30 hari, penuh saat baru mulai', () {
    expect(score(g('a', startedAgo: Duration.zero), aff) - score(g('b', startedAgo: const Duration(days: 30)), aff), closeTo(0.1 / 0.7, 1e-9));
  });

  test('cold start memakai popularitas dan alasan "Sedang populer"; <3 kandidat = kosong', () {
    final items = [g('a', cat: 'a', tickets: 2), g('b', cat: 'b', tickets: 10), g('c', cat: 'c', tickets: 5)];
    final r = recommend(items, const {}, now);
    expect(r.map((e) => e.giveaway.id), ['b', 'c', 'a']);
    expect(r.first.reasons, ['Sedang populer']);
    expect(recommend(items.take(2).toList(), const {}, now), isEmpty);
    expect(recommend(items.take(2).toList(), {'a': 1}, now), isNotEmpty);
  });

  test('keragaman: maks 3 per kategori, maks 10 total, minimal 3 bila cukup', () {
    final five = [for (var i = 0; i < 5; i++) g('t$i')];
    expect(recommend(five, aff, now).length, 3);
    final many = [for (var i = 0; i < 20; i++) g('g$i', cat: 'c${i % 5}')];
    final r = recommend(many, {'c0': 1}, now);
    expect(r.length, 10);
    final counts = <String, int>{};
    for (final e in r) { counts[e.giveaway.category] = (counts[e.giveaway.category] ?? 0) + 1; }
    expect(counts.values.every((n) => n <= 3), isTrue);
  });

  test('alasan: faktor dominan, maks 2, tanpa kontribusi nol', () {
    final near = recommend([g('a', cat: 'tech', km: 1, endIn: const Duration(hours: 5))], {'tech': 2, 'food': 5}, now).single;
    expect(near.reasons, ['1 km dari kamu', 'Batas ikut segera berakhir']); // 0,3*0,98 > 0,2*~1 > 0,4*0,5
    final mid = recommend([g('e', cat: 'tech')], {'tech': 3, 'food': 6}, now).single;
    expect(mid.reasons, ['Sesuai minatmu di Tech']);
    final top = recommend([g('b', cat: 'tech', km: 10)], {'tech': 3}, now).single;
    expect(top.reasons, ['Karena kamu sering ikut kategori Tech', '10 km dari kamu']);
    final none = recommend([g('c', cat: 'food', km: 60)], {'tech': 3}, now).single;
    expect(none.reasons, isEmpty); // afinitas 0, >=50 km, tidak mendesak
    final urgent = recommend([g('d', cat: 'food', endIn: const Duration(hours: 3))], {'tech': 3}, now).single;
    expect(urgent.reasons, ['Batas ikut segera berakhir']);
  });

  test('pengecualian: selesai (drawn/menunggu draw) dan belum dimulai', () {
    final items = [g('drawn', status: 'drawn'), g('wait', endIn: const Duration(hours: -1)), Giveaway(id: 'up', title: 'up', category: 'tech', startAt: now.add(const Duration(days: 1)), endAt: now.add(const Duration(days: 3))), g('ok')];
    expect(recommend(items, aff, now).map((e) => e.giveaway.id), ['ok']);
  });

  test('urutan stabil untuk skor sama', () {
    final r = recommend([g('x', cat: 'a'), g('y', cat: 'b'), g('z', cat: 'c')], const {}, now);
    expect(r.map((e) => e.giveaway.id), ['x', 'y', 'z']);
  });
}
