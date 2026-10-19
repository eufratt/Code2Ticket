import 'dart:convert';
import 'dart:io';

import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/location/location_service.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/auth/auth_models.dart';
import 'package:code2ticket/features/discover/discover_controller.dart';
import 'package:code2ticket/features/discover/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'cache_test.dart' show gw;
import 'discover_test.dart' show listOf;
import 'input_code_test.dart' show FakeApi, FakeAuth;
import 'support/fake_location.dart';
import 'support/display.dart';
import 'support/memory_cache.dart';

/// Tile palsu: peta tidak menyentuh jaringan di tes.
class _NoTiles extends TileProvider {
  static final _png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => MemoryImage(_png);
}

void main() {
  late DiscoverController controller;
  late FakeAuth auth;

  Future<void> pump(WidgetTester tester, List<dynamic> giveaways) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final api = FakeApi((m, p, b) async => listOf(giveaways.cast()));
    auth = FakeAuth(api);
    auth.user = AppUser(id: 'u1', username: 'a', email: 'a@x.id', fullName: 'A', role: 'user', xp: 0, level: 1);
    controller = DiscoverController(AuthedApi(api, auth), auth, MemoryCacheStore(), LocationService(FakeGateway()),
        retryInterval: null);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => MapScreen(tileProvider: _NoTiles())),
      GoRoute(path: '/giveaway/:id', builder: (_, s) => Scaffold(body: Text('DETAIL ${s.pathParameters['id']}'))),
    ]);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ...displayProviders(),
        ChangeNotifierProvider<DiscoverController>.value(value: controller),
      ],
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('penanda hanya untuk giveaway berkoordinat; ringkasan menyebut yang tanpa lokasi', (tester) async {
    await pump(tester, [
      gw('a', title: 'Jakarta', lat: -6.2, lng: 106.8),
      gw('b', title: 'Bandung', lat: -6.9, lng: 107.6),
      gw('c', title: 'Online'),
    ]);
    expect(find.byKey(const Key('marker_a')), findsOneWidget);
    expect(find.byKey(const Key('marker_b')), findsOneWidget);
    expect(find.byKey(const Key('marker_c')), findsNothing);
    expect(find.text('2 giveaway di peta (1 tanpa lokasi)'), findsOneWidget);
  });

  testWidgets('atribusi "© OpenStreetMap contributors" terlihat; tile memakai OSM + userAgentPackageName', (tester) async {
    await pump(tester, [gw('a', title: 'Jakarta', lat: -6.2, lng: 106.8)]);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
    final layer = tester.widget<TileLayer>(find.byType(TileLayer));
    expect(layer.urlTemplate, 'https://tile.openstreetmap.org/{z}/{x}/{y}.png');
    expect(layer.tileProvider.headers['User-Agent'], 'flutter_map ($osmUserAgentPackage)');
  });

  test('userAgentPackageName sama dengan applicationId Android', () {
    final gradle = File('android/app/build.gradle.kts').existsSync()
        ? File('android/app/build.gradle.kts').readAsStringSync()
        : File('android/app/build.gradle').readAsStringSync();
    expect(gradle, contains('"$osmUserAgentPackage"'));
  });

  testWidgets('ketuk penanda -> kartu ringkas -> Lihat detail membuka Detail; ketuk peta menutup kartu', (tester) async {
    await pump(tester, [
      gw('a', title: 'Jakarta', lat: -6.2, lng: 106.8),
      gw('b', title: 'Bandung', lat: -6.9, lng: 107.6),
    ]);
    expect(find.byKey(const Key('selected_card')), findsNothing);
    await tester.tap(find.byKey(const Key('marker_b')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected_card')), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('selected_card')), matching: find.text('Bandung')), findsOneWidget);

    await tester.tapAt(const Offset(20, 300)); // area peta kosong (tepi kiri, jauh dari penanda dan tombol)
    await tester.pump(const Duration(milliseconds: 400)); // flutter_map menunggu kemungkinan double-tap
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('selected_card')), findsNothing);

    await tester.tap(find.byKey(const Key('marker_a')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('open_detail')));
    await tester.pumpAndSettle();
    expect(find.text('DETAIL a'), findsOneWidget);
  });

  testWidgets('posisi pengguna (bila ada) tampil sebagai titik di peta', (tester) async {
    await pump(tester, [gw('a', title: 'Jakarta', lat: -6.2, lng: 106.8)]);
    expect(find.byKey(const Key('my_position')), findsNothing);
    await controller.setPosition((lat: -6.21, lng: 106.81));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('my_position')), findsOneWidget);
  });

  testWidgets('tanpa hasil: peta tetap tampil dengan pesan, tanpa crash', (tester) async {
    await pump(tester, []);
    expect(find.text('Tidak ada giveaway untuk filter ini'), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
  });
}
