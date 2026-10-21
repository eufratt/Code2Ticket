import 'dart:async';

import 'package:code2ticket/app_router.dart';
import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/location/location_service.dart';
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/features/admin/admin_controller.dart';
import 'package:code2ticket/features/admin/admin_giveaway_screen.dart';
import 'package:code2ticket/features/admin/admin_giveaways_screen.dart';
import 'package:code2ticket/features/admin/admin_models.dart';
import 'package:code2ticket/features/admin/codes_list_screen.dart';
import 'package:code2ticket/features/admin/create_giveaway_screen.dart';
import 'package:code2ticket/features/admin/generate_codes_screen.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/discover/discover_controller.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart';
import 'package:code2ticket/features/notifications/notifications_controller.dart';
import 'package:code2ticket/features/profile/profile_screen.dart';
import 'package:code2ticket/features/tickets/tickets_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'input_code_test.dart' show FakeApi, FakeAuth;
import 'layout/screens_layout_test.dart' show SampleEnv, sampleGiveaway, sampleUser;
import 'support/display.dart';
import 'support/fake_location.dart';
import 'support/memory_cache.dart';
import 'support/ui.dart';

const gid = '5deb977d-ff30-4e4e-849d-ff389fe51e6a';

GiveawayDraft draft({int? max, double? lat}) => GiveawayDraft(
      title: 'Giveaway Uji',
      organizer: 'Penyelenggara',
      description: '',
      category: 'gaming',
      prizeName: 'Laptop',
      prizeValueIdr: 20000000,
      howToParticipate: 'Cari kode di Instagram penyelenggara.',
      winnerCount: 2,
      maxTicketsPerUser: max,
      startAt: DateTime.utc(2026, 10, 19, 3, 0),
      endAt: DateTime.utc(2026, 10, 19, 4, 0),
      drawAt: DateTime.utc(2026, 10, 19, 4, 0),
      latitude: lat,
      longitude: lat == null ? null : 106.8,
      radiusKm: lat == null ? null : 5,
    );

void main() {
  late FakeApi api;
  late FakeAuth auth;
  late AdminController c;
  Future<Map<String, dynamic>> Function(String, String, dynamic) handler = (m, p, b) async => {'ok': true};

  setUp(() {
    handler = (m, p, b) async {
      if (m == 'GET' && p.startsWith('/admin/giveaways?')) return {'ok': true, 'data': [sampleGiveaway(gid, 'gaming', title: 'Giveaway Uji')]};
      return {'ok': true};
    };
    api = FakeApi((m, p, b) => handler(m, p, b));
    auth = FakeAuth(api);
    c = AdminController(AuthedApi(api, auth), auth);
  });

  group('AdminController: buat giveaway', () {
    test('sukses: POST tanpa retry, waktu UTC "Z", kolom opsional kosong tidak dikirim, daftar dimuat ulang', () async {
      handler = (m, p, b) async => m == 'POST' ? {'ok': true, 'giveaway_id': gid, 'created': true} : {'ok': true, 'data': []};
      final r = await c.createGiveaway(draft());
      expect(r!.isOk, isTrue);
      expect(r.data, gid);
      final post = api.calls.singleWhere((x) => x.method == 'POST');
      expect(post.path, '/admin/giveaways');
      expect(post.retry, isFalse);
      final body = post.body as Map<String, dynamic>;
      expect(body['draw_at'], '2026-10-19T04:00:00.000Z');
      expect(body['prize_value_idr'], 20000000);
      expect(body.containsKey('prize_value_usd'), isFalse);
      expect(body['how_to_participate'], 'Cari kode di Instagram penyelenggara.');
      expect(body.containsKey('organizer_url'), isFalse); // kosong tidak dikirim
      expect(body.containsKey('max_tickets_per_user'), isFalse);
      expect(body.containsKey('latitude'), isFalse);
      expect(body.containsKey('address'), isFalse);
      expect(api.calls.last.method, 'GET'); // daftar dimuat ulang
    });

    test('lokasi dan batas tiket ikut terkirim bila diisi', () async {
      await c.createGiveaway(draft(max: 3, lat: -6.2));
      final body = api.calls.singleWhere((x) => x.method == 'POST').body as Map<String, dynamic>;
      expect(body['max_tickets_per_user'], 3);
      expect([body['latitude'], body['longitude'], body['radius_km']], [-6.2, 106.8, 5]);
    });

    test('galat bisnis: pesan per kolom, dan pesan umum untuk pelanggaran jadwal dari database', () async {
      handler = (m, p, b) async => {'ok': false, 'error': 'invalid_input', 'field': 'winner_count'};
      expect((await c.createGiveaway(draft()))!.error, 'Jumlah pemenang 1-100.');
      handler = (m, p, b) async => {'ok': false, 'error': 'invalid_input', 'detail': 'giveaways_time_order'};
      expect((await c.createGiveaway(draft()))!.error, contains('jadwal'));
    });

    test('403 forbidden -> "Akses ditolak"; POST tidak diulang', () async {
      handler = (m, p, b) async => throw ForbiddenException();
      final r = await c.createGiveaway(draft());
      expect(r!.error, startsWith('Akses ditolak'));
      expect(api.posts('/admin/giveaways'), 1);
    });

    test('401 invalid_session -> null dan logout', () async {
      handler = (m, p, b) async => throw InvalidSessionException();
      expect(await c.createGiveaway(draft()), isNull);
      expect(auth.invalidated, 1);
    });

    test('jaringan putus -> pesan, tidak diulang', () async {
      handler = (m, p, b) async => throw NetworkException('Tidak ada koneksi internet.');
      expect((await c.createGiveaway(draft()))!.error, 'Tidak ada koneksi internet.');
      expect(api.posts('/admin/giveaways'), 1);
    });

    test('kirim ganda saat masih berjalan diabaikan', () async {
      final gate = Completer<Map<String, dynamic>>();
      handler = (m, p, b) => m == 'POST' ? gate.future : Future.value({'ok': true, 'data': []});
      final first = c.createGiveaway(draft());
      expect(c.busy, isTrue);
      expect(await c.createGiveaway(draft()), isNull);
      gate.complete({'ok': true, 'giveaway_id': gid});
      expect((await first)!.isOk, isTrue);
      expect(api.posts('/admin/giveaways'), 1);
      expect(c.busy, isFalse);
    });
  });

  group('AdminController: kode', () {
    test('generateCodes: body {count}, tanpa retry, mengembalikan kode', () async {
      handler = (m, p, b) async => {'ok': true, 'codes': ['AAAA-BBBB-CCCC', 'DDDD-EEEE-FFFF']};
      final r = await c.generateCodes(gid, 2);
      expect(r!.data, ['AAAA-BBBB-CCCC', 'DDDD-EEEE-FFFF']);
      final post = api.calls.single;
      expect(post.path, '/admin/giveaways/$gid/codes');
      expect(post.body, {'count': 2});
      expect(post.retry, isFalse);
    });

    test('generateCodes galat: giveaway_drawn, 403, 401, jaringan', () async {
      handler = (m, p, b) async => {'ok': false, 'error': 'giveaway_drawn'};
      expect((await c.generateCodes(gid, 1))!.error, contains('sudah diundi'));
      handler = (m, p, b) async => throw ForbiddenException();
      expect((await c.generateCodes(gid, 1))!.error, startsWith('Akses ditolak'));
      handler = (m, p, b) async => throw NetworkException('putus');
      expect((await c.generateCodes(gid, 1))!.error, 'putus');
      handler = (m, p, b) async => throw InvalidSessionException();
      expect(await c.generateCodes(gid, 1), isNull);
      expect(auth.invalidated, 1);
      expect(api.posts('/admin/giveaways/$gid/codes'), 4); // tidak ada retry
    });

    test('listCodes: mengurai status, melewati elemen rusak; galat 403 dan ok:false', () async {
      handler = (m, p, b) async => {
            'ok': true,
            'data': [
              {'code': 'AAAA-BBBB-CCCC', 'is_used': false, 'used_at': null, 'geo_radius_km': null},
              {'code': 'DDDD-EEEE-FFFF', 'is_used': true, 'used_at': '2026-10-19T03:00:00.000Z', 'geo_radius_km': '5.00'},
              {'rusak': 1},
            ],
          };
      final r = await c.listCodes(gid);
      expect(r!.data!.map((x) => (x.code, x.isUsed)), [('AAAA-BBBB-CCCC', false), ('DDDD-EEEE-FFFF', true)]);
      expect(api.calls.single.method, 'GET');
      handler = (m, p, b) async => throw ForbiddenException();
      expect((await c.listCodes(gid))!.error, startsWith('Akses ditolak'));
      handler = (m, p, b) async => {'ok': false, 'error': 'not_found'};
      expect((await c.listCodes(gid))!.error, 'Giveaway tidak ditemukan.');
      handler = (m, p, b) async => throw InvalidSessionException();
      expect(await c.listCodes(gid), isNull);
    });
  });

  group('AdminController: draw manual', () {
    test('sukses: hasil dari server, POST tanpa retry, daftar dimuat ulang', () async {
      handler = (m, p, b) async => m == 'POST'
          ? {'ok': true, 'draw_id': 'd1', 'status': 'completed', 'total_tickets': 12, 'winning_tickets': [3, 7], 'block_index': 2}
          : {'ok': true, 'data': []};
      final r = await c.runDraw(gid);
      expect(r!.data!.totalTickets, 12);
      expect(r.data!.winningTickets, [3, 7]);
      final post = api.calls.firstWhere((x) => x.method == 'POST');
      expect(post.path, '/admin/giveaways/$gid/draw');
      expect(post.retry, isFalse);
      expect(api.calls.last.method, 'GET');
    });

    test('galat server dipetakan ke pesan Indonesia', () async {
      for (final (code, text) in [
        ('already_drawn', 'sudah diundi'),
        ('not_started', 'belum dimulai'),
        ('demo_disabled', 'dimatikan'),
        ('seed_mismatch', 'seed'),
        ('not_found', 'tidak ditemukan'),
        ('too_many_requests', 'Terlalu banyak'),
      ]) {
        handler = (m, p, b) async => {'ok': false, 'error': code};
        expect((await c.runDraw(gid))!.error, contains(text), reason: code);
      }
    });

    test('403, 401, jaringan; tidak pernah diulang', () async {
      handler = (m, p, b) async => throw ForbiddenException();
      expect((await c.runDraw(gid))!.error, startsWith('Akses ditolak'));
      handler = (m, p, b) async => throw NetworkException('Koneksi terlalu lama. Coba lagi.');
      expect((await c.runDraw(gid))!.error, 'Koneksi terlalu lama. Coba lagi.');
      handler = (m, p, b) async => throw InvalidSessionException();
      expect(await c.runDraw(gid), isNull);
      expect(auth.invalidated, 1);
      expect(api.posts('/admin/giveaways/$gid/draw'), 3);
    });
  });

  group('AdminController: daftar giveaway', () {
    test('memuat GET /admin/giveaways; galat jaringan -> state error; logout mengosongkan', () async {
      await c.loadGiveaways();
      expect(c.giveaways.single.id, gid);
      expect(api.calls.last.path, '/admin/giveaways?limit=50');
      handler = (m, p, b) async => throw NetworkException('putus');
      await c.loadGiveaways();
      expect(c.error, 'putus');
      auth.status = AuthStatus.signedOut;
      auth.notifyListeners();
      expect(c.giveaways, isEmpty);
    });
  });

  // ------------------------------------------------------------------ widget
  Future<void> pumpWith(WidgetTester tester, Widget Function(GoRouter) home, {double width = 360, double height = 3000}) async {
    await setViewport(tester, width: width, height: height);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('halaman sebelumnya'))),
      GoRoute(path: '/page', builder: (ctx, _) => home(GoRouter.of(ctx))),
      GoRoute(path: '/admin/create', builder: (_, _) => const Scaffold(body: Text('form buat'))),
      GoRoute(path: '/admin/giveaway/:id', builder: (_, s) => Scaffold(body: Text('kelola ${s.pathParameters['id']}'))),
    ]);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        Provider<AuthedApi>.value(value: AuthedApi(api, auth)),
        ...displayProviders(),
        ChangeNotifierProvider<AdminController>.value(value: c),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), darkTheme: AppTheme.dark(), routerConfig: router),
    ));
    router.push('/page');
    await tester.pumpAndSettle();
  }

  group('form Buat Giveaway', () {
    Future<void> fillValid(WidgetTester tester) async {
      await tester.enterText(find.byKey(const Key('giveaway_title')), 'Giveaway Uji');
      await tester.enterText(find.byKey(const Key('giveaway_organizer')), 'Penyelenggara');
      await tester.enterText(find.byKey(const Key('giveaway_prize')), 'Laptop');
      await tester.enterText(find.byKey(const Key('giveaway_value')), '5000000');
      await tester.enterText(find.byKey(const Key('giveaway_how_to')), 'Ambil kode di stan penyelenggara.');
      await tester.tap(find.byKey(const Key('giveaway_category')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gaming').last);
      await tester.pumpAndSettle();
    }

    Future<void> submit(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('submit_giveaway')));
      await tester.pumpAndSettle();
    }

    testWidgets('saklar batas lokasi: tanpa lintang/bujur/radius ditolak di klien dengan pesan jelas', (tester) async {
      await pumpWith(tester, (_) => const CreateGiveawayScreen());
      await fillValid(tester);
      await tester.ensureVisible(find.byKey(const Key('giveaway_geo_restricted')));
      await tester.tap(find.byKey(const Key('giveaway_geo_restricted')));
      await tester.pumpAndSettle();
      expect(find.text('Peserta harus berada dalam radius dari lokasi giveaway saat menukar kode.'), findsOneWidget);
      await submit(tester);
      expect(find.text('Isi lintang, bujur, dan radius dulu untuk membatasi lokasi tukar kode.'), findsOneWidget);
      expect(api.calls.where((x) => x.method == 'POST'), isEmpty);
    });

    testWidgets('saklar batas lokasi: lengkap -> redeem_geo_restricted true terkirim; mati -> false', (tester) async {
      handler = (m, p, b) async => m == 'POST' ? {'ok': true, 'giveaway_id': gid} : {'ok': true, 'data': []};
      await pumpWith(tester, (_) => const CreateGiveawayScreen());
      await fillValid(tester);
      await tester.enterText(find.byKey(const Key('giveaway_lat')), '-6.2');
      await tester.enterText(find.byKey(const Key('giveaway_lng')), '106.8');
      await tester.enterText(find.byKey(const Key('giveaway_radius')), '5');
      await tester.ensureVisible(find.byKey(const Key('giveaway_geo_restricted')));
      await tester.tap(find.byKey(const Key('giveaway_geo_restricted')));
      await tester.pumpAndSettle();
      await submit(tester);
      final body = api.calls.singleWhere((x) => x.method == 'POST').body as Map<String, dynamic>;
      expect(body['redeem_geo_restricted'], true);
      expect(body['radius_km'], 5);
    });

    testWidgets('saklar mati (bawaan): redeem_geo_restricted false', (tester) async {
      handler = (m, p, b) async => m == 'POST' ? {'ok': true, 'giveaway_id': gid} : {'ok': true, 'data': []};
      await pumpWith(tester, (_) => const CreateGiveawayScreen());
      await fillValid(tester);
      await submit(tester);
      final body = api.calls.singleWhere((x) => x.method == 'POST').body as Map<String, dynamic>;
      expect(body['redeem_geo_restricted'], false);
    });

    testWidgets('kosong: pesan validasi, tidak ada permintaan', (tester) async {
      await pumpWith(tester, (_) => const CreateGiveawayScreen());
      await submit(tester);
      expect(find.text('Judul wajib diisi'), findsOneWidget);
      expect(find.text('Penyelenggara wajib diisi'), findsOneWidget);
      expect(find.text('Nama hadiah wajib diisi'), findsOneWidget);
      expect(find.text('Pilih kategori'), findsOneWidget);
      expect(find.text('Nilai hadiah harus berupa angka positif.'), findsOneWidget);
      expect(api.calls.where((x) => x.method == 'POST'), isEmpty);
    });

    testWidgets('nilai di luar batas: pemenang 0, judul > 120, nilai hadiah nol', (tester) async {
      await pumpWith(tester, (_) => const CreateGiveawayScreen());
      await fillValid(tester);
      await tester.enterText(find.byKey(const Key('giveaway_winners')), '0');
      await tester.enterText(find.byKey(const Key('giveaway_title')), 'x' * 121);
      await tester.enterText(find.byKey(const Key('giveaway_value')), '0');
      await submit(tester);
      expect(find.text('Isi bilangan 1 sampai 100'), findsOneWidget);
      expect(find.text('Judul maksimal 120 karakter'), findsOneWidget);
      expect(find.text('Nilai hadiah harus berupa angka positif.'), findsOneWidget);
      expect(api.calls.where((x) => x.method == 'POST'), isEmpty);
    });

    testWidgets('jadwal draw di masa lalu ditolak di klien', (tester) async {
      final past = DateTime.now().toUtc().subtract(const Duration(hours: 1));
      await pumpWith(tester, (_) => CreateGiveawayScreen(pickDateTime: (_, _) async => past));
      await fillValid(tester);
      await tester.tap(find.byKey(const Key('pick_draw_at')));
      await tester.pumpAndSettle();
      await submit(tester);
      expect(find.text('Jadwal draw harus di masa depan'), findsOneWidget);
      expect(api.calls.where((x) => x.method == 'POST'), isEmpty);
    });

    testWidgets('berakhir setelah jadwal draw ditolak', (tester) async {
      final later = DateTime.now().toUtc().add(const Duration(days: 2));
      await pumpWith(tester, (_) => CreateGiveawayScreen(pickDateTime: (_, _) async => later));
      await fillValid(tester);
      await tester.tap(find.byKey(const Key('pick_end_at')));
      await tester.pumpAndSettle();
      await submit(tester);
      expect(find.text('Berakhir tidak boleh setelah jadwal draw'), findsOneWidget);
    });

    testWidgets('lintang tanpa bujur, dan radius tanpa koordinat, ditolak', (tester) async {
      await pumpWith(tester, (_) => const CreateGiveawayScreen());
      await fillValid(tester);
      await tester.enterText(find.byKey(const Key('giveaway_lat')), '-6.2');
      await submit(tester);
      expect(find.text('Isi lintang dan bujur bersamaan'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('giveaway_lat')), '95');
      await tester.enterText(find.byKey(const Key('giveaway_lng')), '106.8');
      await submit(tester);
      expect(find.text('Harus antara -90 dan 90'), findsOneWidget);
      expect(api.calls.where((x) => x.method == 'POST'), isEmpty);
    });

    testWidgets('cara mendapatkan kode wajib 10-2000 karakter; tautan opsional hanya https', (tester) async {
      await pumpWith(tester, (_) => const CreateGiveawayScreen());
      await fillValid(tester);
      final how = find.byKey(const Key('giveaway_how_to')), url = find.byKey(const Key('giveaway_org_url'));
      Future<void> tryWith(String h, String u) async {
        await tester.enterText(how, h);
        await tester.enterText(url, u);
        await submit(tester);
      }

      await tryWith('', '');
      expect(find.text('Cara mendapatkan kode wajib diisi'), findsOneWidget);
      await tryWith('pendek', '');
      expect(find.text('Cara mendapatkan kode minimal 10 karakter'), findsOneWidget);
      await tryWith('x' * 2001, '');
      expect(find.text('Cara mendapatkan kode maksimal 2000 karakter'), findsOneWidget);
      for (final bad in ['http://example.com', 'javascript:alert(1)', 'ftp://example.com']) {
        await tryWith('Ambil kode di stan penyelenggara.', bad);
        expect(find.text('Tautan harus diawali https://'), findsOneWidget, reason: bad);
      }
      await tryWith('Ambil kode di stan penyelenggara.', 'https://user:pw@example.com');
      expect(find.text('Tautan tidak valid'), findsOneWidget);
      expect(api.calls.where((x) => x.method == 'POST'), isEmpty);
    });

    testWidgets('tautan https valid terkirim apa adanya bersama cara ikut', (tester) async {
      handler = (m, p, b) async => m == 'POST' ? {'ok': true, 'giveaway_id': gid} : {'ok': true, 'data': []};
      await pumpWith(tester, (_) => const CreateGiveawayScreen());
      await fillValid(tester);
      await tester.enterText(find.byKey(const Key('giveaway_org_url')), ' https://example.com/giveaway ');
      await submit(tester);
      final body = api.calls.singleWhere((x) => x.method == 'POST').body as Map<String, dynamic>;
      expect(body['organizer_url'], 'https://example.com/giveaway');
      expect(body['how_to_participate'], 'Ambil kode di stan penyelenggara.');
    });

    testWidgets('nilai hadiah rupiah: pemisah ribuan otomatis, label Rp, batas atas', (tester) async {
      await pumpWith(tester, (_) => const CreateGiveawayScreen());
      expect(find.text('Nilai hadiah (Rp)'), findsOneWidget);
      final field = find.byKey(const Key('giveaway_value'));
      await tester.enterText(field, '5000000');
      expect(tester.widget<TextField>(find.descendant(of: field, matching: find.byType(TextField))).controller!.text, '5.000.000');
      await tester.enterText(field, '999999999999'); // 12 digit: di atas Rp 100.000.000.000
      await submit(tester);
      expect(find.text('Nilai hadiah maksimal Rp 100.000.000.000.'), findsOneWidget);
      expect(api.calls.where((x) => x.method == 'POST'), isEmpty);
    });

    testWidgets('sukses: satu POST, kembali ke layar sebelumnya dengan konfirmasi', (tester) async {
      handler = (m, p, b) async => m == 'POST' ? {'ok': true, 'giveaway_id': gid} : {'ok': true, 'data': []};
      await pumpWith(tester, (_) => const CreateGiveawayScreen());
      await fillValid(tester);
      await submit(tester);
      final posts = api.calls.where((x) => x.method == 'POST').toList();
      expect(posts.length, 1);
      final body = posts.single.body as Map<String, dynamic>;
      expect(body['title'], 'Giveaway Uji');
      expect(body['category'], 'gaming');
      expect(body['prize_value_idr'], 5000000); // round-trip: Rp 5.000.000 persis, bilangan bulat
      expect(body['prize_value_idr'], isA<int>());
      expect(body['winner_count'], 1);
      expect(find.text('Giveaway dibuat.'), findsOneWidget);
      expect(find.byType(CreateGiveawayScreen), findsNothing);
      expect(api.calls.last.path, '/admin/giveaways?limit=50'); // daftar dimuat ulang setelah dibuat
    });

    testWidgets('galat server tampil di layar (bukan hanya snackbar); tombol memuat mencegah kirim ganda', (tester) async {
      final gate = Completer<Map<String, dynamic>>();
      handler = (m, p, b) => m == 'POST' ? gate.future : Future.value({'ok': true, 'data': []});
      await pumpWith(tester, (_) => const CreateGiveawayScreen());
      await fillValid(tester);
      await tester.tap(find.byKey(const Key('submit_giveaway')));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byKey(const Key('submit_giveaway')), warnIfMissed: false);
      await tester.pump();
      expect(api.posts('/admin/giveaways'), 1);
      gate.complete({'ok': false, 'error': 'forbidden'});
      await tester.pumpAndSettle();
      expect(find.text('Akses ditolak. Akun ini bukan admin.'), findsOneWidget);
      expect(find.byType(CreateGiveawayScreen), findsOneWidget);
    });
  });

  group('layar Admin', () {
    testWidgets('semua status tampil dengan chip teks; Generate Code ada untuk upcoming', (tester) async {
      Map<String, dynamic> g(String id, String title, String status, Duration start, Duration end) => {
            ...sampleGiveaway(id, 'gaming', title: title),
            'status': status,
            'start_at': DateTime.now().toUtc().add(start).toIso8601String(),
            'end_at': DateTime.now().toUtc().add(end).toIso8601String(),
          };
      handler = (m, p, b) async => {
            'ok': true,
            'data': [
              g('g1', 'Akan Datang', 'upcoming', const Duration(hours: 2), const Duration(hours: 5)),
              g('g2', 'Sedang Jalan', 'active', const Duration(hours: -1), const Duration(hours: 2)),
              g('g3', 'Tunggu Undi', 'waiting_draw', const Duration(hours: -5), const Duration(hours: -1)),
              g('g4', 'Sudah Undi', 'drawn', const Duration(hours: -5), const Duration(hours: -1)),
            ],
          };
      await pumpWith(tester, (_) => const AdminGiveawaysScreen());
      for (final t in ['Akan Datang', 'Sedang Jalan', 'Tunggu Undi', 'Sudah Undi']) {
        expect(find.text(t), findsOneWidget);
      }
      for (final label in ['Segera dimulai', 'Aktif', 'Menunggu draw', 'Selesai']) {
        expect(find.text(label), findsOneWidget);
      }
    });

    testWidgets('daftar giveaway: ketuk membuka kelola; tombol Buat giveaway', (tester) async {
      await pumpWith(tester, (_) => const AdminGiveawaysScreen());
      expect(find.text('Giveaway Uji'), findsOneWidget);
      await tester.tap(find.byKey(const Key('admin_create')));
      await tester.pumpAndSettle();
      expect(find.text('form buat'), findsOneWidget);
    });

    testWidgets('galat memuat: ErrorState', (tester) async {
      handler = (m, p, b) async => throw NetworkException('Tidak ada koneksi internet.');
      await pumpWith(tester, (_) => const AdminGiveawaysScreen());
      expect(find.text('Tidak ada koneksi internet.'), findsOneWidget);
    });

    testWidgets('Generate Code: hasil sekali, salin per kode dan salin semua, peringatan jelas', (tester) async {
      handler = (m, p, b) async => {'ok': true, 'codes': ['AAAA-BBBB-CCCC', 'DDDD-EEEE-FFFF']};
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pumpWith(tester, (_) => const GenerateCodesScreen(giveawayId: gid));
      await tester.enterText(find.byKey(const Key('code_count')), '2');
      await tester.tap(find.byKey(const Key('generate_codes')));
      await tester.pumpAndSettle();
      expect(api.calls.single.body, {'count': 2});
      expect(find.text('AAAA-BBBB-CCCC'), findsOneWidget);
      expect(find.textContaining('tidak disimpan di perangkat'), findsOneWidget);
      await tester.tap(find.byKey(const Key('copy_AAAA-BBBB-CCCC')));
      await tester.pump();
      expect(copied.last, 'AAAA-BBBB-CCCC');
      await tester.tap(find.byKey(const Key('copy_all')));
      await tester.pump();
      expect(copied.last, 'AAAA-BBBB-CCCC\nDDDD-EEEE-FFFF');
    });

    testWidgets('Generate Code: jumlah tidak valid ditolak; galat server tampil', (tester) async {
      handler = (m, p, b) async => {'ok': false, 'error': 'giveaway_drawn'};
      await pumpWith(tester, (_) => const GenerateCodesScreen(giveawayId: gid));
      await tester.enterText(find.byKey(const Key('code_count')), '1001');
      await tester.tap(find.byKey(const Key('generate_codes')));
      await tester.pumpAndSettle();
      expect(find.text('Isi bilangan 1 sampai 1000'), findsOneWidget);
      expect(api.calls, isEmpty);
      await tester.enterText(find.byKey(const Key('code_count')), '3');
      await tester.tap(find.byKey(const Key('generate_codes')));
      await tester.pumpAndSettle();
      expect(find.textContaining('sudah diundi'), findsOneWidget);
    });

    testWidgets('Daftar Kode: status Dipakai / Belum dipakai dengan chip; 403 tampil sebagai galat', (tester) async {
      handler = (m, p, b) async => {
            'ok': true,
            'data': [
              {'code': 'AAAA-BBBB-CCCC', 'is_used': false},
              {'code': 'DDDD-EEEE-FFFF', 'is_used': true, 'used_at': '2026-10-19T03:00:00.000Z'},
            ],
          };
      await pumpWith(tester, (_) => const CodesListScreen(giveawayId: gid));
      expect(find.text('Belum dipakai'), findsOneWidget);
      expect(find.text('Dipakai'), findsOneWidget);
      expect(find.text('2 kode, 1 dipakai'), findsOneWidget);
    });

    testWidgets('Daftar Kode: tidak ada chip radius per kode (data lama dengan geo_radius_km diabaikan)', (tester) async {
      handler = (m, p, b) async => {
            'ok': true,
            'data': [
              {'code': 'AAAA-BBBB-CCCC', 'is_used': false, 'geo_radius_km': '5.00'},
            ],
          };
      await pumpWith(tester, (_) => const CodesListScreen(giveawayId: gid));
      expect(find.textContaining('Radius'), findsNothing);
    });

    testWidgets('Daftar Kode: 403 -> "Akses ditolak"', (tester) async {
      handler = (m, p, b) async => throw ForbiddenException();
      await pumpWith(tester, (_) => const CodesListScreen(giveawayId: gid));
      expect(find.textContaining('Akses ditolak'), findsOneWidget);
    });

    Giveaway g() => Giveaway.tryParse(sampleGiveaway(gid, 'gaming', title: 'Giveaway Uji'))!;

    testWidgets('Draw manual: konfirmasi menjelaskan tidak bisa dibatalkan; batal = tanpa POST', (tester) async {
      await pumpWith(tester, (_) => AdminGiveawayScreen(giveawayId: gid, initial: g()));
      await tester.tap(find.byKey(const Key('run_draw')));
      await tester.pumpAndSettle();
      expect(find.textContaining('tidak bisa dibatalkan'), findsWidgets);
      await tester.tap(find.byKey(const Key('draw_cancel')));
      await tester.pumpAndSettle();
      expect(api.calls.where((x) => x.method == 'POST'), isEmpty);
    });

    testWidgets('Draw manual: konfirmasi -> satu POST, hasil tampil', (tester) async {
      handler = (m, p, b) async => m == 'POST'
          ? {'ok': true, 'status': 'completed', 'total_tickets': 12, 'winning_tickets': [3], 'block_index': 2}
          : {'ok': true, 'data': []};
      await pumpWith(tester, (_) => AdminGiveawayScreen(giveawayId: gid, initial: g()));
      await tester.tap(find.byKey(const Key('run_draw')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('draw_confirm')));
      await tester.pumpAndSettle();
      expect(api.posts('/admin/giveaways/$gid/draw'), 1);
      expect(find.textContaining('12 tiket ikut'), findsOneWidget);
      expect(find.textContaining('#000003'), findsOneWidget);
    });

    testWidgets('Draw manual: galat server tampil apa adanya dalam bahasa Indonesia', (tester) async {
      handler = (m, p, b) async => {'ok': false, 'error': 'demo_disabled'};
      await pumpWith(tester, (_) => AdminGiveawayScreen(giveawayId: gid, initial: g()));
      await tester.tap(find.byKey(const Key('run_draw')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('draw_confirm')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Draw manual dimatikan'), findsOneWidget);
      expect(api.posts('/admin/giveaways/$gid/draw'), 1);
    });
  });

  group('akses Admin', () {
    Future<void> pumpProfile(WidgetTester tester, String role) async {
      await setViewport(tester, height: 1400);
      final env = SampleEnv();
      env.auth.user = sampleUser(role: role);
      await tester.pumpWidget(env.app(const ProfileScreen()));
      await tester.pumpAndSettle();
    }

    testWidgets('user biasa: menu Admin tidak ada', (tester) async {
      await pumpProfile(tester, 'user');
      expect(find.byKey(const Key('open_admin')), findsNothing);
      expect(find.byKey(const Key('open_settings')), findsOneWidget);
    });

    testWidgets('admin: menu Admin tampil', (tester) async {
      await pumpProfile(tester, 'admin');
      expect(find.byKey(const Key('open_admin')), findsOneWidget);
    });

    for (final (role, allowed) in [('user', false), ('admin', true)]) {
      testWidgets('router: /admin ${allowed ? 'dibuka' : 'dialihkan ke Profil'} untuk role $role', (tester) async {
        await setViewport(tester, height: 900);
        final env = SampleEnv();
        env.auth.user = sampleUser(role: role);
        final router = buildRouter(env.auth);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthController>.value(value: env.auth),
            ...displayProviders(),
            Provider<AuthedApi>.value(value: env.authed),
            ChangeNotifierProvider(create: (_) => GiveawaysController(env.authed, env.auth, MemoryCacheStore(), retryInterval: null)),
            ChangeNotifierProvider(create: (_) => TicketsController(env.authed, env.auth, MemoryCacheStore(), retryInterval: null)),
            ChangeNotifierProvider(create: (_) => NotificationsController(env.authed, env.auth)),
            ChangeNotifierProvider(create: (_) => AdminController(env.authed, env.auth)),
            ChangeNotifierProvider(create: (_) => DiscoverController(env.authed, env.auth, MemoryCacheStore(), LocationService(FakeGateway()), retryInterval: null)),
          ],
          child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router),
        ));
        await tester.pumpAndSettle();
        router.go('/admin');
        await tester.pumpAndSettle();
        expect(router.state.matchedLocation, allowed ? '/admin' : '/profile');
        expect(find.byType(AdminGiveawaysScreen), allowed ? findsOneWidget : findsNothing);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
