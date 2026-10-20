import 'dart:math';

import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/game/code_hunt.dart';
import 'package:code2ticket/features/game/game_controller.dart';
import 'package:code2ticket/features/game/game_hub_screen.dart';
import 'package:code2ticket/features/game/maze.dart';
import 'package:code2ticket/features/game/maze_play_screen.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart';
import 'package:code2ticket/features/tickets/ticket_models.dart';
import 'package:code2ticket/features/tickets/tickets_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../input_code_test.dart' show FakeApi, FakeAuth;
import '../layout/screens_layout_test.dart' show sampleUser;
import '../support/display.dart';
import '../support/memory_cache.dart';
import '../support/ui.dart';
import 'game_test.dart' show okScore;

final _format = RegExp(r'^[A-Z0-9]{4}(-[A-Z0-9]{4}){0,2}$');

Giveaway giveaway(String id, String title, String category, {DateTime? now}) {
  final t = now ?? DateTime.now();
  return Giveaway(id: id, title: title, category: category, startAt: t.subtract(const Duration(days: 1)), endAt: t.add(const Duration(days: 1)), drawAt: t.add(const Duration(days: 2)));
}

Ticket ticket(String giveawayId, String title, {String category = 'travel', TicketResult result = TicketResult.eligible, DateTime? drawAt}) => Ticket(
      id: 't-$giveawayId',
      ticketNumber: 12,
      giveawayId: giveawayId,
      giveawayTitle: title,
      category: category,
      result: result,
      drawAt: drawAt ?? DateTime.now().add(const Duration(days: 2)),
    );

void main() {
  group('pembuat kode latihan', () {
    test('deterministik: seed sama -> kode sama, seed beda -> beda', () {
      expect(practiceSegments(42, 8), practiceSegments(42, 8));
      expect(practiceSegments(42, 8), isNot(practiceSegments(43, 8)));
      expect(practiceTicketNumber(42), practiceTicketNumber(42));
    });

    test('jumlah segmen = jumlah item koleksi tiap tingkat; format dan karakter valid', () {
      for (final l in MazeLevel.all) {
        final segs = practiceSegments(7, l.stars);
        expect(segs, hasLength(l.stars));
        expect(segs.every((s) => RegExp(r'^[A-Z0-9]{4}$').hasMatch(s)), isTrue);
        for (final row in codeRows(segs, segs.length)) {
          expect(_format.hasMatch(row), isTrue, reason: row);
        }
        expect(codeRows(segs, segs.length).join('-').split('-'), segs);
      }
    });

    test('bukan kode redeem yang valid: karakter pertama selalu I/O/0/1 (tidak ada di alfabet kode asli)', () {
      for (var seed = 0; seed < 300; seed++) {
        expect('IO01'.contains(practiceSegments(seed, 5).first[0]), isTrue, reason: 'seed $seed');
      }
    });

    test('baris kode: 3 segmen per baris, baris terakhir menyesuaikan jumlah segmen', () {
      expect(codeRows(practiceSegments(1, 5), 5).map((r) => r.split('-').length), [3, 2]);
      expect(codeRows(practiceSegments(1, 8), 8).map((r) => r.split('-').length), [3, 3, 2]);
      expect(codeRows(practiceSegments(1, 12), 12).map((r) => r.split('-').length), [3, 3, 3, 3]);
    });

    test('terisi bertahap: slot kosong "····", batas jumlah dijaga', () {
      final segs = practiceSegments(3, 5);
      expect(codeRows(segs, 0), ['····-····-····', '····-····']);
      expect(codeRows(segs, 2), ['${segs[0]}-${segs[1]}-····', '····-····']);
      expect(codeRows(segs, 4), ['${segs[0]}-${segs[1]}-${segs[2]}', '${segs[3]}-····']);
      expect(codeRows(segs, 5), ['${segs[0]}-${segs[1]}-${segs[2]}', '${segs[3]}-${segs[4]}']);
      expect(codeRows(segs, 99), codeRows(segs, 5));
      expect(codeRows(segs, -1), codeRows(segs, 0));
    });
  });

  group('target latihan dari data yang sudah ada', () {
    final now = DateTime.now();
    test('giveaway aktif milik pengguna didahulukan atas rekomendasi', () {
      final t = PracticeTarget.pick(
        tickets: [ticket('g2', 'Milik saya', category: 'travel')],
        giveaways: [giveaway('g1', 'Rekomendasi', 'gaming'), giveaway('g2', 'Milik saya', 'travel')],
        affinity: {'gaming': 9},
        now: now,
      );
      expect((t!.title, t.category), ('Milik saya', 'travel'));
    });

    test('tiket yang sudah diundi diabaikan; jatuh ke teratas "Untuk kamu"', () {
      final t = PracticeTarget.pick(
        tickets: [ticket('g2', 'Sudah selesai', result: TicketResult.notSelected)],
        giveaways: [giveaway('g1', 'Rekomendasi', 'gaming')],
        affinity: {'gaming': 9},
        now: now,
      );
      expect(t!.title, 'Rekomendasi');
    });

    test('tanpa data: null (tampilan generik)', () {
      expect(PracticeTarget.pick(tickets: const [], giveaways: const [], affinity: const {}, now: now), isNull);
    });
  });

  group('layar Code Hunt', () {
    late FakeApi api;
    late FakeAuth auth;
    late GiveawaysController giveaways;
    late TicketsController tickets;
    Future<Map<String, dynamic>> Function(String, String, dynamic) handler = (m, p, b) async => okScore();

    setUp(() {
      handler = (m, p, b) async => m == 'POST' ? okScore() : {'ok': true, 'data': []};
      api = FakeApi((m, p, b) => handler(m, p, b));
      auth = FakeAuth(api)..user = sampleUser();
      final authed = AuthedApi(api, auth);
      giveaways = GiveawaysController(authed, auth, MemoryCacheStore(), retryInterval: null);
      tickets = TicketsController(authed, auth, MemoryCacheStore(), retryInterval: null);
    });

    Future<void> pump(WidgetTester tester, Widget page, {double width = 360, double scale = 1, Brightness brightness = Brightness.light}) async {
      await setViewport(tester, width: width, textScale: scale, brightness: brightness);
      final authed = AuthedApi(api, auth);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('awal'))),
        GoRoute(path: '/page', builder: (_, _) => page),
        GoRoute(path: '/leaderboard', builder: (_, _) => const Scaffold(body: Text('papan'))),
      ]);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<AuthedApi>.value(value: authed),
          ...displayProviders(),
          ChangeNotifierProvider<GiveawaysController>.value(value: giveaways),
          ChangeNotifierProvider<TicketsController>.value(value: tickets),
          ChangeNotifierProvider(create: (_) => GameController(authed, auth)),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), darkTheme: AppTheme.dark(), routerConfig: router),
      ));
      router.push('/page');
      await tester.pumpAndSettle();
    }

    MazePlayScreen screen({int seed = 5, int level = 0}) => MazePlayScreen(levelIndex: level, seed: seed, tilt: () => const Stream.empty());

    /// Berjalan sepanjang jalur terpendek lewat D-pad; [stopBefore] langkah terakhir dilewati (tidak masuk Mesin Undian).
    Future<void> walk(WidgetTester tester, Maze m, {bool stopBefore = false, void Function()? each}) async {
      final path = m.solve()!;
      for (var i = 1; i < path.length - (stopBefore ? 1 : 0); i++) {
        final d = Dir.values.firstWhere((d) => path[i - 1].$1 + d.dx == path[i].$1 && path[i - 1].$2 + d.dy == path[i].$2);
        await tester.tap(find.byKey(Key('dpad_${d.name}')));
        await tester.pump();
        each?.call();
      }
      await tester.pump(const Duration(milliseconds: 50));
    }

    String hudCode(WidgetTester tester) => tester
        .widgetList<RichText>(find.descendant(of: find.byKey(const Key('maze_code')), matching: find.byType(RichText)))
        .map((r) => r.text.toPlainText())
        .join('\n');

    testWidgets('HUD: kode terisi bertahap seiring segmen terkumpul; mulai dari semua slot kosong', (tester) async {
      await pump(tester, screen());
      expect(hudCode(tester), '····-····-····\n····-····');
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      final segs = practiceSegments(levelCodeSeed(5, 0), 5);
      final m = Maze.generate(6, 6, Random(5), stars: 5);
      var maxSeen = 0;
      await walk(tester, m, stopBefore: true, each: () {
        final n = int.parse(tester.widget<Text>(find.byKey(const Key('maze_stars'))).data!.split('/').first);
        expect(n, greaterThanOrEqualTo(maxSeen));
        maxSeen = n;
        expect(hudCode(tester), codeRows(segs, n).join('\n'));
      });
      expect(find.bySemanticsLabel(RegExp('Kode 5 segmen, $maxSeen terisi')), findsOneWidget);
    });

    testWidgets('sukses: Tiket Latihan (kode lengkap, nomor, label tegas, XP, lencana); nilai skor yang dikirim tidak berubah', (tester) async {
      await pump(tester, screen());
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      await walk(tester, Maze.generate(6, 6, Random(5), stars: 5));
      await tester.pumpAndSettle();
      final segs = practiceSegments(levelCodeSeed(5, 0), 5);
      expect(find.text('Tiket Latihan terbit!'), findsOneWidget);
      expect(find.byKey(const Key('practice_ticket')), findsOneWidget);
      expect(tester.widget<Text>(find.byKey(const Key('practice_ticket_number'))).data, practiceTicketNumber(levelCodeSeed(5, 0)));
      expect(find.textContaining(codeRows(segs, 5).first, findRichText: true), findsWidgets);
      expect(find.text('Tiket latihan: tidak memengaruhi peluang menang'), findsOneWidget);
      expect(find.text('+70 XP'), findsOneWidget);
      expect(find.text('Lencana: First Maze Clear'), findsOneWidget);
      expect(find.textContaining('Skor tersimpan'), findsOneWidget);

      final post = api.calls.singleWhere((c) => c.method == 'POST');
      final body = post.body as Map<String, dynamic>;
      expect(body.keys.toSet(), {'stars', 'seconds_left', 'cleared', 'duration_sec'});
      expect(post.path, '/game/scores');
      expect(post.retry, isFalse);
      expect(body['cleared'], isTrue);
      expect(body['stars'], int.parse(tester.widget<Text>(find.textContaining('segmen kode')).data!.split(' ').first));
    });

    testWidgets('semantik tiket latihan: kode dieja dan label tegas ada', (tester) async {
      await pump(tester, screen());
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      await walk(tester, Maze.generate(6, 6, Random(5), stars: 5));
      await tester.pumpAndSettle();
      final h = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp(r'^Tiket latihan nomor TL-\d{4}\..*Kode rakitan: .*Tiket latihan: tidak memengaruhi peluang menang')), findsOneWidget);
      h.dispose();
    });

    testWidgets('waktu habis: segmen yang sempat terkumpul tampil, tiket tidak terbit', (tester) async {
      // Cari labirin yang punya segmen di jalur terpendek (selain sel keluar) supaya ada yang terkumpul.
      var seed = 0;
      late Maze m;
      int onPath(Maze x) => x.solve()!.where((c) => x.stars.contains(c)).length;
      for (; seed < 200; seed++) {
        m = Maze.generate(6, 6, Random(seed), stars: 5);
        if (onPath(m) >= 1) break;
      }
      final collected = onPath(m);
      await pump(tester, screen(seed: seed));
      await tester.tap(find.byKey(const Key('maze_start')));
      await tester.pump();
      await walk(tester, m, stopBefore: true);
      for (var i = 0; i < 20 * 65; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      expect(find.text('Waktu habis'), findsOneWidget);
      expect(find.byKey(const Key('practice_ticket')), findsNothing);
      final segs = practiceSegments(levelCodeSeed(seed, 0), 5);
      final shown = tester
          .widgetList<RichText>(find.descendant(of: find.byKey(const Key('maze_result_code')), matching: find.byType(RichText)))
          .map((r) => r.text.toPlainText())
          .join('\n');
      expect(shown, codeRows(segs, collected).join('\n'));
      expect(find.text('$collected dari 5 segmen kode'), findsOneWidget);
    });

    testWidgets('layar awal: "Latihan untuk" dari tiket pengguna; tanpa data tampil generik; tanpa permintaan jaringan baru', (tester) async {
      await pump(tester, const GameHubScreen());
      expect(tester.widget<Text>(find.byKey(const Key('practice_target'))).data, 'Latihan merakit kode menjadi tiket');
      tickets.items = [ticket('g2', 'Giveaway Tiket Saya')];
      giveaways.items = [giveaway('g2', 'Giveaway Tiket Saya', 'travel')];
      giveaways.notifyListeners();
      await tester.pump();
      expect(tester.widget<Text>(find.byKey(const Key('practice_target'))).data, 'Latihan untuk: Giveaway Tiket Saya');
      expect(api.calls, isEmpty);
    });

    testWidgets('overlay Siap?: menampilkan "Latihan untuk" dari data yang ada dan kode kosong di HUD', (tester) async {
      tickets.items = [ticket('g2', 'Giveaway Tiket Saya')];
      giveaways.items = [giveaway('g2', 'Giveaway Tiket Saya', 'travel')];
      await pump(tester, screen());
      expect(find.text('Latihan untuk: Giveaway Tiket Saya'), findsOneWidget);
      expect(api.calls, isEmpty);
    });

    for (final v in [(w: 320.0, s: 1.3, b: Brightness.light), (w: 360.0, s: 1.3, b: Brightness.dark), (w: 428.0, s: 1.3, b: Brightness.dark)]) {
      testWidgets('tata letak hasil ${v.w} dp font 1,3x ${v.b.name}: tidak meluap (sukses tingkat sulit + gagal)', (tester) async {
        tickets.items = [ticket('g2', 'Judul giveaway yang sangat panjang sekali untuk menguji pemotongan teks pada layar sempit')];
        giveaways.items = [giveaway('g2', 'Judul giveaway yang sangat panjang sekali untuk menguji pemotongan teks pada layar sempit', 'gaming')];
        await pump(tester, screen(seed: 1, level: 2), width: v.w, scale: v.s, brightness: v.b);
        await tester.tap(find.byKey(const Key('maze_start')));
        await tester.pump();
        await walk(tester, Maze.generate(10, 10, Random(1), stars: 12));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('practice_ticket')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final scroll = find.byType(Scrollable).last;
        for (var i = 0; i < 10; i++) {
          await tester.drag(scroll, const Offset(0, -300), warnIfMissed: false);
          await tester.pump();
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
