import 'dart:async';
import 'dart:math';

import 'package:code2ticket/core/activity.dart';
import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/auth/auth_models.dart';
import 'package:code2ticket/features/game/game_controller.dart';
import 'package:code2ticket/features/game/game_hub_screen.dart';
import 'package:code2ticket/features/game/leaderboard_screen.dart';
import 'package:code2ticket/features/game/maze.dart';
import 'package:code2ticket/features/game/maze_game.dart';
import 'package:code2ticket/features/game/maze_play_screen.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart' show LoadState;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../input_code_test.dart' show FakeApi, FakeAuth;
import '../layout/screens_layout_test.dart' show sampleUser;
import '../support/display.dart';
import '../support/ui.dart';

const goodScore = GameScore(stars: 3, secondsLeft: 40, cleared: true, durationSec: 20);

Map<String, dynamic> userJson({List<String> badges = const []}) => {
      'id': 'u1',
      'username': 'pengguna_uji',
      'email': 'a@b.co',
      'full_name': 'Pengguna Uji',
      'role': 'user',
      'xp': 330,
      'level': 1,
      'badges': badges,
    };

Map<String, dynamic> okScore({int xp = 70, bool cap = false, List<String> badges = const ['first_maze_clear']}) =>
    {'ok': true, 'score': 700, 'xp_earned': xp, 'daily_xp_total': 70, 'daily_cap_reached': cap, 'user': userJson(badges: badges)};

Map<String, dynamic> entry(int rank, String name, int score, {int level = 2}) => {'rank': rank, 'username': name, 'level': level, 'total_score': score};

void main() {
  late FakeApi api;
  late FakeAuth auth;
  Future<Map<String, dynamic>> Function(String, String, dynamic) handler = (m, p, b) async => {'ok': true};

  setUp(() {
    handler = (m, p, b) async => m == 'POST' ? okScore() : {'ok': true, 'data': []};
    api = FakeApi((m, p, b) => handler(m, p, b));
    auth = FakeAuth(api)..user = sampleUser();
  });

  group('GameController: kirim skor', () {
    late GameController c;
    setUp(() => c = GameController(AuthedApi(api, auth), auth));

    test('sukses: POST /game/scores dengan badan sesuai kontrak, tanpa retry; hasil dari server; user (lencana) diperbarui', () async {
      final r = await c.submitScore(goodScore);
      expect(r!.isOk, isTrue);
      expect(r.data!.score, 700);
      expect(r.data!.xpEarned, 70);
      final post = api.calls.single;
      expect(post.path, '/game/scores');
      expect(post.body, {'stars': 3, 'seconds_left': 40, 'cleared': true, 'duration_sec': 20});
      expect(post.retry, isFalse);
      expect(auth.user!.badges, ['first_maze_clear']); // lencana versi server, bukan hitungan klien
      expect(auth.user!.xp, 330);
    });

    test('batas XP harian tercapai dilaporkan', () async {
      handler = (m, p, b) async => okScore(cap: true, xp: 0);
      final r = await c.submitScore(goodScore);
      expect(r!.data!.dailyCapReached, isTrue);
    });

    test('ditolak server: invalid_input dan too_many_requests -> pesan Indonesia', () async {
      handler = (m, p, b) async => {'ok': false, 'error': 'invalid_input'};
      expect((await c.submitScore(goodScore))!.error, contains('ditolak server'));
      handler = (m, p, b) async => {'ok': false, 'error': 'too_many_requests'};
      expect((await c.submitScore(goodScore))!.error, contains('Terlalu banyak'));
      handler = (m, p, b) async => {'ok': false, 'error': 'aneh'};
      expect((await c.submitScore(goodScore))!.error, contains('aneh'));
    });

    test('jaringan, 403, 401; tidak pernah diulang otomatis', () async {
      handler = (m, p, b) async => throw NetworkException('Tidak ada koneksi internet.');
      expect((await c.submitScore(goodScore))!.error, 'Tidak ada koneksi internet.');
      handler = (m, p, b) async => throw ForbiddenException();
      expect((await c.submitScore(goodScore))!.error, 'Akses ditolak.');
      handler = (m, p, b) async => throw InvalidSessionException();
      expect(await c.submitScore(goodScore), isNull);
      expect(auth.invalidated, 1);
      expect(api.posts('/game/scores'), 3);
    });

    test('kirim ganda saat masih berjalan diabaikan', () async {
      final gate = Completer<Map<String, dynamic>>();
      handler = (m, p, b) => gate.future;
      final first = c.submitScore(goodScore);
      expect(c.submitting, isTrue);
      expect(await c.submitScore(goodScore), isNull);
      gate.complete(okScore());
      expect((await first)!.isOk, isTrue);
      expect(api.posts('/game/scores'), 1);
      expect(c.submitting, isFalse);
    });
  });

  group('GameController: papan peringkat', () {
    late GameController c;
    setUp(() => c = GameController(AuthedApi(api, auth), auth));

    test('memuat GET /game/leaderboard, melewati elemen rusak', () async {
      handler = (m, p, b) async => {'ok': true, 'data': [entry(1, 'a***', 900), entry(2, 'b***', 500), {'rusak': 1}]};
      await c.loadLeaderboard();
      expect(api.calls.single.path, startsWith('/game/leaderboard'));
      expect(c.state, LoadState.loaded);
      expect(c.entries.map((e) => (e.rank, e.totalScore)), [(1, 900), (2, 500)]);
    });

    test('galat jaringan, 403, ok:false, dan 401', () async {
      handler = (m, p, b) async => throw NetworkException('putus');
      await c.loadLeaderboard();
      expect((c.state, c.error), (LoadState.error, 'putus'));
      handler = (m, p, b) async => throw ForbiddenException();
      await c.loadLeaderboard();
      expect(c.error, 'Akses ditolak.');
      handler = (m, p, b) async => {'ok': false, 'error': 'x'};
      await c.loadLeaderboard();
      expect(c.error, contains('x'));
      handler = (m, p, b) async => throw InvalidSessionException();
      await c.loadLeaderboard();
      expect(auth.invalidated, 1);
    });

    test('logout mengosongkan papan', () async {
      handler = (m, p, b) async => {'ok': true, 'data': [entry(1, 'a', 1)]};
      await c.loadLeaderboard();
      auth.status = AuthStatus.signedOut;
      auth.notifyListeners();
      expect(c.entries, isEmpty);
    });
  });

  group('ActivityLogger', () {
    test('POST /activity tanpa retry, jenis sesuai kontrak; tidak memblokir', () async {
      ActivityLogger(AuthedApi(api, auth)).viewGiveaway(giveawayId: 'g1', category: 'gaming');
      await Future<void>.delayed(Duration.zero);
      final call = api.calls.single;
      expect((call.path, call.retry), ('/activity', false));
      expect(call.body, {'type': 'view_giveaway', 'giveaway_id': 'g1', 'category': 'gaming'});
    });

    test('kegagalan diam-diam: tidak melempar, tidak mengulang', () async {
      handler = (m, p, b) async => throw NetworkException('putus');
      ActivityLogger(AuthedApi(api, auth)).viewGiveaway(giveawayId: 'g1', category: 'gaming');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(api.posts('/activity'), 1);
    });

    test('401 saat mencatat: sesi berakhir tanpa galat ke pemanggil', () async {
      handler = (m, p, b) async => throw InvalidSessionException();
      ActivityLogger(AuthedApi(api, auth)).log('search');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(auth.invalidated, 1);
    });
  });

  // ------------------------------------------------------------------ widget
  Future<GoRouter> pump(WidgetTester tester, Widget Function() page, {double width = 360, double height = 800, double scale = 1, Brightness brightness = Brightness.light}) async {
    await setViewport(tester, width: width, height: height, textScale: scale, brightness: brightness);
    final authed = AuthedApi(api, auth);
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('halaman awal'))),
      GoRoute(path: '/page', builder: (_, _) => page()),
      GoRoute(path: '/leaderboard', builder: (_, _) => const Scaffold(body: Text('papan'))),
      GoRoute(path: '/game/play', builder: (_, s) => Scaffold(body: Text('main tingkat ${s.extra}'))),
    ]);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        Provider<AuthedApi>.value(value: authed),
        ...displayProviders(),
        ChangeNotifierProvider(create: (_) => GameController(authed, auth)),
      ],
      child: MaterialApp.router(theme: AppTheme.light(), darkTheme: AppTheme.dark(), routerConfig: router),
    ));
    router.push('/page');
    await tester.pumpAndSettle();
    return router;
  }

  group('layar Maze', () {
    late StreamController<({double x, double y})> tilt;
    setUp(() {
      tilt = StreamController<({double x, double y})>.broadcast();
      addTearDown(tilt.close);
    });

    Maze mazeOf(int seed, MazeLevel l) => Maze.generate(l.cols, l.rows, Random(seed), stars: l.stars);
    MazePlayScreen screen({int seed = 5}) => MazePlayScreen(levelIndex: 0, seed: seed, tilt: () => tilt.stream);

    Future<void> solveWithDpad(WidgetTester tester, Maze m) async {
      final path = m.solve()!;
      for (var i = 1; i < path.length; i++) {
        final d = Dir.values.firstWhere((d) => path[i - 1].$1 + d.dx == path[i].$1 && path[i - 1].$2 + d.dy == path[i].$2);
        await tester.tap(find.byKey(Key('dpad_${d.name}')));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 50));
    }

    testWidgets('mulai: overlay "Siap?" lalu permainan berjalan; tombol panah tersedia tanpa sensor', (tester) async {
      await pump(tester, screen);
      expect(find.text('Siap?'), findsOneWidget);
      expect(find.byKey(const Key('dpad_n')), findsOneWidget);
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      expect(find.text('Siap?'), findsNothing);
      expect(find.byKey(const Key('maze_time')), findsOneWidget);
    });

    testWidgets('D-pad: menyelesaikan labirin tanpa memiringkan; hasil menampilkan waktu, bintang, skor; skor terkirim sekali', (tester) async {
      await pump(tester, screen);
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      await solveWithDpad(tester, mazeOf(5, MazeLevel.easy));
      await tester.pumpAndSettle();
      expect(find.text('Labirin selesai!'), findsOneWidget);
      expect(find.text('Waktu'), findsOneWidget);
      expect(find.textContaining('dari 5 bintang'), findsOneWidget);
      expect(find.byKey(const Key('maze_score')), findsOneWidget);
      final post = api.calls.singleWhere((c) => c.method == 'POST');
      expect(post.path, '/game/scores');
      expect(post.retry, isFalse);
      final body = post.body as Map<String, dynamic>;
      expect(body['cleared'], isTrue);
      expect(body['seconds_left'], inInclusiveRange(55, 60));
      expect(body['stars'], inInclusiveRange(0, 5));
      expect(find.textContaining('Skor tersimpan'), findsOneWidget);
      expect(find.byKey(const Key('maze_retry_submit')), findsNothing);
      expect(auth.user!.badges, contains('first_maze_clear'));
    });

    testWidgets('gagal kirim: pesan galat dan "Kirim skor" mengirim ulang (hanya atas ketukan, tidak otomatis)', (tester) async {
      handler = (m, p, b) async => throw NetworkException('Tidak ada koneksi internet.');
      await pump(tester, screen);
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      await solveWithDpad(tester, mazeOf(5, MazeLevel.easy));
      await tester.pumpAndSettle();
      expect(find.text('Tidak ada koneksi internet.'), findsOneWidget);
      expect(api.posts('/game/scores'), 1);
      handler = (m, p, b) async => okScore();
      await tester.tap(find.byKey(const Key('maze_retry_submit')));
      await tester.pumpAndSettle();
      expect(api.posts('/game/scores'), 2);
      expect(find.textContaining('Skor tersimpan'), findsOneWidget);
      expect(find.byKey(const Key('maze_retry_submit')), findsNothing);
    });

    testWidgets('ditolak server: pesan Indonesia di layar', (tester) async {
      handler = (m, p, b) async => {'ok': false, 'error': 'invalid_input'};
      await pump(tester, screen);
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      await solveWithDpad(tester, mazeOf(5, MazeLevel.easy));
      await tester.pumpAndSettle();
      expect(find.textContaining('ditolak server'), findsOneWidget);
    });

    Future<void> play(WidgetTester tester, int seconds) async {
      // Satu frame lebih lama dari 50 ms dipotong oleh game (tick maks 0,05 dtk), jadi maju per 50 ms.
      for (var i = 0; i < seconds * 20; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    testWidgets('jeda menghentikan waktu; lanjut meneruskan', (tester) async {
      await pump(tester, screen);
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      await play(tester, 2);
      await tester.tap(find.byKey(const Key('maze_pause')));
      await tester.pump();
      expect(find.text('Dijeda'), findsOneWidget);
      final before = tester.widget<Text>(find.byKey(const Key('maze_time'))).data;
      expect(before, isNot('60 dtk'));
      await tester.pump(const Duration(seconds: 5));
      expect(tester.widget<Text>(find.byKey(const Key('maze_time'))).data, before);
      await tester.tap(find.byKey(const Key('maze_resume')));
      await tester.pump();
      expect(find.text('Dijeda'), findsNothing);
      await play(tester, 3);
      expect(tester.widget<Text>(find.byKey(const Key('maze_time'))).data, isNot(before));
    });

    testWidgets('kemiringan dari sensor menggerakkan bola (tanpa menyentuh tombol)', (tester) async {
      final m = mazeOf(5, MazeLevel.easy);
      await pump(tester, screen);
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      final east = m.canMove(0, 0, Dir.e);
      tilt.add(east ? (x: 8, y: 0) : (x: 0, y: 8));
      await tester.pump();
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      // Waktu berjalan (ticker hidup) dan tidak ada galat; posisi bola diuji pada tes logika (maze_test).
      expect(find.byKey(const Key('maze_board')), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('waktu habis: "Waktu habis"; skor hanya dari bintang; tanpa bintang tidak dikirim', (tester) async {
      await pump(tester, screen);
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      await play(tester, 65);
      await tester.pumpAndSettle();
      expect(find.text('Waktu habis'), findsOneWidget);
      expect(find.textContaining('Skor 0 tidak dikirim'), findsOneWidget);
      expect(api.posts('/game/scores'), 0);
    });

    testWidgets('Main lagi memulai labirin baru dengan overlay "Siap?"', (tester) async {
      await pump(tester, screen);
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      await solveWithDpad(tester, mazeOf(5, MazeLevel.easy));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('maze_again')));
      await tester.tap(find.byKey(const Key('maze_again')));
      await tester.pumpAndSettle();
      expect(find.text('Siap?'), findsOneWidget);
    });

    testWidgets('animasi dikurangi: permainan tetap berjalan lewat tombol', (tester) async {
      await pump(tester, screen);
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await tester.pump();
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      await solveWithDpad(tester, mazeOf(5, MazeLevel.easy));
      await tester.pumpAndSettle();
      expect(find.text('Labirin selesai!'), findsOneWidget);
    });

    testWidgets('sensor galat: layar tetap berfungsi', (tester) async {
      await pump(tester, () => MazePlayScreen(levelIndex: 1, seed: 1, tilt: () => Stream.error(StateError('tanpa sensor'))));
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const Key('dpad_e')), findsOneWidget);
    });
  });

  group('Hub dan papan peringkat', () {
    testWidgets('Hub: tiga tingkat, ketuk membuka permainan dengan indeks tingkat', (tester) async {
      await pump(tester, () => const GameHubScreen());
      expect(find.byKey(const Key('level_0')), findsOneWidget);
      expect(find.byKey(const Key('level_2')), findsOneWidget);
      await tester.tap(find.byKey(const Key('level_1')));
      await tester.pumpAndSettle();
      expect(find.text('main tingkat 1'), findsOneWidget);
    });

    testWidgets('Papan: daftar peringkat dan baris pengguna disorot dengan chip "Kamu" (teks + ikon)', (tester) async {
      handler = (m, p, b) async => {'ok': true, 'data': [entry(1, 'ab***', 900), entry(2, 'pengguna_uji', 500), entry(3, 'cd***', 300), entry(4, 'ef***', 100)]};
      auth.user = AppUser(id: 'u1', username: 'pengguna_uji', email: 'a@b.co', fullName: 'Pengguna Uji', role: 'user', xp: 1, level: 1);
      await pump(tester, () => const LeaderboardScreen());
      expect(find.byKey(const Key('rank_1')), findsOneWidget);
      expect(find.text('900'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('rank_2')), matching: find.text('Kamu')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('rank_2')), matching: find.byIcon(Icons.person)), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('rank_1')), matching: find.text('Kamu')), findsNothing);
      expect(find.byIcon(Icons.emoji_events), findsNWidgets(3)); // tiga teratas ikon piala (bukan hanya warna)
    });

    testWidgets('Papan: pengguna di luar daftar mendapat petunjuk', (tester) async {
      handler = (m, p, b) async => {'ok': true, 'data': [entry(1, 'ab***', 900)]};
      await pump(tester, () => const LeaderboardScreen());
      expect(find.textContaining('belum masuk daftar'), findsOneWidget);
    });

    testWidgets('Papan: kosong -> EmptyState; galat -> ErrorState dengan "Coba lagi"', (tester) async {
      await pump(tester, () => const LeaderboardScreen());
      expect(find.text('Belum ada skor'), findsOneWidget);
    });

    testWidgets('Papan: galat jaringan lalu Coba lagi', (tester) async {
      handler = (m, p, b) async => throw NetworkException('Tidak ada koneksi internet.');
      await pump(tester, () => const LeaderboardScreen());
      expect(find.text('Tidak ada koneksi internet.'), findsOneWidget);
      handler = (m, p, b) async => {'ok': true, 'data': [entry(1, 'ab***', 900)]};
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('rank_1')), findsOneWidget);
    });

    testWidgets('Papan: tarik untuk muat ulang memanggil GET lagi', (tester) async {
      handler = (m, p, b) async => {'ok': true, 'data': [entry(1, 'ab***', 900)]};
      await pump(tester, () => const LeaderboardScreen());
      final before = api.calls.length;
      await tester.fling(find.byType(ListView).first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(api.calls.length, before + 1);
    });
  });
}
