import '../../core/json.dart';

/// Kategori yang diterima backend (backend\src\services\admin.js, CATEGORIES).
const giveawayCategories = ['tech', 'gaming', 'travel', 'fashion', 'food', 'lifestyle', 'other'];

/// Isi form Buat Giveaway; bentuk JSON mengikuti POST /admin/giveaways (tanpa `id` = buat).
/// `prizeValueIdr` = rupiah bulat (mata uang dasar). Kontrak backend: satu `prize_name` + `winner_count` (bukan daftar hadiah); waktu wajib memakai zona (kirim UTC "Z").
class GiveawayDraft {
  const GiveawayDraft({
    required this.title,
    required this.organizer,
    required this.description,
    required this.category,
    required this.prizeName,
    required this.prizeValueIdr,
    required this.howToParticipate,
    this.organizerUrl,
    required this.winnerCount,
    required this.startAt,
    required this.endAt,
    required this.drawAt,
    this.maxTicketsPerUser,
    this.latitude,
    this.longitude,
    this.radiusKm,
    this.address,
  });

  final String title, organizer, description, category, prizeName;
  final int prizeValueIdr;
  final String howToParticipate;
  final String? organizerUrl;
  final int winnerCount;
  final int? maxTicketsPerUser;
  final DateTime startAt, endAt, drawAt;
  final double? latitude, longitude, radiusKm;
  final String? address;

  Map<String, dynamic> toJson() => {
        'title': title,
        'organizer': organizer,
        'description': description,
        'category': category,
        'prize_name': prizeName,
        'prize_value_idr': prizeValueIdr,
        'how_to_participate': howToParticipate,
        if (organizerUrl != null && organizerUrl!.isNotEmpty) 'organizer_url': organizerUrl,
        'winner_count': winnerCount,
        'start_at': startAt.toUtc().toIso8601String(),
        'end_at': endAt.toUtc().toIso8601String(),
        'draw_at': drawAt.toUtc().toIso8601String(),
        'max_tickets_per_user': ?maxTicketsPerUser,
        'latitude': ?latitude,
        'longitude': ?longitude,
        'radius_km': ?radiusKm,
        if (address != null && address!.isNotEmpty) 'address': address,
      };
}

/// Satu baris GET /admin/giveaways/:id/codes. Backend mengirim kode LENGKAP (hanya untuk admin).
class AdminCode {
  const AdminCode({required this.code, required this.isUsed, this.usedAt, this.geoRadiusKm});
  final String code;
  final bool isUsed;
  final DateTime? usedAt;
  final double? geoRadiusKm;

  static AdminCode? tryParse(dynamic raw) {
    final j = asMap(raw);
    final code = asString(j?['code']);
    if (j == null || code == null) return null;
    return AdminCode(code: code, isUsed: j['is_used'] == true, usedAt: asDate(j['used_at']), geoRadiusKm: asDouble(j['geo_radius_km']));
  }
}

/// Hasil POST /admin/giveaways/:id/draw.
class DrawOutcome {
  const DrawOutcome({required this.status, required this.totalTickets, required this.winningTickets});
  final String status;
  final int totalTickets;
  final List<int> winningTickets;

  factory DrawOutcome.fromJson(Map<String, dynamic> j) => DrawOutcome(
        status: asString(j['status']) ?? 'completed',
        totalTickets: asInt(j['total_tickets']),
        winningTickets: [for (final n in (j['winning_tickets'] is List ? j['winning_tickets'] as List : const [])) asInt(n, -1)].where((n) => n >= 0).toList(),
      );
}

/// Pesan Indonesia untuk kode galat backend (admin.js, codes.js, draw.js, middleware).
String adminErrorMessage(String? code, {String? field}) {
  switch (code) {
    case 'forbidden':
      return 'Akses ditolak. Akun ini bukan admin.';
    case 'not_found':
      return 'Giveaway tidak ditemukan.';
    case 'giveaway_drawn':
      return 'Giveaway sudah diundi, tidak bisa diubah atau diberi kode baru.';
    case 'already_drawn':
      return 'Giveaway ini sudah diundi.';
    case 'not_started':
      return 'Draw manual belum bisa: giveaway belum dimulai.';
    case 'demo_disabled':
      return 'Draw manual dimatikan di server (mode demo nonaktif). Draw berjalan otomatis sesuai jadwal.';
    case 'seed_mismatch':
      return 'Server menolak draw: seed tidak cocok dengan commitment. Jangan ulangi; hubungi pengembang.';
    case 'too_many_requests':
      return 'Terlalu banyak permintaan. Tunggu sebentar lalu coba lagi.';
    case 'winner_count_locked':
      return 'Jumlah pemenang tidak bisa diubah setelah giveaway dimulai.';
    case 'start_at_locked':
      return 'Waktu mulai tidak bisa diubah setelah giveaway dimulai.';
    case 'invalid_input':
      return switch (field) {
        'title' => 'Judul wajib diisi (1-120 karakter).',
        'organizer' => 'Penyelenggara maksimal 200 karakter.',
        'description' => 'Deskripsi maksimal 5000 karakter.',
        'category' => 'Kategori tidak valid.',
        'prize_name' => 'Nama hadiah wajib diisi (maksimal 200 karakter).',
        'prize_value_idr' => 'Nilai hadiah harus berupa angka positif (maksimal Rp 100.000.000.000).',
        'how_to_participate' => 'Cara mendapatkan kode wajib diisi (10-2000 karakter).',
        'organizer_url' => 'Tautan penyelenggara harus berupa alamat https:// yang valid (maksimal 500 karakter).',
        'latitude' || 'longitude' || 'geo' || 'geo_lat' || 'geo_lng' => 'Koordinat tidak valid.',
        'radius_km' || 'geo_radius_km' => 'Radius harus lebih dari 0 km.',
        'start_at' || 'end_at' || 'draw_at' => 'Waktu tidak valid.',
        'winner_count' => 'Jumlah pemenang 1-100.',
        'max_tickets_per_user' => 'Batas tiket per pengguna minimal 1.',
        'count' => 'Jumlah kode 1-1000.',
        _ => 'Data ditolak server. Periksa isian dan jadwal (mulai < berakhir <= draw).',
      };
    default:
      return 'Terjadi kesalahan ($code).';
  }
}
