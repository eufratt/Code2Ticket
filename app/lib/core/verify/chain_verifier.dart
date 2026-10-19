import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import '../json.dart';

// Implementasi ulang kontrak hash-chain commit-reveal di Dart, IDENTIK dengan backend\src\lib\chain.js dan
// backend\test\reference\test_m1.py (verify). Jangan ubah format di sini tanpa mengubah kontrak di backend.
// Tes kecocokan: test\verify\chain_verifier_test.dart memakai vektor yang dihasilkan implementasi acuan Python.

const genesisHash = '0000000000000000000000000000000000000000000000000000000000000000';

const _hex = '0123456789abcdef';

/// SHA-256 dari teks UTF-8, heksadesimal huruf kecil (pointycastle; bukan implementasi sendiri).
String sha256Hex(String s) {
  final out = SHA256Digest().process(Uint8List.fromList(utf8.encode(s)));
  final b = StringBuffer();
  for (final x in out) {
    b..write(_hex[x >> 4])..write(_hex[x & 15]);
  }
  return b.toString();
}

/// Nilai dalam template string JavaScript: null menjadi "null" (sama dengan chain.js).
String _js(Object? v) => v == null ? 'null' : '$v';

/// Satu baris draw_chain dari GET /giveaways/:id/verification.
class ChainBlock {
  const ChainBlock({
    required this.blockIndex,
    required this.blockType,
    required this.giveawayId,
    required this.previousHash,
    required this.blockHash,
    required this.tsMs,
    this.drawId,
    this.seedHash,
    this.seed,
    this.winnerCount,
    this.totalTickets,
    this.ticketsHash,
    this.winningTickets,
  });

  final int blockIndex, tsMs;
  final String blockType, giveawayId, previousHash, blockHash;
  final String? drawId, seedHash, seed, ticketsHash, winningTickets;
  final int? winnerCount, totalTickets;

  bool get isCommit => blockType == 'commit';
  bool get isResult => blockType == 'result';

  /// null bila kolom wajib hilang (data rusak).
  static ChainBlock? tryParse(dynamic raw) {
    final j = asMap(raw);
    if (j == null) return null;
    final type = asString(j['block_type']);
    final gid = asString(j['giveaway_id']);
    final prev = asString(j['previous_hash']);
    final hash = asString(j['block_hash']);
    if (type == null || gid == null || prev == null || hash == null || j['block_index'] == null || j['ts_ms'] == null) return null;
    int? optInt(String k) => j[k] == null ? null : asInt(j[k], 0);
    return ChainBlock(
      blockIndex: asInt(j['block_index']),
      blockType: type,
      giveawayId: gid,
      previousHash: prev,
      blockHash: hash,
      tsMs: asInt(j['ts_ms']),
      drawId: asString(j['draw_id']),
      seedHash: asString(j['seed_hash']),
      seed: asString(j['seed']),
      winnerCount: optInt('winner_count'),
      totalTickets: optInt('total_tickets'),
      ticketsHash: asString(j['tickets_hash']),
      winningTickets: asString(j['winning_tickets']),
    );
  }

  /// Teks yang di-hash (chain.js: blockHashInput).
  String get hashInput => isCommit
      ? 'C|${_js(blockIndex)}|$giveawayId|${_js(seedHash)}|${_js(winnerCount)}|${_js(tsMs)}|$previousHash'
      : 'R|${_js(blockIndex)}|$giveawayId|${_js(drawId)}|${_js(seed)}|${_js(totalTickets)}|'
          '${_js(ticketsHash)}|${_js(winningTickets)}|${_js(tsMs)}|$previousHash';

  String computeHash() => sha256Hex(hashInput);
}

/// Isi GET /giveaways/:id/verification (setelah ok:true). [tickets] baru ada setelah draw: [nomor, owner_key] terurut.
class VerificationData {
  const VerificationData({
    required this.giveawayId,
    required this.winnerCount,
    required this.status,
    required this.seedHash,
    required this.chain,
    this.firstTicketMs,
    this.tickets,
  });

  final String giveawayId, status, seedHash;
  final int winnerCount;
  final List<ChainBlock> chain;
  final int? firstTicketMs;
  final List<(int, String)>? tickets;

  static VerificationData? tryParse(Map<String, dynamic> j) {
    final g = asMap(j['giveaway']);
    final id = asString(g?['id']);
    if (g == null || id == null || j['chain'] is! List) return null;
    final chain = <ChainBlock>[];
    for (final e in j['chain'] as List) {
      final b = ChainBlock.tryParse(e);
      if (b == null) return null; // satu blok rusak = data tidak bisa dipercaya
      chain.add(b);
    }
    List<(int, String)>? tickets;
    if (j['tickets'] is List) {
      tickets = [];
      for (final t in j['tickets'] as List) {
        if (t is! List || t.length != 2 || t[0] is! num || t[1] is! String) return null;
        tickets.add(((t[0] as num).toInt(), t[1] as String));
      }
    }
    return VerificationData(
      giveawayId: id,
      winnerCount: asInt(g['winner_count'], 1),
      status: asString(g['status']) ?? '',
      seedHash: asString(g['seed_hash']) ?? '',
      chain: chain,
      firstTicketMs: j['first_ticket_ms'] == null ? null : asInt(j['first_ticket_ms']),
      tickets: tickets,
    );
  }

  ChainBlock? get commit => chain.where((b) => b.giveawayId == giveawayId && b.isCommit).firstOrNull;
  ChainBlock? get result => chain.where((b) => b.giveawayId == giveawayId && b.isResult).firstOrNull;
}

/// chain.js: ticketsHash dan pickWinners. [tickets] = [(nomor, owner_key)] terurut naik.
String ticketsHash(List<(int, String)> tickets) => sha256Hex(tickets.map((t) => '${t.$1}:${t.$2}').join(','));

/// 7 byte pertama hash (56 bit, muat di int 64-bit) modulo ukuran kumpulan; satu hadiah per owner_key.
({String ticketsHash, List<int> winners}) pickWinners(String seed, String giveawayId, List<(int, String)> tickets, int winnerCount) {
  final th = ticketsHash(tickets);
  var pool = tickets;
  final winners = <int>[];
  for (var j = 0; winners.length < winnerCount && pool.isNotEmpty; j++) {
    final h = sha256Hex('$seed:$giveawayId:$th:$j');
    final idx = int.parse(h.substring(0, 14), radix: 16) % pool.length;
    final (n, o) = pool[idx];
    winners.add(n);
    pool = [for (final t in pool) if (t.$2 != o) t];
  }
  return (ticketsHash: th, winners: winners);
}

/// chain.js: ownerKey (dipakai tes vektor; app tidak membutuhkannya untuk verifikasi).
String ownerKey(String userId, String giveawayId) => sha256Hex('$userId:$giveawayId').substring(0, 12);

enum StepStatus { pass, fail, skipped }

enum VerifyStepId { commit, chain, seed, winners }

/// Satu langkah verifikasi untuk orang awam. [evidence] = nilai hash yang diperiksa (ditampilkan terpotong + salin).
class VerifyStep {
  const VerifyStep(this.id, this.status, this.detail, {this.evidence = const []});
  final VerifyStepId id;
  final StepStatus status;
  final String detail;
  final List<({String label, String value})> evidence;
}

class VerificationReport {
  const VerificationReport({required this.steps, required this.drawn, this.winningTickets = const [], this.totalTickets, this.drawnAtMs});
  final List<VerifyStep> steps;

  /// false = giveaway belum diundi (seed masih terkunci): hanya langkah rantai dan komitmen yang bisa diperiksa.
  final bool drawn;

  /// Pemenang yang DIHITUNG ULANG di perangkat.
  final List<int> winningTickets;
  final int? totalTickets;
  final int? drawnAtMs;

  VerifyStep step(VerifyStepId id) => steps.firstWhere((s) => s.id == id);
  bool get verified => drawn && steps.every((s) => s.status == StepStatus.pass);
  bool get mismatch => steps.any((s) => s.status == StepStatus.fail);
}

/// Memverifikasi data server sepenuhnya di perangkat; mengikuti verify() di backend\test\reference\test_m1.py.
/// [announced] = nomor tiket pemenang dari GET /winners; bila diberikan harus sama dengan hasil hitung ulang.
VerificationReport verifyData(VerificationData d, {List<int>? announced}) {
  final commit = d.commit, result = d.result;
  final drawn = result != null;

  // 1. Komitmen
  VerifyStep commitStep;
  if (commit == null) {
    commitStep = const VerifyStep(VerifyStepId.commit, StepStatus.fail, 'Catatan komitmen seed tidak ditemukan di rantai.');
  } else if (d.firstTicketMs != null && commit.tsMs > d.firstTicketMs!) {
    commitStep = VerifyStep(VerifyStepId.commit, StepStatus.fail, 'Komitmen seed dibuat SETELAH tiket pertama terbit, sehingga bisa saja disesuaikan.',
        evidence: [(label: 'Hash komitmen', value: commit.seedHash ?? '')]);
  } else {
    commitStep = VerifyStep(VerifyStepId.commit, StepStatus.pass, 'Seed dikunci (hanya hash-nya yang tercatat) sebelum tiket pertama terbit.',
        evidence: [(label: 'Hash komitmen', value: commit.seedHash ?? '')]);
  }

  // 2. Rantai
  var prev = genesisHash;
  String? brokenAt;
  for (final b in d.chain) {
    if (b.previousHash != prev) {
      brokenAt = 'Blok ${b.blockIndex} tidak tersambung ke blok sebelumnya.';
      break;
    }
    if (b.computeHash() != b.blockHash) {
      brokenAt = 'Isi blok ${b.blockIndex} tidak cocok dengan hash-nya (data diubah).';
      break;
    }
    prev = b.blockHash;
  }
  final chainStep = brokenAt != null
      ? VerifyStep(VerifyStepId.chain, StepStatus.fail, brokenAt)
      : VerifyStep(VerifyStepId.chain, StepStatus.pass, '${d.chain.length} blok dihitung ulang; tiap blok tersambung ke blok sebelumnya tanpa putus.',
          evidence: d.chain.isEmpty ? const [] : [(label: 'Hash blok terakhir', value: d.chain.last.blockHash)]);

  // 3. Seed vs komitmen
  VerifyStep seedStep;
  if (!drawn) {
    seedStep = const VerifyStep(VerifyStepId.seed, StepStatus.skipped, 'Belum bisa diperiksa: giveaway belum diundi, seed masih terkunci.');
  } else if (commit == null) {
    seedStep = const VerifyStep(VerifyStepId.seed, StepStatus.fail, 'Tidak ada komitmen untuk dibandingkan dengan seed.');
  } else {
    final seed = result.seed;
    final computed = seed == null ? null : sha256Hex(seed);
    final ok = computed != null && computed == commit.seedHash && (d.seedHash.isEmpty || d.seedHash == commit.seedHash);
    seedStep = VerifyStep(
      VerifyStepId.seed,
      ok ? StepStatus.pass : StepStatus.fail,
      ok ? 'Seed yang dibuka saat draw, di-hash ulang, sama dengan komitmen yang dikunci sebelumnya.' : 'Seed yang dibuka TIDAK cocok dengan komitmen sebelum draw.',
      evidence: [(label: 'Hash seed (dihitung)', value: computed ?? '-'), (label: 'Hash komitmen', value: commit.seedHash ?? '-')],
    );
  }

  // 4. Pemenang
  VerifyStep winnersStep;
  var recomputed = <int>[];
  if (!drawn) {
    winnersStep = const VerifyStep(VerifyStepId.winners, StepStatus.skipped, 'Belum bisa diperiksa: giveaway belum diundi.');
  } else if (commit == null || result.seed == null || d.tickets == null) {
    winnersStep = const VerifyStep(VerifyStepId.winners, StepStatus.fail, 'Data untuk menghitung ulang pemenang tidak lengkap.');
  } else {
    final r = pickWinners(result.seed!, d.giveawayId, d.tickets!, commit.winnerCount ?? d.winnerCount);
    recomputed = r.winners;
    final claimed = result.winningTickets ?? '';
    final String? problem;
    if (r.ticketsHash != result.ticketsHash) {
      problem = 'Daftar tiket peserta tidak cocok dengan yang dicatat saat draw.';
    } else if (r.winners.join(',') != claimed) {
      problem = 'Pemenang hasil hitung ulang berbeda dari hasil yang dicatat server.';
    } else if (announced != null && !_sameSet(announced, r.winners)) {
      problem = 'Pemenang yang ditampilkan di app berbeda dari hasil hitung ulang.';
    } else {
      problem = null;
    }
    winnersStep = VerifyStep(
      VerifyStepId.winners,
      problem == null ? StepStatus.pass : StepStatus.fail,
      problem ?? 'Pemenang dihitung ulang dari seed dan daftar ${d.tickets!.length} tiket; hasilnya sama persis dengan hasil server.',
      evidence: [(label: 'Hash daftar tiket', value: r.ticketsHash), (label: 'Tiket pemenang (dihitung)', value: r.winners.join(', '))],
    );
  }

  return VerificationReport(
    steps: [commitStep, chainStep, seedStep, winnersStep],
    drawn: drawn,
    winningTickets: recomputed,
    totalTickets: result?.totalTickets,
    drawnAtMs: result?.tsMs,
  );
}

bool _sameSet(List<int> a, List<int> b) => a.length == b.length && a.toSet().containsAll(b);

/// Titik masuk untuk compute()/isolate: hanya tipe sederhana yang dikirim. null = data tidak bisa dibaca.
VerificationReport? verifyRaw(({Map<String, dynamic> raw, List<int>? announced}) args) {
  final d = VerificationData.tryParse(args.raw);
  return d == null ? null : verifyData(d, announced: args.announced);
}
