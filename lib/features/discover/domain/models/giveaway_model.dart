class GiveawayModel {
  final String id;
  final String title;
  final String category;
  final String prizeName;
  final double prizeValueUsd;
  final String? description;
  final double? latitude;
  final double? longitude;
  final double? radiusKm;
  final bool isGeoRestricted;
  final DateTime startAt;
  final DateTime endAt;
  final DateTime drawAt;
  final int winnerCount;
  final String status;
  final int ticketCount;
  final double? distanceKm;

  const GiveawayModel({
    required this.id,
    required this.title,
    required this.category,
    required this.prizeName,
    required this.prizeValueUsd,
    this.description,
    this.latitude,
    this.longitude,
    this.radiusKm,
    this.isGeoRestricted = false,
    required this.startAt,
    required this.endAt,
    required this.drawAt,
    this.winnerCount = 1,
    this.status = 'active',
    this.ticketCount = 0,
    this.distanceKm,
  });

  bool get isDrawing => status == 'drawing';
  bool get isCompleted => status == 'completed';
  bool get isActive => status == 'active';

  Duration get timeUntilDraw => drawAt.difference(DateTime.now());
  bool get hasEnded => DateTime.now().isAfter(drawAt);

  GiveawayModel copyWith({
    String? id,
    String? title,
    String? category,
    String? prizeName,
    double? prizeValueUsd,
    String? description,
    double? latitude,
    double? longitude,
    double? radiusKm,
    bool? isGeoRestricted,
    DateTime? startAt,
    DateTime? endAt,
    DateTime? drawAt,
    int? winnerCount,
    String? status,
    int? ticketCount,
    double? distanceKm,
  }) {
    return GiveawayModel(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      prizeName: prizeName ?? this.prizeName,
      prizeValueUsd: prizeValueUsd ?? this.prizeValueUsd,
      description: description ?? this.description,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusKm: radiusKm ?? this.radiusKm,
      isGeoRestricted: isGeoRestricted ?? this.isGeoRestricted,
      startAt: startAt ?? this.startAt,
      endAt: endAt ?? this.endAt,
      drawAt: drawAt ?? this.drawAt,
      winnerCount: winnerCount ?? this.winnerCount,
      status: status ?? this.status,
      ticketCount: ticketCount ?? this.ticketCount,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }

  factory GiveawayModel.fromJson(Map<String, dynamic> json) {
    final prizeValue = json['prize_value_usd'];
    final double parsedPrize = prizeValue is num
        ? prizeValue.toDouble()
        : double.tryParse(prizeValue?.toString() ?? '0') ?? 0.0;

    int tickets = 0;
    if (json['tickets'] is List && (json['tickets'] as List).isNotEmpty) {
      final first = (json['tickets'] as List).first;
      if (first is Map && first['count'] is int) {
        tickets = first['count'] as int;
      }
    } else if (json['ticket_count'] is int) {
      tickets = json['ticket_count'] as int;
    }

    final now = DateTime.now();
    return GiveawayModel(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Giveaway Event',
      category: json['category'] as String? ?? 'Umum',
      prizeName: json['prize_name'] as String? ??
          json['prize_description'] as String? ??
          json['description'] as String? ??
          '-',
      prizeValueUsd: parsedPrize,
      description: json['description'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      radiusKm: (json['radius_km'] as num?)?.toDouble(),
      isGeoRestricted: json['geo_restricted'] as bool? ?? false,
      startAt: json['start_at'] != null
          ? DateTime.tryParse(json['start_at'].toString()) ?? now
          : now,
      endAt: json['end_at'] != null
          ? DateTime.tryParse(json['end_at'].toString()) ?? now.add(const Duration(days: 30))
          : now.add(const Duration(days: 30)),
      drawAt: json['draw_at'] != null
          ? DateTime.tryParse(json['draw_at'].toString()) ?? now.add(const Duration(days: 31))
          : now.add(const Duration(days: 31)),
      winnerCount: json['winner_count'] as int? ?? 1,
      status: json['status'] as String? ?? 'active',
      ticketCount: tickets,
    );
  }
}
