import '../../core/json.dart';

/// Status tiket dari GET /tickets (kolom `result`).
enum TicketResult { eligible, waitingForDraw, winner, notSelected }

String _resultValue(TicketResult r) => switch (r) {
      TicketResult.winner => 'winner',
      TicketResult.notSelected => 'not_selected',
      TicketResult.waitingForDraw => 'waiting_for_draw',
      TicketResult.eligible => 'eligible',
    };

TicketResult _result(dynamic v) => switch (v) {
      'winner' => TicketResult.winner,
      'not_selected' => TicketResult.notSelected,
      'waiting_for_draw' => TicketResult.waitingForDraw,
      _ => TicketResult.eligible, // nilai baru/tak dikenal: tampil netral, bukan menang/kalah
    };

class Ticket {
  const Ticket({
    required this.id,
    required this.ticketNumber,
    required this.giveawayId,
    this.giveawayTitle = '',
    this.prizeName = '',
    this.category = 'other',
    this.endAt,
    this.drawAt,
    this.createdAt,
    this.result = TicketResult.eligible,
    this.codeMasked = '',
  });

  final String id, giveawayId, giveawayTitle, prizeName, category, codeMasked;
  final int ticketNumber;
  final DateTime? endAt, drawAt, createdAt;
  final TicketResult result;

  /// Baris tabel cached_tickets, terikat pengguna. Kode lengkap tidak pernah ada di sini (hanya yang disamarkan).
  Map<String, Object?> toRow(String userId, DateTime cachedAt) => {
        'id': id, 'user_id': userId, 'giveaway_id': giveawayId, 'giveaway_title': giveawayTitle,
        'prize_name': prizeName, 'ticket_number': ticketNumber, 'result': _resultValue(result),
        'end_at': endAt?.toUtc().toIso8601String(), 'draw_at': drawAt?.toUtc().toIso8601String(),
        'code_masked': codeMasked, 'created_at': createdAt?.toUtc().toIso8601String(),
        'cached_at': cachedAt.toUtc().toIso8601String(),
      };

  static Ticket? tryParse(dynamic raw) {
    final j = asMap(raw);
    final id = asString(j?['id']);
    final gid = asString(j?['giveaway_id']);
    if (j == null || id == null || gid == null) return null;
    return Ticket(
      id: id,
      ticketNumber: asInt(j['ticket_number']),
      giveawayId: gid,
      giveawayTitle: asString(j['giveaway_title']) ?? '',
      prizeName: asString(j['prize_name']) ?? '',
      category: asString(j['category']) ?? 'other',
      endAt: asDate(j['end_at']),
      drawAt: asDate(j['draw_at']),
      createdAt: asDate(j['created_at']),
      result: _result(j['result']),
      codeMasked: asString(j['code_masked']) ?? '',
    );
  }
}

/// Tiket yang baru dibuat oleh POST /codes/redeem.
class RedeemedTicket {
  const RedeemedTicket({
    required this.id,
    required this.ticketNumber,
    required this.giveawayId,
    this.giveawayTitle = '',
    this.prizeName = '',
    this.drawAt,
  });

  final String id, giveawayId, giveawayTitle, prizeName;
  final int ticketNumber;
  final DateTime? drawAt;

  static RedeemedTicket? tryParse(dynamic raw) {
    final j = asMap(raw);
    final id = asString(j?['id']);
    final gid = asString(j?['giveaway_id']);
    if (j == null || id == null || gid == null) return null;
    return RedeemedTicket(
      id: id,
      ticketNumber: asInt(j['ticket_number']),
      giveawayId: gid,
      giveawayTitle: asString(j['giveaway_title']) ?? '',
      prizeName: asString(j['prize_name']) ?? '',
      drawAt: asDate(j['draw_at']),
    );
  }
}

/// Hasil penukaran kode: tiket, atau kode galat dari backend (+ jeda bila rate_limited/locked).
class RedeemOutcome {
  const RedeemOutcome.success(RedeemedTicket this.ticket)
      : error = null,
        retryAfterSeconds = null;
  const RedeemOutcome.failure(String this.error, {this.retryAfterSeconds}) : ticket = null;

  final RedeemedTicket? ticket;
  final String? error;
  final int? retryAfterSeconds;
  bool get isSuccess => ticket != null;

  /// Respons POST /codes/redeem. Bentuk tak dikenal dianggap galat, bukan sukses.
  factory RedeemOutcome.fromJson(Map<String, dynamic> r) {
    if (r['ok'] == true) {
      final t = RedeemedTicket.tryParse(r['ticket']);
      if (t != null) return RedeemOutcome.success(t);
      return const RedeemOutcome.failure('bad_response');
    }
    return RedeemOutcome.failure(
      asString(r['error']) ?? 'unknown',
      retryAfterSeconds: r['retry_after_seconds'] == null ? null : asInt(r['retry_after_seconds']),
    );
  }
}
