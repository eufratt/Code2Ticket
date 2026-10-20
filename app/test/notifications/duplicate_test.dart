import 'package:code2ticket/core/notifications/draw_spoiler.dart';
import 'package:code2ticket/core/notifications/notification_service.dart';
import 'package:code2ticket/core/notifications/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/display.dart' show MemorySettings;
import 'reminder_test.dart' show FakeGateway, notif, now, ticket;

void main() {
  final past = now.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch.toString();
  final future = now.add(const Duration(minutes: 1)).millisecondsSinceEpoch.toString();

  group('localDrawReminderFired (murni)', () {
    test('terjadwal dan sudah lewat -> true', () => expect(localDrawReminderFired(marker: past, now: now, remindersEnabled: true), isTrue));
    test('belum lewat -> false', () => expect(localDrawReminderFired(marker: future, now: now, remindersEnabled: true), isFalse));
    test('saklar mati -> false', () => expect(localDrawReminderFired(marker: past, now: now, remindersEnabled: false), isFalse));
    test('tanpa penanda / rusak -> false', () {
      expect(localDrawReminderFired(marker: null, now: now, remindersEnabled: true), isFalse);
      expect(localDrawReminderFired(marker: 'x', now: now, remindersEnabled: true), isFalse);
    });
    test('server dilewati hanya bila lokal sudah berbunyi', () {
      expect(shouldShowDrawResultNotification(giveawayId: 'g1', revealed: false, activeResultGiveawayId: null, localReminderFired: true), isFalse);
      expect(shouldShowDrawResultNotification(giveawayId: 'g1', revealed: false, activeResultGiveawayId: null), isTrue);
    });
  });

  test('id notifikasi hasil draw sama dengan id alarm lokal saat draw', () {
    expect(drawResultNotificationId('g1'), reminderId('g1', ReminderKind.atDraw));
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
      await svc.onSignedIn('u1');
    });

    test('pengingat dipasang -> penanda draw_at tersimpan', () async {
      final draw = now.add(const Duration(hours: 3));
      await svc.syncReminders([ticket('t', 'g1', drawAt: draw)]);
      expect(store.values['u1|${drawReminderKey('g1')}'], '${draw.millisecondsSinceEpoch}');
    });

    test('lokal sudah berbunyi -> server dilewati, batas terakhir tetap maju', () async {
      await store.setSetting(drawReminderKey('g1'), past, userId: 'u1');
      await svc.showServerNotifications('u1', [notif(5, type: 'winner')]);
      expect(gw.shown, isEmpty);
      expect(store.values['u1|${NotifKeys.lastShown}'], '5');
    });

    test('lokal belum lewat -> server tetap tampil, dengan id yang sama dengan lokal', () async {
      await store.setSetting(drawReminderKey('g1'), future, userId: 'u1');
      await svc.showServerNotifications('u1', [notif(5, type: 'winner')]);
      expect(gw.shown.single.$1, drawResultNotificationId('g1'));
    });

    test('saklar mati -> server tampil', () async {
      await store.setSetting(drawReminderKey('g1'), past, userId: 'u1');
      await svc.setRemindersEnabled(false);
      await svc.showServerNotifications('u1', [notif(5)]);
      expect(gw.shown.length, 1);
    });

    test('jadwal dibatalkan (saklar mati) menghapus penanda', () async {
      await svc.syncReminders([ticket('t', 'g1', drawAt: now.add(const Duration(hours: 3)))]);
      await svc.setRemindersEnabled(false);
      expect(store.values.containsKey('u1|${drawReminderKey('g1')}'), isFalse);
    });
  });
}
