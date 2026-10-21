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

/// Regresi galat "Gagal memuat / Tidak ada koneksi internet." di Home setelah login: cache SQLite KOSONG
/// (server belum punya giveaway/tiket aktif saat terakhir online) + jaringan gagal harus tetap menjadi daftar kosong
/// + banner offline, bukan ErrorState. Jalur: cold start, resume dari latar, refresh di layar.
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

  // Keadaan server/jaringan yang bisa diganti di tengah tes.
  var mode = 'online';
  var hasData = false;
  final calls = <String>[];
  Future<http.Response> server(http.Request r) async {
    calls.add('${r.method} ${r.url.path} [$mode]');
    switch (mode) {
      case 'socket':
        throw const SocketException('Failed host lookup', osError: OSError('No address associated with hostname', 7));
      case 'timeout':
        throw TimeoutException('timeout');
      case '500':
        return http.Response('Internal Server Error', 500);
      case '401':
        return http.Response(jsonEncode({'ok': false, 'error': 'invalid_session'}), 401, headers: {'content-type': 'application/json'});
    }
    return switch (r.url.path) {
      '/auth/me' => ok({'ok': true, 'user': {'id': 'u1', 'username': 'user1', 'email': 'u1@example.com', 'full_name': 'User One', 'role': 'user', 'xp': 1, 'level': 1}}),
      '/giveaways' => ok({'ok': true, 'data': [if (hasData) giveaway]}),
      '/tickets' => ok({'ok': true, 'data': [if (hasData) ticket]}),
      _ => ok({'ok': true, 'data': []}),
    };
  }

  late LocalDb db;
  Widget app() => Code2TicketApp(
        key: UniqueKey(),
        api: ApiClient(client: MockClient(server), baseUrl: 'https://test.api'),
        sessionStore: SessionStore(),
        db: db,
        biometric: FakeBiometricService(),
        poller: _NoPoller(),
      );

  /// Waktu nyata untuk SQLite, waktu palsu untuk jeda ulang (3 dtk + 6 dtk), timeout, dan animasi.
  Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump(const Duration(seconds: 1));
    }
  }

  /// Boot: sesi online lebih dulu (profil + cache tersimpan sesuai [hasData]), lalu [mode] diganti dan app dibuka ulang.
  Future<void> bootOnlineThen(WidgetTester tester, {required bool data, required String thenMode, bool coldStart = true}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    mode = 'online';
    hasData = data;
    calls.clear();
    FlutterSecureStorage.setMockInitialValues({'c2t_token': 'tok'});
    await tester.runAsync(() async {
      final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(version: LocalDb.dbVersion, onCreate: LocalDb.createTables, singleInstance: false));
      db = LocalDb.withDatabase(raw);
    });
    await tester.pumpWidget(app());
    await settle(tester, rounds: 10);
    if (find.text('Nanti').evaluate().isNotEmpty) {
      await tester.tap(find.text('Nanti')); // dialog izin notifikasi (sekali) menutupi Home
      await settle(tester, rounds: 2);
    }
    expect(find.byType(ErrorState), findsNothing, reason: _texts(tester));
    expect(find.byType(OfflineBanner), findsNothing, reason: _texts(tester));
    if (coldStart) {
      await tester.pumpWidget(const SizedBox());
      mode = thenMode;
      await tester.pumpWidget(app());
      await settle(tester);
    }
  }

  /// SliverList membangun item secukupnya: gulir sampai judul giveaway terlihat.
  Future<bool> giveawayShown(WidgetTester tester) async {
    final f = find.text('Laptop Gaming');
    if (f.evaluate().isNotEmpty) return true;
    try {
      await tester.scrollUntilVisible(f, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 10);
    } catch (_) {
      return false;
    }
    return f.evaluate().isNotEmpty;
  }

  Future<void> closeDb(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async => db.database.then((d) => d.close()));
  }

  Future<void> expectOfflineEmptyHome(WidgetTester tester, String why, {bool banner = true}) async {
    expect(find.byType(ErrorState), findsNothing, reason: '$why: layar "Coba lagi" muncul, harusnya daftar kosong + banner. ${_texts(tester)} | $calls');
    if (banner) expect(find.byType(OfflineBanner), findsOneWidget, reason: '$why: ${_texts(tester)} | $calls');
    final empty = find.text('Belum ada giveaway aktif');
    if (empty.evaluate().isEmpty) await tester.scrollUntilVisible(empty, 300, scrollable: find.byType(Scrollable).first, maxScrolls: 10);
    expect(empty, findsOneWidget, reason: '$why: ${_texts(tester)}');
  }

  group('jalur A: cold start, token + profil tersimpan, cache kosong, jaringan gagal', () {
    for (final m in ['socket', 'timeout', '500']) {
      testWidgets('Home: daftar kosong + banner offline, bukan ErrorState ($m)', (tester) async {
        await bootOnlineThen(tester, data: false, thenMode: m);
        await expectOfflineEmptyHome(tester, 'cold start $m');
        await closeDb(tester);
      });
    }

    testWidgets('My Tickets: cache kosong offline = "Belum ada tiket" + banner, bukan ErrorState', (tester) async {
      await bootOnlineThen(tester, data: false, thenMode: 'socket');
      await tester.tap(find.byKey(const Key('ticket_summary')));
      await settle(tester, rounds: 12);
      expect(find.byType(ErrorState), findsNothing, reason: '${_texts(tester)} | $calls');
      expect(find.text('Belum ada tiket'), findsWidgets, reason: _texts(tester));
      expect(find.byType(OfflineBanner), findsOneWidget, reason: _texts(tester));
      await closeDb(tester);
    });

    testWidgets('Discover: cache kosong offline = "Belum ada giveaway" + banner, bukan ErrorState', (tester) async {
      await bootOnlineThen(tester, data: false, thenMode: 'socket');
      await tester.tap(find.byKey(const Key('home_search')));
      await settle(tester, rounds: 12);
      expect(find.byType(ErrorState), findsNothing, reason: '${_texts(tester)} | $calls');
      expect(find.text('Belum ada giveaway'), findsOneWidget, reason: _texts(tester));
      expect(find.byType(OfflineBanner), findsOneWidget, reason: _texts(tester));
      await closeDb(tester);
    });

    testWidgets('satu sumber gagal tidak menjatuhkan bagian lain: giveaway dari cache, tiket/minat/notifikasi gagal', (tester) async {
      await bootOnlineThen(tester, data: true, thenMode: 'online', coldStart: false);
      expect(await giveawayShown(tester), isTrue, reason: _texts(tester));
      await tester.pumpWidget(const SizedBox());
      mode = 'socket';
      await tester.pumpWidget(app());
      await settle(tester);
      expect(find.byType(ErrorState), findsNothing, reason: _texts(tester));
      expect(await giveawayShown(tester), isTrue, reason: '${_texts(tester)} | $calls');
      expect(find.byType(OfflineBanner), findsOneWidget);
      await closeDb(tester);
    });
  });

  group('jalur B: resume dari latar', () {
    Future<void> resume(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await settle(tester);
    }

    testWidgets('sesi online lalu jaringan mati, app kembali ke depan: konten tetap, tanpa ErrorState', (tester) async {
      await bootOnlineThen(tester, data: true, thenMode: 'online', coldStart: false);
      mode = 'socket';
      await resume(tester);
      expect(find.byType(ErrorState), findsNothing, reason: '${_texts(tester)} | $calls');
      expect(await giveawayShown(tester), isTrue, reason: _texts(tester));
      await closeDb(tester);
    });

    testWidgets('sesi online, cache kosong, jaringan mati lalu resume: tetap daftar kosong', (tester) async {
      await bootOnlineThen(tester, data: false, thenMode: 'online', coldStart: false);
      mode = 'socket';
      await resume(tester);
      expect(find.byType(ErrorState), findsNothing, reason: '${_texts(tester)} | $calls');
      await expectOfflineEmptyHome(tester, 'resume sesi online', banner: false); // tanpa muat ulang giveaway saat resume: daftar tetap, tanpa galat
      await closeDb(tester);
    });

    testWidgets('sesi offline lalu resume: 200 -> online dan data dimuat ulang', (tester) async {
      await bootOnlineThen(tester, data: false, thenMode: 'socket');
      await expectOfflineEmptyHome(tester, 'sebelum resume');
      mode = 'online';
      hasData = true;
      await resume(tester);
      expect(find.byType(OfflineBanner), findsNothing, reason: '${_texts(tester)} | $calls');
      expect(await giveawayShown(tester), isTrue, reason: '${_texts(tester)} | $calls');
      await closeDb(tester);
    });

    testWidgets('sesi offline lalu resume: jaringan masih mati -> tetap offline, tanpa ErrorState', (tester) async {
      await bootOnlineThen(tester, data: false, thenMode: 'socket');
      await resume(tester);
      await expectOfflineEmptyHome(tester, 'resume masih offline');
      await closeDb(tester);
    });

    testWidgets('sesi offline lalu resume: 401 -> keluar ke Login', (tester) async {
      await bootOnlineThen(tester, data: false, thenMode: 'socket');
      mode = '401';
      await resume(tester);
      expect(find.text('Masuk'), findsWidgets, reason: '${_texts(tester)} | $calls');
      expect(find.byType(ErrorState), findsNothing);
      await closeDb(tester);
    });
  });

  group('jalur C: di Home saat jaringan putus, tarik untuk menyegarkan', () {
    Future<void> pull(WidgetTester tester) async {
      await tester.fling(find.byType(CustomScrollView).first, const Offset(0, 400), 1000);
      await settle(tester);
    }

    testWidgets('cache kosong: refresh gagal jaringan -> daftar kosong + banner, bukan ErrorState', (tester) async {
      await bootOnlineThen(tester, data: false, thenMode: 'online', coldStart: false);
      mode = 'socket';
      await pull(tester);
      await expectOfflineEmptyHome(tester, 'refresh offline');
      await closeDb(tester);
    });

    testWidgets('cache berisi: refresh gagal jaringan -> data lama + banner', (tester) async {
      await bootOnlineThen(tester, data: true, thenMode: 'online', coldStart: false);
      mode = 'socket';
      await pull(tester);
      expect(find.byType(ErrorState), findsNothing, reason: _texts(tester));
      expect(await giveawayShown(tester), isTrue, reason: _texts(tester));
      expect(find.byType(OfflineBanner), findsOneWidget, reason: _texts(tester));
      await closeDb(tester);
    });

    testWidgets('galat server tak terduga (500) saat sesi online dan cache kosong: ErrorState + Coba lagi, bukan banner offline', (tester) async {
      await bootOnlineThen(tester, data: false, thenMode: 'online', coldStart: false);
      mode = '500';
      await pull(tester);
      expect(find.byType(ErrorState), findsOneWidget, reason: '${_texts(tester)} | $calls');
      expect(find.text('Coba lagi'), findsOneWidget);
      expect(find.byType(OfflineBanner), findsNothing, reason: _texts(tester));
      await closeDb(tester);
    });

    testWidgets('galat server tak terduga (500) pada pemuatan pertama sesi online: ErrorState + Coba lagi', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      mode = '500';
      calls.clear();
      FlutterSecureStorage.setMockInitialValues({'c2t_token': 'tok'});
      await tester.runAsync(() async {
        final raw = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
            options: OpenDatabaseOptions(version: LocalDb.dbVersion, onCreate: LocalDb.createTables, singleInstance: false));
        db = LocalDb.withDatabase(raw);
        await db.setSetting(
            'last_profile', jsonEncode({'id': 'u1', 'username': 'user1', 'full_name': 'User One', 'role': 'user', 'xp': 1, 'level': 1}));
      });
      // /auth/me sehat tetapi /giveaways 500: sesi online, bukan sesi offline.
      Future<http.Response> mixed(http.Request r) async => r.url.path == '/auth/me'
          ? ok({'ok': true, 'user': {'id': 'u1', 'username': 'user1', 'email': 'u1@example.com', 'full_name': 'User One', 'role': 'user', 'xp': 1, 'level': 1}})
          : http.Response('Internal Server Error', 500);
      await tester.pumpWidget(Code2TicketApp(
        key: UniqueKey(),
        api: ApiClient(client: MockClient(mixed), baseUrl: 'https://test.api'),
        sessionStore: SessionStore(),
        db: db,
        biometric: FakeBiometricService(),
        poller: _NoPoller(),
      ));
      await settle(tester);
      expect(find.byType(ErrorState), findsOneWidget, reason: _texts(tester));
      expect(find.text('Coba lagi'), findsOneWidget);
      expect(find.byType(OfflineBanner), findsNothing);
      await closeDb(tester);
    });
  });
}
