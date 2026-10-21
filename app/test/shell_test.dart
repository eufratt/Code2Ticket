import 'package:code2ticket/app_router.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/location/location_service.dart';
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/features/assistant/assistant_controller.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/discover/discover_controller.dart';
import 'package:code2ticket/features/game/game_controller.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart';
import 'package:code2ticket/features/tickets/tickets_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'input_code_test.dart' show FakeApi, FakeAuth, json;
import 'layout/screens_layout_test.dart' show sampleUser;
import 'support/fake_location.dart';
import 'support/display.dart';
import 'support/memory_cache.dart';
import 'support/memory_chat_store.dart';
import 'models_test.dart' show giveawayJson, ticketJson;

class _Auth extends FakeAuth {
  _Auth(super.api);
  int logouts = 0;

  /// Alur logout asli menyentuh penyimpanan perangkat; di tes cukup dihitung.
  @override
  Future<void> logout() async => logouts++;

  @override
  Future<bool> isBiometricAvailable() async => false;
  @override
  Future<bool> isBiometricEnabled({String? userId}) async => false;
}

Widget _createTestApp({required _Auth auth, required AuthedApi authed, ThemeMode mode = ThemeMode.light}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<AuthController>.value(value: auth),
      ...displayProviders(),
      Provider<AuthedApi>.value(value: authed),
      ChangeNotifierProvider(create: (_) => GiveawaysController(authed, auth, MemoryCacheStore(), retryInterval: null)),
      ChangeNotifierProvider(create: (_) => TicketsController(authed, auth, MemoryCacheStore(), retryInterval: null)),
      ChangeNotifierProvider(create: (_) => DiscoverController(authed, auth, MemoryCacheStore(), LocationService(FakeGateway()), retryInterval: null)),
      ChangeNotifierProvider(create: (_) => AssistantController(authed, auth, MemoryChatStore())),
      ChangeNotifierProvider(create: (_) => GameController(authed, auth)),
    ],
    child: MaterialApp.router(theme: AppTheme.light(), darkTheme: AppTheme.dark(), themeMode: mode, routerConfig: buildRouter(auth)),
  );
}

const _navKeys = ['nav_home', 'nav_profile', 'nav_feedback', 'nav_logout'];
const _navLabels = ['Home', 'Profil', 'Saran & Kesan', 'Logout'];

FakeApi _api() => FakeApi((m, p, b) async => p.startsWith('/giveaways/')
    ? json(giveawayJson) // GET /giveaways/:id
    : p.startsWith('/giveaways')
        ? {'ok': true, 'data': [json(giveawayJson)]}
        : {'ok': true, 'data': [json(ticketJson)]});

Future<_Auth> _pump(WidgetTester tester, {double width = 360, double height = 800, double scale = 1.0, ThemeMode mode = ThemeMode.light, bool withUser = true}) async {
  tester.view.physicalSize = Size(width * 3, height * 3);
  tester.view.devicePixelRatio = 3;
  tester.platformDispatcher.textScaleFactorTestValue = scale;
  addTearDown(() {
    tester.view.reset();
    tester.platformDispatcher.clearAllTestValues();
  });
  final api = _api();
  final auth = _Auth(api);
  if (withUser) auth.user = sampleUser();
  await tester.pumpWidget(_createTestApp(auth: auth, authed: AuthedApi(api, auth), mode: mode));
  await tester.pumpAndSettle();
  return auth;
}

/// Status terpilih sebuah item bar (Semantics pembungkus InkWell).
bool _selected(WidgetTester tester, String key) =>
    tester.widget<Semantics>(find.ancestor(of: find.byKey(Key(key)), matching: find.byType(Semantics)).first).properties.selected ?? false;

void main() {
  for (final w in [360.0, 428.0]) {
    testWidgets('bottom nav 4 item sama lebar di $w dp, urut Home, Profil, Saran & Kesan, Logout; tanpa FAB', (tester) async {
      await _pump(tester, width: w);
      expect(find.byKey(const Key('home_greeting')), findsOneWidget);
      double? lastX;
      for (final (i, label) in _navLabels.indexed) {
        final item = find.byKey(Key(_navKeys[i]));
        expect(item, findsOneWidget, reason: label);
        expect(find.descendant(of: item, matching: find.text(label)), findsOneWidget, reason: label);
        final size = tester.getSize(item);
        expect(size.width, closeTo(w / 4, 0.1), reason: '$label harus sama lebar');
        expect(size.height, greaterThanOrEqualTo(48), reason: '$label: target sentuh >= 48 dp');
        final x = tester.getTopLeft(item).dx;
        if (lastX != null) expect(x, greaterThan(lastX), reason: 'urutan $label');
        lastX = x;
      }
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(find.byTooltip('Input Code'), findsNothing);
      // Tab lama sudah keluar dari bar (hanya ada di menu fitur Home).
      for (final gone in ['Discover', 'My Tickets', 'Asisten']) {
        expect(find.descendant(of: find.byType(BottomAppBar), matching: find.text(gone)), findsNothing, reason: gone);
      }
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Profil dan Saran & Kesan: tab terpilih bergantian; Saran & Kesan layar akar tanpa tombol kembali; kembali sistem ke Home', (tester) async {
    await _pump(tester);
    expect(_selected(tester, 'nav_home'), isTrue);
    expect(_selected(tester, 'nav_profile'), isFalse);

    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile_name')), findsOneWidget);
    expect(_selected(tester, 'nav_profile'), isTrue);
    expect(_selected(tester, 'nav_home'), isFalse);

    await tester.tap(find.byKey(const Key('nav_feedback')));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Saran & Kesan'), findsOneWidget);
    expect(find.byType(BackButton), findsNothing);
    expect(_selected(tester, 'nav_feedback'), isTrue);
    expect(find.byKey(const Key('nav_logout')), findsOneWidget, reason: 'bar tetap tampil');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('home_greeting')), findsOneWidget);
    expect(_selected(tester, 'nav_home'), isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('ikon Profil: lingkaran kecil dengan inisial bila belum ada foto; terpilih = cincin + pil + label tebal', (tester) async {
    await _pump(tester);
    final item = find.byKey(const Key('nav_profile'));
    final avatar = find.descendant(of: item, matching: find.byKey(const Key('avatar_initials')));
    expect(avatar, findsOneWidget);
    expect(find.descendant(of: item, matching: find.byType(ClipOval)), findsOneWidget);
    expect(find.descendant(of: avatar, matching: find.text('NS')), findsOneWidget); // sampleUser: "Nama ... Sekali"
    expect(tester.getSize(avatar).width, closeTo(22, 0.5));

    FontWeight? weight() => tester.widget<Text>(find.descendant(of: item, matching: find.text('Profil'))).style?.fontWeight;
    expect(weight(), FontWeight.w500);
    await tester.tap(item);
    await tester.pumpAndSettle();
    expect(weight(), FontWeight.w700, reason: 'label tebal saat terpilih (bukan hanya warna)');
    final ring = find.ancestor(of: avatar, matching: find.byType(DecoratedBox)).first;
    final border = ((tester.widget<DecoratedBox>(ring).decoration) as BoxDecoration).border as Border;
    expect(border.top.width, 2, reason: 'cincin penanda terpilih');
  });

  testWidgets('avatar bar tanpa data pengguna: fallback "?" (tanpa galat)', (tester) async {
    await _pump(tester, withUser: false);
    expect(find.descendant(of: find.byKey(const Key('nav_profile')), matching: find.byKey(const Key('avatar_initials'))), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Logout: dialog konfirmasi; Batal tetap di halaman; Logout bukan tab terpilih; Keluar memakai alur logout yang ada', (tester) async {
    final auth = await _pump(tester);
    await tester.tap(find.byKey(const Key('nav_logout')));
    await tester.pumpAndSettle();
    expect(find.text('Keluar dari akun?'), findsOneWidget);
    expect(auth.logouts, 0);
    expect(_selected(tester, 'nav_logout'), isFalse);
    expect(_selected(tester, 'nav_home'), isTrue);

    await tester.tap(find.byKey(const Key('logout_cancel')));
    await tester.pumpAndSettle();
    expect(find.text('Keluar dari akun?'), findsNothing);
    expect(auth.logouts, 0);
    expect(find.byKey(const Key('home_greeting')), findsOneWidget);

    // Dari tab Profil: batal tidak memindahkan tab.
    await tester.tap(find.byKey(const Key('nav_profile')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nav_logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout_cancel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('profile_name')), findsOneWidget);
    expect(_selected(tester, 'nav_profile'), isTrue);

    await tester.tap(find.byKey(const Key('nav_logout')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('logout_confirm')));
    await tester.pumpAndSettle();
    expect(auth.logouts, 1);
  });

  testWidgets('Home: tombol Input Code dan grid Menu fitur membuka rute yang benar (layar penuh, tanpa bottom nav, kembali ke Home)', (tester) async {
    await _pump(tester, height: 2600);
    expect(find.byKey(const Key('home_input_code')), findsOneWidget);
    expect(find.text('Menu fitur'), findsOneWidget);

    Future<void> opens(String key, Finder screen) async {
      await tester.tap(find.byKey(Key(key)));
      await tester.pumpAndSettle();
      expect(screen, findsOneWidget, reason: key);
      expect(find.byType(BottomAppBar), findsNothing, reason: '$key: layar penuh tanpa bottom nav');
      expect(find.byType(BackButton), findsOneWidget, reason: '$key: tombol kembali');
      await tester.binding.handlePopRoute(); // tombol kembali sistem Android
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('home_greeting')), findsOneWidget, reason: '$key: kembali ke Home');
      expect(find.byType(BottomAppBar), findsOneWidget);
    }

    await opens('home_input_code', find.byKey(const Key('code_field')));
    await opens('menu_discover', find.byKey(const Key('search_field')));
    await opens('menu_tickets', find.text('#000001'));
    await opens('menu_assistant', find.byKey(const Key('chat_field')));
    await opens('menu_game', find.widgetWithText(AppBar, 'Pilih game'));
    await opens('menu_converter', find.widgetWithText(AppBar, 'Konverter'));
    await opens('menu_map', find.widgetWithText(AppBar, 'Peta'));
    await opens('home_search', find.byKey(const Key('search_field')));
    await opens('ticket_summary', find.text('#000001'));
    expect(tester.takeException(), isNull);
  });

  for (final w in [320.0, 360.0, 428.0]) {
    for (final scale in [1.0, 1.3]) {
      for (final mode in [ThemeMode.light, ThemeMode.dark]) {
        testWidgets('tata letak $w dp, font ${scale}x, ${mode.name}: label bar utuh dalam item, grid menu tanpa overflow', (tester) async {
          await _pump(tester, width: w, scale: scale, mode: mode);
          for (final label in _navLabels) {
            final text = find.descendant(of: find.byType(BottomAppBar), matching: find.text(label));
            expect(tester.renderObject<RenderParagraph>(text).didExceedMaxLines, isFalse, reason: '$label terpotong');
            expect(tester.getSize(find.ancestor(of: text, matching: find.byType(FittedBox)).first).width, lessThanOrEqualTo(w / 4), reason: '$label melebihi item');
          }
          expect(find.text('Menu fitur'), findsOneWidget);
          // Semua kotak menu terbangun setelah digulir, cukup besar untuk disentuh, tanpa overflow.
          for (final k in ['discover', 'tickets', 'assistant', 'game', 'converter', 'map']) {
            await tester.scrollUntilVisible(find.byKey(Key('menu_$k')), 120, scrollable: find.byType(Scrollable).first);
            expect(tester.getSize(find.byKey(Key('menu_$k'))).height, greaterThanOrEqualTo(48), reason: 'menu_$k: target sentuh');
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

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

    await tester.scrollUntilVisible(find.text('Demo: Laptop Gaming Giveaway'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Demo: Laptop Gaming Giveaway'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Demo: Laptop Gaming Giveaway'));
    await tester.pumpAndSettle();
    expect(find.text('Detail Giveaway'), findsOneWidget);
    expect(find.text('Rp 20.000.000'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Tiket saya'), 200, scrollable: find.byType(Scrollable).first);
    expect(find.text('Tiket saya'), findsOneWidget);
    expect(find.text('1'), findsWidgets);
    await tester.scrollUntilVisible(find.text('Jadwal draw di zona lain'), 200, scrollable: find.byType(Scrollable).first);
    await tester.ensureVisible(find.text('Jadwal draw di zona lain'));
    await tester.pumpAndSettle();
    expect(find.text('19 Okt 2026, 03.29 WIB'), findsOneWidget); // draw 20:29Z di zona pilihan (WIB)
    await tester.tap(find.text('Jadwal draw di zona lain')); // tiga zona lain dapat dibuka
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('zone_london')), findsOneWidget);
    final activity = api.calls.where((c) => c.path == '/activity').single;
    expect(activity.body, {
      'type': 'view_giveaway',
      'giveaway_id': '5deb977d-ff30-4e4e-849d-ff389fe51e6a',
      'category': 'gaming',
    });
    expect(tester.takeException(), isNull);
  });
}
