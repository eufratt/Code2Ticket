import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/notifications/background_check.dart';
import 'package:code2ticket/core/notifications/notification_service.dart';
import 'package:code2ticket/core/notifications/reminder_planner.dart';
import 'package:code2ticket/core/session/session_store.dart';
import 'package:code2ticket/features/notifications/notification_models.dart';
import 'package:flutter_test/flutter_test.dart';

import '../input_code_test.dart' show FakeApi;
import '../support/display.dart' show MemorySettings;
import 'reminder_test.dart' show FakeGateway;

class _Session extends SessionStore {
  _Session(this.token);
  final String? token;
  @override
  Future<String?> readToken() async => token;
}

Map<String, dynamic> _notif(int id, {String type = 'winner', bool read = false}) =>
    {'id': id, 'type': type, 'title': 'Judul $id', 'body': 'Isi', 'giveaway_id': 'g1', 'is_read': read};

void main() {
  late FakeGateway gw;
  late MemorySettings store;

  setUp(() {
    gw = FakeGateway();
    store = MemorySettings();
  });

  Future<void> run(FakeApi api, {String? token = 'tok'}) =>
      runBackgroundCheck(session: _Session(token), store: store, api: api, gateway: gw);

  test('notifikasi server baru tampil sekali; pemeriksaan berikutnya (foreground atau latar) tidak menggandakan', () async {
    await store.setSetting(NotifKeys.activeUser, 'u1');
    final api = FakeApi((m, p, b) async => {'ok': true, 'data': [_notif(5), _notif(4, read: true)]});
    await run(api);
    expect(gw.shown.map((s) => s.$1), [drawResultNotificationId('g1')]);
    expect(gw.shown.single.$4, 'result/g1');
    await run(api);
    expect(gw.shown.length, 1);
    // Foreground memakai batas yang sama.
    final fg = NotificationService(gw, store);
    await fg.init();
    await fg.showServerNotifications('u1', [AppNotification.tryParse(_notif(5))!]);
    expect(gw.shown.length, 1);
  });

  test('tanpa token atau tanpa pengguna aktif: tidak ada permintaan jaringan', () async {
    final api = FakeApi((m, p, b) async => {'ok': true, 'data': [_notif(1)]});
    await run(api); // pengguna aktif belum ada
    await store.setSetting(NotifKeys.activeUser, 'u1');
    await run(api, token: null);
    expect(api.calls, isEmpty);
    expect(gw.shown, isEmpty);
  });

  test('galat jaringan, sesi berakhir, respons gagal: tidak melempar dan tidak menampilkan apa pun', () async {
    await store.setSetting(NotifKeys.activeUser, 'u1');
    await run(FakeApi((m, p, b) async => throw NetworkException('mati')));
    await run(FakeApi((m, p, b) async => throw InvalidSessionException()));
    await run(FakeApi((m, p, b) async => throw ForbiddenException()));
    await run(FakeApi((m, p, b) async => {'ok': false, 'error': 'x'}));
    expect(gw.shown, isEmpty);
  });

  test('token tidak ada di isi notifikasi', () async {
    await store.setSetting(NotifKeys.activeUser, 'u1');
    await run(FakeApi((m, p, b) async => {'ok': true, 'data': [_notif(9)]}), token: 'RAHASIA-TOKEN');
    for (final s in gw.shown) {
      expect('${s.$2} ${s.$3} ${s.$4}'.contains('RAHASIA'), isFalse);
    }
  });
}
