import '../giveaways/affinity_controller.dart' show recommendFor;
import '../giveaways/giveaway_models.dart';
import '../tickets/ticket_models.dart';

/// Narasi Code Hunt (kode -> tiket -> draw) di atas labirin: murni tampilan, tidak mengubah skor, fisika, atau kontrak
/// POST /game/scores. Satu item koleksi = satu "segmen kode" 4 karakter; jumlah segmen = jumlah item koleksi labirin.

const _alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';

/// Karakter yang TIDAK pernah dipakai kode redeem asli (backend\src\services\codes.js: tanpa I/O/0/1).
const _neverInRealCodes = 'IO01';

const emptySegment = '····';

/// PRNG kecil buatan sendiri (xorshift32 dari hash FNV-1a): hasil tetap sama di semua versi Dart/platform,
/// tidak seperti dart:math Random yang tidak menjamin urutan antarversi.
class _Stream {
  _Stream(int seed) : _s = _mix(seed);
  int _s;

  static int _mix(int v) {
    var h = 0x811C9DC5;
    for (var i = 0; i < 4; i++) {
      h = ((h ^ ((v >> (8 * i)) & 0xFF)) * 0x01000193) & 0xFFFFFFFF;
    }
    return h == 0 ? 0x9E3779B9 : h;
  }

  int next(int bound) {
    _s ^= (_s << 13) & 0xFFFFFFFF;
    _s ^= _s >> 17;
    _s ^= (_s << 5) & 0xFFFFFFFF;
    return _s % bound;
  }
}

/// [count] segmen 4 karakter (A-Z, 0-9), deterministik untuk [seed] yang sama. Karakter pertama segmen pertama selalu salah satu
/// dari I/O/0/1 sehingga kode latihan TIDAK PERNAH sama dengan kode redeem asli (yang tidak memuat keempat karakter itu).
List<String> practiceSegments(int seed, int count) {
  final r = _Stream(seed);
  return [
    for (var i = 0; i < count; i++)
      [
        for (var j = 0; j < 4; j++)
          i == 0 && j == 0 ? _neverInRealCodes[r.next(_neverInRealCodes.length)] : _alphabet[r.next(_alphabet.length)],
      ].join(),
  ];
}

/// Susunan tampil kode: 3 segmen per baris, "XXXX-XXXX-XXXX"; baris terakhir bisa lebih pendek. Segmen ke-[filled] dan
/// sesudahnya tampil "····". [filled] dibatasi 0..jumlah segmen.
List<String> codeRows(List<String> segments, int filled) {
  final f = filled.clamp(0, segments.length);
  final cells = [for (var i = 0; i < segments.length; i++) i < f ? segments[i] : emptySegment];
  return [for (var i = 0; i < cells.length; i += 3) cells.skip(i).take(3).join('-')];
}

/// Seed kode latihan satu permainan: dari seed labirin dan tingkat, jadi kode tetap sama untuk labirin yang sama.
int levelCodeSeed(int mazeSeed, int levelIndex) => mazeSeed + levelIndex * 7919;

/// Nomor tiket latihan, mis. "TL-0421": awalan membedakannya dari nomor tiket asli ("#000012").
String practiceTicketNumber(int seed) => 'TL-${(_Stream(seed ^ 0x5bd1e995).next(10000)).toString().padLeft(4, '0')}';

/// Giveaway yang jadi "latihan untuk": giveaway milik pengguna yang masih berjalan (aktif/menunggu draw, terdekat draw-nya),
/// kalau tidak ada = teratas "Untuk kamu". Hanya dari data yang sudah ada di controller/cache; null = tampil generik.
class PracticeTarget {
  const PracticeTarget({required this.title, required this.category});
  final String title, category;

  static PracticeTarget? pick({required List<Ticket> tickets, required List<Giveaway> giveaways, required Map<String, int> affinity, required DateTime now}) {
    final byId = {for (final g in giveaways) g.id: g};
    final owned = [
      for (final t in tickets)
        if (t.result == TicketResult.eligible || t.result == TicketResult.waitingForDraw) t,
    ]..sort((a, b) => (a.drawAt ?? DateTime(9999)).compareTo(b.drawAt ?? DateTime(9999)));
    for (final t in owned) {
      final g = byId[t.giveawayId];
      final phase = g?.phaseAt(now);
      final live = g == null ? (t.drawAt == null || t.drawAt!.isAfter(now)) : phase == GiveawayPhase.active || phase == GiveawayPhase.waitingDraw;
      if (live && t.giveawayTitle.isNotEmpty) return PracticeTarget(title: t.giveawayTitle, category: g?.category ?? t.category);
    }
    final top = recommendFor(giveaways, affinity, now, limit: 1);
    return top.isEmpty ? null : PracticeTarget(title: top.first.title, category: top.first.category);
  }
}
