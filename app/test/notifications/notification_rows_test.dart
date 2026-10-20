import 'package:code2ticket/core/notifications/draw_spoiler.dart';
import 'package:code2ticket/features/notifications/notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotification n(int id, String type, {bool read = false, String? gid = 'g1'}) => AppNotification(
    id: id, type: type, title: 'Selamat, kamu menang!', body: 'Tiket menang hadiah', giveawayId: gid, isRead: read, createdAt: DateTime.utc(2026, 10, 20, 10, id));

void main() {
  bool spoils(String s) => spoilerWords.any(s.toLowerCase().contains) || s.toLowerCase().contains('kalah');

  test('belum reveal: 1 baris netral per notifikasi, tanpa kata menang/kalah', () {
    final rows = notificationRows([n(2, 'winner'), n(1, 'draw_result', gid: 'g2')], const {}, titleOf: (_) => 'Laptop');
    expect(rows.length, 2);
    for (final r in rows) {
      expect(r.kind, NotificationRowKind.announcement);
      expect(r.title, neutralDrawTitle);
      expect(spoils('${r.title} ${r.body}'), isFalse);
    }
  });

  test('sudah reveal menang: 2 baris, hasil di atas pengumuman, waktu created_at', () {
    final rows = notificationRows([n(2, 'winner')], {'g1'}, titleOf: (_) => 'Laptop');
    expect(rows.map((r) => r.kind), [NotificationRowKind.result, NotificationRowKind.announcement]);
    expect(rows[0].title, 'Selamat, kamu menang!');
    expect(rows[0].won, isTrue);
    expect(rows[1].title, neutralDrawTitle);
    expect(rows[0].at, rows[1].at);
    expect(rows.every((r) => r.source.id == 2), isTrue);
  });

  test('sudah reveal tidak terpilih: 2 baris dengan teks "belum terpilih"', () {
    final rows = notificationRows([n(1, 'draw_result')], {'g1'});
    expect(rows.length, 2);
    expect(rows[0].title, 'Kamu belum terpilih');
    expect(rows[0].won, isFalse);
    expect(rows[1].kind, NotificationRowKind.announcement);
  });

  test('hitungan belum dibaca tetap per notifikasi server; urutan dipertahankan', () {
    final items = [n(3, 'winner'), n(2, 'ticket_created', gid: null), n(1, 'draw_result', gid: 'g2', read: true)];
    final rows = notificationRows(items, {'g1', 'g2'});
    expect(rows.map((r) => '${r.source.id}:${r.kind.name}'), ['3:result', '3:announcement', '2:normal', '1:result', '1:announcement']);
    expect(items.where((x) => !x.isRead).length, 2); // sumber tidak berubah
    expect({for (final r in rows) if (!r.source.isRead) r.source.id}.length, 2); // tanpa hitungan ganda
  });
}
