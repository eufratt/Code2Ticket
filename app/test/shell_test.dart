import 'package:code2ticket/app_router.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/location/location_service.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/discover/discover_controller.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart';
import 'package:code2ticket/features/tickets/tickets_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'input_code_test.dart' show FakeApi, FakeAuth, json;
import 'support/fake_location.dart';
import 'support/display.dart';
import 'support/memory_cache.dart';
import 'models_test.dart' show giveawayJson, ticketJson;

class _Auth extends FakeAuth {
  _Auth(super.api);
  @override
  Future<bool> isBiometricAvailable() async => false;
  @override
  Future<bool> isBiometricEnabled({String? userId}) async => false;
}

Widget _createTestApp({required _Auth auth, required AuthedApi authed}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthController>.value(value: auth),
        ...displayProviders(),
      Provider<AuthedApi>.value(value: authed),
      ChangeNotifierProvider(create: (_) => GiveawaysController(authed, auth, MemoryCacheStore(), retryInterval: null)),
      ChangeNotifierProvider(create: (_) => TicketsController(authed, auth, MemoryCacheStore(), retryInterval: null)),
      ChangeNotifierProvider(create: (_) => DiscoverController(authed, auth, MemoryCacheStore(), LocationService(FakeGateway()), retryInterval: null)),
    ],
    child: MaterialApp.router(routerConfig: buildRouter(auth)),
  );
}

void main() {
  testWidgets('5 tab sama lebar + FAB melayang di lebar 360 dp: navigasi, FAB, tanpa overflow', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final api = FakeApi((m, p, b) async => p.startsWith('/giveaways/')
        ? json(giveawayJson) // GET /giveaways/:id
        : p.startsWith('/giveaways')
        ? {'ok': true, 'data': [json(giveawayJson)]}
        : {'ok': true, 'data': [json(ticketJson)]});
    final auth = _Auth(api);
    final authed = AuthedApi(api, auth);
    await tester.pumpWidget(_createTestApp(auth: auth, authed: authed));
    await tester.pumpAndSettle();

    // Home memuat giveaway aktif.
    expect(find.text('Demo: Laptop Gaming Giveaway'), findsOneWidget);
    final tabs = ['Home', 'Discover', 'My Tickets', 'Asisten', 'Profil'];
    for (final label in tabs) {
      expect(find.text(label), findsOneWidget, reason: label);
      final item = find.widgetWithText(InkWell, label);
      expect(tester.getSize(item).width, closeTo(360 / 5, 0.1), reason: '$label harus sama lebar (72 dp)');
    }

    final fabFinder = find.byTooltip('Input Code');
    expect(fabFinder, findsOneWidget);

    final fabCenter = tester.getCenter(fabFinder);
    expect(fabCenter.dx, closeTo(360 / 2, 1.0), reason: 'FAB harus di tengah horizontal');
    final fabBottom = tester.getBottomRight(fabFinder).dy;
    final barTop = tester.getTopLeft(find.byType(BottomAppBar)).dy;
    final gap = barTop - fabBottom;
    expect(gap, inInclusiveRange(8.0, 12.0), reason: 'FAB harus melayang 8-12 dp di atas bar');

    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('search_field')), findsOneWidget);

    await tester.tap(find.text('My Tickets'));
    await tester.pumpAndSettle();
    expect(find.text('#000001'), findsOneWidget);

    await tester.tap(find.text('Asisten'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Segera hadir'), findsOneWidget);

    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Keluar'), 200, scrollable: find.byType(Scrollable).last);
    expect(find.text('Keluar'), findsOneWidget);
    expect(find.text('Pengaturan'), findsOneWidget);
    expect(find.text('Saran & Kesan'), findsOneWidget);
    expect(find.text('Konverter'), findsOneWidget);

    await tester.tap(fabFinder);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('code_field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('5 tab sama lebar + FAB melayang di lebar 428 dp: navigasi, FAB, tanpa overflow', (tester) async {
    tester.view.physicalSize = const Size(428 * 3, 926 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final api = FakeApi((m, p, b) async => p.startsWith('/giveaways/')
        ? json(giveawayJson) // GET /giveaways/:id
        : p.startsWith('/giveaways')
        ? {'ok': true, 'data': [json(giveawayJson)]}
        : {'ok': true, 'data': [json(ticketJson)]});
    final auth = _Auth(api);
    final authed = AuthedApi(api, auth);

    await tester.pumpWidget(_createTestApp(auth: auth, authed: authed));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    final tabs = ['Home', 'Discover', 'My Tickets', 'Asisten', 'Profil'];
    for (final label in tabs) {
      expect(find.text(label), findsOneWidget, reason: label);
      final item = find.widgetWithText(InkWell, label);
      expect(tester.getSize(item).width, closeTo(428 / 5, 0.1), reason: '$label harus sama lebar (85.6 dp)');
    }

    final fabFinder = find.byTooltip('Input Code');
    expect(fabFinder, findsOneWidget);

    final fabCenter = tester.getCenter(fabFinder);
    expect(fabCenter.dx, closeTo(428 / 2, 1.0));
    final fabBottom = tester.getBottomRight(fabFinder).dy;
    final barTop = tester.getTopLeft(find.byType(BottomAppBar)).dy;
    final gap = barTop - fabBottom;
    expect(gap, inInclusiveRange(8.0, 12.0));

    await tester.tap(find.text('My Tickets'));
    await tester.pumpAndSettle();
    expect(find.text('#000001'), findsOneWidget);

    await tester.tap(fabFinder);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('code_field')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home -> Detail Giveaway: info, jadwal WIB, tiket saya, aktivitas dicatat', (tester) async {
    final api = FakeApi((m, p, b) async => p.startsWith('/giveaways/')
        ? json(giveawayJson) // GET /giveaways/:id
        : p.startsWith('/giveaways')
        ? {'ok': true, 'data': [json(giveawayJson)]}
        : p == '/activity'
            ? throw Exception('gagal catat') // tidak boleh mengganggu layar
            : {'ok': true, 'data': [json(ticketJson)]});
    final auth = _Auth(api);
    final authed = AuthedApi(api, auth);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ...displayProviders(),
        Provider<AuthedApi>.value(value: authed),
        ChangeNotifierProvider(create: (_) => GiveawaysController(authed, auth, MemoryCacheStore(), retryInterval: null)),
        ChangeNotifierProvider(create: (_) => TicketsController(authed, auth, MemoryCacheStore(), retryInterval: null)),
      ],
      child: MaterialApp.router(routerConfig: buildRouter(auth)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Demo: Laptop Gaming Giveaway'));
    await tester.pumpAndSettle();
    expect(find.text('Detail Giveaway'), findsOneWidget);
    expect(find.text('19 Okt 2026, 03.29 WIB'), findsWidgets); // draw 20:29Z: baris Draw + daftar 4 zona
    expect(find.byKey(const Key('zone_london')), findsOneWidget);
    expect(find.text('US\$1.200,00'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Tiket saya'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Tiket saya'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    final activity = api.calls.where((c) => c.path == '/activity').single;
    expect(activity.body, {
      'type': 'view_giveaway',
      'giveaway_id': '5deb977d-ff30-4e4e-849d-ff389fe51e6a',
      'category': 'gaming',
    });
    expect(tester.takeException(), isNull);
  });
}
