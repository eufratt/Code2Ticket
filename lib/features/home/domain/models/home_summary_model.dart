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
  final double? latitude;
  final double? longitude;
  final double? distanceKm;

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
    this.latitude,
    this.longitude,
    this.distanceKm,
  });

  bool get isWithinRadius {
    if (!isGeoRestricted) return true;
    if (distanceKm == null || radiusKm == null) return false;
    return distanceKm! <= radiusKm!;
  }

  HomeGiveawayItem copyWith({
    String? id,
    String? title,
    String? category,
    String? prize,
    double? prizeValueUsd,
    String? locationName,
    double? radiusKm,
    DateTime? drawAt,
    int? totalTicketsIssued,
    bool? isGeoRestricted,
    double? latitude,
    double? longitude,
    double? distanceKm,
  }) {
    return HomeGiveawayItem(
      id: id ?? this.id,
      title: title ?? this.title,
      category: category ?? this.category,
      prize: prize ?? this.prize,
      prizeValueUsd: prizeValueUsd ?? this.prizeValueUsd,
      locationName: locationName ?? this.locationName,
      radiusKm: radiusKm ?? this.radiusKm,
      drawAt: drawAt ?? this.drawAt,
      totalTicketsIssued: totalTicketsIssued ?? this.totalTicketsIssued,
      isGeoRestricted: isGeoRestricted ?? this.isGeoRestricted,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      distanceKm: distanceKm ?? this.distanceKm,
    );
  }

  factory HomeGiveawayItem.fromJson(Map<String, dynamic> json) {
    final prizeValue = json['prize_value_usd'];
    final double parsedPrize = prizeValue is num
        ? prizeValue.toDouble()
        : double.tryParse(prizeValue?.toString() ?? '0') ?? 0.0;

    return HomeGiveawayItem(
      id: json['id'] as String? ?? '',
      title: json['title'] as String? ?? 'Giveaway Event',
      category: json['category'] as String? ?? 'Umum',
      prize: json['prize_name'] as String? ??
          json['prize_description'] as String? ??
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
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
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
