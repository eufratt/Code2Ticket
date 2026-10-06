class HomeGiveawayItem {
  final String id;
  final String title;
  final String category;
  final String prize;
  final double prizeValueUsd;
  final String locationName;
  final double? radiusKm;
  final DateTime? drawAt;
  final int totalTicketsIssued;
  final bool isGeoRestricted;

  const HomeGiveawayItem({
    required this.id,
    required this.title,
    required this.category,
    required this.prize,
    required this.prizeValueUsd,
    required this.locationName,
    this.radiusKm,
    this.drawAt,
    this.totalTicketsIssued = 0,
    this.isGeoRestricted = false,
  });

  factory HomeGiveawayItem.fromJson(Map<String, dynamic> json) {
    final prizeValue = json['prize_value_usd'];
    final double parsedPrize = prizeValue is num
        ? prizeValue.toDouble()
        : double.tryParse(prizeValue?.toString() ?? '0') ?? 0.0;

    return HomeGiveawayItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Giveaway Event',
      category: json['category'] as String? ?? 'Umum',
      prize: json['prize_description'] as String? ??
          json['description'] as String? ??
          '',
      prizeValueUsd: parsedPrize,
      locationName: json['geo_restricted'] == true
          ? 'Daerah Istimewa Yogyakarta'
          : 'Nasional / Seluruh Indonesia',
      radiusKm: (json['radius_km'] as num?)?.toDouble(),
      drawAt: json['draw_at'] != null
          ? DateTime.tryParse(json['draw_at'].toString())
          : null,
      totalTicketsIssued: json['ticket_count'] as int? ?? 0,
      isGeoRestricted: json['geo_restricted'] as bool? ?? false,
    );
  }
}

class HomeSummaryModel {
  final int totalTickets;
  final int activeTickets;
  final HomeGiveawayItem? nearestDraw;
  final List<HomeGiveawayItem> recommendedDraws;
  final List<HomeGiveawayItem> nearbyDraws;

  const HomeSummaryModel({
    required this.totalTickets,
    required this.activeTickets,
    this.nearestDraw,
    required this.recommendedDraws,
    required this.nearbyDraws,
  });
}
