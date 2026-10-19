import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/db/rate_cache.dart' show SettingsStore;
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/core/verify/chain_verifier.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/draw/draw_controller.dart';
import 'package:code2ticket/features/draw/draw_result_screen.dart';
import 'package:code2ticket/features/draw/draw_verify_screen.dart';
import 'package:code2ticket/features/draw/shake.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart' show LoadState;
import 'package:code2ticket/features/tickets/tickets_controller.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'input_code_test.dart' show FakeApi, FakeAuth;
import 'layout/screens_layout_test.dart' show sampleUser;
import 'support/display.dart';
import 'support/memory_cache.dart';
import 'support/ui.dart';

late final Map<String, dynamic> vectors;
late final String gid;

/// Animasi berulang (goyang, kerangka) membuat pumpAndSettle tak pernah selesai: maju beberapa frame saja.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 15; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

Map<String, dynamic> scen(String name) =>
    jsonDecode(jsonEncode((vectors['scenarios'] as List).firstWhere((s) => s['name'] == name)['data'])) as Map<String, dynamic>;

Future<VerificationReport?> syncRunner(({Map<String, dynamic> raw, List<int>? announced}) a) async => verifyRaw(a);

List<int> winnersOf(Map<String, dynamic> raw) => verifyData(VerificationData.tryParse(raw)!).winningTickets;

Map<String, dynamic> winnersJson(List<int> numbers, {bool drawn = true}) => {
      'ok': true,
      'drawn': drawn,
      'winners': [for (var i = 0; i < numbers.length; i++) {'rank': i + 1, 'ticket_number': numbers[i], 'name': 'pe***${i + 1}'}],
    };

Map<String, dynamic> ticketJson(int n, String result) => {
      'id': 'tk$n',
      'ticket_number': n,
      'giveaway_id': gid,
      'giveaway_title': 'Giveaway Uji',
      'prize_name': 'Laptop',
      'category': 'gaming',
      'result': result,
      'code_masked': '****-****-AB12',
    };

void main() {
  setUpAll(() {
    vectors = jsonDecode(File('test/fixtures/m1_vectors.json').readAsStringSync()) as Map<String, dynamic>;
    gid = (scen('valid')['giveaway'] as Map)['id'] as String;
  });

  // ------------------------------------------------------------ detektor goyang
  group('ShakeDetector', () {
    Duration ms(int v) => Duration(milliseconds: v);

    test('tiga lonjakan kuat dalam 1,2 detik = goyangan, lalu hitungan diulang', () {
      final d = ShakeDetector();
      expect(d.add(20, ms(0)), isFalse);
      expect(d.add(20, ms(200)), isFalse);
      expect(d.add(20, ms(400)), isTrue);
      expect(d.add(20, ms(600)), isFalse); // mulai dari nol
    });

    test('gerakan biasa (di bawah ambang) atau lonjakan tunggal tidak dihitung', () {
      final d = ShakeDetector();
      for (var t = 0; t < 3000; t += 20) {
        expect(d.add(6, ms(t)), isFalse);
      }
      expect(d.add(30, ms(4000)), isFalse);
    });

    test('lonjakan terlalu rapat (< 120 ms, satu ayunan) dihitung sekali; lonjakan terlalu jarang tidak cukup', () {
      final d = ShakeDetector();
      expect(d.add(20, ms(0)), isFalse);
      expect(d.add(20, ms(40)), isFalse);
      expect(d.add(20, ms(80)), isFalse);
      expect(d.add(20, ms(1500)), isFalse); // di luar jendela dari yang pertama
      expect(d.add(20, ms(2800)), isFalse);
    });
  });

  // ------------------------------------------------------------ penanda dilihat
  group('DrawSeenStore', () {
    test('baru -> tandai -> terlihat; terpisah per pengguna dan per giveaway', () async {
      final s = MemorySettings();
      final a = DrawSeenStore(s, 'u1'), b = DrawSeenStore(s, 'u2');
      expect(await a.isSeen('g1'), isFalse);
      await a.markSeen('g1');
      expect(await a.isSeen('g1'), isTrue);
      expect(await a.isSeen('g2'), isFalse);
      expect(await b.isSeen('g1'), isFalse);
      expect(s.values.values.every((v) => v == '1'), isTrue, reason: 'hanya penanda, tanpa data lain');
    });

    test('penyimpanan rusak atau tidak ada: dianggap baru, tidak melempar', () async {
      final s = MemorySettings()..failing = true;
      expect(await DrawSeenStore(s, 'u1').isSeen('g1'), isFalse);
      await DrawSeenStore(s, 'u1').markSeen('g1');
      expect(await const DrawSeenStore(null, 'u1').isSeen('g1'), isFalse);
    });
  });

  // ------------------------------------------------------------ controller
  group('DrawController', () {
    late FakeApi api;
    late FakeAuth auth;
    late DrawController c;
    Future<Map<String, dynamic>> Function(String, String, dynamic) handler = (m, p, b) async => {};

    void ok({Map<String, dynamic>? verification, Map<String, dynamic>? winners}) {
      final v = verification ?? scen('valid');
      handler = (m, p, b) async => p.endsWith('/winners') ? (winners ?? winnersJson(winnersOf(v))) : {'ok': true, ...v};
    }

    setUp(() {
      api = FakeApi((m, p, b) => handler(m, p, b));
      auth = FakeAuth(api);
      ok();
      c = DrawController(AuthedApi(api, auth), gid, runner: syncRunner);
    });

    test('sukses: dua GET, pemenang, laporan terverifikasi', () async {
      await c.load();
      expect(api.calls.map((x) => (x.method, x.path)), [('GET', '/giveaways/$gid/winners'), ('GET', '/giveaways/$gid/verification')]);
      expect(c.state, LoadState.loaded);
      expect(c.drawn, isTrue);
      expect(c.winners.length, 3);
      expect(c.winners.first.name, 'pe***1');
      expect(c.report!.verified, isTrue);
    });

    test('data server dirusak: laporan tidak cocok', () async {
      ok(verification: scen('pemenang dipalsukan, hash blok disesuaikan'), winners: winnersJson([1, 2, 3]));
      await c.load();
      expect(c.report!.verified, isFalse);
      expect(c.report!.mismatch, isTrue);
    });

    test('pemenang yang diumumkan berbeda dari hasil hitung ulang: langkah pemenang gagal', () async {
      ok(winners: winnersJson([1, 2, 3]));
      await c.load();
      expect(c.report!.step(VerifyStepId.winners).status, StepStatus.fail);
    });

    test('belum diundi: drawn false, laporan hanya rantai dan komitmen', () async {
      ok(verification: scen('belum diundi'), winners: winnersJson([], drawn: false));
      await c.load();
      expect(c.drawn, isFalse);
      expect(c.report!.drawn, isFalse);
      expect(c.state, LoadState.loaded);
    });

    test('galat bisnis ok:false -> pesan Indonesia', () async {
      handler = (m, p, b) async => {'ok': false, 'error': 'not_found'};
      await c.load();
      expect(c.state, LoadState.error);
      expect(c.error, 'Giveaway tidak ditemukan.');
    });

    test('jaringan putus -> state error', () async {
      handler = (m, p, b) async => throw NetworkException('Tidak ada koneksi internet.');
      await c.load();
      expect(c.state, LoadState.error);
      expect(c.error, 'Tidak ada koneksi internet.');
    });

    test('401 invalid_session: logout, tanpa galat', () async {
      handler = (m, p, b) async => throw InvalidSessionException();
      await c.load();
      expect(auth.invalidated, 1);
      expect(c.error, isNull);
    });

    test('403 forbidden -> "Akses ditolak."', () async {
      handler = (m, p, b) async => throw ForbiddenException();
      await c.load();
      expect(c.error, 'Akses ditolak.');
    });

    test('verifikasi tidak bisa dibaca (rantai bukan daftar): galat jelas, bukan "terverifikasi"', () async {
      handler = (m, p, b) async => p.endsWith('/winners') ? winnersJson([1]) : {'ok': true, 'giveaway': {'id': gid}, 'chain': 'rusak'};
      await c.load();
      expect(c.state, LoadState.error);
      expect(c.report, isNull);
      expect(c.error, contains('tidak lengkap'));
    });

    test('semua permintaan hanya GET (tidak ada POST)', () async {
      await c.load();
      expect(api.calls.every((x) => x.method == 'GET'), isTrue);
    });
  });

  // ------------------------------------------------------------ widget
  group('layar Hasil Draw dan Cek Keaslian', () {
    late FakeApi api;
    late FakeAuth auth;
    late MemorySettings settings;
    late StreamController<void> shakes;
    Map<String, dynamic> verification = {};
    Map<String, dynamic> winners = {};
    List<Map<String, dynamic>> tickets = [];
    Object? failWith;

    setUp(() {
      verification = scen('valid');
      winners = winnersJson(winnersOf(verification));
      tickets = [];
      failWith = null;
      settings = MemorySettings();
      shakes = StreamController<void>.broadcast();
      addTearDown(shakes.close);
      api = FakeApi((m, p, b) async {
        if (failWith != null) throw failWith!;
        if (p == '/tickets') return {'ok': true, 'data': tickets};
        if (p.endsWith('/winners')) return winners;
        return {'ok': true, ...verification};
      });
      auth = FakeAuth(api)..user = sampleUser();
    });

    Future<void> pump(WidgetTester tester, Widget screen, {double width = 360, double height = 900, double textScale = 1}) async {
      await setViewport(tester, width: width, height: height, textScale: textScale);
      final authed = AuthedApi(api, auth);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<AuthedApi>.value(value: authed),
          Provider<SettingsStore>.value(value: settings),
          ...displayProviders(),
          ChangeNotifierProvider(create: (_) => TicketsController(authed, auth, MemoryCacheStore(), retryInterval: null)),
        ],
        child: MaterialApp(theme: AppTheme.light(), darkTheme: AppTheme.dark(), home: screen),
      ));
      await settle(tester);
    }

    DrawResultScreen result() => DrawResultScreen(giveawayId: gid, shakes: () => shakes.stream, runner: syncRunner);
    String seenKey() => 'u1|draw_seen:$gid';

    testWidgets('peserta, hasil baru: layar goyang muncul dan hasil belum terlihat', (tester) async {
      tickets = [ticketJson(winnersOf(verification).first, 'winner')];
      await pump(tester, result());
      expect(find.byKey(const Key('shake_gate')), findsOneWidget);
      expect(find.text('Goyangkan untuk melihat hasil'), findsOneWidget);
      expect(find.byKey(const Key('result_outcome')), findsNothing);
      expect(find.byKey(const Key('reveal_button')), findsOneWidget);
      expect(settings.values.containsKey(seenKey()), isFalse);
    });

    testWidgets('tombol alternatif "Lihat hasil" membuka hasil tanpa menunggu goyangan dan menyimpan penanda', (tester) async {
      tickets = [ticketJson(winnersOf(verification).first, 'winner')];
      await pump(tester, result());
      await tester.tap(find.byKey(const Key('reveal_button')));
      await settle(tester);
      expect(find.byKey(const Key('shake_gate')), findsNothing);
      expect(find.text('Tiketmu menang!'), findsOneWidget);
      expect(settings.values[seenKey()], '1');
    });

    testWidgets('goyangan dari sensor juga membuka hasil', (tester) async {
      tickets = [ticketJson(winnersOf(verification).first, 'winner')];
      await pump(tester, result());
      shakes.add(null);
      await settle(tester);
      expect(find.byKey(const Key('shake_gate')), findsNothing);
      expect(find.text('Tiketmu menang!'), findsOneWidget);
      expect(settings.values[seenKey()], '1');
    });

    testWidgets('sensor galat: layar goyang tetap berfungsi lewat tombol', (tester) async {
      tickets = [ticketJson(winnersOf(verification).first, 'winner')];
      await pump(tester, DrawResultScreen(giveawayId: gid, runner: syncRunner, shakes: () => Stream<void>.error(StateError('tanpa sensor'))));
      expect(find.byKey(const Key('shake_gate')), findsOneWidget);
      await tester.tap(find.byKey(const Key('reveal_button')));
      await settle(tester);
      expect(find.text('Tiketmu menang!'), findsOneWidget);
    });

    testWidgets('sudah pernah dibuka: langsung hasil, tidak minta goyang lagi', (tester) async {
      tickets = [ticketJson(winnersOf(verification).first, 'winner')];
      settings.values[seenKey()] = '1';
      await pump(tester, result());
      expect(find.byKey(const Key('shake_gate')), findsNothing);
      expect(find.text('Tiketmu menang!'), findsOneWidget);
    });

    testWidgets('dibuka ulang setelah reveal: tidak minta goyang lagi', (tester) async {
      tickets = [ticketJson(winnersOf(verification).first, 'winner')];
      await pump(tester, result());
      await tester.tap(find.byKey(const Key('reveal_button')));
      await settle(tester);
      await tester.pumpWidget(const SizedBox());
      await pump(tester, result());
      expect(find.byKey(const Key('shake_gate')), findsNothing);
      expect(find.byKey(const Key('result_outcome')), findsOneWidget);
    });

    testWidgets('bukan peserta: hasil langsung, tanpa kartu hasil tiket', (tester) async {
      await pump(tester, result());
      expect(find.byKey(const Key('shake_gate')), findsNothing);
      expect(find.byKey(const Key('result_outcome')), findsNothing);
      expect(find.text('Daftar pemenang'), findsOneWidget);
      for (final n in winnersOf(verification)) {
        expect(find.byKey(Key('result_winner_$n')), findsOneWidget);
      }
    });

    testWidgets('pemenang: hanya data dari server (nama tersamar); jumlah tiket dan waktu draw tampil', (tester) async {
      await pump(tester, result());
      expect(find.text('pe***1'), findsOneWidget);
      expect(find.text('Tiket yang ikut'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(find.text('Diundi'), findsOneWidget);
    });

    testWidgets('peserta tidak terpilih: "Tiketmu tidak terpilih", tetap bisa membuka Cek keaslian', (tester) async {
      tickets = [ticketJson(999, 'not_selected')];
      settings.values[seenKey()] = '1';
      await pump(tester, result());
      expect(find.text('Tiketmu tidak terpilih'), findsOneWidget);
      expect(find.text('Tiketmu menang!'), findsNothing);
      expect(find.byKey(const Key('open_verify')), findsOneWidget);
    });

    testWidgets('pemenang melihat baris tiketnya ditandai "Tiketmu" (teks + ikon)', (tester) async {
      final mine = winnersOf(verification).first;
      tickets = [ticketJson(mine, 'winner')];
      settings.values[seenKey()] = '1';
      await pump(tester, result());
      expect(find.descendant(of: find.byKey(Key('result_winner_$mine')), matching: find.text('Tiketmu')), findsOneWidget);
    });

    testWidgets('belum diundi: EmptyState "Belum diundi"', (tester) async {
      verification = scen('belum diundi');
      winners = winnersJson([], drawn: false);
      tickets = [ticketJson(1, 'eligible')];
      await pump(tester, result());
      expect(find.text('Belum diundi'), findsOneWidget);
      expect(find.byKey(const Key('shake_gate')), findsNothing);
    });

    testWidgets('galat jaringan: ErrorState; "Coba lagi" memuat ulang', (tester) async {
      failWith = NetworkException('Tidak ada koneksi internet.');
      await pump(tester, result());
      expect(find.text('Tidak ada koneksi internet.'), findsOneWidget);
      failWith = null;
      await tester.tap(find.text('Coba lagi'));
      await settle(tester);
      expect(find.text('Daftar pemenang'), findsOneWidget);
    });

    testWidgets('animasi dikurangi: reveal tetap bekerja tanpa konfeti', (tester) async {
      tickets = [ticketJson(winnersOf(verification).first, 'winner')];
      await pump(tester, result());
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await settle(tester);
      await tester.tap(find.byKey(const Key('reveal_button')));
      await settle(tester);
      expect(find.text('Tiketmu menang!'), findsOneWidget);
      expect(find.byType(IgnorePointer).evaluate().where((e) => e.widget is IgnorePointer && (e.widget as IgnorePointer).child is ExcludeSemantics), isEmpty);
    });

    // ---------------------------------------------------------- verifikasi
    List<VerifyStepId> orderOnScreen(WidgetTester tester) {
      final ys = {for (final id in VerifyStepId.values) id: tester.getTopLeft(find.byKey(Key('verify_step_${id.name}'))).dy};
      return (ys.keys.toList()..sort((a, b) => ys[a]!.compareTo(ys[b]!)));
    }

    testWidgets('Cek keaslian: empat langkah berurutan, semua "Lulus" (teks + ikon), ringkasan Terverifikasi', (tester) async {
      await pump(tester, DrawVerifyScreen(giveawayId: gid, runner: syncRunner), height: 3200);
      expect(orderOnScreen(tester), [VerifyStepId.commit, VerifyStepId.chain, VerifyStepId.seed, VerifyStepId.winners]);
      expect(find.text('Lulus'), findsNWidgets(4));
      expect(find.byIcon(Icons.check_circle), findsNWidgets(4));
      expect(find.descendant(of: find.byKey(const Key('verify_summary')), matching: find.text('Terverifikasi')), findsOneWidget);
      expect(find.text('Gagal'), findsNothing);
    });

    testWidgets('hasil dirusak: langkah "Gagal" (teks + ikon) dan ringkasan "Tidak cocok"', (tester) async {
      verification = scen('pemenang dipalsukan, hash blok disesuaikan');
      winners = winnersJson(winnersOf(scen('valid')));
      await pump(tester, DrawVerifyScreen(giveawayId: gid, runner: syncRunner), height: 3200);
      expect(find.text('Gagal'), findsOneWidget);
      expect(find.byIcon(Icons.cancel), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('verify_step_winners')), matching: find.text('Gagal')), findsOneWidget);
      expect(find.descendant(of: find.byKey(const Key('verify_summary')), matching: find.text('Tidak cocok')), findsOneWidget);
      expect(find.text('Terverifikasi'), findsNothing);
    });

    testWidgets('rantai putus: langkah rantai gagal dan menyebut blok', (tester) async {
      verification = scen('previous_hash putus');
      await pump(tester, DrawVerifyScreen(giveawayId: gid, runner: syncRunner), height: 3200);
      expect(find.descendant(of: find.byKey(const Key('verify_step_chain')), matching: find.text('Gagal')), findsOneWidget);
      expect(find.textContaining('Blok 2'), findsOneWidget);
    });

    testWidgets('belum diundi: dua langkah "Belum dicek", bukan Terverifikasi', (tester) async {
      verification = scen('belum diundi');
      winners = winnersJson([], drawn: false);
      await pump(tester, DrawVerifyScreen(giveawayId: gid, runner: syncRunner), height: 3200);
      expect(find.text('Belum dicek'), findsNWidgets(2));
      expect(find.text('Belum diundi'), findsOneWidget);
      expect(find.text('Terverifikasi'), findsNothing);
    });

    testWidgets('hash dipotong dengan tombol salin yang menyalin nilai penuh', (tester) async {
      final copied = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      await pump(tester, DrawVerifyScreen(giveawayId: gid, runner: syncRunner), height: 3200);
      final commitHash = (((verification['chain'] as List)[1]) as Map)['seed_hash'] as String;
      final shown = tester.widget<Text>(find.byKey(const Key('hash_commit_Hash komitmen')));
      expect(shown.data, contains('…'));
      expect(shown.data!.length, lessThan(commitHash.length));
      await tester.tap(find.byKey(const Key('copy_commit_Hash komitmen')));
      await tester.pump();
      expect(copied.single, commitHash);
    });

    testWidgets('Cek keaslian: galat jaringan -> ErrorState', (tester) async {
      failWith = NetworkException('Tidak ada koneksi internet.');
      await pump(tester, DrawVerifyScreen(giveawayId: gid, runner: syncRunner));
      expect(find.text('Tidak ada koneksi internet.'), findsOneWidget);
      expect(find.text('Coba lagi'), findsOneWidget);
    });

    test('shortHash: memotong yang panjang, membiarkan yang pendek', () {
      expect(shortHash('a' * 64), '${'a' * 8}…${'a' * 8}');
      expect(shortHash('3, 7, 12'), '3, 7, 12');
    });
  });
}
