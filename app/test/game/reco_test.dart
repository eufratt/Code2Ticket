import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/auth/auth_models.dart';
import 'package:code2ticket/features/giveaways/affinity_controller.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart' show LoadState;
import 'package:code2ticket/features/giveaways/home_screen.dart';
import 'package:code2ticket/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../input_code_test.dart' show FakeApi, FakeAuth;
import '../layout/screens_layout_test.dart' show SampleEnv, sampleGiveaway;
import '../support/ui.dart';

Giveaway gw(String id, String category, {int drawHours = 3, String status = 'active', int startHours = -1, double? distanceKm, bool clearDistance = false}) {
  final m = sampleGiveaway(id, category);
  final now = DateTime.now().toUtc();
  m['start_at'] = now.add(Duration(hours: startHours)).toIso8601String();
  m['end_at'] = now.add(Duration(hours: drawHours - 1)).toIso8601String();
  m['draw_at'] = now.add(Duration(hours: drawHours)).toIso8601String();
  m['status'] = status;
  if (distanceKm != null) {
    m['distance_km'] = distanceKm;
  } else if (clearDistance) {
    m['distance_km'] = null;
  }
  return Giveaway.tryParse(m)!;
}

void main() {
  group('recommendFor', () {
    final now = DateTime.now();
    test('urut skor minat tertinggi dulu, lalu draw terdekat; kategori tanpa skor tidak ikut', () {
      final items = [gw('a', 'tech', drawHours: 5), gw('b', 'gaming', drawHours: 9), gw('c', 'gaming', drawHours: 4), gw('d', 'food'), gw('e', 'travel', drawHours: 2)];
      final r = recommendFor(items, {'gaming': 5, 'tech': 1, 'travel': 3}, now);
      expect(r.map((g) => g.id), ['c', 'b', 'e', 'a']);
    });

    test('affinity kosong -> kosong (bagian disembunyikan)', () {
      expect(recommendFor([gw('a', 'tech')], const {}, now), isEmpty);
    });

    test('yang sudah diundi atau menunggu draw tidak direkomendasikan; yang belum mulai boleh', () {
      final items = [gw('drawn', 'tech', status: 'drawn'), gw('wait', 'tech', drawHours: -1, startHours: -5), gw('soon', 'tech', startHours: 2, drawHours: 6), gw('ok', 'tech')];
      expect(recommendFor(items, {'tech': 2}, now).map((g) => g.id), containsAll(['ok', 'soon']));
      expect(recommendFor(items, {'tech': 2}, now).map((g) => g.id), isNot(contains('drawn')));
      expect(recommendFor(items, {'tech': 2}, now).map((g) => g.id), isNot(contains('wait')));
    });

    test('dibatasi limit', () {
      final items = [for (var i = 0; i < 10; i++) gw('g$i', 'tech', drawHours: 2 + i)];
      expect(recommendFor(items, {'tech': 1}, now, limit: 4).length, 4);
    });
  });

  group('recommendationReasons', () {
    final now = DateTime.now();

    test('kategori teratas: "Karena kamu sering ikut kategori {kategori}"', () {
      final g = gw('1', 'gaming', drawHours: 48, clearDistance: true);
      final r = recommendationReasons(g, {'gaming': 5, 'tech': 2}, now);
      expect(r, ['Karena kamu sering ikut kategori Gaming']);
    });

    test('bukan teratas: "Sesuai minatmu di {kategori}"', () {
      final g = gw('2', 'tech', drawHours: 48, clearDistance: true);
      final r = recommendationReasons(g, {'gaming': 5, 'tech': 2}, now);
      expect(r, ['Sesuai minatmu di Tech']);
    });

    test('kosong: afinitas kosong -> tidak ada alasan', () {
      final g = gw('3', 'gaming', drawHours: 5, distanceKm: 2.3);
      expect(recommendationReasons(g, const {}, now), isEmpty);
    });

    test('kategori tanpa skor minat -> kosong', () {
      final g = gw('4', 'food', drawHours: 5, distanceKm: 2.3);
      expect(recommendationReasons(g, {'gaming': 5}, now), isEmpty);
    });

    test('alasan kedua: draw < 24 jam -> "Draw segera"', () {
      final g = gw('5', 'gaming', drawHours: 12, clearDistance: true);
      final r = recommendationReasons(g, {'gaming': 5}, now);
      expect(r, ['Karena kamu sering ikut kategori Gaming', 'Draw segera']);
    });

    test('draw >= 24 jam -> tidak memuat "Draw segera"', () {
      final g = gw('6', 'gaming', drawHours: 30, clearDistance: true);
      final r = recommendationReasons(g, {'gaming': 5}, now);
      expect(r, ['Karena kamu sering ikut kategori Gaming']);
      expect(r, isNot(contains('Draw segera')));
    });

    test('alasan kedua: jarak diketahui -> "{n} km dari kamu"', () {
      final g1 = gw('7', 'gaming', drawHours: 48, distanceKm: 3.5);
      final r1 = recommendationReasons(g1, {'gaming': 5}, now);
      expect(r1, ['Karena kamu sering ikut kategori Gaming', '3,5 km dari kamu']);

      // Jarak bulat
      final g2 = gw('8', 'gaming', drawHours: 48, distanceKm: 5.0);
      final r2 = recommendationReasons(g2, {'gaming': 5}, now);
      expect(r2, ['Karena kamu sering ikut kategori Gaming', '5 km dari kamu']);

      // Jarak sangat dekat
      final g3 = gw('9', 'gaming', drawHours: 48, distanceKm: 0.05);
      final r3 = recommendationReasons(g3, {'gaming': 5}, now);
      expect(r3, ['Karena kamu sering ikut kategori Gaming', '<0,1 km dari kamu']);
    });

    test('maksimal 2 alasan dengan urutan afinitas dulu', () {
      // Ada afinitas, draw < 24h, dan jarak: hanya 2 alasan pertama yang diambil
      final g = gw('10', 'gaming', drawHours: 6, distanceKm: 2.3);
      final r = recommendationReasons(g, {'gaming': 5}, now);
      expect(r.length, 2);
      expect(r[0], 'Karena kamu sering ikut kategori Gaming');
      expect(r[1], 'Draw segera');
    });
  });

  group('AffinityController', () {
    late FakeApi api;
    late FakeAuth auth;
    late AffinityController c;
    Future<Map<String, dynamic>> Function(String, String, dynamic) handler = (m, p, b) async => {};

    setUp(() {
      handler = (m, p, b) async => {'gaming': 5, 'travel': 3, 'food': 0, 'rusak': 'x'};
      api = FakeApi((m, p, b) => handler(m, p, b));
      auth = FakeAuth(api);
      c = AffinityController(AuthedApi(api, auth), auth);
    });

    test('objek polos {kategori: skor}: hanya skor positif numerik; satu GET /me/affinity', () async {
      await c.load();
      expect(c.scores, {'gaming': 5, 'travel': 3});
      expect(c.state, LoadState.loaded);
      expect(api.calls.single.path, '/me/affinity');
    });

    test('loadOnce: tidak membuat permintaan baru setelah dimuat', () async {
      await c.loadOnce();
      await c.loadOnce();
      expect(api.calls.length, 1);
    });

    test('galat jaringan / 403 / ok:false: kosong tanpa melempar; 401 -> logout', () async {
      handler = (m, p, b) async => throw NetworkException('putus');
      await c.load();
      expect(c.state, LoadState.error);
      expect(c.scores, isEmpty);
      handler = (m, p, b) async => throw ForbiddenException();
      await c.load();
      expect(c.state, LoadState.error);
      handler = (m, p, b) async => {'ok': false, 'error': 'x'};
      await c.load();
      expect(c.scores, isEmpty);
      handler = (m, p, b) async => throw InvalidSessionException();
      await c.load();
      expect(auth.invalidated, 1);
    });

    test('logout mengosongkan', () async {
      await c.load();
      auth.status = AuthStatus.signedOut;
      auth.notifyListeners();
      expect(c.scores, isEmpty);
    });
  });

  group('Home: "Untuk kamu"', () {
    Future<SampleEnv> pumpHome(WidgetTester tester, Map<String, dynamic> affinity) async {
      await setViewport(tester, height: 1600);
      final env = SampleEnv()..affinity = affinity;
      await tester.pumpWidget(env.app(const HomeScreen()));
      await tester.pumpAndSettle();
      return env;
    }

    int gets(SampleEnv env) => env.api.calls.where((c) => c.path == '/me/affinity').length;

    testWidgets('affinity berisi: bagian tampil; dimuat satu kali', (tester) async {
      final env = await pumpHome(tester, {'travel': 5, 'gaming': 2});
      expect(find.text('Untuk kamu'), findsOneWidget);
      expect(gets(env), 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('affinity kosong: bagian disembunyikan', (tester) async {
      final env = await pumpHome(tester, {});
      expect(find.text('Untuk kamu'), findsNothing);
      expect(gets(env), 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('kategori tanpa giveaway yang cocok: bagian disembunyikan', (tester) async {
      await pumpHome(tester, {'fashion': 9});
      expect(find.text('Untuk kamu'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('tidak ada permintaan berlebih saat Home digulir dan dibangun ulang', (tester) async {
      final env = await pumpHome(tester, {'travel': 5});
      await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
      await tester.pumpAndSettle();
      expect(gets(env), 1);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Profil: Game dan lencana dari server', () {
    Future<SampleEnv> pumpProfile(WidgetTester tester, List<String> badges) async {
      await setViewport(tester, height: 2200);
      final env = SampleEnv();
      env.auth.user = AppUser(id: 'u1', username: 'pengguna_uji', email: 'a@b.co', fullName: 'Pengguna Uji', role: 'user', xp: 10, level: 1, badges: badges);
      await tester.pumpWidget(env.app(const ProfileScreen()));
      await tester.pumpAndSettle();
      return env;
    }

    testWidgets('menu Game Maze tidak ada lagi di Profil (pindah ke menu fitur Home)', (tester) async {
      await pumpProfile(tester, const []);
      expect(find.byKey(const Key('open_game')), findsNothing);
    });

    testWidgets('lencana Maze sesuai data server; tidak dihitung di klien', (tester) async {
      await pumpProfile(tester, const ['first_maze_clear']);
      expect(find.bySemanticsLabel('First Maze Clear, sudah diraih'), findsOneWidget);
      expect(find.bySemanticsLabel('Maze Master, terkunci'), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('badge_maze_master')), matching: find.byIcon(Icons.lock)), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('Widget & Layout: Alasan rekomendasi di Home', () {
    Future<SampleEnv> pumpHome(WidgetTester tester, Map<String, dynamic> affinity, {double width = 360, double textScale = 1.0, Brightness brightness = Brightness.light}) async {
      await setViewport(tester, width: width, height: 1600, textScale: textScale, brightness: brightness);
      final env = SampleEnv()..affinity = affinity;
      await tester.pumpWidget(env.app(const HomeScreen()));
      await tester.pumpAndSettle();
      return env;
    }

    testWidgets('alasan tampil pada kartu "Untuk kamu" dan tidak pada bagian lain', (tester) async {
      await pumpHome(tester, {'travel': 5, 'gaming': 2});
      final forYouFinder = find.byKey(const Key('for_you'));
      expect(forYouFinder, findsOneWidget);

      expect(find.text('Karena kamu sering ikut kategori Travel'), findsOneWidget);
      expect(find.text('Sesuai minatmu di Gaming'), findsOneWidget);
      expect(find.text('Draw segera'), findsAtLeastNWidgets(1));

      expect(find.bySemanticsLabel('Alasan rekomendasi: Karena kamu sering ikut kategori Travel'), findsOneWidget);

      // Hanya tampil satu kali di layar (hanya di Untuk kamu, bukan di Segera draw atau Semua giveaway)
      expect(find.text('Karena kamu sering ikut kategori Travel'), findsExactly(1));
      expect(find.text('Sesuai minatmu di Gaming'), findsExactly(1));

      await tester.pumpWidget(const SizedBox());
    });

    for (final (w, sc, b, label) in [
      (360.0, 1.3, Brightness.light, '360 dp font 1,3x terang'),
      (360.0, 1.3, Brightness.dark, '360 dp font 1,3x gelap'),
      (428.0, 1.3, Brightness.light, '428 dp font 1,3x terang'),
      (428.0, 1.3, Brightness.dark, '428 dp font 1,3x gelap'),
    ]) {
      testWidgets('layout: kartu "Untuk kamu" dengan alasan di $label tanpa overflow', (tester) async {
        await pumpHome(tester, {'travel': 5, 'gaming': 2}, width: w, textScale: sc, brightness: b);
        expect(tester.takeException(), isNull);
        expect(find.text('Untuk kamu'), findsOneWidget);
        expect(find.text('Karena kamu sering ikut kategori Travel'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
