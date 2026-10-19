import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/features/giveaways/giveaway_detail_screen.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/tickets/tickets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'layout/screens_layout_test.dart' show SampleEnv, sampleGiveaways;
import 'support/ui.dart';

/// Pintu masuk ke Hasil Draw dan Cek Keaslian dari Detail Giveaway dan My Tickets.
void main() {
  Future<GoRouter> pump(WidgetTester tester, SampleEnv env, String start) async {
    await setViewport(tester, height: 2400);
    final router = GoRouter(initialLocation: start, routes: [
      GoRoute(path: '/detail', builder: (_, _) => GiveawayDetailScreen(giveawayId: 'g1', initial: Giveaway.tryParse({...sampleGiveaways().first, 'status': env.giveawayStatus}))),
      GoRoute(path: '/tickets', builder: (_, _) => const TicketsScreen()),
      GoRoute(path: '/code', builder: (_, _) => const Scaffold(body: Text('input code'))),
      GoRoute(path: '/giveaway/:id', builder: (_, s) => Scaffold(body: Text('detail ${s.pathParameters['id']}'))),
      GoRoute(path: '/giveaway/:id/result', builder: (_, s) => Scaffold(body: Text('hasil ${s.pathParameters['id']}'))),
      GoRoute(path: '/giveaway/:id/verify', builder: (_, s) => Scaffold(body: Text('verifikasi ${s.pathParameters['id']}'))),
    ]);
    await tester.pumpWidget(env.wrap(MaterialApp.router(theme: AppTheme.light(), darkTheme: AppTheme.dark(), routerConfig: router)));
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('Detail giveaway selesai: tombol "Lihat hasil" dan "Cek keaslian", tanpa Input Code', (tester) async {
    final env = SampleEnv()..giveawayStatus = 'drawn';
    await pump(tester, env, '/detail');
    expect(find.text('Input Code'), findsNothing);
    await tester.tap(find.byKey(const Key('open_result')));
    await tester.pumpAndSettle();
    expect(find.text('hasil g1'), findsOneWidget);
  });

  testWidgets('Detail giveaway selesai: "Cek keaslian" membuka layar verifikasi', (tester) async {
    final env = SampleEnv()..giveawayStatus = 'drawn';
    await pump(tester, env, '/detail');
    await tester.tap(find.byKey(const Key('open_verify_detail')));
    await tester.pumpAndSettle();
    expect(find.text('verifikasi g1'), findsOneWidget);
  });

  testWidgets('Detail giveaway aktif: tetap "Input Code", tanpa tombol hasil', (tester) async {
    await pump(tester, SampleEnv(), '/detail');
    expect(find.text('Input Code'), findsOneWidget);
    expect(find.byKey(const Key('open_result')), findsNothing);
    expect(find.byKey(const Key('open_verify_detail')), findsNothing);
  });

  testWidgets('My Tickets: tiket menang ditandai chip "Menang"; mengetuknya membuka hasil, tiket lain membuka detail', (tester) async {
    final env = SampleEnv();
    await pump(tester, env, '/tickets');
    expect(find.text('Menang'), findsWidgets);
    await tester.tap(find.text('#000003')); // tiket menang (giveaway g2)
    await tester.pumpAndSettle();
    expect(find.text('hasil g2'), findsOneWidget);
  });

  testWidgets('My Tickets: tiket belum diundi membuka Detail Giveaway', (tester) async {
    final env = SampleEnv();
    await pump(tester, env, '/tickets');
    await tester.tap(find.text('#123456')); // menunggu draw (g1)
    await tester.pumpAndSettle();
    expect(find.text('detail g1'), findsOneWidget);
  });
}
