import 'dart:convert';

import '../../core/json.dart';

/// Satu pemenang dari GET /giveaways/:id/winners. Nama sudah disamarkan server; tidak ada data pribadi lain.
class DrawWinner {
  const DrawWinner({required this.rank, required this.ticketNumber, required this.name});
  final int rank, ticketNumber;
  final String name;

  static DrawWinner? tryParse(dynamic raw) {
    final j = asMap(raw);
    if (j == null || j['ticket_number'] == null) return null;
    return DrawWinner(rank: asInt(j['rank']), ticketNumber: asInt(j['ticket_number']), name: asString(j['name']) ?? '');
  }

  Map<String, dynamic> toJson() => {'rank': rank, 'ticket_number': ticketNumber, 'name': name};
}

/// Hasil draw yang sudah final (giveaway berstatus drawn) untuk cache offline: ringkasan + pemenang publik.
/// Tidak memuat seed, token, atau data pribadi; penanda "tiket milikmu" dihitung dari tiket pengguna, bukan disimpan.
class CachedDrawResult {
  const CachedDrawResult({
    required this.giveawayId,
    required this.winners,
    this.drawnAtMs,
    this.totalTickets,
    this.status = 'drawn',
    this.cachedAt,
  });

  final String giveawayId, status;
  final int? drawnAtMs, totalTickets;
  final List<DrawWinner> winners;

  /// Diisi penyimpanan saat dibaca (null pada objek yang baru dibuat).
  final DateTime? cachedAt;

  Map<String, Object?> toRow(String userId, DateTime now) => {
        'giveaway_id': giveawayId,
        'user_id': userId,
        'status': status,
        'drawn_at_ms': drawnAtMs,
        'total_tickets': totalTickets,
        'winner_count': winners.length,
        'winners_json': jsonEncode([for (final w in winners) w.toJson()]),
        'cached_at': now.toUtc().toIso8601String(),
      };

  /// null bila baris rusak.
  static CachedDrawResult? tryParse(Map<String, Object?> r) {
    try {
      final id = r['giveaway_id'] as String?;
      final at = DateTime.tryParse(r['cached_at'] as String? ?? '');
      final list = jsonDecode(r['winners_json'] as String? ?? '');
      if (id == null || at == null || list is! List) return null;
      return CachedDrawResult(
        giveawayId: id,
        status: r['status'] as String? ?? 'drawn',
        drawnAtMs: (r['drawn_at_ms'] as num?)?.toInt(),
        totalTickets: (r['total_tickets'] as num?)?.toInt(),
        winners: parseList(list, DrawWinner.tryParse),
        cachedAt: at.toLocal(),
      );
    } catch (_) {
      return null;
    }
  }
}
