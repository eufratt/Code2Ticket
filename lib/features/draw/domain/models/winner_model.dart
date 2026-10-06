class WinnerModel {
  final String id;
  final String drawId;
  final String ticketId;
  final String ticketNumber;
  final String username;
  final DateTime wonAt;

  const WinnerModel({
    required this.id,
    required this.drawId,
    required this.ticketId,
    required this.ticketNumber,
    required this.username,
    required this.wonAt,
  });

  factory WinnerModel.fromJson(Map<String, dynamic> json) {
    String tNumber = '-';
    String uName = 'Peserta';

    if (json['tickets'] is Map) {
      tNumber = (json['tickets'] as Map)['ticket_number']?.toString() ?? '-';
    } else if (json['ticket_number'] != null) {
      tNumber = json['ticket_number'].toString();
    }

    if (json['users'] is Map) {
      uName = (json['users'] as Map)['username']?.toString() ?? 'Peserta';
    } else if (json['username'] != null) {
      uName = json['username'].toString();
    }

    return WinnerModel(
      id: json['id'] as String? ?? '',
      drawId: json['draw_id'] as String? ?? '',
      ticketId: json['ticket_id'] as String? ?? '',
      ticketNumber: tNumber,
      username: uName,
      wonAt: json['created_at'] != null
          ? DateTime.tryParse(json['created_at'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
