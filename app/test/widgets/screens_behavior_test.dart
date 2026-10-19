import 'package:code2ticket/core/widgets/widgets.dart' show TicketCard;
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/giveaways/home_screen.dart';
import 'package:code2ticket/features/profile/profile_screen.dart';
import 'package:code2ticket/features/tickets/tickets_screen.dart';
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../layout/screens_layout_test.dart' show SampleEnv, sampleGiveaway, sampleGiveaways;
import '../support/ui.dart';

/// Perilaku layar yang baru dari desain: ringkasan tiket, carousel, filter kategori/status, level dan lencana.
void main() {
  /// Aplikasi mini dengan router supaya ketukan yang berpindah layar bisa diperiksa.
  Widget routed(SampleEnv env, Widget home, List<String> visited) {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => home),
      for (final p in ['/tickets', '/discover', '/profile'])
        GoRoute(
          path: p,
          builder: (_, _) {
            visited.add(p);
            return Scaffold(body: Text('layar $p'));
          },
        ),
    ]);
    return env.wrap(MaterialApp.router(theme: AppTheme.light(), darkTheme: AppTheme.dark(), routerConfig: router));
  }

  group('Home', () {
    testWidgets('sapaan, ringkasan tiket, carousel, dan daftar semua giveaway', (tester) async {
      await setViewport(tester, height: 1400);
      final env = SampleEnv();
      await tester.pumpWidget(routed(env, const HomeScreen(), []));
      await tester.pumpAndSettle();
      expect(find.text('Nama'), findsOneWidget); // nama depan pengguna
      expect(find.text('Kamu punya 4 tiket'), findsOneWidget);
      expect(find.text('Segera draw'), findsOneWidget);
      expect(find.text('Semua giveaway'), findsOneWidget);
      expect(find.text('Terdekat'), findsNothing); // belum ada data Terdekat dari Discover
      // Hanya satu permintaan daftar giveaway: carousel memakai data yang sama, tanpa permintaan jaringan baru.
      expect(env.api.calls.where((c) => c.path.startsWith('/giveaways')), hasLength(1));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('chip kategori menyaring daftar; ketuk lagi / "Semua" mengembalikan', (tester) async {
      await setViewport(tester, height: 1400);
      final env = SampleEnv();
      await tester.pumpWidget(routed(env, const HomeScreen(), []));
      await tester.pumpAndSettle();
      expect(find.text('Giveaway g2'), findsWidgets);
      await tester.tap(find.byKey(const Key('home_cat_gaming')));
      await tester.pumpAndSettle();
      expect(find.text('Giveaway g2'), findsNothing);
      expect(find.textContaining('Giveaway dengan judul'), findsWidgets);
      await tester.tap(find.text('Semua').first);
      await tester.pumpAndSettle();
      expect(find.text('Giveaway g2'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('kolom cari dan ringkasan tiket membuka Discover dan My Tickets', (tester) async {
      await setViewport(tester, height: 1400);
      final visited = <String>[];
      final env = SampleEnv();
      await tester.pumpWidget(routed(env, const HomeScreen(), visited));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('home_search')));
      await tester.pumpAndSettle();
      expect(visited, ['/discover']);
      await tester.pumpWidget(routed(env, const HomeScreen(), visited));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('ticket_summary')));
      await tester.pumpAndSettle();
      expect(visited, ['/discover', '/tickets']);
      await tester.pumpWidget(const SizedBox());
    });

    test('soonestDraws: hanya yang belum diundi dan jadwalnya di depan, terdekat dulu, dibatasi', () {
      final now = DateTime.now();
      Giveaway g(String id, Duration? draw, {String status = 'active'}) {
        final j = sampleGiveaway(id, 'gaming')
          ..['draw_at'] = draw == null ? null : now.add(draw).toUtc().toIso8601String()
          ..['status'] = status;
        return Giveaway.tryParse(j)!;
      }

      final items = [
        g('lama', const Duration(hours: -1)),
        g('jauh', const Duration(days: 5)),
        g('dekat', const Duration(hours: 1)),
        g('tanpa', null),
        g('selesai', const Duration(hours: 2), status: 'drawn'),
        g('tengah', const Duration(days: 1)),
      ];
      expect(soonestDraws(items, now).map((e) => e.id), ['dekat', 'tengah', 'jauh']);
      expect(soonestDraws(items, now, limit: 2).map((e) => e.id), ['dekat', 'tengah']);
    });
  });

  Future<void> tapChip(WidgetTester tester, String key) async {
    await tester.ensureVisible(find.byKey(Key(key)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  group('My Tickets', () {
    testWidgets('kartu tiket per giveaway; filter status menyaring dan bisa dibatalkan', (tester) async {
      await setViewport(tester, height: 5000);
      final env = SampleEnv();
      await tester.pumpWidget(env.wrap(themedApp(const TicketsScreen())));
      await tester.pumpAndSettle();
      expect(find.byType(TicketCard), findsNWidgets(4));
      for (final n in ['#000001', '#123456', '#000003', '#000004']) {
        expect(find.text(n), findsOneWidget, reason: n);
      }

      await tapChip(tester, 'ticket_filter_won');
      expect(find.text('#000003'), findsOneWidget);
      expect(find.text('#000001'), findsNothing);
      expect(find.text('Menang'), findsWidgets);

      await tapChip(tester, 'ticket_filter_pending');
      expect(find.text('#000001'), findsOneWidget);
      expect(find.text('#123456'), findsOneWidget);
      expect(find.text('#000003'), findsNothing);

      await tapChip(tester, 'ticket_filter_all');
      expect(find.byType(TicketCard), findsNWidgets(4));
    });

    testWidgets('filter tanpa hasil: keadaan kosong dengan aksi "Tampilkan semua"', (tester) async {
      await setViewport(tester, height: 5000);
      final env = SampleEnv();
      env.tickets.removeWhere((t) => t['result'] == 'not_selected');
      await tester.pumpWidget(env.wrap(themedApp(const TicketsScreen())));
      await tester.pumpAndSettle();
      await tapChip(tester, 'ticket_filter_lost');
      expect(find.textContaining('Tidak ada tiket'), findsOneWidget);
      await tester.tap(find.text('Tampilkan semua'));
      await tester.pumpAndSettle();
      expect(find.text('#000001'), findsOneWidget);
    });

    testWidgets('tanpa tiket: keadaan kosong dengan aksi Masukkan kode', (tester) async {
      await setViewport(tester, height: 5000);
      final env = SampleEnv();
      env.tickets.clear();
      await tester.pumpWidget(env.wrap(themedApp(const TicketsScreen())));
      await tester.pumpAndSettle();
      expect(find.text('Belum ada tiket'), findsOneWidget);
      expect(find.text('Masukkan kode'), findsOneWidget);
    });
  });

  group('Profil', () {
    testWidgets('lingkaran level, bar XP menuju level berikutnya, lencana terkunci berwarna abu', (tester) async {
      await setViewport(tester, height: 1800);
      final semantics = tester.ensureSemantics();
      final env = SampleEnv();
      await tester.pumpWidget(env.wrap(themedApp(const ProfileScreen())));
      await tester.pumpAndSettle();
      expect(tester.widget<Text>(find.byKey(const Key('level_circle'))).data, '3');
      expect(find.text('Level 3'), findsOneWidget);
      expect(find.text('1234 XP'), findsOneWidget);
      // 1234 XP: 234 dari 500 menuju level 4 (level = xp / 500 + 1 di skema database).
      expect(tester.widget<LinearProgressIndicator>(find.byKey(const Key('xp_bar'))).value, closeTo(234 / 500, 1e-9));
      expect(find.text('234 / 500 XP menuju level 4'), findsOneWidget);
      // 5 lencana dikenal: 2 diraih, 3 terkunci (ikon gembok).
      expect(find.byIcon(Icons.lock), findsNWidgets(3));
      expect(find.bySemanticsLabel('First Ticket, sudah diraih'), findsOneWidget);
      expect(find.bySemanticsLabel('Maze Master, terkunci'), findsOneWidget);
      semantics.dispose();
    });
  });

  test('sampleGiveaways menyediakan 5 kategori berbeda', () {
    expect({for (final g in sampleGiveaways()) g['category']}.length, 5);
  });
}
