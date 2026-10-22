import 'dart:convert';

import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/location/location_service.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/auth/auth_models.dart';
import 'package:code2ticket/features/discover/discover_controller.dart';
import 'package:code2ticket/features/discover/map_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'cache_test.dart' show gw;
import 'discover_test.dart' show listOf;
import 'input_code_test.dart' show FakeApi, FakeAuth;
import 'support/display.dart';
import 'support/fake_location.dart';
import 'support/memory_cache.dart';

class _NoTiles extends TileProvider {
  static final _png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) => MemoryImage(_png);
}

// Izin lokasi diminta saat layar Peta dibuka (sekali), dengan banner untuk tiap penolakan.
void main() {
  Future<(FakeGateway, DiscoverController)> pump(WidgetTester tester, FakeGateway g, {Brightness b = Brightness.dark}) async {
    tester.view.physicalSize = const Size(400 * 3, 800 * 3);
    tester.view.devicePixelRatio = 3;
    tester.platformDispatcher.platformBrightnessTestValue = b;
    addTearDown(() {
      tester.view.reset();
      tester.platformDispatcher.clearAllTestValues();
    });
    final api = FakeApi((m, p, bd) async => listOf([gw('a', title: 'Jakarta', lat: -6.2, lng: 106.8)]));
    final auth = FakeAuth(api)..user = AppUser(id: 'u1', username: 'a', email: 'a@x.id', fullName: 'A', role: 'user', xp: 0, level: 1);
    final service = LocationService(g);
    final c = DiscoverController(AuthedApi(api, auth), auth, MemoryCacheStore(), service, retryInterval: null);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        Provider<LocationService>.value(value: service),
        ...displayProviders(),
        ChangeNotifierProvider<DiscoverController>.value(value: c),
      ],
      child: MaterialApp(home: MapScreen(tileProvider: _NoTiles())),
    ));
    await tester.pumpAndSettle();
    return (g, c);
  }

  Future<void> resume(WidgetTester tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
  }

  const banner = Key('map_location_banner');
  const action = Key('map_location_action');

  testWidgets('izin belum ada: diminta sekali, diizinkan -> posisi tampil, tanpa banner', (tester) async {
    final (g, c) = await pump(tester, FakeGateway());
    expect(g.requests, 1);
    expect(find.byKey(const Key('my_position')), findsOneWidget);
    expect(find.byKey(banner), findsNothing);
    expect(c.position, isNull); // mode Terdekat Discover tidak disentuh
  });

  testWidgets('rebuild dan resume tidak meminta ulang', (tester) async {
    final (g, _) = await pump(tester, FakeGateway());
    await resume(tester);
    await tester.tap(find.byKey(const Key('map_summary')), warnIfMissed: false);
    await tester.pumpAndSettle();
    await resume(tester);
    expect(g.requests, 1);
  });

  testWidgets('ditolak: peta tetap tampil, banner "Izinkan lokasi" meminta lagi', (tester) async {
    final g = FakeGateway(afterRequest: GatewayPermission.denied);
    await pump(tester, g);
    expect(g.requests, 1);
    expect(find.byKey(banner), findsOneWidget);
    expect(find.byKey(const Key('marker_a')), findsOneWidget);
    expect(find.text('Izinkan lokasi'), findsOneWidget);
    expect(tester.getSize(find.byKey(action)).height, greaterThanOrEqualTo(48));
    g.afterRequest = GatewayPermission.granted;
    await tester.tap(find.byKey(action));
    await tester.pumpAndSettle();
    expect(g.requests, 2);
    expect(find.byKey(banner), findsNothing);
    expect(find.byKey(const Key('my_position')), findsOneWidget);
  });

  testWidgets('ditolak permanen: "Buka pengaturan" membuka pengaturan aplikasi; resume setelah diizinkan menghapus banner tanpa dialog', (tester) async {
    final g = FakeGateway(permission: GatewayPermission.deniedForever);
    await pump(tester, g);
    expect(find.text('Buka pengaturan'), findsOneWidget);
    await tester.tap(find.byKey(action));
    await tester.pumpAndSettle();
    expect(g.appSettingsOpened, 1);
    expect(g.requests, 0);
    g.permission = GatewayPermission.granted;
    await resume(tester);
    expect(find.byKey(banner), findsNothing);
    expect(find.byKey(const Key('my_position')), findsOneWidget);
    expect(g.requests, 0);
  });

  testWidgets('GPS mati: banner aktifkan lokasi, tanpa dialog izin; resume setelah GPS hidup memperbarui', (tester) async {
    final g = FakeGateway(service: false);
    await pump(tester, g);
    expect(g.requests, 0);
    expect(find.text(locationStatusMessage(LocationStatus.serviceOff)), findsOneWidget);
    await tester.tap(find.byKey(action));
    await tester.pumpAndSettle();
    expect(g.locationSettingsOpened, 1);
    expect(g.requests, 0);
    await resume(tester); // masih mati: banner tetap, tetap tanpa dialog
    expect(find.byKey(banner), findsOneWidget);
    g.service = true;
    g.permission = GatewayPermission.granted;
    await resume(tester);
    expect(find.byKey(banner), findsNothing);
    expect(g.requests, 0);
  });

  testWidgets('resume tanpa masalah lokasi tidak memanggil layanan lagi', (tester) async {
    final (g, _) = await pump(tester, FakeGateway(), b: Brightness.light);
    final before = g.positions;
    await resume(tester);
    expect(g.positions, before);
  });

  test('locate(prompt: false) (jalur Input Code) tidak memunculkan dialog izin', () async {
    final g = FakeGateway();
    final fix = await LocationService(g).locate(prompt: false);
    expect(fix.status, LocationStatus.denied);
    expect(g.requests, 0);
  });
}
