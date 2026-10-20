import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart' show LoadState;
import 'package:code2ticket/features/giveaways/giveaways_controller.dart' show GiveawaysController;
import 'package:code2ticket/features/giveaways/home_screen.dart';
import 'package:code2ticket/features/notifications/notification_bell.dart';
import 'package:code2ticket/features/notifications/notification_models.dart';
import 'package:code2ticket/features/notifications/notifications_controller.dart';
import 'package:code2ticket/features/notifications/notifications_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import 'input_code_test.dart' show FakeApi, FakeAuth;
import 'layout/screens_layout_test.dart' show SampleEnv;
import 'support/display.dart';
import 'support/memory_cache.dart';
import 'support/ui.dart';

Map<String, dynamic> notif(int id, {String type = 'winner', bool read = false, String? gid = 'g1', String title = 'Selamat, kamu menang!'}) => {
      'id': id,
      'type': type,
      'title': title,
      'body': 'Isi $id',
      'giveaway_id': gid,
      'is_read': read,
      'created_at': '2026-10-19T03:00:00.000Z',
    };

void main() {
  late FakeApi api;
  late FakeAuth auth;
  late NotificationsController c;
  Future<Map<String, dynamic>> Function(String, String, dynamic) handler = (m, p, b) async => {'ok': true};

  void setUpController() {
    api = FakeApi((m, p, b) => handler(m, p, b));
    auth = FakeAuth(api);
    c = NotificationsController(AuthedApi(api, auth), auth);
  }

  setUp(() {
    handler = (m, p, b) async => m == 'GET'
        ? {'ok': true, 'data': [notif(3), notif(2, type: 'draw_result', read: true), notif(1, type: 'ticket_created', gid: null)]}
        : {'ok': true, 'updated': 2};
    setUpController();
  });

  group('NotificationsController', () {
    test('load: mengurai daftar, menghitung belum dibaca (hanya GET /notifications)', () async {
      await c.load();
      expect(api.calls.single.method, 'GET');
      expect(api.calls.single.path, startsWith('/notifications'));
      expect(c.state, LoadState.loaded);
      expect(c.items.map((n) => n.id), [3, 2, 1]);
      expect(c.unreadCount, 2);
    });

    test('elemen rusak dilewati, data bukan list menjadi kosong', () async {
      handler = (m, p, b) async => {'ok': true, 'data': [notif(1), {'id': 'x'}, 'rusak', null]};
      await c.load();
      expect(c.items.length, 1);
    });

    test('galat jaringan: state error + pesan', () async {
      handler = (m, p, b) async => throw NetworkException('Tidak ada koneksi internet.');
      await c.load();
      expect(c.state, LoadState.error);
      expect(c.error, 'Tidak ada koneksi internet.');
    });

    test('galat bisnis ok:false dari server menjadi state error', () async {
      handler = (m, p, b) async => {'ok': false, 'error': 'invalid_input'};
      await c.load();
      expect(c.state, LoadState.error);
      expect(c.error, contains('invalid_input'));
    });

    test('401 invalid_session: logout lewat AuthedApi, tidak menampilkan galat', () async {
      handler = (m, p, b) async => throw InvalidSessionException();
      await c.load();
      expect(auth.invalidated, 1);
      expect(c.error, isNull);
    });

    test('403 forbidden: "Akses ditolak."', () async {
      handler = (m, p, b) async => throw ForbiddenException();
      await c.load();
      expect(c.state, LoadState.error);
      expect(c.error, 'Akses ditolak.');
    });

    test('refreshUnread diam-diam: galat tidak mengubah daftar lama', () async {
      await c.load();
      handler = (m, p, b) async => throw NetworkException('putus');
      await c.refreshUnread();
      expect(c.state, LoadState.loaded);
      expect(c.items.length, 3);
    });

    test('markAllRead: POST tanpa retry, ids null, semua jadi dibaca', () async {
      await c.load();
      final err = await c.markAllRead();
      expect(err, isNull);
      final post = api.calls.singleWhere((x) => x.method == 'POST');
      expect(post.path, '/notifications/read');
      expect(post.body, {'ids': null});
      expect(post.retry, isFalse);
      expect(c.unreadCount, 0);
    });

    test('markRead: hanya id itu; yang sudah dibaca tidak memicu POST', () async {
      await c.load();
      expect(await c.markRead(2), isNull);
      expect(api.posts('/notifications/read'), 0);
      expect(await c.markRead(3), isNull);
      expect(api.calls.last.body, {'ids': [3]});
      expect(c.unreadCount, 1);
    });

    test('POST gagal jaringan: pesan galat, daftar tetap belum dibaca, tidak diulang', () async {
      await c.load();
      handler = (m, p, b) async => m == 'POST' ? throw NetworkException('Tidak ada koneksi internet.') : {'ok': true, 'data': []};
      final err = await c.markAllRead();
      expect(err, 'Tidak ada koneksi internet.');
      expect(c.unreadCount, 2);
      expect(api.posts('/notifications/read'), 1);
      expect(c.markingAll, isFalse);
    });

    test('POST 403 dan 401', () async {
      await c.load();
      handler = (m, p, b) async => throw ForbiddenException();
      expect(await c.markAllRead(), 'Akses ditolak.');
      handler = (m, p, b) async => throw InvalidSessionException();
      expect(await c.markAllRead(), isNull);
      expect(auth.invalidated, 1);
    });

    test('POST ok:false: pesan galat, tidak mengubah daftar', () async {
      await c.load();
      handler = (m, p, b) async => {'ok': false, 'error': 'invalid_input'};
      expect(await c.markAllRead(), contains('invalid_input'));
      expect(c.unreadCount, 2);
    });

    test('logout mengosongkan daftar', () async {
      await c.load();
      auth.status = AuthStatus.signedOut;
      auth.notifyListeners();
      expect(c.items, isEmpty);
      expect(c.unreadCount, 0);
    });
  });

  group('jenis notifikasi', () {
    test('semua jenis backend punya ikon + label Indonesia; jenis tak dikenal memakai tampilan umum', () {
      expect(NotificationKind.of('winner').label, 'Menang');
      expect(NotificationKind.of('draw_result').label, 'Draw selesai');
      expect(NotificationKind.of('ticket_created').label, 'Tiket baru');
      expect(NotificationKind.of('reminder').label, 'Pengingat');
      expect(NotificationKind.of('info').label, 'Info');
      expect(NotificationKind.of('apa_saja').icon, Icons.notifications_none);
    });

    test('badgeText: "9+" bila lebih dari 9', () {
      expect(badgeText(0), '0');
      expect(badgeText(9), '9');
      expect(badgeText(10), '9+');
      expect(badgeText(120), '9+');
    });
  });

  group('NotificationsScreen', () {
    Future<void> pumpScreen(WidgetTester tester) async {
      await setViewport(tester, height: 900);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const NotificationsScreen()),
        GoRoute(path: '/giveaway/:id', builder: (_, s) => Scaffold(body: Text('detail ${s.pathParameters['id']}'))),
        GoRoute(path: '/giveaway/:id/result', builder: (_, s) => Scaffold(body: Text('hasil ${s.pathParameters['id']}'))),
      ]);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<NotificationsController>.value(value: c),
          ...displayProviders(),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), darkTheme: AppTheme.dark(), routerConfig: router),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('daftar: belum dibaca ditandai dengan teks "Belum dibaca", jenis dengan ikon + label', (tester) async {
      await pumpScreen(tester);
      expect(find.text('Belum dibaca'), findsNWidgets(2));
      expect(find.text('2 belum dibaca'), findsOneWidget);
      // hasil draw belum di-reveal: label/ikon/teks netral (tanpa spoiler menang)
      expect(find.text('Menang'), findsNothing);
      expect(find.text('Selamat, kamu menang!'), findsOneWidget); // hanya item tiket (helper memakai judul yang sama)
      expect(find.text('Hasil draw sudah keluar'), findsWidgets);
      expect(find.text('Draw selesai'), findsWidgets);
      expect(find.byKey(const Key('mark_all_read')), findsOneWidget);
    });

    testWidgets('"Tandai semua dibaca": POST sekali, penanda dan tombol hilang', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('mark_all_read')));
      await tester.pumpAndSettle();
      expect(api.posts('/notifications/read'), 1);
      expect(find.text('Belum dibaca'), findsNothing);
      expect(find.byKey(const Key('mark_all_read')), findsNothing);
    });

    testWidgets('gagal menandai: snackbar galat, penanda tetap', (tester) async {
      await pumpScreen(tester);
      handler = (m, p, b) async => throw NetworkException('Tidak ada koneksi internet.');
      await tester.tap(find.byKey(const Key('mark_all_read')));
      await tester.pumpAndSettle();
      expect(find.text('Tidak ada koneksi internet.'), findsOneWidget);
      expect(find.text('Belum dibaca'), findsNWidgets(2));
    });

    testWidgets('ketuk notifikasi winner / draw_result: ditandai dibaca lalu membuka layar Hasil Draw', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('notification_3')));
      await tester.pumpAndSettle();
      expect(api.calls.last.body, {'ids': [3]});
      expect(find.text('hasil g1'), findsOneWidget);
    });

    testWidgets('ketuk notifikasi jenis lain dengan giveaway_id: membuka Detail Giveaway', (tester) async {
      handler = (m, p, b) async => {'ok': true, 'data': [notif(7, type: 'reminder', gid: 'g2', title: 'Draw sebentar lagi')]};
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('notification_7')));
      await tester.pumpAndSettle();
      expect(find.text('detail g2'), findsOneWidget);
    });

    testWidgets('ketuk notifikasi tanpa giveaway_id: tetap di daftar', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('notification_1')));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsScreen), findsOneWidget);
      expect(find.textContaining('detail'), findsNothing);
    });

    testWidgets('kosong: EmptyState', (tester) async {
      handler = (m, p, b) async => {'ok': true, 'data': []};
      await pumpScreen(tester);
      expect(find.text('Belum ada notifikasi'), findsOneWidget);
    });

    testWidgets('galat: ErrorState dengan "Coba lagi" yang memuat ulang', (tester) async {
      handler = (m, p, b) async => throw NetworkException('Tidak ada koneksi internet.');
      await pumpScreen(tester);
      expect(find.text('Tidak ada koneksi internet.'), findsOneWidget);
      handler = (m, p, b) async => {'ok': true, 'data': [notif(1)]};
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.text('Hasil draw sudah keluar'), findsOneWidget);
    });

    testWidgets('tarik untuk menyegarkan memanggil GET lagi', (tester) async {
      await pumpScreen(tester);
      final before = api.calls.where((x) => x.method == 'GET').length;
      await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(api.calls.where((x) => x.method == 'GET').length, before + 1);
    });
  });

  group('lonceng di Home', () {
    testWidgets('lencana: jumlah, "9+" bila lebih, label Semantics jelas, hilang bila 0', (tester) async {
      await setViewport(tester);
      handler = (m, p, b) async => {'ok': true, 'data': [for (var i = 1; i <= 12; i++) notif(i)]};
      await tester.pumpWidget(MultiProvider(
        providers: [ChangeNotifierProvider<NotificationsController>.value(value: c)],
        child: themedApp(const Scaffold(body: Center(child: NotificationBell()))),
      ));
      expect(find.byKey(const Key('notification_badge')), findsNothing); // belum dimuat
      expect(find.bySemanticsLabel('Notifikasi'), findsOneWidget);
      await c.load();
      await tester.pump();
      expect(find.text('9+'), findsOneWidget);
      expect(find.bySemanticsLabel('Notifikasi, 12 belum dibaca'), findsOneWidget);
      await c.markAllRead();
      await tester.pump();
      expect(find.byKey(const Key('notification_badge')), findsNothing);
      expect(find.bySemanticsLabel('Notifikasi'), findsOneWidget);
    });

    testWidgets('Home memuat hitungan saat dibuka dan saat app kembali ke foreground', (tester) async {
      await setViewport(tester, height: 900);
      final env = SampleEnv();
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: env.auth),
          Provider<AuthedApi>.value(value: env.authed),
          ...displayProviders(),
          ChangeNotifierProvider(create: (_) => GiveawaysController(env.authed, env.auth, MemoryCacheStore(), retryInterval: null)),
          ChangeNotifierProvider(create: (_) => NotificationsController(env.authed, env.auth)),
        ],
        child: themedApp(const HomeScreen()),
      ));
      await tester.pumpAndSettle();
      int notifGets() => env.api.calls.where((x) => x.method == 'GET' && x.path.startsWith('/notifications')).length;
      expect(notifGets(), 1);
      expect(find.text('3'), findsOneWidget); // 3 belum dibaca pada contoh
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(notifGets(), 2);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
