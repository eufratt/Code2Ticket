import 'dart:convert';

import '../../core/db/rate_cache.dart' show SettingsStore;
import '../../core/verify/chain_verifier.dart' show genesisHash, sha256Hex;

/// Game "Rakit Rantai": latihan konsep hash-chain yang dipakai draw asli. Murni (tanpa jaringan/I/O), kecuali [ChainProgressStore].
/// Data latihan bukan data draw asli dan tidak pernah dikirim ke server.

enum ChainMode { arrange, inspect }

/// Satu block latihan: block_hash = SHA-256(previous_hash + "|" + payload). Hash penuh disimpan; yang tampil 8 hex pertama.
class ChainBlock {
  const ChainBlock({required this.index, required this.payload, required this.previousHash, required this.hash});
  final int index;
  final String payload, previousHash, hash;

  static String compute(String previousHash, String payload) => sha256Hex('$previousHash|$payload');

  String get shortHash => hash.substring(0, 8);
  String get shortPrevious => previousHash.substring(0, 8);

  /// Hash yang dihitung ulang dari previous_hash dan payload saat ini.
  String get recomputed => compute(previousHash, payload);
  String get shortRecomputed => recomputed.substring(0, 8);
  bool get hashMatches => recomputed == hash;
}

class ChainLevel {
  const ChainLevel(this.number, this.mode, this.blockCount);
  final int number, blockCount;
  final ChainMode mode;

  String get title => 'Level $number';
  String get modeLabel => mode == ChainMode.arrange ? 'Susun' : 'Periksa';

  /// Level 1-3 = Susun (3, 4, 5 block); level 4-5 = Periksa (5, 6 block).
  static const all = [
    ChainLevel(1, ChainMode.arrange, 3),
    ChainLevel(2, ChainMode.arrange, 4),
    ChainLevel(3, ChainMode.arrange, 5),
    ChainLevel(4, ChainMode.inspect, 5),
    ChainLevel(5, ChainMode.inspect, 6),
  ];
}

/// PRNG xorshift32 bersemai (hasil sama di semua platform; bukan acak sungguhan).
class _Rng {
  _Rng(int seed) : _s = (seed * 2654435761 + 0x9E3779B9) & 0xFFFFFFFF {
    if (_s == 0) _s = 0x9E3779B9;
  }
  int _s;
  int next(int bound) {
    _s ^= (_s << 13) & 0xFFFFFFFF;
    _s ^= _s >> 17;
    _s ^= (_s << 5) & 0xFFFFFFFF;
    return _s % bound;
  }
}

/// Teka-teki satu level, deterministik per nomor level.
class ChainPuzzle {
  ChainPuzzle._(this.level, this.correct, this.shuffled, this.brokenAfter);

  final ChainLevel level;

  /// Urutan benar (di mode Periksa, satu block sudah diubah dan hash-nya dihitung ulang).
  final List<ChainBlock> correct;

  /// Urutan tampil awal (mode Susun): acak, dijamin berbeda dari [correct].
  final List<ChainBlock> shuffled;

  /// Mode Periksa: posisi block t yang diubah; sambungan t -> t+1 putus (block t+1 masih menyimpan previous_hash lama). Bukan block
  /// terakhir. null di mode Susun.
  final int? brokenAfter;

  /// Hash baru block t (dihitung ulang) dan hash lama yang masih tersimpan di block t+1 (mode Periksa).
  String? get newHash => brokenAfter == null ? null : correct[brokenAfter!].shortHash;
  String? get storedHash => brokenAfter == null ? null : correct[brokenAfter! + 1].shortPrevious;

  static ChainPuzzle generate(ChainLevel level) {
    final r = _Rng(level.number * 7919 + 17);
    final blocks = <ChainBlock>[];
    var prev = genesisHash;
    for (var i = 0; i < level.blockCount; i++) {
      final payload = 'tiket #${(r.next(999999) + 1).toString().padLeft(6, '0')}';
      final h = ChainBlock.compute(prev, payload);
      blocks.add(ChainBlock(index: i, payload: payload, previousHash: prev, hash: h));
      prev = h;
    }
    if (level.mode == ChainMode.inspect) {
      // Block t (bukan yang terakhir) diubah payload-nya dan hash-nya dihitung ulang, jadi block t konsisten dengan dirinya sendiri;
      // block t+1 tetap menyimpan previous_hash lama, sehingga tepat satu sambungan (t -> t+1) putus.
      final t = r.next(level.blockCount - 1);
      var fake = blocks[t].payload;
      while (fake == blocks[t].payload) {
        fake = 'tiket #${(r.next(999999) + 1).toString().padLeft(6, '0')}';
      }
      blocks[t] = ChainBlock(index: t, payload: fake, previousHash: blocks[t].previousHash, hash: ChainBlock.compute(blocks[t].previousHash, fake));
      return ChainPuzzle._(level, blocks, List.of(blocks), t);
    }
    final order = List.of(blocks);
    for (var i = order.length - 1; i > 0; i--) {
      final j = r.next(i + 1);
      final tmp = order[i];
      order[i] = order[j];
      order[j] = tmp;
    }
    if (_sameOrder(order, blocks)) order.add(order.removeAt(0)); // putar satu: hash unik, jadi pasti berbeda
    return ChainPuzzle._(level, blocks, order, null);
  }

  static bool _sameOrder(List<ChainBlock> a, List<ChainBlock> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i].index != b[i].index) return false;
    }
    return true;
  }
}

/// Per posisi: true bila previous_hash block itu sama dengan hash block sebelumnya (posisi pertama: hash genesis).
List<bool> checkChain(List<ChainBlock> order) => [
      for (var i = 0; i < order.length; i++) order[i].previousHash == (i == 0 ? genesisHash : order[i - 1].hash),
    ];

/// Mode Periksa: sambungan i (antara block i dan i+1) utuh bila previous_hash block i+1 sama dengan hash block i.
bool linkIntact(List<ChainBlock> chain, int i) => chain[i + 1].previousHash == chain[i].hash;

/// Seluruh rantai bersambung.
bool isChained(List<ChainBlock> order) => checkChain(order).every((x) => x);

/// Progres lokal: level selesai dan langkah terbaik (lebih sedikit lebih baik). Tanpa XP/badge/skor server.
class ChainProgress {
  const ChainProgress({this.best = const {}});

  /// nomor level -> langkah terbaik; adanya kunci = level selesai.
  final Map<int, int> best;

  bool isDone(int level) => best.containsKey(level);

  ChainProgress record(int level, int steps) {
    final old = best[level];
    return ChainProgress(best: {...best, level: old == null || steps < old ? steps : old});
  }

  String encode() => jsonEncode({for (final e in best.entries) '${e.key}': e.value});

  static ChainProgress decode(String? raw) {
    if (raw == null) return const ChainProgress();
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return const ChainProgress();
      final out = <int, int>{};
      for (final e in j.entries) {
        final k = int.tryParse('${e.key}');
        final v = e.value;
        if (k != null && v is int && v >= 0) out[k] = v;
      }
      return ChainProgress(best: out);
    } catch (_) {
      return const ChainProgress();
    }
  }
}

/// Simpan progres di app_settings per pengguna (kunci `chain_progress`). Kegagalan penyimpanan tidak mengganggu permainan.
class ChainProgressStore {
  ChainProgressStore(this._store, this._userId);
  final SettingsStore? _store;
  final String _userId;

  static const key = 'chain_progress';

  Future<ChainProgress> load() async {
    try {
      return ChainProgress.decode(await _store?.getSetting(key, userId: _userId));
    } catch (_) {
      return const ChainProgress();
    }
  }

  /// Kartu "Cara main" per mode: true bila sudah pernah dibuka otomatis (kunjungan pertama).
  Future<bool> howToSeen(ChainMode m) async {
    try {
      return await _store?.getSetting('chain_howto_${m.name}', userId: _userId) == '1';
    } catch (_) {
      return false;
    }
  }

  Future<void> markHowToSeen(ChainMode m) async {
    try {
      await _store?.setSetting('chain_howto_${m.name}', '1', userId: _userId);
    } catch (_) {}
  }

  Future<ChainProgress> record(int level, int steps) async {
    final p = (await load()).record(level, steps);
    try {
      await _store?.setSetting(key, p.encode(), userId: _userId);
    } catch (_) {}
    return p;
  }
}
