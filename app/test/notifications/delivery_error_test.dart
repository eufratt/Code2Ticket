import 'dart:io';

import 'package:code2ticket/core/notifications/notification_service.dart';
import 'package:code2ticket/core/notifications/reminder_planner.dart';
import 'package:code2ticket/features/tickets/ticket_models.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_test/flutter_test.dart';

import '../support/display.dart' show MemorySettings;
import 'reminder_test.dart' show FakeGateway, now, ticket;

class _FailingGateway extends FakeGateway {
  Object? error = PlatformException(code: 'invalid_icon', message: 'rahasia-jangan-dicatat');
  @override
  Future<void> show(int id, String title, String body, String payload) async => throw error!;
  @override
  Future<void> schedule(PlannedReminder r, ScheduleMode mode) async => throw error!;
}

void main() {
  const redeemed = RedeemedTicket(id: 't1', ticketNumber: 12, giveawayId: 'g1', giveawayTitle: 'Laptop');

  test('show() gagal: tidak melempar, jenis galat tercatat, pulih setelah berhasil', () async {
    final gw = _FailingGateway();
    final svc = NotificationService(gw, MemorySettings(), clock: () => now);
    await svc.init();
    await svc.onTicketCreated(redeemed);
    expect(svc.deliveryError, 'invalid_icon');
    expect(svc.deliveryError, isNot(contains('rahasia')));

    final ok = NotificationService(FakeGateway(), MemorySettings(), clock: () => now);
    await ok.init();
    await ok.onTicketCreated(redeemed);
    expect(ok.deliveryError, isNull);
  });

  test('jadwal gagal: notifikasi tes mengembalikan false dan galat non-Platform dicatat sebagai tipe', () async {
    final gw = _FailingGateway()..error = StateError('x');
    final svc = NotificationService(gw, MemorySettings(), clock: () => now);
    await svc.init();
    await svc.syncReminders([ticket('t', 'g1', drawAt: now.add(const Duration(hours: 3)))]);
    expect(svc.deliveryError, 'StateError');
    expect(await svc.scheduleTestNotification(), isFalse);
  });

  test('keep.xml memuat ikon kecil yang dirujuk kode notifikasi', () {
    final code = File('lib/core/notifications/notification_service.dart').readAsStringSync();
    final icons = RegExp(r"AndroidInitializationSettings\('@(drawable|mipmap)/(\w+)'\)").allMatches(code).toList();
    expect(icons, isNotEmpty);
    final keep = File('android/app/src/main/res/raw/keep.xml').readAsStringSync();
    for (final m in icons) {
      expect(keep, contains('@${m[1]}/${m[2]}'));
      expect(File('android/app/src/main/res/${m[1]}-mdpi/${m[2]}.png').existsSync(), isTrue);
    }
    expect(keep, contains('tools:keep'));
  });
}
