// Aturan anti-spoiler untuk notifikasi hasil draw (murni, tanpa plugin/UI). Notifikasi dan item pusat notifikasi
// untuk hasil draw tidak boleh membocorkan menang/tidak sebelum pengguna melakukan reveal (goyang / "Lihat hasil").

const String neutralDrawTitle = 'Hasil draw sudah keluar';

String neutralDrawBody(String giveawayTitle) => 'Ketuk untuk melihat hasil ${giveawayTitle.isEmpty ? 'giveaway' : giveawayTitle}';

/// Kata yang tidak boleh muncul di teks netral.
const List<String> spoilerWords = ['menang', 'kalah', 'terpilih', 'hadiah', 'selamat', 'pemenang'];

/// Jenis notifikasi server yang isinya memuat hasil (menang / tidak terpilih).
bool isDrawResultType(String type) => type == 'winner' || type == 'draw_result';

/// Kunci app_settings (per pengguna) penanda "hasil giveaway ini sudah dibuka"; dipakai layar hasil dan aturan ini.
String drawSeenKey(String giveawayId) => 'draw_seen:$giveawayId';

/// Teks yang ditampilkan: netral bila jenisnya hasil draw dan belum di-reveal; selain itu teks aslinya.
({String title, String body}) drawNotificationText({
  required String type,
  required String title,
  required String body,
  required String giveawayTitle,
  required bool revealed,
}) =>
    isDrawResultType(type) && !revealed ? (title: neutralDrawTitle, body: neutralDrawBody(giveawayTitle)) : (title: title, body: body);

/// Notifikasi sistem hasil draw hanya tampil bila belum di-reveal dan layar hasil giveaway itu tidak sedang terbuka.
bool shouldShowDrawResultNotification({required String giveawayId, required bool revealed, required String? activeResultGiveawayId}) =>
    !revealed && activeResultGiveawayId != giveawayId;
