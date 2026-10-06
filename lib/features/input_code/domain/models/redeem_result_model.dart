class RedeemTicketInfo {
  final String id;
  final String ticketNumber;
  final String giveawayId;
  final String giveawayTitle;
  final String status;
  final DateTime? drawAt;

  const RedeemTicketInfo({
    required this.id,
    required this.ticketNumber,
    required this.giveawayId,
    required this.giveawayTitle,
    required this.status,
    this.drawAt,
  });

  factory RedeemTicketInfo.fromJson(Map<String, dynamic> json) {
    return RedeemTicketInfo(
      id: json['id'] as String? ?? '',
      ticketNumber: json['ticket_number'] as String? ?? '',
      giveawayId: json['giveaway_id'] as String? ?? '',
      giveawayTitle: json['giveaway_title'] as String? ?? '',
      status: json['status'] as String? ?? 'waiting_for_draw',
      drawAt: json['draw_at'] != null ? DateTime.tryParse(json['draw_at'] as String) : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'ticket_number': ticketNumber,
      'giveaway_id': giveawayId,
      'giveaway_title': giveawayTitle,
      'status': status,
      'draw_at': drawAt?.toIso8601String(),
    };
  }
}

class RedeemResultModel {
  final bool success;
  final String message;
  final String? error;
  final RedeemTicketInfo? ticket;

  const RedeemResultModel({
    required this.success,
    required this.message,
    this.error,
    this.ticket,
  });

  factory RedeemResultModel.fromJson(Map<String, dynamic> json) {
    final success = json['success'] as bool? ?? false;
    final message = json['message'] as String? ?? (success ? 'Berhasil' : 'Gagal');
    final error = json['error'] as String?;
    final ticketData = json['ticket'] as Map<String, dynamic>?;

    return RedeemResultModel(
      success: success,
      message: message,
      error: error,
      ticket: ticketData != null ? RedeemTicketInfo.fromJson(ticketData) : null,
    );
  }
}
