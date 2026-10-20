import 'package:code2ticket/core/db/rate_cache.dart' show SettingsStore;
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/core/verify/chain_verifier.dart' show genesisHash, sha256Hex;
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/game/chain_levels_screen.dart';
import 'package:code2ticket/features/game/chain_play_screen.dart';
import 'package:code2ticket/features/game/chain_puzzle.dart';
import 'package:code2ticket/features/game/code_hunt_record.dart';
import 'package:code2ticket/features/game/game_chooser_screen.dart';
import 'package:code2ticket/features/game/game_hub_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../input_code_test.dart' show FakeApi, FakeAuth;
import '../layout/screens_layout_test.dart' show sampleUser;
import '../support/display.dart';
import '../support/ui.dart';

void main() {
  group('generator rantai', () {
    test('deterministik per level dan jumlah block sesuai level', () {
      for (final l in ChainLevel.all) {
        final a = ChainPuzzle.generate(l), b = ChainPuzzle.generate(l);
        expect(a.correct.map((x) => x.hash), b.correct.map((x) => x.hash));
        expect(a.shuffled.map((x) => x.hash), b.shuffled.map((x) => x.hash));
        expect(a.correct, hasLength(l.blockCount));
      }
      expect(ChainLevel.all.map((l) => l.blockCount), [3, 4, 5, 5, 6]);
      expect(ChainLevel.all.map((l) => l.mode), [ChainMode.arrange, ChainMode.arrange, ChainMode.arrange, ChainMode.inspect, ChainMode.inspect]);
      expect(ChainPuzzle.generate(ChainLevel.all[0]).correct.map((x) => x.payload), isNot(ChainPuzzle.generate(ChainLevel.all[1]).correct.map((x) => x.payload).take(3)));
    });

    test('hash tersambung: block pertama memakai genesis, hash = SHA-256(prev|payload), 8 hex ditampilkan', () {
      for (final l in ChainLevel.all.where((l) => l.mode == ChainMode.arrange)) {
        final c = ChainPuzzle.generate(l).correct;
        expect(c.first.previousHash, genesisHash);
        for (var i = 0; i < c.length; i++) {
          expect(c[i].hash, sha256Hex('${c[i].previousHash}|${c[i].payload}'));
          expect(c[i].hash, hasLength(64));
          expect(c[i].shortHash, c[i].hash.substring(0, 8));
          expect(c[i].hashMatches, isTrue);
          expect(c[i].payload, matches(RegExp(r'^tiket #\d{6}$')));
          if (i > 0) expect(c[i].previousHash, c[i - 1].hash);
        }
        expect(isChained(c), isTrue);
      }
    });

    test('urutan acak selalu berbeda dari urutan benar dan memuat block yang sama', () {
      for (final l in ChainLevel.all.where((l) => l.mode == ChainMode.arrange)) {
        final p = ChainPuzzle.generate(l);
        expect(p.shuffled.map((x) => x.index), isNot(p.correct.map((x) => x.index)));
        expect(p.shuffled.map((x) => x.index).toSet(), p.correct.map((x) => x.index).toSet());
        expect(isChained(p.shuffled), isFalse);
      }
    });

    test('mode Periksa: tepat satu sambungan putus (t -> t+1), t bukan block terakhir, tiap block konsisten sendiri, deterministik', () {
      for (final l in ChainLevel.all.where((l) => l.mode == ChainMode.inspect)) {
        final p = ChainPuzzle.generate(l);
        final t = p.brokenAfter!;
        expect(t, inInclusiveRange(0, l.blockCount - 2));
        expect([for (var i = 0; i < l.blockCount - 1; i++) linkIntact(p.correct, i)], [for (var i = 0; i < l.blockCount - 1; i++) i != t]);
        expect(p.correct.every((b) => b.hashMatches), isTrue); // block t dihitung ulang: konsisten dengan dirinya sendiri
        expect(p.correct.first.previousHash, genesisHash);
        expect(p.newHash, p.correct[t].shortHash);
        expect(p.storedHash, p.correct[t + 1].shortPrevious);
        expect(p.newHash, isNot(p.storedHash));
        final again = ChainPuzzle.generate(l);
        expect(again.brokenAfter, t);
        expect(again.correct.map((b) => b.hash), p.correct.map((b) => b.hash));
      }
    });
  });

  group('cek rantai', () {
    final c = ChainPuzzle.generate(ChainLevel.all[2]).correct;
    test('benar semua', () => expect(checkChain(c), everyElement(isTrue)));
    test('sebagian: tukar dua block yang bersebelahan', () {
      final o = List.of(c)..[1] = c[2]..[2] = c[1];
      expect(checkChain(o), [true, false, false, false, true]);
      expect(isChained(o), isFalse);
    });
    test('terbalik: salah semua kecuali mungkin tidak ada yang cocok', () {
      expect(checkChain(c.reversed.toList()).where((x) => x), isEmpty);
    });
  });

  group('progres', () {
    test('langkah terbaik hanya turun; selesai = ada nilai', () {
      var p = const ChainProgress();
      expect(p.isDone(1), isFalse);
      p = p.record(1, 8).record(1, 5).record(1, 9);
      expect(p.best[1], 5);
      expect(p.isDone(1), isTrue);
    });

    test('encode/decode dan data rusak', () {
      final p = const ChainProgress().record(2, 4).record(5, 1);
      expect(ChainProgress.decode(p.encode()).best, {2: 4, 5: 1});
      for (final bad in [null, '', 'bukan json', '[1]', '{"a":1,"2":"x","3":-1}']) {
        expect(ChainProgress.decode(bad).best, isEmpty, reason: '$bad');
      }
    });

    test('disimpan per pengguna di app_settings; gagal simpan tidak melempar', () async {
      final s = MemorySettings();
      await ChainProgressStore(s, 'u1').record(1, 3);
      await ChainProgressStore(s, 'u1').record(1, 2);
      expect((await ChainProgressStore(s, 'u1').load()).best, {1: 2});
      expect((await ChainProgressStore(s, 'u2').load()).best, isEmpty);
      expect(s.values.keys, ['u1|chain_progress']);
      s.failing = true;
      expect((await ChainProgressStore(s, 'u1').record(2, 1)).best[2], 1);
      expect((await ChainProgressStore(s, 'u1').load()).best, isEmpty);
    });
  });

  group('layar Rakit Rantai', () {
    late MemorySettings settings;
    late FakeAuth auth;

    setUp(() {
      settings = MemorySettings();
      auth = FakeAuth(FakeApi((m, p, b) async => {'ok': true}))..user = sampleUser();
    });

    Future<void> pump(WidgetTester tester, Widget Function() page, {double width = 360, double scale = 1, Brightness brightness = Brightness.light}) async {
      await setViewport(tester, width: width, height: 3000, textScale: scale, brightness: brightness); // alto: ListView membangun anak secara malas
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Text('awal'))),
        GoRoute(path: '/page', builder: (_, _) => page()),
        GoRoute(path: '/game/codehunt', builder: (_, _) => const GameHubScreen()),
        GoRoute(path: '/leaderboard', builder: (_, _) => Scaffold(appBar: AppBar(), body: const Text('papan'))),
        GoRoute(path: '/game/chain', builder: (_, _) => const ChainLevelsScreen()),
        GoRoute(path: '/game/chain/play', builder: (_, s) => ChainPlayScreen(levelNumber: s.extra as int)),
      ]);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<SettingsStore>.value(value: settings),
          ...displayProviders(),
        ],
        child: MaterialApp.router(theme: AppTheme.light(), darkTheme: AppTheme.dark(), routerConfig: router),
      ));
      router.push('/page');
      await tester.pumpAndSettle();
    }

    /// Gulir sampai terlihat (ListView membangun anak secara malas) lalu ketuk.
    Future<void> tapKey(WidgetTester tester, Key k) async {
      final f = find.byKey(k);
      if (f.evaluate().isEmpty) {
        await tester.scrollUntilVisible(f, 150, scrollable: find.byType(Scrollable).first);
      } else {
        await tester.ensureVisible(f);
      }
      await tester.pump();
      await tester.tap(f);
    }

    String steps(WidgetTester t) => t.widget<Text>(find.byKey(const Key('chain_steps'))).data!;

    /// Selesaikan mode Susun hanya dengan tombol naik: tiap block ke posisinya.
    Future<void> solveWithButtons(WidgetTester tester, ChainLevel l) async {
      final p = ChainPuzzle.generate(l);
      final cur = [for (final b in p.shuffled) b.payload];
      for (var t = 0; t < l.blockCount; t++) {
        var pos = cur.indexOf(p.correct[t].payload);
        while (pos > t) {
          await tapKey(tester, Key('chain_up_$pos'));
          await tester.pump();
          cur.insert(pos - 1, cur.removeAt(pos));
          pos--;
        }
      }
    }

    testWidgets('pemilih game: dua kartu; Code Hunt membuka hub-nya, kembali ke pemilih; papan peringkat dari Code Hunt', (tester) async {
      await pump(tester, () => const GameChooserScreen());
      expect(find.text('Pilih game'), findsOneWidget);
      expect(find.byKey(const Key('choose_codehunt')), findsOneWidget);
      expect(find.byKey(const Key('choose_chain')), findsOneWidget);
      expect(find.text('Sensor: gyroscope + accelerometer'), findsOneWidget);
      expect(find.text('Belum ada rekor'), findsOneWidget);
      expect(find.text('Puzzle hash-chain'), findsOneWidget);
      expect(find.text('0/5 level selesai'), findsOneWidget);
      await tester.tap(find.byKey(const Key('choose_codehunt')));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Code Hunt'), findsOneWidget);
      expect(find.byKey(const Key('level_0')), findsOneWidget);
      expect(find.byKey(const Key('open_chain')), findsNothing);
      await tapKey(tester, const Key('open_leaderboard'));
      await tester.pumpAndSettle();
      expect(find.text('papan'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Pilih game'), findsOneWidget);
    });

    testWidgets('pemilih game: Rakit Rantai membuka daftar level; progres dan rekor tampil di kartu', (tester) async {
      settings.values['u1|chain_progress'] = const ChainProgress().record(1, 4).record(4, 3).encode();
      settings.values['u1|codehunt_best'] = const CodeHuntRecord().merge(1, 820).encode();
      await pump(tester, () => const GameChooserScreen());
      expect(find.text('2/5 level selesai'), findsOneWidget);
      expect(find.text('Rekor 820 · level Sedang selesai'), findsOneWidget);
      await tester.tap(find.byKey(const Key('choose_chain')));
      await tester.pumpAndSettle();
      for (final l in ChainLevel.all) {
        expect(find.byKey(Key('chain_level_${l.number}')), findsOneWidget);
      }
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('Pilih game'), findsOneWidget);
    });

    testWidgets('pemilih game: tautan papan peringkat kecil', (tester) async {
      await pump(tester, () => const GameChooserScreen());
      await tester.tap(find.byKey(const Key('chooser_leaderboard')));
      await tester.pumpAndSettle();
      expect(find.text('papan'), findsOneWidget);
    });

    testWidgets('Susun: tombol naik/turun menghitung langkah; Cek Rantai menandai benar/salah (ikon + teks)', (tester) async {
      await pump(tester, () => const ChainPlayScreen(levelNumber: 2));
      expect(steps(tester), 'Langkah: 0');
      await tapKey(tester, const Key('chain_check'));
      await tester.pump();
      expect(find.text('Posisi salah'), findsWidgets);
      expect(find.byIcon(Icons.cancel_outlined), findsWidgets);
      await tester.tap(find.byKey(const Key('chain_down_0')));
      await tester.pump();
      expect(steps(tester), 'Langkah: 1');
      expect(find.text('Posisi salah'), findsNothing); // tanda hilang saat urutan berubah
    });

    testWidgets('Susun level 1: menang lewat tombol; penjelasan, langkah terbaik, progres tersimpan', (tester) async {
      await pump(tester, () => const ChainPlayScreen(levelNumber: 1));
      await solveWithButtons(tester, ChainLevel.all[0]);
      await tapKey(tester, const Key('chain_check'));
      await tester.pumpAndSettle();
      expect(find.text(chainExplanation), findsOneWidget);
      expect(find.textContaining('Rantai bersambung'), findsOneWidget);
      final n = int.parse(steps(tester).split(' ').last);
      expect(n, greaterThan(0));
      expect(find.text('Langkah terbaik level ini: $n'), findsOneWidget);
      expect(ChainProgress.decode(settings.values['u1|chain_progress']).best, {1: n});
      expect(find.byKey(const Key('chain_next')), findsOneWidget);
      expect(find.byKey(const Key('chain_check')), findsNothing);
    });

    testWidgets('Susun: seret gagang juga memindahkan block dan menghitung langkah', (tester) async {
      await pump(tester, () => const ChainPlayScreen(levelNumber: 1));
      final g = await tester.startGesture(tester.getCenter(find.byIcon(Icons.drag_indicator).first));
      await tester.pump(const Duration(milliseconds: 100));
      for (var i = 0; i < 12; i++) {
        await g.moveBy(const Offset(0, 15));
        await tester.pump(const Duration(milliseconds: 30));
      }
      await g.up();
      await tester.pumpAndSettle();
      expect(steps(tester), 'Langkah: 1');
    });

    testWidgets('Periksa: sambungan cocok -> petunjuk dan coba lagi; petunjuk muncul setelah 2 salah dan menyorot dua block; benar -> penjelasan', (tester) async {
      final p = ChainPuzzle.generate(ChainLevel.all[3]);
      final t = p.brokenAfter!;
      final wrongLinks = [for (var i = 0; i < 4; i++) if (i != t) i];
      await pump(tester, () => const ChainPlayScreen(levelNumber: 4));
      expect(find.byKey(const Key('chain_hint')), findsNothing);
      await tapKey(tester, Key('chain_link_${wrongLinks[0]}'));
      await tester.pump();
      expect(find.textContaining('Sambungan itu cocok'), findsOneWidget);
      expect(find.text('Sambungan cocok'), findsOneWidget);
      expect(find.text('Percobaan: 1'), findsOneWidget);
      expect(find.byKey(const Key('chain_hint')), findsNothing);
      await tapKey(tester, Key('chain_link_${wrongLinks[1]}'));
      await tester.pump();
      expect(find.byKey(const Key('chain_hint')), findsOneWidget);
      expect(find.text('Periksa di sini'), findsNothing);
      await tapKey(tester, const Key('chain_hint'));
      await tester.pump();
      expect(find.text('Periksa di sini'), findsNWidgets(2)); // block t dan t+1
      expect(find.byKey(const Key('chain_broken_explain')), findsNothing);
      expect(settings.values.containsKey('u1|chain_progress'), isFalse);
      await tapKey(tester, Key('chain_link_$t'));
      await tester.pumpAndSettle();
      expect(find.text('Sambungan putus'), findsOneWidget);
      expect(find.text('Periksa di sini'), findsNothing);
      expect(find.text(brokenExplanation(p)), findsOneWidget);
      expect(brokenExplanation(p), startsWith('Block ${t + 1} diubah, hash barunya ${p.newHash} tidak lagi sama dengan yang tersimpan di block berikutnya (${p.storedHash}).'));
      expect(find.text(chainExplanation), findsOneWidget);
      expect(ChainProgress.decode(settings.values['u1|chain_progress']).best, {4: 3});
    });

    testWidgets('Periksa: langsung benar tanpa salah', (tester) async {
      final t = ChainPuzzle.generate(ChainLevel.all[3]).brokenAfter!;
      await pump(tester, () => const ChainPlayScreen(levelNumber: 4));
      await tapKey(tester, Key('chain_link_$t'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chain_broken_explain')), findsOneWidget);
      expect(ChainProgress.decode(settings.values['u1|chain_progress']).best, {4: 1});
    });

    testWidgets('Semantics konektor: status belum diperiksa, cocok, putus (teks, bukan hanya warna)', (tester) async {
      final t = ChainPuzzle.generate(ChainLevel.all[3]).brokenAfter!;
      final other = t == 0 ? 1 : 0;
      await pump(tester, () => const ChainPlayScreen(levelNumber: 4));
      final h = tester.ensureSemantics();
      expect(find.bySemanticsLabel(RegExp('Sambungan antara block ${other + 1} dan block ${other + 2}, belum diperiksa')), findsOneWidget);
      await tapKey(tester, Key('chain_link_$other'));
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('Sambungan antara block ${other + 1} dan block ${other + 2}, cocok')), findsOneWidget);
      await tapKey(tester, Key('chain_link_$t'));
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp('Sambungan antara block ${t + 1} dan block ${t + 2}, putus')), findsOneWidget);
      h.dispose();
    });

    testWidgets('Cara main: terbuka otomatis pada kunjungan pertama tiap mode, bisa dibuka lagi lewat ikon ?', (tester) async {
      await pump(tester, () => const ChainPlayScreen(levelNumber: 1));
      expect(find.byKey(const Key('chain_howto')), findsOneWidget);
      expect(find.text(howToArrange), findsOneWidget);
      expect(settings.values['u1|chain_howto_arrange'], '1');
      expect(settings.values.containsKey('u1|chain_howto_inspect'), isFalse);
      await tester.tap(find.byKey(const Key('chain_howto_close')));
      await tester.pump();
      expect(find.byKey(const Key('chain_howto')), findsNothing);
      await tester.tap(find.byKey(const Key('chain_help')));
      await tester.pump();
      expect(find.byKey(const Key('chain_howto')), findsOneWidget);
      // Kunjungan kedua ke mode yang sama: tertutup.
      await pump(tester, () => const ChainPlayScreen(levelNumber: 2));
      expect(find.byKey(const Key('chain_howto')), findsNothing);
      // Mode Periksa masih kunjungan pertama.
      await pump(tester, () => const ChainPlayScreen(levelNumber: 4));
      expect(find.text(howToInspect), findsOneWidget);
      expect(settings.values['u1|chain_howto_inspect'], '1');
    });

    testWidgets('daftar level menampilkan progres tersimpan setelah dibuka lagi', (tester) async {
      settings.values['u1|chain_progress'] = const ChainProgress().record(3, 7).encode();
      await pump(tester, () => const ChainLevelsScreen());
      expect(find.text('Selesai · terbaik 7 langkah'), findsOneWidget);
      expect(find.text('Belum selesai'), findsNWidgets(4));
    });

    testWidgets('Semantics block: posisi, isi, hash pendek, status', (tester) async {
      await pump(tester, () => const ChainPlayScreen(levelNumber: 1));
      final h = tester.ensureSemantics();
      await tapKey(tester, const Key('chain_check'));
      await tester.pump();
      expect(find.bySemanticsLabel(RegExp(r'Block posisi 1, isi tiket #\d{6}, prev [0-9a-f]{8}, hash [0-9a-f]{8}, Posisi (benar|salah)')), findsOneWidget);
      h.dispose();
    });

    for (final v in [(w: 320.0, s: 1.3, b: Brightness.light), ...layoutVariants.map((x) => (w: x.width, s: x.scale, b: x.brightness))]) {
      testWidgets('tata letak ${v.w} dp font ${v.s}x ${v.b.name}: tanpa meluap (daftar level, susun + tanda + menang, periksa)', (tester) async {
        await pump(tester, () => const ChainLevelsScreen(), width: v.w, scale: v.s, brightness: v.b);
        expect(tester.takeException(), isNull);
        await pump(tester, () => const ChainPlayScreen(levelNumber: 3), width: v.w, scale: v.s, brightness: v.b);
        await tapKey(tester, const Key('chain_check'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await solveWithButtons(tester, ChainLevel.all[2]);
        await tapKey(tester, const Key('chain_check'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chain_explain')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await pump(tester, () => const GameChooserScreen(), width: v.w, scale: v.s, brightness: v.b);
        expect(tester.takeException(), isNull);
        await pump(tester, () => const ChainPlayScreen(levelNumber: 5), width: v.w, scale: v.s, brightness: v.b);
        expect(find.byKey(const Key('chain_howto')), findsOneWidget);
        expect(tester.takeException(), isNull);
        final t = ChainPuzzle.generate(ChainLevel.all[4]).brokenAfter!;
        final wrong = [for (var i = 0; i < 5; i++) if (i != t) i];
        await tapKey(tester, Key('chain_link_${wrong[0]}'));
        await tapKey(tester, Key('chain_link_${wrong[1]}'));
        await tapKey(tester, const Key('chain_hint'));
        await tester.pump();
        expect(tester.takeException(), isNull);
        await tapKey(tester, Key('chain_link_$t'));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('chain_explain')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  });
}
