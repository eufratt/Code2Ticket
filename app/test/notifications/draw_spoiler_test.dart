import 'package:code2ticket/core/notifications/draw_spoiler.dart';
import 'package:code2ticket/core/notifications/notification_service.dart';
import 'package:code2ticket/core/notifications/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/display.dart' show MemorySettings;
import 'reminder_test.dart' show FakeGateway, notif, now, ticket;

void main() {
  group('drawNotificationText', () {
    for (final type in ['winner', 'draw_result']) {
      test('$type belum reveal -> netral', () {
        final t = drawNotificationText(type: type, title: 'Selamat, kamu menang!', body: 'Tiket menang hadiah', giveawayTitle: 'Laptop', revealed: false);
        expect(t.title, 'Hasil draw sudah keluar');
        expect(t.body, 'Ketuk untuk melihat hasil Laptop');
      });
      test('$type sudah reveal -> teks asli', () {
        final t = drawNotificationText(type: type, title: 'A', body: 'B', giveawayTitle: 'Laptop', revealed: true);
        expect((t.title, t.body), ('A', 'B'));
      });
    }
    test('jenis lain tidak disentuh', () {
      final t = drawNotificationText(type: 'info', title: 'A', body: 'B', giveawayTitle: 'L', revealed: false);
      expect((t.title, t.body), ('A', 'B'));
    });
    test('teks netral tidak memuat kata terlarang', () {
      for (final g in ['', 'Laptop Gaming', 'Giveaway Akbar']) {
        final s = '$neutralDrawTitle ${neutralDrawBody(g)}'.toLowerCase();
        for (final w in [...spoilerWords, 'kalah']) {
          expect(s.contains(w), isFalse, reason: w);
        }
      }
    });
  });

  group('shouldShowDrawResultNotification', () {
    test('belum reveal dan layar lain/tidak ada -> tampil', () {
      expect(shouldShowDrawResultNotification(giveawayId: 'g1', revealed: false, activeResultGiveawayId: null), isTrue);
      expect(shouldShowDrawResultNotification(giveawayId: 'g1', revealed: false, activeResultGiveawayId: 'g2'), isTrue);
    });
    test('layar hasil giveaway itu terbuka -> tidak tampil', () {
      expect(shouldShowDrawResultNotification(giveawayId: 'g1', revealed: false, activeResultGiveawayId: 'g1'), isFalse);
    });
    test('sudah reveal -> tidak tampil', () {
      expect(shouldShowDrawResultNotification(giveawayId: 'g1', revealed: true, activeResultGiveawayId: null), isFalse);
    });
  });

  test('pengingat saat draw bernada netral dan menuju layar hasil', () {
    final plan = planReminders([ticket('t', 'g1', drawAt: now.add(const Duration(minutes: 3)))], now, enabled: true);
    expect(plan.single.title, neutralDrawTitle);
    expect(plan.single.body, neutralDrawBody('Laptop Gaming'));
    expect(plan.single.payload, 'result/g1');
  });

  group('NotificationService', () {
    late FakeGateway gw;
    late MemorySettings store;
    late NotificationService svc;
    setUp(() async {
      gw = FakeGateway();
      store = MemorySettings();
      svc = NotificationService(gw, store, clock: () => now);
      await svc.init();
      await svc.syncReminders([ticket('t', 'g1')]);
    });

    test('hasil draw belum reveal: notifikasi netral, rute hasil', () async {
      await svc.showServerNotifications('u1', [notif(1, type: 'winner')]);
      expect(gw.shown.single.$2, neutralDrawTitle);
      expect(gw.shown.single.$3, neutralDrawBody('Laptop Gaming'));
      expect(gw.shown.single.$4, 'result/g1');
    });

    test('layar hasil terbuka: tidak ditampilkan', () async {
      svc.activeResultGiveawayId = 'g1';
      await svc.showServerNotifications('u1', [notif(1, type: 'winner')]);
      expect(gw.shown, isEmpty);
    });

    test('sudah reveal: tidak ditampilkan', () async {
      await store.setSetting(drawSeenKey('g1'), '1', userId: 'u1');
      await svc.showServerNotifications('u1', [notif(1)]);
      expect(gw.shown, isEmpty);
    });

    test('reveal membatalkan notifikasi hasil draw giveaway itu', () async {
      final id = reminderId('g1', ReminderKind.atDraw);
      gw.scheduled[id] = PlannedReminder(id: id, at: now, title: 't', body: 'b', payload: 'result/g1');
      await svc.onDrawRevealed('g1', [7]);
      expect(gw.scheduled, isEmpty);
    });
  });
}
