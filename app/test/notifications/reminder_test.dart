import 'package:code2ticket/core/notifications/notification_service.dart';
import 'package:code2ticket/core/notifications/reminder_planner.dart';
import 'package:code2ticket/features/notifications/notification_models.dart';
import 'package:code2ticket/features/tickets/ticket_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/display.dart' show MemorySettings;

final now = DateTime.utc(2026, 10, 19, 12);

Ticket ticket(String id, String gid, {DateTime? drawAt, TicketResult result = TicketResult.eligible, String title = 'Laptop Gaming', int n = 12}) =>
    Ticket(id: id, ticketNumber: n, giveawayId: gid, giveawayTitle: title, drawAt: drawAt, result: result);

AppNotification notif(int id, {String type = 'draw_result', bool read = false, String? gid = 'g1'}) =>
    AppNotification(id: id, type: type, title: 'Judul $id', body: 'Isi $id', giveawayId: gid, isRead: read);

class FakeGateway implements NotificationGateway {
  bool enabled = true;
  bool grantOnRequest = true;
  String? launch;
  void Function(String?)? onTap;
  final Map<int, PlannedReminder> scheduled = {};
  final List<(int, String, String, String)> shown = [];
  int cancelAllCalls = 0, settingsOpened = 0;

  @override
  Future<void> init(void Function(String? payload) tap) async => onTap = tap;
  @override
  Future<String?> launchPayload() async => launch;
  @override
  Future<bool> areEnabled() async => enabled;
  @override
  Future<bool> requestPermission() async => enabled = grantOnRequest;
  @override
  Future<void> openSystemSettings() async => settingsOpened++;
  @override
  Future<void> show(int id, String title, String body, String payload) async => shown.add((id, title, body, payload));
  @override
  Future<void> schedule(PlannedReminder r) async => scheduled[r.id] = r; // id sama menimpa, seperti plugin
  @override
  Future<List<int>> pendingIds() async => scheduled.keys.toList();
  @override
  Future<void> cancel(int id) async => scheduled.remove(id);
  @override
  Future<void> cancelAll() async {
    cancelAllCalls++;
    scheduled.clear();
  }
}

void main() {
  group('planReminders (murni)', () {
    test('draw 3 jam lagi: pengingat H-1 jam dan saat draw, dengan teks dan muatan yang benar', () {
      final draw = now.add(const Duration(hours: 3));
      final plan = planReminders([ticket('t1', 'g1', drawAt: draw)], now, enabled: true);
      expect(plan.length, 2);
      expect(plan[0].at, draw.subtract(const Duration(hours: 1)));
      expect(plan[0].body, contains('Laptop Gaming'));
      expect(plan[0].payload, 'giveaway/g1');
      expect(plan[1].at, draw);
      expect(plan[1].body, 'Draw Laptop Gaming sudah dijalankan. Buka aplikasi untuk melihat hasilnya.');
      expect(plan[1].payload, 'result/g1');
    });

    test('draw kurang dari 1 jam lagi: hanya pengingat saat draw', () {
      final plan = planReminders([ticket('t1', 'g1', drawAt: now.add(const Duration(minutes: 30)))], now, enabled: true);
      expect(plan.map((r) => r.id), [reminderId('g1', ReminderKind.atDraw)]);
    });

    test('draw sudah lewat atau tanpa draw_at: tidak dijadwalkan', () {
      expect(planReminders([ticket('t1', 'g1', drawAt: now.subtract(const Duration(minutes: 1)))], now, enabled: true), isEmpty);
      expect(planReminders([ticket('t1', 'g1', drawAt: now)], now, enabled: true), isEmpty);
      expect(planReminders([ticket('t1', 'g1')], now, enabled: true), isEmpty);
    });

    test('giveaway sudah diundi (tiket menang / tidak terpilih): tidak dijadwalkan', () {
      final draw = now.add(const Duration(hours: 3));
      expect(planReminders([ticket('t1', 'g1', drawAt: draw, result: TicketResult.winner)], now, enabled: true), isEmpty);
      expect(planReminders([ticket('t1', 'g1', drawAt: draw, result: TicketResult.notSelected)], now, enabled: true), isEmpty);
    });

    test('saklar mati: tidak ada jadwal', () {
      expect(planReminders([ticket('t1', 'g1', drawAt: now.add(const Duration(hours: 3)))], now, enabled: false), isEmpty);
    });

    test('banyak tiket pada satu giveaway = satu pasang pengingat (tanpa duplikat); dua giveaway = dua pasang dengan id berbeda', () {
      final draw = now.add(const Duration(hours: 3));
      final plan = planReminders([
        ticket('t1', 'g1', drawAt: draw),
        ticket('t2', 'g1', drawAt: draw, n: 13),
        ticket('t3', 'g2', drawAt: draw.add(const Duration(hours: 1)), title: 'Voucher'),
      ], now, enabled: true);
      expect(plan.length, 4);
      expect(plan.map((r) => r.id).toSet().length, 4);
    });

    test('id deterministik, positif 31-bit, dan tidak bertabrakan antar rentang', () {
      final a = reminderId('g1', ReminderKind.atDraw), b = reminderId('g1', ReminderKind.atDraw);
      expect(a, b);
      expect(reminderId('g1', ReminderKind.oneHourBefore), isNot(a));
      for (final id in [a, ticketCreatedId('t1'), serverNotificationId(987654321)]) {
        expect(id, inInclusiveRange(0, 0x7FFFFFFF));
      }
      expect(isReminderId(a), isTrue);
      expect(isReminderId(ticketCreatedId('t1')), isFalse);
      expect(isReminderId(serverNotificationId(5)), isFalse);
    });

    test('diffReminders: yang tidak diinginkan dibatalkan (hanya id pengingat); semua yang diinginkan dijadwalkan', () {
      final plan = planReminders([ticket('t1', 'g1', drawAt: now.add(const Duration(hours: 3)))], now, enabled: true);
      final stale = reminderId('gX', ReminderKind.atDraw);
      final d = diffReminders(plan, [plan.first.id, stale, ticketCreatedId('t1')]);
      expect(d.cancel, [stale]); // id tiket baru bukan milik pengingat: tidak disentuh
      expect(d.schedule.length, 2);
    });
  });

  group('routeForPayload', () {
    test('muatan dikenal -> rute; tidak dikenal atau berbahaya -> null', () {
      expect(routeForPayload('giveaway/abc-123'), '/giveaway/abc-123');
      expect(routeForPayload('result/abc-123'), '/giveaway/abc-123/result');
      expect(routeForPayload('notifications'), '/notifications');
      expect(routeForPayload(null), isNull);
      expect(routeForPayload('admin/1'), isNull);
      expect(routeForPayload('giveaway/../admin'), isNull);
      expect(routeForPayload('giveaway/a b'), isNull);
    });
  });

  group('selectNewServer (murni)', () {
    test('hanya yang belum dibaca dan lebih baru dari batas; batas naik; ticket_created dilewati', () {
      final b = selectNewServer([notif(5), notif(4, read: true), notif(3, type: 'ticket_created'), notif(2)], 2);
      expect(b.show.map((n) => n.id), [5]);
      expect(b.lastShownId, 5);
    });

    test('tanpa batas (pertama kali): paling banyak 3 terbaru, urut lama ke baru', () {
      final b = selectNewServer([for (var i = 10; i >= 1; i--) notif(i)], null);
      expect(b.show.map((n) => n.id), [8, 9, 10]);
      expect(b.lastShownId, 10);
    });

    test('tidak ada yang baru: batas tetap, tidak ada yang ditampilkan', () {
      final b = selectNewServer([notif(3), notif(2)], 3);
      expect(b.show, isEmpty);
      expect(b.lastShownId, 3);
    });

    test('muatan ketuk: hasil/pemenang -> Hasil Draw; lain dengan giveaway -> Detail; tanpa giveaway -> pusat notifikasi', () {
      expect(payloadForServer(notif(1, type: 'winner')), 'result/g1');
      expect(payloadForServer(notif(1, type: 'draw_result')), 'result/g1');
      expect(payloadForServer(notif(1, type: 'reminder')), 'giveaway/g1');
      expect(payloadForServer(notif(1, type: 'info', gid: null)), 'notifications');
    });
  });

  group('NotificationService', () {
    late FakeGateway gw;
    late MemorySettings store;
    late DateTime clock;
    late NotificationService svc;

    Future<void> setUpService({bool granted = true}) async {
      gw = FakeGateway()..enabled = granted;
      store = MemorySettings();
      clock = now;
      svc = NotificationService(gw, store, clock: () => clock);
      await svc.init();
    }

    final draw = now.add(const Duration(hours: 3));

    test('H-1 jam dan saat draw dijadwalkan; sinkron ulang tidak menggandakan', () async {
      await setUpService();
      final ts = [ticket('t1', 'g1', drawAt: draw)];
      await svc.syncReminders(ts);
      expect(gw.scheduled.length, 2);
      await svc.syncReminders(ts);
      await svc.syncReminders([...ts, ticket('t2', 'g1', drawAt: draw, n: 13)]);
      expect(gw.scheduled.length, 2, reason: 'id deterministik: tidak ada duplikat');
    });

    test('draw_at berubah: jadwal diganti (id sama), bukan ditambah', () async {
      await setUpService();
      await svc.syncReminders([ticket('t1', 'g1', drawAt: draw)]);
      final later = draw.add(const Duration(hours: 5));
      await svc.syncReminders([ticket('t1', 'g1', drawAt: later)]);
      expect(gw.scheduled.length, 2);
      expect(gw.scheduled[reminderId('g1', ReminderKind.atDraw)]!.at, later);
    });

    test('draw sudah lewat: tidak dijadwalkan', () async {
      await setUpService();
      await svc.syncReminders([ticket('t1', 'g1', drawAt: now.subtract(const Duration(hours: 1)))]);
      expect(gw.scheduled, isEmpty);
    });

    test('giveaway menjadi drawn: jadwalnya dibatalkan, giveaway lain tetap', () async {
      await setUpService();
      await svc.syncReminders([ticket('t1', 'g1', drawAt: draw), ticket('t2', 'g2', drawAt: draw)]);
      expect(gw.scheduled.length, 4);
      await svc.syncReminders([ticket('t1', 'g1', drawAt: draw, result: TicketResult.winner), ticket('t2', 'g2', drawAt: draw)]);
      expect(gw.scheduled.keys, containsAll([reminderId('g2', ReminderKind.atDraw), reminderId('g2', ReminderKind.oneHourBefore)]));
      expect(gw.scheduled.length, 2);
    });

    test('logout: semua dibatalkan, pengguna aktif dihapus; masuk lagi menjadwalkan ulang', () async {
      await setUpService();
      await svc.onSignedIn('u1');
      expect(await store.getSetting(NotifKeys.activeUser), 'u1');
      await svc.syncReminders([ticket('t1', 'g1', drawAt: draw)]);
      await svc.onLogout();
      expect(gw.cancelAllCalls, 1);
      expect(gw.scheduled, isEmpty);
      expect(await store.getSetting(NotifKeys.activeUser), isNull);
      await svc.syncReminders([ticket('t1', 'g1', drawAt: draw)]);
      expect(gw.scheduled.length, 2);
    });

    test('saklar dimatikan: jadwal dibatalkan; tetap mati saat tiket dimuat lagi; dinyalakan: kembali; tersimpan', () async {
      await setUpService();
      await svc.syncReminders([ticket('t1', 'g1', drawAt: draw)]);
      await svc.setRemindersEnabled(false);
      expect(gw.scheduled, isEmpty);
      expect(await store.getSetting(NotifKeys.reminders), '0');
      await svc.syncReminders([ticket('t1', 'g1', drawAt: draw)]);
      expect(gw.scheduled, isEmpty, reason: 'saklar mati: tetap tidak dijadwalkan');
      await svc.setRemindersEnabled(true);
      expect(gw.scheduled.length, 2);
      await svc.setRemindersEnabled(false);
      final svc2 = NotificationService(gw, store, clock: () => clock);
      await svc2.init();
      expect(svc2.remindersEnabled, isFalse);
    });

    test('izin ditolak: tidak ada jadwal dan tidak ada notifikasi tampil; setelah diizinkan, jadwal dibuat', () async {
      await setUpService(granted: false);
      await svc.syncReminders([ticket('t1', 'g1', drawAt: draw)]);
      expect(gw.scheduled, isEmpty);
      await svc.onTicketCreated(const RedeemedTicket(id: 't1', ticketNumber: 12, giveawayId: 'g1', giveawayTitle: 'Laptop'));
      expect(gw.shown, isEmpty);
      gw.grantOnRequest = true;
      expect(await svc.requestPermission(), isTrue);
      expect(gw.scheduled.length, 2);
    });

    test('izin tetap ditolak saat diminta: status tidak berubah, tanpa galat', () async {
      await setUpService(granted: false);
      gw.grantOnRequest = false;
      expect(await svc.requestPermission(), isFalse);
      expect(svc.permissionGranted, isFalse);
      await svc.openSystemSettings();
      expect(gw.settingsOpened, 1);
    });

    test('tiket dibuat: notifikasi langsung "Tiket #000012 terbit untuk ..." dengan muatan Detail Giveaway', () async {
      await setUpService();
      await svc.onTicketCreated(const RedeemedTicket(id: 't1', ticketNumber: 12, giveawayId: 'g1', giveawayTitle: 'Laptop Gaming'));
      expect(gw.shown.length, 1);
      expect(gw.shown.single.$3, 'Tiket #000012 terbit untuk Laptop Gaming.');
      expect(gw.shown.single.$4, 'giveaway/g1');
    });

    test('notifikasi server: tampil sekali; pemeriksaan ulang tidak menggandakan; batas tersimpan per pengguna', () async {
      await setUpService();
      await svc.showServerNotifications('u1', [notif(7), notif(6, read: true)]);
      expect(gw.shown.map((s) => s.$1), [serverNotificationId(7)]);
      await svc.showServerNotifications('u1', [notif(7), notif(6, read: true)]);
      expect(gw.shown.length, 1);
      expect(await store.getSetting(NotifKeys.lastShown, userId: 'u1'), '7');
      await svc.showServerNotifications('u1', [notif(8, type: 'winner'), notif(7)]);
      expect(gw.shown.length, 2);
      expect(gw.shown.last.$4, 'result/g1');
      // Mulai baru (proses lain): batas dibaca dari penyimpanan.
      final svc2 = NotificationService(gw, store, clock: () => clock);
      await svc2.init();
      await svc2.showServerNotifications('u1', [notif(8, type: 'winner'), notif(7)]);
      expect(gw.shown.length, 2);
      // Pengguna lain punya batas sendiri.
      await svc2.showServerNotifications('u2', [notif(8, type: 'winner')]);
      expect(gw.shown.length, 3);
    });

    test('init mengembalikan muatan peluncuran dari notifikasi', () async {
      gw = FakeGateway()..launch = 'result/g1';
      svc = NotificationService(gw, MemorySettings());
      expect(await svc.init(), 'result/g1');
      expect(svc.pendingPayload, 'result/g1');
      gw.onTap!('giveaway/g2'); // ketukan saat aplikasi hidup
      expect(svc.pendingPayload, 'giveaway/g2');
    });
  });
}
