import 'package:code2ticket/app_router.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/location/location_service.dart';
import 'package:code2ticket/core/notifications/background_check.dart';
import 'package:code2ticket/core/notifications/notification_service.dart';
import 'package:code2ticket/core/notifications/reminder_planner.dart';
import 'package:code2ticket/core/settings/settings_controller.dart';
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/discover/discover_controller.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart';
import 'package:code2ticket/features/notifications/notification_bridge.dart';
import 'package:code2ticket/features/notifications/notifications_controller.dart';
import 'package:code2ticket/features/profile/settings_screen.dart';
import 'package:code2ticket/features/tickets/input_code_screen.dart';
import 'package:code2ticket/features/tickets/tickets_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../input_code_test.dart' show FakeApi, FakeAuth, json;
import '../layout/screens_layout_test.dart' show sampleUser;
import '../models_test.dart' show giveawayJson, redeemOk, ticketJson;
import '../support/display.dart';
import '../support/fake_location.dart' as loc;
import '../support/memory_cache.dart';
import 'reminder_test.dart' show FakeGateway;

/// Layar Hasil Draw beranimasi tanpa henti (goyang untuk melihat), jadi tidak memakai pumpAndSettle.
Future<void> frames(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

class _Poller implements BackgroundPoller {
  int starts = 0, stops = 0;
  @override
  Future<void> start() async => starts++;
  @override
  Future<void> stop() async => stops++;
}

class _Auth extends FakeAuth {
  _Auth(super.api);
  @override
  Future<bool> isBiometricAvailable() async => false;
  @override
  Future<bool> isBiometricEnabled({String? userId}) async => false;
}

class _Env {
  _Env({bool granted = true, String? launch}) {
    gw = FakeGateway()
      ..enabled = granted
      ..launch = launch;
    api = FakeApi((m, p, b) async => p == '/codes/redeem'
        ? json(redeemOk)
        : p.startsWith('/giveaways/')
            ? json(giveawayJson)
            : p.startsWith('/giveaways')
                ? {'ok': true, 'data': [json(giveawayJson)]}
                : p.startsWith('/notifications')
                    ? {'ok': true, 'data': []}
                    : {'ok': true, 'data': [json(ticketJson)]});
    auth = _Auth(api)..user = sampleUser();
    authed = AuthedApi(api, auth);
    store = MemorySettings();
    svc = NotificationService(gw, store);
  }

  late final FakeGateway gw;
  late final FakeApi api;
  late final _Auth auth;
  late final AuthedApi authed;
  late final MemorySettings store;
  late final NotificationService svc;
  late final GoRouter router = buildRouter(auth);

  List<SingleChildWidget> get providers => [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        ...displayProviders(),
        Provider<AuthedApi>.value(value: authed),
        ChangeNotifierProvider<NotificationService>.value(value: svc),
        ChangeNotifierProvider(create: (_) => GiveawaysController(authed, auth, MemoryCacheStore(), retryInterval: null)),
        ChangeNotifierProvider(create: (_) => TicketsController(authed, auth, MemoryCacheStore(), retryInterval: null)),
        ChangeNotifierProvider(create: (_) => NotificationsController(authed, auth)),
        ChangeNotifierProvider(create: (_) => DiscoverController(authed, auth, MemoryCacheStore(), LocationService(loc.FakeGateway()), retryInterval: null)),
        Provider<LocationService>.value(value: LocationService(loc.FakeGateway())),
      ];

  /// Seluruh aplikasi dengan router asli dan jembatan notifikasi.
  Future<void> pumpApp(WidgetTester tester, {bool settle = true, BackgroundPoller? poller}) async {
    await svc.init();
    await tester.pumpWidget(MultiProvider(
      providers: providers,
      child: NotificationBridge(router: router, poller: poller, child: MaterialApp.router(theme: AppTheme.light(), routerConfig: router)),
    ));
    settle ? await tester.pumpAndSettle() : await frames(tester);
  }

  String get path => router.routerDelegate.currentConfiguration.last.matchedLocation;
}

void main() {
  testWidgets('Home: dialog penjelasan muncul DULU; izin sistem baru diminta setelah "Lanjutkan"; tidak diulang', (tester) async {
    final e = _Env(granted: false);
    await e.pumpApp(tester);
    expect(find.text('Aktifkan notifikasi?'), findsOneWidget);
    expect(e.gw.requests, 0, reason: 'belum boleh meminta izin sebelum penjelasan');
    await tester.tap(find.byKey(const Key('notif_allow')));
    await tester.pumpAndSettle();
    expect(e.gw.requests, 1);
    expect(e.svc.permissionGranted, isTrue);
    expect(find.text('Aktifkan notifikasi?'), findsNothing);
    expect(await e.store.getSetting(NotifKeys.permissionAsked), '1');
  });

  testWidgets('Home: pilih "Nanti" -> izin tidak diminta, aplikasi tetap jalan; kunjungan berikutnya tidak bertanya lagi', (tester) async {
    final e = _Env(granted: false);
    await e.pumpApp(tester);
    await tester.tap(find.byKey(const Key('notif_later')));
    await tester.pumpAndSettle();
    expect(e.gw.requests, 0);
    expect(e.svc.permissionGranted, isFalse);
    expect(find.byKey(const Key('home_greeting')), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    final again = _Env(granted: false);
    await again.store.setSetting(NotifKeys.permissionAsked, '1');
    await again.pumpApp(tester);
    expect(find.text('Aktifkan notifikasi?'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('tiket berhasil dibuat: notifikasi sistem langsung tanpa kode di isinya', (tester) async {
    final e = _Env();
    await e.svc.init();
    await tester.pumpWidget(MultiProvider(providers: e.providers, child: const MaterialApp(home: InputCodeScreen())));
    await tester.enterText(find.byKey(const Key('code_field')), 'AAAA-BBBB-CCCC');
    await tester.tap(find.byKey(const Key('submit_code')));
    await tester.pumpAndSettle();
    expect(e.gw.shown.length, 1);
    final (_, title, body, payload) = e.gw.shown.single;
    expect(title, 'Tiket berhasil dibuat');
    expect(body, matches(RegExp(r'^Tiket #\d{6} terbit untuk .+\.$')));
    expect(body.contains('AAAA'), isFalse);
    expect(payload, startsWith('giveaway/'));
  });

  testWidgets('tiket dimuat: pengingat dijadwalkan lewat jembatan; logout membatalkan semuanya', (tester) async {
    final e = _Env();
    await e.pumpApp(tester);
    final tickets = tester.element(find.byKey(const Key('home_greeting'))).read<TicketsController>();
    expect(tickets.items, isNotEmpty);
    // ticketJson punya draw_at tetap (masa lalu bagi jam uji) -> tidak ada jadwal; pastikan tidak ada galat dan penyelarasan berjalan.
    expect(tester.takeException(), isNull);
    expect(e.gw.scheduled.values.every((r) => isReminderId(r.id)), isTrue);

    // Jadwalkan sesuatu secara langsung lalu logout.
    await e.gw.schedule(PlannedReminder(id: reminderId('gx', ReminderKind.atDraw), at: DateTime.now().add(const Duration(hours: 2)), title: 't', body: 'b', payload: 'giveaway/gx'), ScheduleMode.exact);
    expect(e.gw.scheduled, isNotEmpty);
    await e.auth.handleInvalidSession(); // status -> signedOut
    await tester.pumpAndSettle();
    expect(e.gw.cancelAllCalls, 1);
    expect(e.gw.scheduled, isEmpty);
  });

  testWidgets('pemeriksaan latar belakang: dimulai saat masuk, dihentikan saat logout', (tester) async {
    final poller = _Poller();
    final e = _Env();
    await e.pumpApp(tester, poller: poller);
    expect(poller.starts, 1);
    expect(poller.stops, 0);
    await e.auth.handleInvalidSession();
    await tester.pumpAndSettle();
    expect(poller.stops, 1);
  });

  testWidgets('ketuk notifikasi saat aplikasi hidup: membuka Hasil Draw / Detail lewat router (Home tetap di bawah)', (tester) async {
    final e = _Env();
    await e.pumpApp(tester);
    e.gw.onTap!('result/5deb977d-ff30-4e4e-849d-ff389fe51e6a');
    await frames(tester);
    expect(e.path, '/giveaway/5deb977d-ff30-4e4e-849d-ff389fe51e6a/result');
    await tester.binding.handlePopRoute();
    await frames(tester);
    expect(e.path, '/home');
    e.gw.onTap!('giveaway/5deb977d-ff30-4e4e-849d-ff389fe51e6a');
    await tester.pumpAndSettle();
    expect(e.path, '/giveaway/5deb977d-ff30-4e4e-849d-ff389fe51e6a');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    e.gw.onTap!('notifications');
    await tester.pumpAndSettle();
    expect(e.path, '/notifications');
    e.gw.onTap!('admin/1'); // muatan tidak dikenal diabaikan
    await tester.pumpAndSettle();
    expect(e.path, '/notifications');
    expect(tester.takeException(), isNull);
  });

  testWidgets('aplikasi diluncurkan dari notifikasi (keadaan tertutup): layar tujuan terbuka di atas Home', (tester) async {
    final e = _Env(launch: 'result/5deb977d-ff30-4e4e-849d-ff389fe51e6a');
    await e.pumpApp(tester, settle: false);
    expect(e.path, '/giveaway/5deb977d-ff30-4e4e-849d-ff389fe51e6a/result');
    await tester.binding.handlePopRoute();
    await frames(tester);
    expect(e.path, '/home');
  });

  group('Pengaturan', () {
    Future<_Env> pumpSettings(WidgetTester tester, {required bool granted}) async {
      tester.view.physicalSize = const Size(360 * 3, 1600 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final e = _Env(granted: granted);
      await e.svc.init();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ...e.providers,
          ChangeNotifierProvider(create: (_) => SettingsController(e.store)),
        ],
        child: MaterialApp(theme: AppTheme.light(), home: const SettingsScreen()),
      ));
      await tester.pumpAndSettle();
      return e;
    }

    testWidgets('izin diberikan: status diizinkan, saklar aktif bawaan; mematikan menyimpan dan membatalkan jadwal', (tester) async {
      final e = await pumpSettings(tester, granted: true);
      expect(find.text('Izin notifikasi: diizinkan'), findsOneWidget);
      expect(find.byKey(const Key('open_system_notif_settings')), findsNothing);
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('switch_reminders'))).value, isTrue);
      await e.gw.schedule(PlannedReminder(id: reminderId('gx', ReminderKind.atDraw), at: DateTime.now().add(const Duration(hours: 2)), title: 't', body: 'b', payload: 'giveaway/gx'), ScheduleMode.exact);
      await tester.tap(find.byKey(const Key('switch_reminders')));
      await tester.pumpAndSettle();
      expect(e.svc.remindersEnabled, isFalse);
      expect(await e.store.getSetting(NotifKeys.reminders), '0');
      expect(e.gw.scheduled, isEmpty);
    });

    testWidgets('izin ditolak: status + tombol buka pengaturan sistem; layar tetap berfungsi', (tester) async {
      final e = await pumpSettings(tester, granted: false);
      expect(find.text('Izin notifikasi: belum diizinkan'), findsOneWidget);
      await tester.tap(find.byKey(const Key('open_system_notif_settings')));
      await tester.pump();
      expect(e.gw.settingsOpened, 1);
      expect(tester.takeException(), isNull);
    });

    testWidgets('menyalakan saklar tanpa izin: penjelasan dulu, lalu izin diminta', (tester) async {
      final e = await pumpSettings(tester, granted: false);
      await e.svc.setRemindersEnabled(false);
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('switch_reminders')));
      await tester.pumpAndSettle();
      expect(find.text('Aktifkan notifikasi?'), findsOneWidget);
      expect(e.gw.requests, 0);
      await tester.tap(find.byKey(const Key('notif_allow')));
      await tester.pumpAndSettle();
      expect(e.gw.requests, 1);
      expect(e.svc.remindersEnabled, isTrue);
      expect(find.text('Izin notifikasi: diizinkan'), findsOneWidget);
    });
  });

  test('routeForPayload cocok dengan muatan yang dibuat planner', () {
    expect(routeForPayload(giveawayPayload('g-1')), '/giveaway/g-1');
    expect(routeForPayload(resultPayload('g-1')), '/giveaway/g-1/result');
  });
}
