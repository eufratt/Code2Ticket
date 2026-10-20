import '../../features/notifications/notification_models.dart';
import '../../features/tickets/ticket_models.dart';
import '../format.dart';
import 'draw_spoiler.dart';

/// Logika penjadwalan notifikasi yang murni (tanpa plugin): kapan jadwal dibuat, dibatalkan, dan bagaimana
/// menghindari duplikat. Plugin hanya mengeksekusi hasilnya (lihat notification_service.dart).

/// Pengingat dijadwalkan [reminderLead] sebelum draw, dan tepat saat draw.
const Duration reminderLead = Duration(hours: 1);

enum ReminderKind { oneHourBefore, atDraw }

/// Id notifikasi deterministik (int32 positif) supaya jadwal yang sama menimpa, bukan menggandakan.
/// Rentang: [0, 2^29) notifikasi server; [2^29, 2^30) tiket baru; [2^30, 2^31) pengingat (satu pasang per giveaway).
const int _serverBase = 0, _ticketBase = 0x20000000, _reminderBase = 0x40000000, _mask = 0x1FFFFFFF;

int _fnv32(String s) {
  var h = 0x811C9DC5;
  for (final u in s.codeUnits) {
    h = ((h ^ u) * 0x01000193) & 0xFFFFFFFF;
  }
  return h;
}

int reminderId(String giveawayId, ReminderKind kind) => _reminderBase | ((_fnv32(giveawayId) & _mask) << 1) | kind.index;
bool isReminderId(int id) => id >= _reminderBase;
int ticketCreatedId(String ticketId) => _ticketBase | (_fnv32(ticketId) & _mask);
int serverNotificationId(int serverId) => _serverBase | (serverId & _mask);

/// Muatan notifikasi -> rute. Hanya id sederhana yang diterima (bukan jalur sembarang).
String giveawayPayload(String id) => 'giveaway/$id';
String resultPayload(String id) => 'result/$id';
const String notificationsPayload = 'notifications';

final _safeId = RegExp(r'^[A-Za-z0-9-]{1,64}$');

/// Rute router untuk muatan notifikasi; null bila tidak dikenal.
String? routeForPayload(String? payload) {
  if (payload == null) return null;
  if (payload == notificationsPayload) return '/notifications';
  final i = payload.indexOf('/');
  if (i <= 0) return null;
  final kind = payload.substring(0, i), id = payload.substring(i + 1);
  if (!_safeId.hasMatch(id)) return null;
  return switch (kind) {
    'giveaway' => '/giveaway/$id',
    'result' => '/giveaway/$id/result',
    _ => null,
  };
}

/// Satu notifikasi terjadwal (waktu absolut; zona waktu tidak berpengaruh).
class PlannedReminder {
  const PlannedReminder({required this.id, required this.at, required this.title, required this.body, required this.payload});
  final int id;
  final DateTime at;
  final String title, body, payload;
}

/// Pengingat yang seharusnya ada untuk [tickets] pada waktu [now].
/// - [enabled] false -> kosong (semua jadwal harus dibatalkan);
/// - giveaway yang sudah diundi (ada tiket bernilai winner/notSelected) -> tidak dijadwalkan;
/// - draw_at kosong atau sudah lewat -> tidak ada pengingat yang waktunya sudah lewat.
List<PlannedReminder> planReminders(List<Ticket> tickets, DateTime now, {required bool enabled}) {
  if (!enabled) return const [];
  final byGiveaway = <String, List<Ticket>>{};
  for (final t in tickets) {
    (byGiveaway[t.giveawayId] ??= []).add(t);
  }
  final out = <PlannedReminder>[];
  for (final MapEntry(key: gid, value: ts) in byGiveaway.entries) {
    final drawn = ts.any((t) => t.result == TicketResult.winner || t.result == TicketResult.notSelected);
    if (drawn) continue;
    final draws = [for (final t in ts) if (t.drawAt != null) t.drawAt!];
    if (draws.isEmpty) continue;
    final drawAt = draws.reduce((a, b) => a.isAfter(b) ? a : b);
    final name = ts.map((t) => t.giveawayTitle).firstWhere((s) => s.isNotEmpty, orElse: () => 'giveaway');
    final before = drawAt.subtract(reminderLead);
    if (before.isAfter(now)) {
      out.add(PlannedReminder(
        id: reminderId(gid, ReminderKind.oneHourBefore),
        at: before,
        title: 'Draw satu jam lagi',
        body: 'Draw $name dijalankan satu jam lagi.',
        payload: giveawayPayload(gid),
      ));
    }
    if (drawAt.isAfter(now)) {
      out.add(PlannedReminder(
        id: reminderId(gid, ReminderKind.atDraw),
        at: drawAt,
        title: neutralDrawTitle,
        body: neutralDrawBody(name),
        payload: resultPayload(gid),
      ));
    }
  }
  out.sort((a, b) => a.at.compareTo(b.at));
  return out;
}

/// Perbedaan antara jadwal yang diinginkan dan yang sedang tertunda di sistem.
class ReminderDiff {
  const ReminderDiff({required this.cancel, required this.schedule});

  /// Id pengingat tertunda yang tidak lagi diinginkan (giveaway sudah diundi, saklar mati, logout).
  final List<int> cancel;

  /// Semua yang diinginkan; id yang sama menimpa jadwal lama, jadi draw_at yang berubah otomatis terpakai dan tidak ada duplikat.
  final List<PlannedReminder> schedule;
}

ReminderDiff diffReminders(List<PlannedReminder> desired, Iterable<int> pendingIds) {
  final want = {for (final r in desired) r.id};
  return ReminderDiff(
    cancel: [for (final id in pendingIds) if (isReminderId(id) && !want.contains(id)) id],
    schedule: desired,
  );
}

/// Notifikasi tiket baru: "Tiket #000012 terbit untuk {giveaway}". Tanpa kode atau data pribadi.
({String title, String body}) ticketCreatedText(int ticketNumber, String giveawayTitle) => (
      title: 'Tiket berhasil dibuat',
      body: 'Tiket ${formatTicketNumber(ticketNumber)} terbit untuk ${giveawayTitle.isEmpty ? 'giveaway' : giveawayTitle}.',
    );

/// Notifikasi server yang perlu ditampilkan sebagai notifikasi sistem.
class ServerBatch {
  const ServerBatch(this.show, this.lastShownId);
  final List<AppNotification> show;

  /// Id terbesar yang sudah dilihat; disimpan sebagai batas berikutnya.
  final int lastShownId;
}

/// Memilih notifikasi server yang belum dibaca dan lebih baru dari [lastShownId] (null = belum pernah).
/// - jenis `ticket_created` dilewati (sudah ada notifikasi lokal langsung) tetapi tetap menggeser batas;
/// - paling banyak [max] terbaru per pemeriksaan (mencegah banjir pada pemasangan baru); batas selalu naik, jadi tidak ada duplikat.
ServerBatch selectNewServer(List<AppNotification> items, int? lastShownId, {int max = 3}) {
  final last = lastShownId ?? 0;
  final fresh = [for (final n in items) if (n.id > last) n];
  if (fresh.isEmpty) return ServerBatch(const [], last);
  final newLast = fresh.map((n) => n.id).reduce((a, b) => a > b ? a : b);
  final candidates = [for (final n in fresh) if (!n.isRead && n.type != 'ticket_created') n]..sort((a, b) => b.id.compareTo(a.id));
  final show = candidates.take(max).toList()..sort((a, b) => a.id.compareTo(b.id));
  return ServerBatch(show, newLast);
}

/// Muatan ketuk untuk notifikasi server: hasil draw/pemenang -> Hasil Draw; punya giveaway -> Detail; selain itu pusat notifikasi.
String payloadForServer(AppNotification n) {
  final gid = n.giveawayId;
  if (gid == null) return notificationsPayload;
  return n.type == 'winner' || n.type == 'draw_result' ? resultPayload(gid) : giveawayPayload(gid);
}
