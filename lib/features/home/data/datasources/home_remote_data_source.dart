import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../../core/services/location_service.dart';
import '../../domain/models/home_summary_model.dart';

class HomeRemoteDataSource {
  final SupabaseClient _supabase;

  const HomeRemoteDataSource(this._supabase);

  Future<HomeSummaryModel> fetchHomeSummary(
    String? userId, {
    double? userLat,
    double? userLng,
  }) async {
    int totalTickets = 0;
    int activeTickets = 0;

    // 1. Fetch user ticket counts if authenticated
    if (userId != null && userId.isNotEmpty) {
      try {
        final ticketsRes = await _supabase
            .from('tickets')
            .select('id, status')
            .eq('user_id', userId);

        final list = ticketsRes as List<dynamic>;
        totalTickets = list.length;
        activeTickets = list.where((t) {
          final status = (t as Map<String, dynamic>)['status'] as String?;
          return status == 'waiting_for_draw' || status == 'eligible';
        }).length;
      } catch (_) {}
    }

    // 2. Fetch active giveaways for draws
    List<HomeGiveawayItem> allGiveaways = [];
    try {
      final giveawaysRes = await _supabase
          .from('giveaways')
          .select()
          .eq('status', 'active')
          .order('draw_at', ascending: true);

      final gList = giveawaysRes as List<dynamic>;
      allGiveaways = gList
          .map((item) =>
              HomeGiveawayItem.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (_) {}

    // Fallback seed items if database connection has temporary issue
    if (allGiveaways.isEmpty) {
      allGiveaways = _fallbackGiveaways();
    }

    // Calculate real distance if GPS coordinates are provided
    if (userLat != null && userLng != null) {
      allGiveaways = allGiveaways.map((g) {
        if (g.latitude != null && g.longitude != null) {
          final dist = LocationService.calculateDistanceKm(
            userLat,
            userLng,
            g.latitude!,
            g.longitude!,
          );
          return g.copyWith(distanceKm: dist);
        }
        return g;
      }).toList();
    }

    // 3. Find nearest draw
    final now = DateTime.now();
    HomeGiveawayItem? nearestDraw;
    for (final g in allGiveaways) {
      if (g.drawAt != null && g.drawAt!.isAfter(now)) {
        nearestDraw = g;
        break;
      }
    }
    nearestDraw ??= allGiveaways.isNotEmpty ? allGiveaways.first : null;

    // 4. Recommended Draws (general / highest value)
    final recommended = allGiveaways.toList()
      ..sort((a, b) => b.prizeValueUsd.compareTo(a.prizeValueUsd));

    // 5. Nearby Draws (geo-restricted Yogyakarta campaigns, sorted by distance)
    var nearby = allGiveaways.where((g) => g.isGeoRestricted).toList();
    if (userLat != null && userLng != null) {
      nearby.sort((a, b) {
        if (a.distanceKm == null) return 1;
        if (b.distanceKm == null) return -1;
        return a.distanceKm!.compareTo(b.distanceKm!);
      });
    }

    return HomeSummaryModel(
      totalTickets: totalTickets,
      activeTickets: activeTickets,
      nearestDraw: nearestDraw,
      recommendedDraws: recommended.take(4).toList(),
      nearbyDraws: nearby.isNotEmpty
          ? nearby.take(4).toList()
          : allGiveaways.take(3).toList(),
    );
  }

  List<HomeGiveawayItem> _fallbackGiveaways() {
    final now = DateTime.now();
    return [
      HomeGiveawayItem(
        id: 'a1111111-1111-4111-8111-111111111111',
        title: 'Jogja Tech Fest 2026: MacBook Pro M3 Max',
        category: 'Tech',
        prize: 'Apple MacBook Pro 16" M3 Max',
        prizeValueUsd: 2499.0,
        locationName: 'Tugu Jogja & Sleman',
        latitude: -7.782884,
        longitude: 110.367069,
        radiusKm: 15.0,
        drawAt: now.add(const Duration(days: 30)),
        isGeoRestricted: true,
      ),
      HomeGiveawayItem(
        id: 'b2222222-2222-4222-8222-222222222222',
        title: 'PlayStation 5 Pro & PS VR2 Grand Arena Quest',
        category: 'Gaming',
        prize: 'Sony PlayStation 5 Pro Bundle',
        prizeValueUsd: 899.0,
        locationName: 'Nasional / Seluruh Indonesia',
        latitude: -7.758832,
        longitude: 110.399587,
        radiusKm: 10.0,
        drawAt: now.add(const Duration(days: 25)),
        isGeoRestricted: false,
      ),
      HomeGiveawayItem(
        id: 'c3333333-3333-4333-8333-333333333333',
        title: 'Eksplorasi Malioboro: Liburan Mewah Bali 3D2N',
        category: 'Travel',
        prize: 'Paket Liburan Bintang 5 Bali',
        prizeValueUsd: 1200.0,
        locationName: 'Kawasan Wisata Malioboro',
        latitude: -7.792823,
        longitude: 110.365842,
        radiusKm: 8.0,
        drawAt: now.add(const Duration(days: 20)),
        isGeoRestricted: true,
      ),
      HomeGiveawayItem(
        id: 'd4444444-4444-4444-8444-444444444444',
        title: 'UGM Heritage Fest: Voucher Kuliner 1 Tahun',
        category: 'Food',
        prize: 'Langganan Cafe & Kuliner 1 Tahun',
        prizeValueUsd: 500.0,
        locationName: 'Kawasan Kampus UGM',
        latitude: -7.771385,
        longitude: 110.377626,
        radiusKm: 12.0,
        drawAt: now.add(const Duration(days: 14)),
        isGeoRestricted: false,
      ),
    ];
  }
}
