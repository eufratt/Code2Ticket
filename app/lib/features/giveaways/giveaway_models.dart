import '../../core/json.dart';

enum GiveawayPhase { upcoming, active, waitingDraw, drawn }

/// Satu giveaway dari GET /giveaways (field sesuai backend/src/services/giveaways.js).
class Giveaway {
  const Giveaway({
    required this.id,
    required this.title,
    this.description = '',
    this.organizer = '',
    this.category = 'other',
    this.prizeName = '',
    this.prizeValueUsd,
    this.latitude,
    this.longitude,
    this.address,
    this.radiusKm,
    this.startAt,
    this.endAt,
    this.drawAt,
    this.winnerCount = 1,
    this.ticketCount = 0,
    this.status = '',
    this.distanceKm,
  });

  final String id, title, description, organizer, category, prizeName, status;
  final double? prizeValueUsd, latitude, longitude, radiusKm, distanceKm;
  final String? address;
  final DateTime? startAt, endAt, drawAt;
  final int winnerCount, ticketCount;

  /// null bila id/judul tidak ada (elemen rusak dilewati oleh parseList).
  static Giveaway? tryParse(dynamic raw) {
    final j = asMap(raw);
    final id = asString(j?['id']);
    final title = asString(j?['title']);
    if (j == null || id == null || id.isEmpty || title == null) return null;
    return Giveaway(
      id: id,
      title: title,
      description: asString(j['description']) ?? '',
      organizer: asString(j['organizer']) ?? '',
      category: asString(j['category']) ?? 'other',
      prizeName: asString(j['prize_name']) ?? '',
      prizeValueUsd: asDouble(j['prize_value_usd']),
      latitude: asDouble(j['latitude']),
      longitude: asDouble(j['longitude']),
      address: asString(j['address']),
      radiusKm: asDouble(j['radius_km']),
      startAt: asDate(j['start_at']),
      endAt: asDate(j['end_at']),
      drawAt: asDate(j['draw_at']),
      winnerCount: asInt(j['winner_count'], 1),
      ticketCount: asInt(j['ticket_count']),
      status: asString(j['status']) ?? '',
      distanceKm: asDouble(j['distance_km']),
    );
  }

  /// Fase dihitung dari waktu, bukan dari kolom status: kolom itu hanya diperbarui scheduler
  /// tiap menit sehingga bisa tertinggal.
  GiveawayPhase phaseAt(DateTime now) {
    if (status == 'drawn') return GiveawayPhase.drawn;
    if (startAt != null && now.isBefore(startAt!)) return GiveawayPhase.upcoming;
    if (endAt != null && now.isBefore(endAt!)) return GiveawayPhase.active;
    return GiveawayPhase.waitingDraw;
  }
}
