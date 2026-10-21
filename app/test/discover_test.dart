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
            'status': 'active', 'distance_km': distance,
          },
      ],
    };

Map<String, String> queryOf(String path) => Uri.parse(path).queryParameters;

void main() {
  group('DiscoverFilters.toQuery', () {
    test('bawaan: status aktif + urutan deadline, tanpa q dan tanpa posisi', () {
      expect(const DiscoverFilters().toQuery(), {'status': 'active', 'sort': 'deadline', 'limit': '20'});
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
    final all = [a, b, c, upcoming, finished];
    List<String> ids(DiscoverFilters f, {double? lat, double? lng}) =>
        f.applyLocal(all, lat: lat, lng: lng, now: now).map((g) => g.id).toList();

    test('bawaan: hanya aktif, urut deadline', () => expect(ids(const DiscoverFilters()), ['c', 'a', 'b']));
    test('kata kunci di judul, hadiah, atau penyelenggara (tak peka huruf besar)', () {
      expect(ids(const DiscoverFilters(query: 'LAPTOP')), ['a']);
      expect(ids(const DiscoverFilters(query: 'biro')), ['b']);
      expect(ids(const DiscoverFilters(query: 'liburan')), ['b']);
      expect(ids(const DiscoverFilters(query: 'tidak ada')), isEmpty);
    });
    test('kategori dan rentang nilai', () {
      expect(ids(const DiscoverFilters(category: 'travel')), ['b']);
      expect(ids(const DiscoverFilters(minValueIdr: 10000000)), ['b']);
      expect(ids(const DiscoverFilters(maxValueIdr: 5000000)), ['c', 'a']);
    });
    test('deadline dalam N hari', () => expect(ids(const DiscoverFilters(deadlineDays: 1)), ['c', 'a']));
    test('status akan datang dan selesai', () {
      expect(ids(const DiscoverFilters(status: GiveawayStatusFilter.upcoming)), ['u']);
      expect(ids(const DiscoverFilters(status: GiveawayStatusFilter.finished)), ['f']);
    });
    test('urutan nilai dan terbaru', () {
      expect(ids(const DiscoverFilters(sort: GiveawaySort.value)), ['b', 'c', 'a']);
    });
    test('terdekat: jarak dihitung lokal, tanpa koordinat di akhir, radius menyaring', () {
      const near = DiscoverFilters(sort: GiveawaySort.nearest);
      expect(ids(near, lat: -6.2, lng: 106.8), ['a', 'b', 'c']);
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
