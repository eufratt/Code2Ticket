import 'package:code2ticket/app_router.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart';
import 'package:code2ticket/features/tickets/tickets_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'input_code_test.dart' show FakeApi, FakeAuth, json;
import 'models_test.dart' show giveawayJson, ticketJson;

class _Auth extends FakeAuth {
  _Auth(super.api);
  @override
  Future<bool> isBiometricAvailable() async => false;
  @override
  Future<bool> isBiometricEnabled({String? userId}) async => false;
}

void main() {
  testWidgets('5 tab + FAB: navigasi antar tab, FAB membuka Input Code, tanpa overflow', (tester) async {
    tester.view.physicalSize = const Size(360 * 3, 640 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    final api = FakeApi((m, p, b) async => p.startsWith('/giveaways')
        ? {'ok': true, 'data': [json(giveawayJson)]}
        : {'ok': true, 'data': [json(ticketJson)]});
    final auth = _Auth(api);
    final authed = AuthedApi(api, auth);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        Provider<AuthedApi>.value(value: authed),
        ChangeNotifierProvider(create: (_) => GiveawaysController(authed, auth)),
        ChangeNotifierProvider(create: (_) => TicketsController(authed, auth)),
      ],
      child: MaterialApp.router(routerConfig: buildRouter(auth)),
    ));
    await tester.pumpAndSettle();

    // Home memuat giveaway aktif.
    expect(find.text('Demo: Laptop Gaming Giveaway'), findsOneWidget);
    for (final label in ['Home', 'Discover', 'My Tickets', 'Asisten', 'Profil']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.byTooltip('Input Code'), findsOneWidget);

    await tester.tap(find.text('Discover'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Segera hadir'), findsOneWidget);

    await tester.tap(find.text('My Tickets'));
    await tester.pumpAndSettle();
    expect(find.text('#000001'), findsOneWidget);

    await tester.tap(find.text('Asisten'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Segera hadir'), findsOneWidget);

    await tester.tap(find.text('Profil'));
    await tester.pumpAndSettle();
    expect(find.text('Keluar'), findsOneWidget);
    expect(find.text('Kunci biometric'), findsOneWidget);

    await tester.tap(find.byTooltip('Input Code'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('code_field')), findsOneWidget);
  });

  testWidgets('Home -> Detail Giveaway: info, jadwal WIB, tiket saya, aktivitas dicatat', (tester) async {
    final api = FakeApi((m, p, b) async => p.startsWith('/giveaways')
        ? {'ok': true, 'data': [json(giveawayJson)]}
        : p == '/activity'
            ? throw Exception('gagal catat') // tidak boleh mengganggu layar
            : {'ok': true, 'data': [json(ticketJson)]});
    final auth = _Auth(api);
    final authed = AuthedApi(api, auth);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        Provider<AuthedApi>.value(value: authed),
        ChangeNotifierProvider(create: (_) => GiveawaysController(authed, auth)),
        ChangeNotifierProvider(create: (_) => TicketsController(authed, auth)),
      ],
      child: MaterialApp.router(routerConfig: buildRouter(auth)),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Demo: Laptop Gaming Giveaway'));
    await tester.pumpAndSettle();
    expect(find.text('Detail Giveaway'), findsOneWidget);
    expect(find.text('19 Okt 2026, 03.29 WIB'), findsOneWidget); // draw 20:29Z
    expect(find.text('USD 1,200'), findsOneWidget);
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
