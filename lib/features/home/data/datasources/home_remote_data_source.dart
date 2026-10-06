import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/home_summary_model.dart';

class HomeRemoteDataSource {
  final SupabaseClient _supabase;

  const HomeRemoteDataSource(this._supabase);

  Future<HomeSummaryModel> fetchHomeSummary(String? userId) async {
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

    // 5. Nearby Draws (geo-restricted Yogyakarta campaigns)
    final nearby = allGiveaways.where((g) => g.isGeoRestricted).toList();

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
        id: 'gw-1',
        title: 'Jogja Tech Fest 2026',
        category: 'Tech',
        prize: 'Apple MacBook Pro 16" M3 Max',
        prizeValueUsd: 2499.0,
        locationName: 'Tugu Jogja & Sleman',
        radiusKm: 15.0,
        drawAt: now.add(const Duration(days: 30)),
        isGeoRestricted: true,
      ),
      HomeGiveawayItem(
        id: 'gw-2',
        title: 'PlayStation 5 Pro & PS VR2 Grand Arena Quest',
        category: 'Gaming',
        prize: 'Sony PlayStation 5 Pro Bundle',
        prizeValueUsd: 899.0,
        locationName: 'Nasional / Seluruh Indonesia',
        drawAt: now.add(const Duration(days: 25)),
        isGeoRestricted: false,
      ),
      HomeGiveawayItem(
        id: 'gw-3',
        title: 'Eksplorasi Malioboro: Liburan Mewah Bali 3D2N',
        category: 'Travel',
        prize: 'Paket Liburan Bintang 5 Bali',
        prizeValueUsd: 1200.0,
        locationName: 'Kawasan Wisata Malioboro',
        radiusKm: 8.0,
        drawAt: now.add(const Duration(days: 20)),
        isGeoRestricted: true,
      ),
      HomeGiveawayItem(
        id: 'gw-4',
        title: 'UGM Heritage Fest: Voucher Kuliner 1 Tahun',
        category: 'Food',
        prize: 'Langganan Cafe & Kuliner 1 Tahun',
        prizeValueUsd: 500.0,
        locationName: 'Kawasan Kampus UGM',
        radiusKm: 12.0,
        drawAt: now.add(const Duration(days: 14)),
        isGeoRestricted: false,
      ),
    ];
  }
}
