import '../../core/currency/currency.dart' show maxPrizeIdr;
import '../../core/geo.dart';
import '../giveaways/giveaway_models.dart';

const giveawayCategories = ['tech', 'gaming', 'travel', 'fashion', 'food', 'lifestyle', 'other'];

String categoryLabel(String c) => switch (c) {
      'other' => 'Lainnya',
      '' => '',
      _ => c[0].toUpperCase() + c.substring(1),
    };

/// Urutan hasil; nilai [api] = parameter `sort` GET /giveaways.
enum GiveawaySort {
  deadline('deadline', 'Deadline terdekat'),
  value('value', 'Nilai hadiah tertinggi'),
  nearest('nearest', 'Terdekat'),
  newest('newest', 'Terbaru');

  const GiveawaySort(this.api, this.label);
  final String api;
  final String label;
}

/// Status giveaway pilihan eksplisit; nilai [api] = parameter `status`. Selesai = menunggu draw + sudah diundi.
/// Tanpa pilihan (null = "Semua"): semua status, dikirim sebagai `status=all`.
enum GiveawayStatusFilter {
  active('active', 'Aktif'),
  upcoming('upcoming', 'Akan datang'),
  finished('finished', 'Selesai');

  const GiveawayStatusFilter(this.api, this.label);
  final String api;
  final String label;
}

const _keep = Object();

/// Kriteria Discover. Dipakai untuk membangun query ke server dan, saat offline, menyaring cache
/// dengan aturan yang sama dengan backend (backend/src/services/giveaways.js).
class DiscoverFilters {
  const DiscoverFilters({
    this.query = '',
    this.category,
    this.minValueIdr,
    this.maxValueIdr,
    this.deadlineDays,
    this.status,
    this.sort = GiveawaySort.deadline,
    this.nearbyRadiusKm,
  });

  final String query;
  final String? category;
  /// Rentang nilai hadiah dalam rupiah (sama dengan `min_value`/`max_value` di backend). Layar filter
  /// mengonversi masukan dalam mata uang pilihan ke rupiah sebelum sampai ke sini.
  final int? minValueIdr, maxValueIdr;

  /// Deadline (end_at) dalam N hari ke depan; null = semua.
  final int? deadlineDays;
  /// null = semua status (lihat [GiveawayStatusFilter]).
  final GiveawayStatusFilter? status;
  final GiveawaySort sort;

  /// Mode "Terdekat": radius km dari posisi pengguna; null = nonaktif.
  final int? nearbyRadiusKm;

  bool get nearby => nearbyRadiusKm != null;

  /// Filter dan urutan non-bawaan selain kata kunci (untuk lencana tombol filter).
  int get activeFilterCount =>
      (category != null ? 1 : 0) +
      (minValueIdr != null || maxValueIdr != null ? 1 : 0) +
      (deadlineDays != null ? 1 : 0) +
      (status != null ? 1 : 0) +
      (sort != GiveawaySort.deadline ? 1 : 0);

  /// Nilai [Object?] bernilai _keep = tidak diubah; null = dikosongkan.
  DiscoverFilters copyWith({
    String? query,
    Object? category = _keep,
    Object? minValueIdr = _keep,
    Object? maxValueIdr = _keep,
    Object? deadlineDays = _keep,
    Object? status = _keep,
    GiveawaySort? sort,
    Object? nearbyRadiusKm = _keep,
  }) =>
      DiscoverFilters(
        query: query ?? this.query,
        category: identical(category, _keep) ? this.category : category as String?,
        minValueIdr: identical(minValueIdr, _keep) ? this.minValueIdr : minValueIdr as int?,
        maxValueIdr: identical(maxValueIdr, _keep) ? this.maxValueIdr : maxValueIdr as int?,
        deadlineDays: identical(deadlineDays, _keep) ? this.deadlineDays : deadlineDays as int?,
        status: identical(status, _keep) ? this.status : status as GiveawayStatusFilter?,
        sort: sort ?? this.sort,
        nearbyRadiusKm: identical(nearbyRadiusKm, _keep) ? this.nearbyRadiusKm : nearbyRadiusKm as int?,
      );

  /// Parameter GET /giveaways. Posisi hanya dikirim bila ada (untuk jarak/urutan/radius), tidak disimpan.
  Map<String, String> toQuery({double? lat, double? lng, int limit = 20, int offset = 0}) {
    final q = query.trim();
    return {
      if (q.isNotEmpty) 'q': q,
      'category': ?category,
      if (minValueIdr != null) 'min_value': '$minValueIdr',
      if (maxValueIdr != null) 'max_value': '$maxValueIdr',
      if (deadlineDays != null) 'deadline_days': '$deadlineDays',
      'status': status?.api ?? 'all',
      'sort': sort.api,
      if (lat != null && lng != null) ...{
        'lat': '$lat',
        'lng': '$lng',
        if (nearbyRadiusKm != null) 'radius_km': '$nearbyRadiusKm',
      },
      'limit': '$limit',
      if (offset > 0) 'offset': '$offset',
    };
  }

  /// Penyaringan lokal (offline) dengan semantik yang sama dengan backend.
  List<Giveaway> applyLocal(List<Giveaway> all, {double? lat, double? lng, DateTime? now}) {
    final at = now ?? DateTime.now();
    final q = query.trim().toLowerCase();
    final havePos = lat != null && lng != null;

    bool statusOk(Giveaway g) {
      final p = g.phaseAt(at);
      return switch (status) {
        null => true,
        GiveawayStatusFilter.active => p == GiveawayPhase.active,
        GiveawayStatusFilter.upcoming => p == GiveawayPhase.upcoming,
        GiveawayStatusFilter.finished => p == GiveawayPhase.drawn || p == GiveawayPhase.waitingDraw,
      };
    }

    final out = <Giveaway>[];
    for (final g in all) {
      if (q.isNotEmpty &&
          !(g.title.toLowerCase().contains(q) ||
              g.prizeName.toLowerCase().contains(q) ||
              g.organizer.toLowerCase().contains(q))) {
        continue;
      }
      if (category != null && g.category != category) continue;
      if (minValueIdr != null && (g.prizeValueIdr ?? -1) < minValueIdr!) continue;
      if (maxValueIdr != null && (g.prizeValueIdr ?? maxPrizeIdr + 1) > maxValueIdr!) continue;
      if (deadlineDays != null && (g.endAt == null || g.endAt!.isAfter(at.add(Duration(days: deadlineDays!))))) continue;
      if (!statusOk(g)) continue;

      double? km;
      if (havePos && g.hasCoordinates) {
        km = (distanceKm(lat, lng, g.latitude!, g.longitude!) * 100).roundToDouble() / 100;
      }
      if (nearbyRadiusKm != null && (km == null || km > nearbyRadiusKm!)) continue;
      out.add(g.withDistance(km));
    }

    int asc(DateTime? a, DateTime? b) => (a ?? DateTime(9999)).compareTo(b ?? DateTime(9999));
    // Deadline terdekat per kelompok: akan datang menurut mulai terdekat, yang sudah berakhir terbaru dulu.
    int byDeadline(Giveaway a, Giveaway b, GiveawayPhase p) => switch (p) {
          GiveawayPhase.upcoming => asc(a.startAt, b.startAt),
          GiveawayPhase.waitingDraw || GiveawayPhase.drawn => (b.endAt ?? DateTime(0)).compareTo(a.endAt ?? DateTime(0)),
          GiveawayPhase.active => asc(a.endAt, b.endAt),
        };
    out.sort((a, b) {
      final pa = a.phaseAt(at), pb = b.phaseAt(at);
      final g = statusGroupRank(pa).compareTo(statusGroupRank(pb));
      if (g != 0) return g;
      final c = switch (sort) {
        GiveawaySort.nearest => (a.distanceKm ?? double.infinity).compareTo(b.distanceKm ?? double.infinity),
        GiveawaySort.value => (b.prizeValueIdr ?? -1).compareTo(a.prizeValueIdr ?? -1),
        GiveawaySort.newest => (b.startAt ?? DateTime(0)).compareTo(a.startAt ?? DateTime(0)),
        GiveawaySort.deadline => 0,
      };
      return c != 0 ? c : byDeadline(a, b, pa);
    });
    return out;
  }
}

/// Urutan kelompok hasil Discover (sama dengan backend): aktif, akan datang, menunggu draw, selesai.
int statusGroupRank(GiveawayPhase p) => switch (p) {
      GiveawayPhase.active => 0,
      GiveawayPhase.upcoming => 1,
      GiveawayPhase.waitingDraw => 2,
      GiveawayPhase.drawn => 3,
    };
