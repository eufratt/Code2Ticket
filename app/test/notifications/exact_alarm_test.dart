import 'package:code2ticket/core/notifications/notification_service.dart';
import 'package:code2ticket/core/notifications/reminder_planner.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/display.dart' show MemorySettings;
import 'reminder_test.dart' show FakeGateway, now, ticket;

void main() {
  test('scheduleModeFor: exact bila diizinkan, inexact bila tidak', () {
    expect(scheduleModeFor(exactAllowed: true), ScheduleMode.exact);
    expect(scheduleModeFor(exactAllowed: false), ScheduleMode.inexact);
  });

  test('notifikasi tes: 1 menit lagi dan di luar rentang id pengingat', () {
    final t = testNotification(now);
    expect(t.at, now.add(const Duration(minutes: 1)));
    expect(isReminderId(t.id), isFalse);
  });

  group('NotificationService', () {
    Future<(NotificationService, FakeGateway)> make({required bool exact}) async {
      final gw = FakeGateway()..exactOk = exact;
      final svc = NotificationService(gw, MemorySettings(), clock: () => now);
      await svc.init();
      await svc.syncReminders([ticket('t', 'g1', drawAt: now.add(const Duration(hours: 3)))]);
      return (svc, gw);
    }

    test('exact diizinkan -> pengingat dijadwalkan exact', () async {
      final (svc, gw) = await make(exact: true);
      expect(svc.exactAllowed, isTrue);
      expect(gw.modes.values.toSet(), {ScheduleMode.exact});
      expect(gw.modes.length, 2);
    });

    test('exact tidak diizinkan -> fallback inexact, tanpa galat', () async {
      final (svc, gw) = await make(exact: false);
      expect(svc.exactAllowed, isFalse);
      expect(gw.modes.values.toSet(), {ScheduleMode.inexact});
    });

    test('izin exact diberikan kemudian -> jadwal dipasang ulang exact', () async {
      final (svc, gw) = await make(exact: false);
      gw.exactOk = true;
      await svc.requestExactAlarms();
      expect(gw.exactRequests, 1);
      expect(gw.modes.values.toSet(), {ScheduleMode.exact});
    });

    test('notifikasi tes memakai mode yang sama dan tidak dibatalkan penyelaras', () async {
      final (svc, gw) = await make(exact: true);
      expect(await svc.scheduleTestNotification(), isTrue);
      expect(gw.modes[testNotificationId], ScheduleMode.exact);
      await svc.syncReminders([ticket('t', 'g1', drawAt: now.add(const Duration(hours: 5)))]);
      expect(gw.scheduled.containsKey(testNotificationId), isTrue);
    });

    test('tanpa izin notifikasi -> tes tidak dijadwalkan', () async {
      final gw = FakeGateway()..enabled = false;
      final svc = NotificationService(gw, MemorySettings(), clock: () => now);
      await svc.init();
      expect(await svc.scheduleTestNotification(), isFalse);
    });
  });
}
