import '../../features/notifications/notification_models.dart';

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
/// [localReminderFired]: alarm lokal draw_at giveaway ini sudah berbunyi (lihat [localDrawReminderFired]); server tidak menampilkan yang kedua.
bool shouldShowDrawResultNotification({
  required String giveawayId,
  required bool revealed,
  required String? activeResultGiveawayId,
  bool localReminderFired = false,
}) =>
    !revealed && activeResultGiveawayId != giveawayId && !localReminderFired;

/// Penanda (app_settings, per pengguna) bahwa pengingat lokal draw_at sudah dijadwalkan; isinya draw_at dalam ms epoch.
String drawReminderKey(String giveawayId) => 'draw_reminder:$giveawayId';

/// Alarm lokal sudah berbunyi bila saklar pengingat menyala, penanda ada, dan draw_at sudah lewat.
/// Saklar mati / penanda kosong (jadwal tidak dipasang) -> false, jadi jalur server tetap tampil.
bool localDrawReminderFired({required String? marker, required DateTime now, required bool remindersEnabled}) {
  final ms = int.tryParse(marker ?? '');
  return remindersEnabled && ms != null && !DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).isAfter(now);
}

/// Jenis baris di pusat notifikasi dalam aplikasi.
enum NotificationRowKind { normal, announcement, result }

/// Satu baris tampilan. [source] tetap satu notifikasi server: hitungan belum dibaca, tandai dibaca, dan rute memakai [source].
class NotificationRow {
  const NotificationRow({required this.source, required this.kind, required this.title, required this.body, required this.won, required this.at});
  final AppNotification source;
  final NotificationRowKind kind;
  final String title, body;

  /// Hanya bermakna untuk [NotificationRowKind.result]: true = menang, false = tidak terpilih.
  final bool won;
  final DateTime? at;
}

const String resultWonTitle = 'Selamat, kamu menang!';
const String resultLostTitle = 'Kamu belum terpilih';
const String resultLostBody = 'Terima kasih sudah ikut. Kamu tetap bisa memeriksa keaslian hasilnya.';

/// Daftar notifikasi server -> baris tampilan (lokal, tanpa mengubah server).
/// - hasil draw belum di-reveal: 1 baris netral;
/// - sudah di-reveal ([revealed] memuat giveaway-nya): baris hasil (teks asli) tepat di atas baris netral dari notifikasi yang sama;
/// - jenis lain: 1 baris apa adanya. Urutan notifikasi asli dipertahankan.
List<NotificationRow> notificationRows(
  List<AppNotification> items,
  Set<String> revealed, {
  String Function(String? giveawayId)? titleOf,
}) {
  final rows = <NotificationRow>[];
  for (final n in items) {
    if (!isDrawResultType(n.type)) {
      rows.add(NotificationRow(source: n, kind: NotificationRowKind.normal, title: n.title, body: n.body, won: false, at: n.createdAt));
      continue;
    }
    final gTitle = titleOf?.call(n.giveawayId) ?? '';
    final seen = n.giveawayId != null && revealed.contains(n.giveawayId);
    if (seen) {
      final won = n.type == 'winner';
      rows.add(NotificationRow(
        source: n,
        kind: NotificationRowKind.result,
        title: won ? (n.title.isEmpty ? resultWonTitle : n.title) : resultLostTitle,
        body: won ? n.body : resultLostBody,
        won: won,
        at: n.createdAt,
      ));
    }
    rows.add(NotificationRow(source: n, kind: NotificationRowKind.announcement, title: neutralDrawTitle, body: neutralDrawBody(gTitle), won: false, at: n.createdAt));
  }
  return rows;
}
