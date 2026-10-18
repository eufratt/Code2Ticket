import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/geocoding/geocoder.dart';
import 'package:code2ticket/core/location/location_service.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/auth/auth_models.dart';
import 'package:code2ticket/features/discover/discover_controller.dart';
import 'package:code2ticket/features/discover/discover_filters.dart';
import 'package:code2ticket/features/discover/discover_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'cache_test.dart' show gw;
import 'discover_test.dart' show listOf, queryOf;
import 'input_code_test.dart' show FakeApi, FakeAuth;
import 'support/fake_location.dart';
import 'support/memory_cache.dart';

void main() {
  late FakeApi api;
  late FakeAuth auth;
  late FakeGateway gateway;
  late DiscoverController c;
  final requests = <Map<String, String>>[];

  void setUpController() {
    requests.clear();
    api = FakeApi((m, p, b) async {
      requests.add(queryOf(p));
      return listOf([gw('a', title: 'Dekat', lat: -6.2, lng: 106.8)], distance: 2.34);
    });
    auth = FakeAuth(api);
    auth.user = AppUser(id: 'u1', username: 'a', email: 'a@x.id', fullName: 'A', role: 'user', xp: 0, level: 1);
    c = DiscoverController(AuthedApi(api, auth), auth, MemoryCacheStore(), LocationService(gateway), retryInterval: null);
  }

  group('DiscoverController: Terdekat (LBS)', () {
    setUp(() {
      gateway = FakeGateway(); // izin belum diminta
      setUpController();
    });

    test('izin diberikan: posisi + radius 10 km + urutan terdekat dikirim ke server', () async {
      await c.enableNearby();
      expect(c.locationProblem, isNull);
      expect(c.filters.nearbyRadiusKm, 10);
      expect(c.filters.sort, GiveawaySort.nearest);
      final q = requests.last;
      expect([q['lat'], q['lng'], q['radius_km'], q['sort']], ['-6.2', '106.8', '10', 'nearest']);
      expect(c.items.single.distanceKm, 2.34);
      expect(gateway.requests, 1);
    });

    test('radius 5/10/25 mengubah parameter radius_km', () async {
      await c.enableNearby();
      for (final km in [5, 25, 10]) {
        await c.setNearbyRadius(km);
        expect(requests.last['radius_km'], '$km');
      }
    });

    test('izin ditolak: mode tetap mati, tidak ada permintaan berposisi, alasan tersedia', () async {
      gateway.afterRequest = GatewayPermission.denied;
      await c.enableNearby();
      expect(c.locationProblem, LocationStatus.denied);
      expect(c.filters.nearby, isFalse);
      expect(c.position, isNull);
      expect(requests, isEmpty);
      expect(c.locating, isFalse);
    });

    test('ditolak permanen -> buka pengaturan aplikasi; layanan mati -> buka pengaturan lokasi', () async {
      gateway.permission = GatewayPermission.deniedForever;
      await c.enableNearby();
      expect(c.locationProblem, LocationStatus.deniedForever);
      expect(await c.openLocationSettings(), isTrue);
      expect(gateway.appSettingsOpened, 1);

      gateway.service = false;
      await c.enableNearby();
      expect(c.locationProblem, LocationStatus.serviceOff);
      await c.openLocationSettings();
      expect(gateway.locationSettingsOpened, 1);
    });

    test('setelah izin diberikan lewat pengaturan, mencoba lagi berhasil dan masalah hilang', () async {
      gateway.permission = GatewayPermission.deniedForever;
      await c.enableNearby();
      expect(c.locationProblem, isNotNull);
      gateway.permission = GatewayPermission.granted;
      await c.enableNearby();
      expect(c.locationProblem, isNull);
      expect(c.filters.nearby, isTrue);
    });

    test('lokasi manual (Nominatim): posisi dari tempat terpilih, label tersedia, bisa dimatikan', () async {
      gateway.permission = GatewayPermission.deniedForever;
      await c.enableNearby();
      await c.useManualPlace(const Place(name: 'Bandung, Jawa Barat', lat: -6.9175, lng: 107.6191));
      expect(c.locationProblem, isNull);
      expect(c.manualLabel, 'Bandung, Jawa Barat');
      expect([requests.last['lat'], requests.last['lng']], ['-6.9175', '107.6191']);
      expect(requests.last['sort'], 'nearest');
      await c.disableNearby();
      expect(c.manualLabel, isNull);
      expect(c.position, isNull);
      expect(requests.last.containsKey('lat'), isFalse);
      expect(c.filters.sort, GiveawaySort.deadline);
    });

    test('posisi tidak disimpan: hilang saat logout', () async {
      gateway.permission = GatewayPermission.granted;
      await c.enableNearby();
      await auth.handleInvalidSession();
      expect(c.position, isNull);
      expect(c.filters.nearby, isFalse);
    });
  });

  group('Discover: widget Terdekat', () {
    Future<void> pump(WidgetTester tester, {http.Client? geoClient}) async {
      setUpController();
      final geocoder = Geocoder(client: geoClient ?? MockClient((r) async => http.Response('[]', 200)), sleep: (_) async {});
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ChangeNotifierProvider<DiscoverController>.value(value: c),
          Provider<Geocoder>.value(value: geocoder),
        ],
        child: const MaterialApp(home: DiscoverScreen()),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('izin ditolak: pesan jelas + opsi mengizinkan / cari tempat', (tester) async {
      gateway = FakeGateway(afterRequest: GatewayPermission.denied);
      await pump(tester);
      await tester.tap(find.byKey(const Key('nearby_chip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('location_banner')), findsOneWidget);
      expect(find.textContaining('Izin lokasi ditolak'), findsOneWidget);
      expect(find.text('Izinkan lokasi'), findsOneWidget);
      expect(find.text('Cari tempat'), findsOneWidget);
      expect(find.byKey(const Key('radius_10')), findsNothing); // mode Terdekat belum aktif
    });

    testWidgets('ditolak permanen: tombol membuka pengaturan aplikasi', (tester) async {
      gateway = FakeGateway(permission: GatewayPermission.deniedForever);
      await pump(tester);
      await tester.tap(find.byKey(const Key('nearby_chip')));
      await tester.pumpAndSettle();
      expect(find.textContaining('ditolak permanen'), findsOneWidget);
      await tester.tap(find.text('Buka pengaturan'));
      await tester.pumpAndSettle();
      expect(gateway.appSettingsOpened, 1);
    });

    testWidgets('layanan lokasi mati: pesan + tombol pengaturan lokasi', (tester) async {
      gateway = FakeGateway(service: false);
      await pump(tester);
      await tester.tap(find.byKey(const Key('nearby_chip')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Layanan lokasi di perangkat mati'), findsOneWidget);
      await tester.tap(find.text('Buka pengaturan lokasi'));
      await tester.pumpAndSettle();
      expect(gateway.locationSettingsOpened, 1);
    });

    testWidgets('izin diberikan: jarak tampil di kartu, radius bisa diganti, bisa dimatikan', (tester) async {
      gateway = FakeGateway(permission: GatewayPermission.granted);
      await pump(tester);
      await tester.tap(find.byKey(const Key('nearby_chip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('location_banner')), findsNothing);
      expect(find.text('2,3 km'), findsOneWidget);
      expect(find.byKey(const Key('radius_5')), findsOneWidget);
      await tester.tap(find.byKey(const Key('radius_25')));
      await tester.pumpAndSettle();
      expect(requests.last['radius_km'], '25');
      await tester.tap(find.byKey(const Key('nearby_chip')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('radius_5')), findsNothing);
      expect(requests.last.containsKey('lat'), isFalse);
    });

    testWidgets('lokasi manual: cari tempat -> pilih hasil -> Terdekat aktif dari tempat itu', (tester) async {
      gateway = FakeGateway(afterRequest: GatewayPermission.denied);
      final geo = MockClient((r) async => http.Response(
          '[{"lat":"-6.9175","lon":"107.6191","display_name":"Bandung, Jawa Barat, Indonesia"}]', 200));
      await pump(tester, geoClient: geo);
      await tester.tap(find.byKey(const Key('nearby_chip')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('manual_location')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('place_field')), 'ba'); // terlalu pendek
      await tester.tap(find.byKey(const Key('place_search')));
      await tester.pumpAndSettle();
      expect(find.textContaining('minimal 3 huruf'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('place_field')), 'Bandung');
      await tester.tap(find.byKey(const Key('place_search')));
      await tester.pumpAndSettle();
      expect(find.textContaining('© OpenStreetMap contributors'), findsOneWidget);
      await tester.tap(find.text('Bandung, Jawa Barat, Indonesia'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('manual_chip')), findsOneWidget);
      expect(find.byKey(const Key('location_banner')), findsNothing);
      expect([requests.last['lat'], requests.last['lng']], ['-6.9175', '107.6191']);
    });
  });
}
