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
    this.prizeValueIdr,
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
  final double? latitude, longitude, radiusKm, distanceKm;

  /// Nilai hadiah dalam rupiah bulat (mata uang dasar); null bila server tidak mengirimnya (mis. backend lama).
  final int? prizeValueIdr;
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
      prizeValueIdr: asIntOrNull(j['prize_value_idr']),
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

  /// Salinan dengan jarak baru (mis. dihitung lokal dari data cache).
  Giveaway withDistance(double? km) => Giveaway(
        id: id, title: title, description: description, organizer: organizer, category: category,
        prizeName: prizeName, prizeValueIdr: prizeValueIdr, latitude: latitude, longitude: longitude,
        address: address, radiusKm: radiusKm, startAt: startAt, endAt: endAt, drawAt: drawAt,
        winnerCount: winnerCount, ticketCount: ticketCount, status: status, distanceKm: km,
      );

  bool get hasCoordinates => latitude != null && longitude != null;

  /// Baris tabel cached_giveaways (nama kolom = nama field API, tanggal ISO UTC).
  /// Jarak tidak disimpan: bergantung pada posisi pengguna, dan lokasi tidak boleh disimpan.
  Map<String, Object?> toRow(DateTime cachedAt) => {
        'id': id, 'title': title, 'description': description, 'organizer': organizer, 'category': category,
        'prize_name': prizeName, 'prize_value_idr': prizeValueIdr, 'latitude': latitude, 'longitude': longitude,
        'address': address, 'radius_km': radiusKm, 'start_at': startAt?.toUtc().toIso8601String(),
        'end_at': endAt?.toUtc().toIso8601String(), 'draw_at': drawAt?.toUtc().toIso8601String(),
        'winner_count': winnerCount, 'ticket_count': ticketCount, 'status': status,
        'cached_at': cachedAt.toUtc().toIso8601String(),
      };

  /// Fase dihitung dari waktu, bukan dari kolom status: kolom itu hanya diperbarui scheduler
  /// tiap menit sehingga bisa tertinggal.
  GiveawayPhase phaseAt(DateTime now) {
    if (status == 'drawn') return GiveawayPhase.drawn;
    if (startAt != null && now.isBefore(startAt!)) return GiveawayPhase.upcoming;
    if (endAt != null && now.isBefore(endAt!)) return GiveawayPhase.active;
    return GiveawayPhase.waitingDraw;
  }
}
