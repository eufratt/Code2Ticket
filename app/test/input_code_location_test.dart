import 'dart:async';

import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/location/location_service.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/tickets/input_code_screen.dart';
import 'package:code2ticket/features/tickets/tickets_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'input_code_test.dart' show FakeApi, FakeAuth, json;
import 'models_test.dart' show redeemOk;
import 'support/fake_location.dart';
import 'support/memory_cache.dart';

void main() {
  late FakeApi api;
  late FakeGateway gateway;

  Future<void> pump(WidgetTester tester, Future<Map<String, dynamic>> Function(String m, String p, dynamic b) h) async {
    api = FakeApi(h);
    final auth = FakeAuth(api);
    final authed = AuthedApi(api, auth);
    final tickets = TicketsController(authed, auth, MemoryCacheStore(), retryInterval: null);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        Provider<AuthedApi>.value(value: authed),
        ChangeNotifierProvider<TicketsController>.value(value: tickets),
        Provider<LocationService>.value(value: LocationService(gateway)),
      ],
      child: const MaterialApp(home: InputCodeScreen()),
    ));
  }

  Future<void> submit(WidgetTester tester) async {
    await tester.enterText(find.byKey(const Key('code_field')), 'AAAA-BBBB-CCCC');
    await tester.tap(find.byKey(const Key('submit_code')));
    await tester.pump();
  }

  Map<String, dynamic>? redeemBody() => api.calls.where((c) => c.path == '/codes/redeem').firstOrNull?.body as Map<String, dynamic>?;

  testWidgets('izin sudah diberikan: lat/lng dikirim tanpa memunculkan dialog izin', (tester) async {
    gateway = FakeGateway(permission: GatewayPermission.granted, lat: -6.205, lng: 106.82);
    await pump(tester, (m, p, b) async => p == '/codes/redeem' ? json(redeemOk) : {'ok': true, 'data': []});
    await submit(tester);
    await tester.pumpAndSettle();
    expect(redeemBody(), {'code': 'AAAA-BBBB-CCCC', 'lat': -6.205, 'lng': 106.82});
    expect(gateway.requests, 0);
    expect(find.byKey(const Key('ticket_number')), findsOneWidget);
  });

  testWidgets('izin belum diberikan: lokasi TIDAK dikirim dan dialog izin TIDAK dimunculkan', (tester) async {
    gateway = FakeGateway(permission: GatewayPermission.denied);
    await pump(tester, (m, p, b) async => p == '/codes/redeem' ? json(redeemOk) : {'ok': true, 'data': []});
    await submit(tester);
    await tester.pumpAndSettle();
    expect(redeemBody(), {'code': 'AAAA-BBBB-CCCC', 'lat': null, 'lng': null});
    expect(gateway.requests, 0);
    expect(gateway.positions, 0);
  });

  testWidgets('layanan lokasi mati atau GPS gagal: kode tetap dikirim tanpa lokasi', (tester) async {
    gateway = FakeGateway(service: false, permission: GatewayPermission.granted);
    await pump(tester, (m, p, b) async => p == '/codes/redeem' ? json(redeemOk) : {'ok': true, 'data': []});
    await submit(tester);
    await tester.pumpAndSettle();
    expect(redeemBody(), {'code': 'AAAA-BBBB-CCCC', 'lat': null, 'lng': null});
  });

  testWidgets('location_required: pesan dengan petunjuk + tombol Aktifkan lokasi; izin diberikan -> petunjuk coba lagi', (tester) async {
    gateway = FakeGateway(permission: GatewayPermission.denied, afterRequest: GatewayPermission.granted);
    await pump(tester, (m, p, b) async => {'ok': false, 'error': 'location_required'});
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('butuh lokasimu'), findsOneWidget);
    expect(find.textContaining('Aktifkan layanan lokasi'), findsOneWidget);
    await tester.tap(find.byKey(const Key('enable_location')));
    await tester.pumpAndSettle();
    expect(gateway.requests, 1); // dialog izin hanya muncul karena pengguna menekan tombol
    expect(find.text('Lokasi aktif. Tekan "Tukar kode" untuk mencoba lagi.'), findsOneWidget);
  });

  testWidgets('out_of_area: pesan di luar area + tombol aktifkan lokasi', (tester) async {
    gateway = FakeGateway(permission: GatewayPermission.granted);
    await pump(tester, (m, p, b) async => {'ok': false, 'error': 'out_of_area'});
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('di luar area kode ini'), findsOneWidget);
    expect(find.textContaining('lokasi aktif dan akurat'), findsOneWidget);
    expect(find.byKey(const Key('enable_location')), findsOneWidget);
    expect(redeemBody()!['lat'], isNotNull); // lokasi ikut terkirim karena izin ada
  });

  testWidgets('izin ditolak permanen: tombol membuka pengaturan aplikasi dan menjelaskan', (tester) async {
    gateway = FakeGateway(permission: GatewayPermission.deniedForever);
    await pump(tester, (m, p, b) async => {'ok': false, 'error': 'location_required'});
    await submit(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('enable_location')));
    await tester.pumpAndSettle();
    expect(gateway.appSettingsOpened, 1);
    expect(find.textContaining('ditolak permanen'), findsOneWidget);
  });

  testWidgets('kode biasa (bukan berbatas area) tidak menampilkan tombol lokasi', (tester) async {
    gateway = FakeGateway();
    await pump(tester, (m, p, b) async => {'ok': false, 'error': 'code_used'});
    await submit(tester);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('enable_location')), findsNothing);
  });

  testWidgets('tombol ditekan berulang saat menunggu GPS: hanya satu permintaan', (tester) async {
    final gps = Completer<void>();
    gateway = FakeGateway(permission: GatewayPermission.granted)..positionGate = gps.future;
    await pump(tester, (m, p, b) async => p == '/codes/redeem' ? json(redeemOk) : {'ok': true, 'data': []});
    await submit(tester);
    expect(tester.widget<FilledButton>(find.byKey(const Key('submit_code'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('submit_code')), warnIfMissed: false);
    await tester.pump();
    gps.complete();
    await tester.pumpAndSettle();
    expect(api.calls.where((c) => c.path == '/codes/redeem'), hasLength(1));
  });

  testWidgets('catatan privasi lokasi tampil', (tester) async {
    gateway = FakeGateway();
    await pump(tester, (m, p, b) async => {'ok': true, 'data': []});
    expect(find.textContaining('tidak disimpan'), findsOneWidget);
  });
}
