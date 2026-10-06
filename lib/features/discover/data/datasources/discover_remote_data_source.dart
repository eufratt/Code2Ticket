import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../domain/models/giveaway_model.dart';

class DiscoverRemoteDataSource {
  final SupabaseClient _supabase;

  const DiscoverRemoteDataSource(this._supabase);

  Future<List<GiveawayModel>> fetchGiveaways({
    double? userLat,
    double? userLng,
  }) async {
    List<GiveawayModel> giveaways = [];

    try {
      final res = await _supabase
          .from('giveaways')
          .select('*, tickets(count)')
          .order('draw_at', ascending: true);

      final list = res as List<dynamic>;
      giveaways = list
          .map((item) => GiveawayModel.fromJson(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('Error fetching giveaways from Supabase: $e');
    }

    if (giveaways.isEmpty) {
      giveaways = _getFallbackGiveaways();
    }

    // Calculate distance if user location is provided
    if (userLat != null && userLng != null) {
      giveaways = giveaways.map((g) {
        if (g.latitude != null && g.longitude != null) {
          final dist = _calculateDistance(userLat, userLng, g.latitude!, g.longitude!);
          return g.copyWith(distanceKm: dist);
        }
        return g;
      }).toList();
    }

    return giveaways;
  }

  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a)); // 2 * R (6371 km)
  }

  List<GiveawayModel> _getFallbackGiveaways() {
    final now = DateTime.now();
    return [
      GiveawayModel(
        id: 'a1111111-1111-4111-8111-111111111111',
        title: 'Jogja Tech Fest 2026: MacBook Pro M3 Max',
        category: 'Tech',
        prizeName: 'Apple MacBook Pro 16" M3 Max (36GB / 1TB)',
        prizeValueUsd: 2499.00,
        description:
            'Undian digital khusus partisipan seminar Jogja Digital Tech Summit. Tukarkan kode Anda dan nantikan live draw terverifikasi on-chain!',
        latitude: -7.782884,
        longitude: 110.367069,
        radiusKm: 15.0,
        isGeoRestricted: true,
        startAt: now.subtract(const Duration(days: 2)),
        endAt: now.add(const Duration(days: 30)),
        drawAt: now.add(const Duration(days: 31)),
        winnerCount: 1,
        status: 'active',
        ticketCount: 12,
      ),
      GiveawayModel(
        id: 'b2222222-2222-4222-8222-222222222222',
        title: 'PlayStation 5 Pro & PS VR2 Grand Arena Quest',
        category: 'Gaming',
        prizeName: 'Sony PlayStation 5 Pro + PS VR2 Horizon Bundle',
        prizeValueUsd: 899.00,
        description:
            'Campaign kolaborasi komunitas gamer dan merchant game center Pakuwon Mall Jogja. Terbuka untuk seluruh gamer Indonesia!',
        latitude: -7.758832,
        longitude: 110.399587,
        radiusKm: 10.0,
        isGeoRestricted: false,
        startAt: now.subtract(const Duration(days: 1)),
        endAt: now.add(const Duration(days: 25)),
        drawAt: now.add(const Duration(days: 26)),
        winnerCount: 1,
        status: 'active',
        ticketCount: 24,
      ),
      GiveawayModel(
        id: 'c3333333-3333-4333-8333-333333333333',
        title: 'Eksplorasi Malioboro: Liburan Mewah 3D2N ke Bali',
        category: 'Travel',
        prizeName: 'Paket Liburan Mewah 3D2N Bali (Flight + Resort Bintang 5)',
        prizeValueUsd: 1200.00,
        description:
            'Khusus pengunjung kawasan wisata Malioboro dan UMKM partner. Wajib verifikasi lokasi GPS saat menukarkan kode tiket.',
        latitude: -7.792823,
        longitude: 110.365842,
        radiusKm: 8.0,
        isGeoRestricted: true,
        startAt: now.subtract(const Duration(days: 3)),
        endAt: now.add(const Duration(days: 20)),
        drawAt: now.add(const Duration(days: 21)),
        winnerCount: 2,
        status: 'active',
        ticketCount: 18,
      ),
      GiveawayModel(
        id: 'd4444444-4444-4444-8444-444444444444',
        title: 'UGM Heritage Fest: Voucher Kuliner & Kopi 1 Tahun',
        category: 'Food',
        prizeName: 'Kartu Langganan Kuliner & Cafe Eksklusif 1 Tahun',
        prizeValueUsd: 500.00,
        description:
            'Nikmati aneka hidangan legendaris gudeg dan kedai kopi seputar kampus UGM sepanjang tahun. Tukarkan voucher partisipasi sekarang.',
        latitude: -7.771385,
        longitude: 110.377626,
        radiusKm: 12.0,
        isGeoRestricted: false,
        startAt: now.subtract(const Duration(days: 1)),
        endAt: now.add(const Duration(days: 14)),
        drawAt: now.add(const Duration(days: 15)),
        winnerCount: 3,
        status: 'active',
        ticketCount: 30,
      ),
      GiveawayModel(
        id: 'e5555555-5555-4555-8555-555555555555',
        title: 'Alkid Night Festival: Motor Honda Vario 160 ABS',
        category: 'Automotive',
        prizeName: 'Sepeda Motor Honda Vario 160cc ABS 2026',
        prizeValueUsd: 1850.00,
        description:
            'Hadiah utama pesta rakyat Alun-Alun Kidul Yogyakarta. Syarat partisipasi berada dalam radius area kota Yogyakarta.',
        latitude: -7.811883,
        longitude: 110.363223,
        radiusKm: 20.0,
        isGeoRestricted: true,
        startAt: now.subtract(const Duration(days: 4)),
        endAt: now.add(const Duration(days: 40)),
        drawAt: now.add(const Duration(days: 41)),
        winnerCount: 1,
        status: 'active',
        ticketCount: 15,
      ),
      GiveawayModel(
        id: 'f6666666-6666-4666-8666-666666666666',
        title: 'Prambanan Creative Hub: Sony Alpha 7 IV Creator Kit',
        category: 'Lifestyle',
        prizeName: 'Kamera Sony A7 IV Full-Frame + Lensa 24-70mm GM',
        prizeValueUsd: 2799.00,
        description:
            'Kompetisi konten kreator dan pengunjung situs warisan budaya Prambanan. Menangkan kamera mirrorless flagship.',
        latitude: -7.752020,
        longitude: 110.491467,
        radiusKm: 25.0,
        isGeoRestricted: false,
        startAt: now.subtract(const Duration(days: 2)),
        endAt: now.add(const Duration(days: 35)),
        drawAt: now.add(const Duration(days: 36)),
        winnerCount: 1,
        status: 'active',
        ticketCount: 9,
      ),
    ];
  }
}
