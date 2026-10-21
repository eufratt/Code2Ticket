/// Pesan untuk kode `error` POST /codes/redeem (ERD bagian 5, disesuaikan dengan
/// kode yang benar-benar dikeluarkan backend/src/services/redeem.js dan middleware).
String redeemErrorMessage(String code, {int? retryAfterSeconds}) {
  String minutes() => '${((retryAfterSeconds ?? 60) / 60).ceil()} menit';
  switch (code) {
    case 'invalid_format':
      return 'Format kode harus XXXX-XXXX-XXXX.';
    case 'code_not_found':
      return 'Kode tidak ditemukan.';
    case 'code_used':
      return 'Kode ini sudah digunakan.';
    case 'giveaway_not_started':
      return 'Undian ini belum dimulai.';
    case 'giveaway_ended':
      return 'Periode undian ini sudah berakhir.';
    case 'giveaway_not_ready':
      return 'Undian belum siap. Coba lagi nanti.';
    case 'ticket_limit':
      return 'Batas tiket untuk undian ini sudah tercapai.';
    case 'location_required':
      return 'Giveaway ini hanya berlaku di area tertentu dan butuh lokasimu. Aktifkan layanan lokasi dan izinkan akses lokasi untuk Code2Ticket, lalu coba lagi.';
    case 'out_of_area':
      return 'Kamu berada di luar area giveaway ini. Datang ke lokasi giveaway untuk menukar kode.';
    case 'rate_limited':
      return 'Terlalu banyak kode salah. Coba lagi dalam ${minutes()}.';
    case 'too_many_requests':
      return 'Terlalu banyak permintaan. Coba lagi sebentar.';
    case 'invalid_input':
      return 'Kode tidak valid.';
    default:
      return 'Terjadi kesalahan ($code). Coba lagi.';
  }
}

const redeemOfflineMessage = 'Butuh koneksi internet untuk menukar kode.';

/// Pesan bila jawaban server tidak diterima (POST tidak diulang otomatis, jadi tiket mungkin sudah terbuat).
const redeemNetworkMessage =
    'Koneksi bermasalah. Cek menu My Tickets sebelum mencoba lagi, kode mungkin sudah terpakai.';
