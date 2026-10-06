class TicketModel {
  final String id;
  final String ticketNumber;
  final String giveawayId;
  final String giveawayTitle;
  final String giveawayCategory;
  final String prizeDescription;
  final double prizeValueUsd;
  final String status; // 'waiting_for_draw', 'eligible', 'winner', 'not_selected'
  final DateTime? drawAt;
  final DateTime createdAt;
  final String? code;
  final bool isWinner;
  final String? blockchainProof;

  const TicketModel({
    required this.id,
    required this.ticketNumber,
    required this.giveawayId,
    required this.giveawayTitle,
    required this.giveawayCategory,
    required this.prizeDescription,
    required this.prizeValueUsd,
    required this.status,
    this.drawAt,
    required this.createdAt,
    this.code,
    this.isWinner = false,
    this.blockchainProof,
  });

  factory TicketModel.fromJson(Map<String, dynamic> json) {
    final giveaway = json['giveaways'] as Map<String, dynamic>?;
    final codeMap = json['codes'] as Map<String, dynamic>?;
    final winnersList = json['winners'] as List<dynamic>?;
    final isWinner = (winnersList != null && winnersList.isNotEmpty) ||
        json['status'] == 'winner';

    DateTime? drawDate;
    if (giveaway != null && giveaway['draw_at'] != null) {
      drawDate = DateTime.tryParse(giveaway['draw_at'].toString());
    } else if (json['draw_at'] != null) {
      drawDate = DateTime.tryParse(json['draw_at'].toString());
    }

    final prizeValue = giveaway?['prize_value_usd'];
    final double parsedPrize = prizeValue is num
        ? prizeValue.toDouble()
        : double.tryParse(prizeValue?.toString() ?? '0') ?? 0.0;

    return TicketModel(
      id: json['id'] as String? ?? '',
      ticketNumber: json['ticket_number'] as String? ?? '',
      giveawayId: json['giveaway_id'] as String? ?? giveaway?['id'] as String? ?? '',
      giveawayTitle: giveaway?['title'] as String? ?? json['giveaway_title'] as String? ?? 'Giveaway',
      giveawayCategory: giveaway?['category'] as String? ?? 'General',
      prizeDescription: giveaway?['prize_name'] as String? ??
          giveaway?['prize_description'] as String? ??
          giveaway?['description'] as String? ??
          '',
      prizeValueUsd: parsedPrize,
      status: isWinner ? 'winner' : (json['status'] as String? ?? 'waiting_for_draw'),
      drawAt: drawDate,
      createdAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
      code: codeMap?['code'] as String? ?? json['code'] as String?,
      isWinner: isWinner,
      blockchainProof: json['blockchain_proof'] as String?,
    );
  }
}

/// Helper model to group tickets by their respective giveaway
class GiveawayTicketsGroup {
  final String giveawayId;
  final String giveawayTitle;
  final String giveawayCategory;
  final String prizeDescription;
  final double prizeValueUsd;
  final DateTime? drawAt;
  final List<TicketModel> tickets;

  const GiveawayTicketsGroup({
    required this.giveawayId,
    required this.giveawayTitle,
    required this.giveawayCategory,
    required this.prizeDescription,
    required this.prizeValueUsd,
    this.drawAt,
    required this.tickets,
  });

  bool get hasWinner => tickets.any((t) => t.isWinner);
  int get ticketCount => tickets.length;
}
