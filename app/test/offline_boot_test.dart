import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/db/local_db.dart';
import 'package:code2ticket/core/notifications/background_check.dart';
import 'package:code2ticket/core/session/session_store.dart';
import 'package:code2ticket/core/widgets/empty_state.dart';
import 'package:code2ticket/core/widgets/offline_banner.dart';
import 'package:code2ticket/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'auth_controller_test.dart' show FakeBiometricService;

class _NoPoller implements BackgroundPoller {
  @override
  dynamic noSuchMethod(Invocation i) => Future<void>.value();
}

String _texts(WidgetTester t) => t.widgetList<Text>(find.byType(Text)).map((w) => w.data).whereType<String>().join(' | ');

/// Boot nyata dari main (Code2TicketApp -> AuthController.restore -> router -> Home/My Tickets) dengan LocalDb SQLite
/// sungguhan; klien HTTP melempar galat jaringan yang dilempar dart:io/package:http di perangkat saat mode pesawat.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final soon = DateTime.now().add(const Duration(hours: 5)).toUtc().toIso8601String();
  final start = DateTime.now().subtract(const Duration(hours: 1)).toUtc().toIso8601String();
  final giveaway = {
    'id': 'g1', 'title': 'Laptop Gaming', 'category': 'gaming', 'prize_name': 'Laptop', 'winner_count': 1, 'ticket_count': 0,
    'status': 'active', 'start_at': start, 'end_at': soon, 'draw_at': soon,
  };
  final ticket = {
    'id': 't1', 'ticket_number': 7, 'giveaway_id': 'g1', 'giveaway_title': 'Laptop Gaming', 'prize_name': 'Laptop',
    'end_at': soon, 'draw_at': soon, 'result': 'eligible', 'created_at': start, 'code_masked': '****-7FES',
  };
  http.Response ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

  var endedCache = false;
  Future<http.Response> online(http.Request r) async => switch (r.url.path) {
        '/auth/me' => ok({'ok': true, 'user': {'id': 'u1', 'username': 'user1', 'email': 'u1@example.com', 'full_name': 'User One', 'role': 'user', 'xp': 1, 'level': 1}}),
        '/giveaways' => ok({'ok': true, 'data': [if (endedCache) {...giveaway, 'end_at': start} else giveaway]}),
        '/tickets' => ok({'ok': true, 'data': [ticket]}),
        _ => ok({'ok': true, 'data': []}),
      };

  // Galat yang benar-benar muncul di perangkat saat tanpa jaringan.
  final errors = <String, Object Function()>{
    'SocketException host lookup': () => const SocketException("Failed host lookup: 'code2ticket.onrender.com'", osError: OSError('No address associated with hostname', 7)),
    'SocketException unreachable': () => const SocketException('Connection failed', osError: OSError('Network is unreachable', 101)),
    'ClientException': () => http.ClientException('Connection closed before full header was received'),
    'HandshakeException': () => const HandshakeException('Connection terminated during handshake'),
    'HttpException': () => const HttpException('Connection reset by peer'),
    'TlsException': () => const TlsException('TLS error'),
    'OSError': () => const OSError('Network is unreachable', 101),
    'TimeoutException': () => TimeoutException('timeout'),
  };

  for (final (biometric, ended) in [(true, false), (false, false), (true, true)]) {
    for (final e in errors.entries) {
      testWidgets('cold start offline (${e.key}, biometric ${biometric ? 'aktif' : 'nonaktif'}${ended ? ', giveaway di cache sudah berakhir' : ''}): Home dan My Tickets dari cache + banner', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        endedCache = ended;
        FlutterSecureStorage.setMockInitialValues({'c2t_token': 'tok'});
        late LocalDb db;
        await tester.runAsync(() async {
          final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
              options: OpenDatabaseOptions(version: LocalDb.dbVersion, onCreate: LocalDb.createTables));
          db = LocalDb.withDatabase(raw);
          if (biometric) await db.setSetting('biometric_enabled', '1', userId: 'u1');
        });
        Widget app(Future<http.Response> Function(http.Request) h, {int tab = 0}) => Code2TicketApp(
              key: UniqueKey(),
              api: ApiClient(client: MockClient(h), baseUrl: 'https://test.api'),
              sessionStore: SessionStore(),
              db: db,
              biometric: FakeBiometricService(),
              poller: _NoPoller(),
            );

        // 1) Sesi online: Home dan My Tickets dimuat -> profil dan cache tersimpan.
        await tester.pumpWidget(app(online));
        for (var i = 0; i < 20; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('Kamu punya 1 tiket'), findsOneWidget, reason: _texts(tester));
        expect(find.byType(OfflineBanner), findsNothing);

        // 2) Tutup total, mode pesawat, buka dingin.
        await tester.pumpWidget(const SizedBox());
        final calls = <String>[];
        await tester.pumpWidget(app((r) async {
          calls.add(r.url.path);
          throw e.value();
        }));
        // Waktu nyata untuk SQLite, waktu palsu untuk jeda ulang (3 dtk + 6 dtk) dan timeout.
        for (var i = 0; i < 300 && find.byType(OfflineBanner).evaluate().isEmpty && find.byType(ErrorState).evaluate().isEmpty; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(milliseconds: 500));
        }
        for (var i = 0; i < 30; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
          await tester.pump(const Duration(seconds: 1)); // menghabiskan jeda ulang yang masih berjalan
        }
        expect(find.byType(ErrorState), findsNothing, reason: '${_texts(tester)} galat ${e.key}: layar "Coba lagi" muncul, harusnya cache. Permintaan: $calls');
        expect(find.byType(OfflineBanner), findsOneWidget, reason: '${_texts(tester)} calls=$calls');
        expect(find.text('Kamu punya 1 tiket'), findsOneWidget, reason: '${_texts(tester)} calls=$calls');
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() async => db.database.then((d) => d.close()));
      });
    }
  }
}
