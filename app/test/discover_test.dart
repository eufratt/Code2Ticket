import 'dart:async';

import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/geocoding/geocoder.dart';
import 'package:code2ticket/core/location/location_service.dart';
import 'package:code2ticket/core/widgets/offline_banner.dart';
import 'package:code2ticket/core/widgets/widgets.dart' show SkeletonLoader;
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/auth/auth_models.dart';
import 'package:code2ticket/features/discover/discover_controller.dart';
import 'package:code2ticket/features/discover/discover_filters.dart';
import 'package:code2ticket/features/discover/discover_screen.dart';
import 'package:code2ticket/features/giveaways/giveaway_card.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'cache_test.dart' show gw;
import 'input_code_test.dart' show FakeApi, FakeAuth, json;
import 'models_test.dart' show giveawayJson;
import 'support/fake_location.dart';
import 'support/display.dart';
import 'support/ui.dart';
import 'support/memory_cache.dart';

Map<String, dynamic> listOf(List<Giveaway> gs, {double? distance}) => {
      'ok': true,
      'data': [
        for (final g in gs)
          {
            'id': g.id, 'title': g.title, 'category': g.category, 'prize_name': g.prizeName,
            'prize_value_idr': g.prizeValueIdr, 'latitude': g.latitude, 'longitude': g.longitude,
            'start_at': g.startAt!.toUtc().toIso8601String(), 'end_at': g.endAt!.toUtc().toIso8601String(),
            'draw_at': g.drawAt!.toUtc().toIso8601String(), 'winner_count': 1, 'ticket_count': 0,
            'status': g.status, 'distance_km': distance,
          },
      ],
    };

Map<String, String> queryOf(String path) => Uri.parse(path).queryParameters;

void main() {
  group('DiscoverFilters.toQuery', () {
    test('bawaan ("Semua"): status=all, urutan deadline', () {
      expect(const DiscoverFilters().toQuery(), {'status': 'all', 'sort': 'deadline', 'limit': '20'});
      expect(const DiscoverFilters(query: 'kamera').toQuery(), {'q': 'kamera', 'status': 'all', 'sort': 'deadline', 'limit': '20'});
      expect(const DiscoverFilters(query: 'kamera', status: GiveawayStatusFilter.finished).toQuery()['status'], 'finished');
    });

    test('semua filter dipetakan ke parameter backend', () {
      final f = const DiscoverFilters().copyWith(
        query: '  laptop ',
        category: 'tech',
        minValueIdr: 1000000,
        maxValueIdr: 25000000,
        deadlineDays: 7,
        status: GiveawayStatusFilter.upcoming,
        sort: GiveawaySort.value,
      );
      expect(f.toQuery(offset: 20), {
        'q': 'laptop', 'category': 'tech', 'min_value': '1000000', 'max_value': '25000000', 'deadline_days': '7',
        'status': 'upcoming', 'sort': 'value', 'limit': '20', 'offset': '20',
      });
    });

    test('posisi dan radius hanya dikirim bila posisi ada', () {
      final f = const DiscoverFilters().copyWith(nearbyRadiusKm: 10, sort: GiveawaySort.nearest);
      expect(f.toQuery().containsKey('lat'), isFalse);
      expect(f.toQuery().containsKey('radius_km'), isFalse);
      final q = f.toQuery(lat: -6.2, lng: 106.8);
      expect([q['lat'], q['lng'], q['radius_km'], q['sort']], ['-6.2', '106.8', '10', 'nearest']);
      // posisi tanpa mode terdekat: jarak saja, tanpa batas radius
      expect(const DiscoverFilters().toQuery(lat: 1, lng: 2).containsKey('radius_km'), isFalse);
    });

    test('copyWith: null mengosongkan, tidak diisi = tetap', () {
      final f = const DiscoverFilters(category: 'tech', minValueIdr: 5);
      expect(f.copyWith(query: 'x').category, 'tech');
      expect(f.copyWith(category: null).category, isNull);
      expect(f.copyWith(minValueIdr: null).minValueIdr, isNull);
      expect(f.activeFilterCount, 2); // kategori + rentang nilai
      final s = f.copyWith(status: GiveawayStatusFilter.active);
      expect([s.status, s.activeFilterCount], [GiveawayStatusFilter.active, 3]); // status eksplisit ikut dihitung
      expect(s.copyWith(query: 'x').status, GiveawayStatusFilter.active);
      expect(s.copyWith(status: null).status, isNull);
    });
  });

  group('DiscoverFilters.applyLocal (offline, aturan sama dengan backend)', () {
    final now = DateTime.now();
    final a = gw('a', title: 'Laptop Gaming', lat: -6.2, lng: 106.8, end: now.add(const Duration(hours: 5)));
    final b = Giveaway(
      id: 'b', title: 'Paket Bali', category: 'travel', prizeName: 'Liburan', organizer: 'Biro Wisata',
      prizeValueIdr: 15000000, latitude: -8.4, longitude: 115.2,
      startAt: now.subtract(const Duration(hours: 1)), endAt: now.add(const Duration(days: 3)),
    );
    final c = gw('c', title: 'Kopi', end: now.add(const Duration(hours: 1)));
    final upcoming = gw('u', title: 'Besok', start: now.add(const Duration(hours: 2)), end: now.add(const Duration(hours: 9)));
    final finished = gw('f', title: 'Selesai', status: 'drawn');
    final waiting = gw('w', title: 'Tunggu', start: now.subtract(const Duration(hours: 3)), end: now.subtract(const Duration(hours: 1)));
    final all = [a, b, c, upcoming, finished, waiting];
    List<String> ids(DiscoverFilters f, {double? lat, double? lng}) =>
        f.applyLocal(all, lat: lat, lng: lng, now: now).map((g) => g.id).toList();

    test('"Semua": aktif (deadline terdekat), akan datang, menunggu draw, selesai',
        () => expect(ids(const DiscoverFilters()), ['c', 'a', 'b', 'u', 'w', 'f']));
    test('chip tiap status berisi kelompoknya saja', () {
      expect(ids(const DiscoverFilters(status: GiveawayStatusFilter.active)), ['c', 'a', 'b']);
      expect(ids(const DiscoverFilters(status: GiveawayStatusFilter.upcoming)), ['u']);
      expect(ids(const DiscoverFilters(status: GiveawayStatusFilter.finished)), ['w', 'f']);
    });
    test('pencarian lintas status', () {
      expect(ids(const DiscoverFilters(query: 'hadiah')), ['c', 'a', 'u', 'w', 'f']);
      expect(ids(const DiscoverFilters(query: 'selesai')), ['f']);
      // kelompok status tetap di depan, sort lain hanya berlaku di dalam kelompok
      expect(ids(const DiscoverFilters(query: 'hadiah', sort: GiveawaySort.newest)).sublist(2), ['u', 'w', 'f']);
    });
    test('status eksplisit menimpa aturan bawaan dan kata kunci', () {
      expect(ids(const DiscoverFilters(query: 'hadiah', status: GiveawayStatusFilter.active)), ['c', 'a']);
      expect(ids(const DiscoverFilters(status: GiveawayStatusFilter.active)), ['c', 'a', 'b']);
    });
    test('kata kunci di judul, hadiah, atau penyelenggara (tak peka huruf besar)', () {
      expect(ids(const DiscoverFilters(query: 'LAPTOP')), ['a']);
      expect(ids(const DiscoverFilters(query: 'biro')), ['b']);
      expect(ids(const DiscoverFilters(query: 'liburan')), ['b']);
      expect(ids(const DiscoverFilters(query: 'tidak ada')), isEmpty);
    });
    test('kategori dan rentang nilai', () {
      expect(ids(const DiscoverFilters(category: 'travel')), ['b']);
      expect(ids(const DiscoverFilters(minValueIdr: 10000000)), ['b']);
      expect(ids(const DiscoverFilters(maxValueIdr: 5000000)), ['c', 'a', 'u', 'w', 'f']);
    });
    test('deadline dalam N hari', () => expect(ids(const DiscoverFilters(deadlineDays: 1)), ['c', 'a', 'u', 'w', 'f']));
    test('status akan datang dan selesai', () {
      expect(ids(const DiscoverFilters(status: GiveawayStatusFilter.upcoming)), ['u']);
      expect(ids(const DiscoverFilters(status: GiveawayStatusFilter.finished)), ['w', 'f']); // menunggu draw dulu
    });
    test('urutan nilai dan terbaru', () {
      expect(ids(const DiscoverFilters(sort: GiveawaySort.value)), ['b', 'c', 'a', 'u', 'w', 'f']);
    });
    test('terdekat: jarak dihitung lokal, tanpa koordinat di akhir, radius menyaring', () {
      const near = DiscoverFilters(sort: GiveawaySort.nearest);
      expect(ids(near, lat: -6.2, lng: 106.8), ['a', 'b', 'c', 'u', 'w', 'f']);
      final first = near.applyLocal(all, lat: -6.2, lng: 106.8, now: now).first;
      expect(first.distanceKm, 0);
      expect(ids(const DiscoverFilters(sort: GiveawaySort.nearest, nearbyRadiusKm: 25), lat: -6.2, lng: 106.8), ['a']);
      expect(ids(const DiscoverFilters(nearbyRadiusKm: 25)), isEmpty); // tanpa posisi tidak ada yang "dekat"
    });
  });

  group('DiscoverController', () {
    late FakeApi api;
    late FakeAuth auth;
    late MemoryCacheStore cache;
    late FakeGateway gateway;
    var online = true;
    final requests = <Map<String, String>>[];

    DiscoverController make({Duration debounce = const Duration(milliseconds: 40), Duration? retry, int pageSize = 20}) {
      cache = MemoryCacheStore();
      gateway = FakeGateway(permission: GatewayPermission.granted);
      auth = FakeAuth(api);
      auth.user = AppUser(id: 'u1', username: 'a', email: 'a@x.id', fullName: 'A', role: 'user', xp: 0, level: 1);
      return DiscoverController(AuthedApi(api, auth), auth, cache, LocationService(gateway),
          debounce: debounce, retryInterval: retry, pageSize: pageSize);
    }

    setUp(() {
      online = true;
      requests.clear();
      api = FakeApi((m, p, b) async {
        requests.add(queryOf(p));
        if (!online) throw NetworkException('Tidak ada koneksi internet.');
        return listOf([gw('a', title: 'Laptop'), gw('b', title: 'Kopi')]);
      });
    });

    test('debounce: ketikan beruntun hanya memicu satu permintaan dengan kata terakhir', () async {
      final c = make();
      c.onQueryChanged('l');
      await Future.delayed(const Duration(milliseconds: 15));
      c.onQueryChanged('la');
      await Future.delayed(const Duration(milliseconds: 15));
      c.onQueryChanged('lap');
      expect(requests, isEmpty); // belum ada permintaan selama masih mengetik
      await Future.delayed(const Duration(milliseconds: 120));
      expect(requests, hasLength(1));
      expect(requests.single['q'], 'lap');
      expect(c.items, hasLength(2));
      c.dispose();
    });

    test('teks yang sama tidak memicu permintaan; submit membatalkan debounce dan langsung mencari', () async {
      final c = make(debounce: const Duration(milliseconds: 200));
      c.onQueryChanged('abc');
      await c.submitQuery('abc');
      await Future.delayed(const Duration(milliseconds: 300));
      expect(requests, hasLength(1)); // dari submit saja, timer debounce dibatalkan
      c.onQueryChanged('abc'); // tidak berubah
      await Future.delayed(const Duration(milliseconds: 300));
      expect(requests, hasLength(1));
      c.dispose();
    });

    test('riwayat: tersimpan saat submit, dedupe, maks. 10, hapus satu, hapus semua', () async {
      final c = make();
      await c.submitQuery('laptop');
      await c.submitQuery('kopi');
      await c.submitQuery('laptop');
      expect(c.history, ['laptop', 'kopi']);
      await c.submitQuery('   '); // kosong tidak masuk riwayat
      expect(c.history, ['laptop', 'kopi']);
      for (var i = 0; i < 12; i++) {
        await c.submitQuery('q$i');
      }
      expect(c.history, hasLength(10));
      await c.deleteHistory('q11');
      expect(c.history.first, 'q10');
      await c.clearHistory();
      expect(c.history, isEmpty);
      c.dispose();
    });

    test('riwayat terpisah per pengguna', () async {
      final c = make();
      await c.submitQuery('rahasia u1');
      cache.searches['u2'] = ['milik u2'];
      expect(c.history, ['rahasia u1']);
      auth.user = AppUser(id: 'u2', username: 'b', email: 'b@x.id', fullName: 'B', role: 'user', xp: 0, level: 1);
      await c.loadHistory();
      expect(c.history, ['milik u2']);
      c.dispose();
    });

    test('status: bawaan status=all; pilihan eksplisit dikirim; null kembali ke all', () async {
      final c = make();
      await c.search();
      expect(requests.last['status'], 'all');
      await c.setFilters(c.filters.copyWith(status: GiveawayStatusFilter.finished));
      expect(requests.last['status'], 'finished');
      await c.submitQuery('laptop');
      expect([requests.last['q'], requests.last['status']], ['laptop', 'finished']);
      await c.setFilters(c.filters.copyWith(status: null));
      expect(requests.last['status'], 'all');
      c.dispose();
    });

    test('activeByDefault (Peta, Terdekat di Home): status bawaan tetap hanya yang aktif', () async {
      final now = DateTime.now();
      api = FakeApi((m, p, b) async => listOf([
            gw('a', title: 'Aktif'),
            gw('u', title: 'Segera', start: now.add(const Duration(hours: 2)), end: now.add(const Duration(hours: 5))),
            gw('f', title: 'Selesai', status: 'drawn'),
          ]));
      final c = make();
      await c.search();
      expect(c.items.map((g) => g.id), ['a', 'u', 'f']);
      expect(c.activeByDefault.map((g) => g.id), ['a']);
      await c.setFilters(c.filters.copyWith(status: GiveawayStatusFilter.upcoming));
      expect(c.activeByDefault.map((g) => g.id), ['a', 'u', 'f']); // status eksplisit: apa adanya
      c.dispose();
    });

    test('offline: cache mengikuti aturan status yang sama ("Semua" = semua status)', () async {
      final now = DateTime.now();
      api = FakeApi((m, p, b) async {
        if (!online) throw NetworkException('Tidak ada koneksi internet.');
        return listOf([
          gw('a', title: 'Kamera Aktif'),
          gw('u', title: 'Kamera Segera', start: now.add(const Duration(hours: 2)), end: now.add(const Duration(hours: 5))),
          gw('f', title: 'Kamera Selesai', status: 'drawn'),
        ]);
      });
      final c = make();
      await c.setFilters(c.filters.copyWith(status: GiveawayStatusFilter.finished)); // cache terisi ketiganya
      await c.setFilters(c.filters.copyWith(status: null));
      online = false;
      await c.search();
      expect(c.offline, isTrue);
      expect(c.items.map((g) => g.id), ['a', 'u', 'f']);
      await c.submitQuery('kamera');
      expect(c.items.map((g) => g.id), ['a', 'u', 'f']);
      await c.setFilters(c.filters.copyWith(status: GiveawayStatusFilter.finished));
      expect(c.items.map((g) => g.id), ['f']);
      c.dispose();
    });

    test('jawaban lama yang datang terlambat diabaikan', () async {
      final slow = Completer<Map<String, dynamic>>();
      var n = 0;
      api = FakeApi((m, p, b) {
        n++;
        return n == 1 ? slow.future : Future.value(listOf([gw('baru', title: 'Baru')]));
      });
      final c = make();
      final first = c.search();
      await c.setFilters(c.filters.copyWith(query: 'baru'));
      slow.complete(listOf([gw('lama', title: 'Lama')]));
      await first;
      expect(c.items.map((g) => g.id), ['baru']);
      c.dispose();
    });

    test('offline: menyaring cache dengan filter yang sama; online kembali -> muat ulang otomatis', () async {
      final c = make(retry: const Duration(milliseconds: 30));
      await c.search(); // online: cache terisi (a: Laptop, b: Kopi)
      online = false;
      await c.submitQuery('kopi');
      expect(c.offline, isTrue);
      expect(c.items.map((g) => g.title), ['Kopi']);
      expect(c.cachedAt, isNotNull);
      expect(c.hasMore, isFalse);
      online = true;
      await Future.delayed(const Duration(milliseconds: 150));
      expect(c.offline, isFalse);
      c.dispose();
    });

    test('offline tanpa cache -> daftar kosong + offline (bukan error); cache rusak tidak membuat crash', () async {
      final c = make();
      online = false;
      await c.search();
      expect((c.state, c.offline), (LoadState.loaded, true));
      expect(c.items, isEmpty);
      cache.failing = true;
      await c.search();
      expect((c.state, c.offline), (LoadState.loaded, true));
      c.dispose();
    });

    test('halaman berikutnya ditambahkan tanpa duplikat; berhenti bila halaman tidak penuh', () async {
      api = FakeApi((m, p, b) async {
        final off = int.parse(queryOf(p)['offset'] ?? '0');
        requests.add(queryOf(p));
        return off == 0 ? listOf([gw('1'), gw('2')]) : listOf([gw('2'), gw('3')]); // '2' dobel: harus diabaikan
      });
      final c = make(pageSize: 2);
      await c.search();
      expect(c.hasMore, isTrue);
      await c.loadMore();
      expect(c.items.map((g) => g.id), ['1', '2', '3']);
      expect(requests.last['offset'], '2');
      c.dispose();
    });

    test('posisi dikirim sebagai lat/lng dan tidak disimpan ke cache; hilang saat logout', () async {
      final c = make();
      await c.setPosition((lat: -6.2, lng: 106.8));
      await c.setFilters(c.filters.copyWith(nearbyRadiusKm: 10, sort: GiveawaySort.nearest));
      expect(requests.last['lat'], '-6.2');
      expect(requests.last['radius_km'], '10');
      expect(requests.last['sort'], 'nearest');
      await c.setPosition(null); // izin dicabut: mode terdekat mati
      expect(c.filters.nearby, isFalse);
      expect(c.filters.sort, GiveawaySort.deadline);
      await c.setPosition((lat: 1, lng: 2));
      await auth.handleInvalidSession();
      expect(c.position, isNull);
      expect(c.items, isEmpty);
      c.dispose();
    });
  });

  group('DiscoverScreen', () {
    late FakeApi api;
    late FakeAuth auth;
    late MemoryCacheStore cache;
    late DiscoverController controller;
    late FakeGateway gateway;
    late Geocoder geocoder;

    Future<void> pump(WidgetTester tester) async {
      cache = MemoryCacheStore();
      auth = FakeAuth(api);
      auth.user = AppUser(id: 'u1', username: 'a', email: 'a@x.id', fullName: 'A', role: 'user', xp: 0, level: 1);
      gateway = FakeGateway();
      geocoder = Geocoder(client: MockClient((r) async => http.Response('[]', 200)), sleep: (_) async {});
      controller = DiscoverController(AuthedApi(api, auth), auth, cache, LocationService(gateway), retryInterval: null);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
        ...displayProviders(),
          ChangeNotifierProvider<DiscoverController>.value(value: controller),
          Provider<Geocoder>.value(value: geocoder),
        ],
        child: const MaterialApp(home: DiscoverScreen()),
      ));
      await tester.pump();
    }

    testWidgets('menampilkan hasil dengan kartu yang sama seperti Home', (tester) async {
      api = FakeApi((m, p, b) async => {'ok': true, 'data': [json(giveawayJson)]});
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('Demo: Laptop Gaming Giveaway'), findsOneWidget);
      expect(find.textContaining('Rp 20.000.000'), findsOneWidget);
    });

    testWidgets('hasil kosong: pesan kosong yang informatif', (tester) async {
      api = FakeApi((m, p, b) async => {'ok': true, 'data': []});
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.textContaining('Belum ada giveaway'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('search_field')), 'zzz');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect(find.textContaining('Tidak ada giveaway yang cocok'), findsOneWidget);
    });

    testWidgets('jaringan gagal tanpa cache: daftar kosong + banner offline, bukan galat', (tester) async {
      api = FakeApi((m, p, b) async => throw NetworkException('Koneksi terlalu lama. Coba lagi.'));
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('Coba lagi'), findsNothing);
      expect(find.byType(OfflineBanner), findsOneWidget);
      expect(find.textContaining('Belum ada giveaway'), findsOneWidget);
    });

    testWidgets('galat server tak terduga tanpa cache: pesan + Coba lagi memuat ulang', (tester) async {
      var fail = true;
      api = FakeApi((m, p, b) async {
        if (fail) throw ServerFaultException('Server menolak permintaan (500).');
        return {'ok': true, 'data': [json(giveawayJson)]};
      });
      await pump(tester);
      await tester.pumpAndSettle();
      expect(find.text('Server menolak permintaan (500).'), findsOneWidget);
      fail = false;
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.text('Demo: Laptop Gaming Giveaway'), findsOneWidget);
      expect(find.text('Coba lagi'), findsNothing);
    });

    testWidgets('memuat: indikator + "Server sedang bangun" saat server lambat', (tester) async {
      final gate = Completer<Map<String, dynamic>>();
      api = FakeApi((m, p, b) => gate.future);
      await pump(tester);
      auth.setWakingUp(true);
      await tester.pump();
      expect(find.byType(SkeletonLoader), findsOneWidget);
      expect(find.text('Server sedang bangun, tunggu sebentar...'), findsOneWidget);
      gate.complete({'ok': true, 'data': []});
      await tester.pumpAndSettle();
    });

    testWidgets('debounce di layar: tidak mencari tiap ketikan, mencari ±400 ms setelah berhenti', (tester) async {
      final seen = <String?>[];
      api = FakeApi((m, p, b) async {
        seen.add(queryOf(p)['q']);
        return {'ok': true, 'data': []};
      });
      await pump(tester);
      await tester.pumpAndSettle();
      seen.clear();
      await tester.enterText(find.byKey(const Key('search_field')), 'l');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.enterText(find.byKey(const Key('search_field')), 'lap');
      await tester.pump(const Duration(milliseconds: 300));
      expect(seen, isEmpty);
      await tester.pump(const Duration(milliseconds: 150));
      await tester.pumpAndSettle();
      expect(seen, ['lap']);
    });

    testWidgets('riwayat tampil saat kolom fokus dan kosong; bisa dipakai dan dihapus', (tester) async {
      api = FakeApi((m, p, b) async => {'ok': true, 'data': []});
      await pump(tester);
      cache.searches['u1'] = ['laptop', 'kopi'];
      await controller.loadHistory();
      await tester.pumpAndSettle();
      expect(find.text('laptop'), findsNothing); // belum fokus
      await tester.tap(find.byKey(const Key('search_field')));
      await tester.pumpAndSettle();
      expect(find.text('Riwayat pencarian'), findsOneWidget);
      expect(find.text('laptop'), findsOneWidget);
      expect(find.text('kopi'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byKey(const Key('history_kopi')), matching: find.byIcon(Icons.close)));
      await tester.pumpAndSettle();
      expect(find.text('kopi'), findsNothing);
      expect(cache.searches['u1'], ['laptop']);

      await tester.tap(find.text('laptop'));
      await tester.pumpAndSettle();
      expect(controller.filters.query, 'laptop');
      expect(find.text('Riwayat pencarian'), findsNothing);
    });

    testWidgets('filter kategori dan nilai dikirim ke server; lencana jumlah filter tampil', (tester) async {
      final queries = <Map<String, String>>[];
      api = FakeApi((m, p, b) async {
        queries.add(queryOf(p));
        return {'ok': true, 'data': []};
      });
      await pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('cat_gaming')));
      await tester.enterText(find.byKey(const Key('min_value')), '1.000.000');
      await tester.enterText(find.byKey(const Key('max_value')), '500.000'); // min > max: ditolak
      await tester.tap(find.byKey(const Key('apply_filter')));
      await tester.pumpAndSettle();
      expect(find.textContaining('tidak boleh lebih besar'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('max_value')), '9000000');
      await tester.tap(find.byKey(const Key('apply_filter')));
      await tester.pumpAndSettle();
      expect([queries.last['category'], queries.last['min_value'], queries.last['max_value']], ['gaming', '1000000', '9000000']);
      expect(find.text('2'), findsOneWidget); // lencana: kategori + nilai
      expect(find.widgetWithText(InputChip, 'Gaming'), findsOneWidget);
    });

    testWidgets('layar hanya kolom cari + daftar: tanpa chip status/urutan, baris ringkas tersembunyi saat semua bawaan', (tester) async {
      api = FakeApi((m, p, b) async => {'ok': true, 'data': []});
      await pump(tester);
      await tester.pumpAndSettle();
      for (final k in ['status_chip_all', 'status_chip_active', 'nearby_chip', 'sort_menu', 'filter_summary']) {
        expect(find.byKey(Key(k)), findsNothing, reason: k);
      }
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(FilterChip), findsNothing);
      expect(find.text('Deadline terdekat'), findsNothing);
      expect(find.text('Semua'), findsNothing);
    });

    testWidgets('sheet: Status lalu Urutkan lalu filter lama; bawaan Semua + Deadline terdekat; tanpa centang; kolom >= 56 dp', (tester) async {
      api = FakeApi((m, p, b) async => {'ok': true, 'data': []});
      await pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_filter')));
      await tester.pumpAndSettle();
      double y(String t) => tester.getTopLeft(find.text(t).first).dy;
      expect(y('Status') < y('Urutkan') && y('Urutkan') < y('Kategori') && y('Kategori') < y('Deadline'), isTrue);
      ChoiceChip chip(String k) => tester.widget<ChoiceChip>(find.byKey(Key(k)));
      for (final k in ['sheet_status_all', 'sheet_status_active', 'sheet_status_upcoming', 'sheet_status_finished', 'sheet_sort_deadline', 'sheet_sort_nearest', 'sheet_sort_value', 'sheet_sort_newest']) {
        expect(chip(k).showCheckmark, isFalse, reason: k);
        expect(tester.getSize(find.byKey(Key(k))).height, greaterThanOrEqualTo(48), reason: k);
      }
      expect([chip('sheet_status_all').selected, chip('sheet_sort_deadline').selected], [true, true]);
      for (final l in ['Aktif', 'Akan datang', 'Selesai', 'Deadline terdekat', 'Terdekat', 'Nilai hadiah tertinggi', 'Terbaru']) {
        expect(find.text(l), findsOneWidget, reason: l);
      }
      await tester.scrollUntilVisible(find.byKey(const Key('min_value')), 100, scrollable: find.byType(Scrollable).last);
      expect(tester.getSize(find.byKey(const Key('min_value'))).height, greaterThanOrEqualTo(56));
      expect(tester.getSize(find.byKey(const Key('max_value'))).height, greaterThanOrEqualTo(56));
    });

    testWidgets('Terdekat nonaktif tanpa lokasi + keterangan "Butuh lokasi"; tidak bisa dipilih', (tester) async {
      api = FakeApi((m, p, b) async => {'ok': true, 'data': []});
      await pump(tester);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_filter')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('sheet_sort_nearest'))).onSelected, isNull);
      expect(find.text('Terdekat: Butuh lokasi'), findsOneWidget);
      await tester.tap(find.byKey(const Key('sheet_sort_nearest')), warnIfMissed: false);
      await tester.tap(find.byKey(const Key('apply_filter')));
      await tester.pumpAndSettle();
      expect(controller.filters.sort, GiveawaySort.deadline);
    });

    testWidgets('Terdekat aktif bila lokasi diketahui: bisa dipilih, tanpa keterangan, radius di sheet', (tester) async {
      api = FakeApi((m, p, b) async => {'ok': true, 'data': []});
      await pump(tester);
      await tester.pumpAndSettle();
      await controller.setPosition((lat: -6.2, lng: 106.8));
      await controller.setFilters(controller.filters.copyWith(nearbyRadiusKm: 10));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_filter')));
      await tester.pumpAndSettle();
      expect(tester.widget<ChoiceChip>(find.byKey(const Key('sheet_sort_nearest'))).onSelected, isNotNull);
      expect(find.text('Terdekat: Butuh lokasi'), findsNothing);
      expect(find.byKey(const Key('radius_10')), findsOneWidget);
    });

    testWidgets('status + urutan dari sheet: query, baris ringkas, lencana; hapus chip memperbarui daftar; Atur ulang', (tester) async {
      final queries = <Map<String, String>>[];
      api = FakeApi((m, p, b) async {
        queries.add(queryOf(p));
        return {'ok': true, 'data': []};
      });
      await pump(tester);
      await tester.pumpAndSettle();
      expect(queries.last['status'], 'all');
      expect(find.text('1'), findsNothing);

      await tester.tap(find.byKey(const Key('open_filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet_status_finished')));
      await tester.tap(find.byKey(const Key('sheet_sort_newest')));
      await tester.tap(find.byKey(const Key('apply_filter')));
      await tester.pumpAndSettle();
      expect([queries.last['status'], queries.last['sort']], ['finished', 'newest']);
      expect(find.byKey(const Key('filter_summary')), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Selesai'), findsOneWidget);
      expect(find.widgetWithText(InputChip, 'Urut: Terbaru'), findsOneWidget);
      expect(find.text('2'), findsOneWidget); // lencana: status + urutan
      expect(find.text('Coba kata kunci atau filter lain.\nCoba pilih status lain.'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byKey(const Key('summary_status')), matching: find.byIcon(Icons.clear)));
      await tester.pumpAndSettle();
      expect(queries.last['status'], 'all');
      expect(queries.last['sort'], 'newest');
      expect(find.byKey(const Key('summary_status')), findsNothing);
      expect(find.text('1'), findsOneWidget);

      await tester.tap(find.descendant(of: find.byKey(const Key('summary_sort')), matching: find.byIcon(Icons.clear)));
      await tester.pumpAndSettle();
      expect(queries.last['sort'], 'deadline');
      expect(find.byKey(const Key('filter_summary')), findsNothing); // semua bawaan
      expect(find.text('1'), findsNothing);

      await controller.setFilters(controller.filters.copyWith(status: GiveawayStatusFilter.active, sort: GiveawaySort.value, category: 'tech', deadlineDays: 7, minValueIdr: 1000000));
      await tester.pumpAndSettle();
      expect(find.text('Aktif'), findsOneWidget);
      expect(find.text('Urut: Nilai hadiah tertinggi'), findsOneWidget);
      expect(find.text('Tech'), findsOneWidget);
      expect(find.text('Deadline: 7 hari'), findsOneWidget);
      expect(find.textContaining('Nilai: min.'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open_filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('reset_filter')));
      await tester.pumpAndSettle();
      expect([queries.last['status'], queries.last['sort']], ['all', 'deadline']);
      expect(find.byKey(const Key('filter_summary')), findsNothing);
    });

    testWidgets('kompatibel dengan pencarian dan paginasi: status/urutan ikut di tiap halaman, pencarian lintas status', (tester) async {
      final queries = <Map<String, String>>[];
      api = FakeApi((m, p, b) async {
        queries.add(queryOf(p));
        final offset = int.tryParse(queryOf(p)['offset'] ?? '0') ?? 0;
        return listOf([for (var i = 0; i < 20; i++) gw('g${offset + i}', title: 'Kamera ${offset + i}')]);
      });
      await pump(tester);
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('search_field')), 'kamera');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      expect([queries.last['q'], queries.last['status']], ['kamera', 'all']);
      await tester.tap(find.byKey(const Key('open_filter')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('sheet_status_active')));
      await tester.tap(find.byKey(const Key('sheet_sort_value')));
      await tester.tap(find.byKey(const Key('apply_filter')));
      await tester.pumpAndSettle();
      expect([queries.last['q'], queries.last['status'], queries.last['sort']], ['kamera', 'active', 'value']);
      await tester.scrollUntilVisible(find.byKey(const Key('load_more')), 400, scrollable: find.byType(Scrollable).last);
      await tester.tap(find.byKey(const Key('load_more')));
      await tester.pumpAndSettle();
      expect([queries.last['offset'], queries.last['status'], queries.last['sort'], queries.last['q']], ['20', 'active', 'value', 'kamera']);
    });

    testWidgets('font 1,3x gelap: sheet dan baris ringkas tanpa overflow', (tester) async {
      await setViewport(tester, textScale: 1.3, brightness: Brightness.dark);
      api = FakeApi((m, p, b) async => {'ok': true, 'data': []});
      await pump(tester);
      await tester.pumpAndSettle();
      await controller.setFilters(controller.filters.copyWith(status: GiveawayStatusFilter.upcoming, sort: GiveawaySort.value, category: 'gaming', deadlineDays: 30, minValueIdr: 1000000, maxValueIdr: 99000000));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('open_filter')));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('pencarian menampilkan giveaway selesai dengan lencana status berteks', (tester) async {
      final now = DateTime.now();
      api = FakeApi((m, p, b) async {
        return listOf([
          gw('a', title: 'Kamera Aktif'),
          gw('u', title: 'Kamera Segera', start: now.add(const Duration(hours: 2)), end: now.add(const Duration(hours: 5))),
          gw('w', title: 'Kamera Tunggu', start: now.subtract(const Duration(hours: 3)), end: now.subtract(const Duration(hours: 1))),
          gw('f', title: 'Kamera Lama', status: 'drawn'),
        ]);
      });
      tester.view.physicalSize = const Size(1080, 4000);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await pump(tester);
      await tester.pumpAndSettle();
      Finder badge(String t) => find.descendant(of: find.byType(GiveawayCard), matching: find.text(t));
      // "Semua" menampilkan keempat status, urut aktif, akan datang, menunggu draw, selesai
      final order = [for (final t in ['Kamera Aktif', 'Kamera Segera', 'Kamera Tunggu', 'Kamera Lama']) tester.getTopLeft(find.text(t)).dy];
      expect(order, orderedEquals([...order]..sort()));
      expect(badge('Aktif'), findsOneWidget);
      expect(badge('Segera dimulai'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('search_field')), 'kamera');
      await tester.pump(const Duration(milliseconds: 450));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Kamera Lama'), 200, scrollable: find.byType(Scrollable).last);
      expect(find.text('Kamera Lama'), findsOneWidget);
      expect(badge('Selesai'), findsOneWidget);
      expect(badge('Menunggu draw'), findsOneWidget);
    });

    testWidgets('mode offline: banner "Data offline" dan hasil dari cache', (tester) async {
      var online = true;
      api = FakeApi((m, p, b) async {
        if (!online) throw NetworkException('Tidak ada koneksi internet.');
        return listOf([gw('a', title: 'Dari Server')]);
      });
      await pump(tester);
      await tester.pumpAndSettle();
      online = false;
      await controller.search();
      await tester.pumpAndSettle();
      expect(find.textContaining('Data offline'), findsOneWidget);
      expect(find.text('Dari Server'), findsOneWidget);
    });
  });
}
