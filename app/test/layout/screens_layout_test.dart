import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:code2ticket/core/db/rate_cache.dart' show SettingsStore;
import 'package:code2ticket/core/verify/chain_verifier.dart';
import 'package:code2ticket/features/draw/draw_result_screen.dart';
import 'package:code2ticket/features/game/chain_levels_screen.dart';
import 'package:code2ticket/features/game/chain_play_screen.dart';
import 'package:code2ticket/features/game/game_chooser_screen.dart';
import 'package:code2ticket/features/game/game_controller.dart';
import 'package:code2ticket/features/game/game_hub_screen.dart';
import 'package:code2ticket/features/game/leaderboard_screen.dart';
import 'package:code2ticket/features/game/maze.dart';
import 'package:code2ticket/features/game/maze_play_screen.dart';
import 'package:code2ticket/features/giveaways/affinity_controller.dart';
import 'package:code2ticket/features/draw/draw_verify_screen.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/location/location_service.dart';
import 'package:code2ticket/features/admin/admin_controller.dart';
import 'package:code2ticket/features/admin/admin_giveaway_screen.dart';
import 'package:code2ticket/features/admin/admin_giveaways_screen.dart';
import 'package:code2ticket/features/admin/codes_list_screen.dart';
import 'package:code2ticket/features/admin/create_giveaway_screen.dart';
import 'package:code2ticket/features/admin/generate_codes_screen.dart';
import 'package:code2ticket/features/assistant/assistant_controller.dart';
import 'package:code2ticket/features/assistant/assistant_screen.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/auth/auth_models.dart';
import 'package:code2ticket/features/auth/biometric_lock_screen.dart';
import 'package:code2ticket/features/auth/login_screen.dart';
import 'package:code2ticket/features/auth/register_screen.dart';
import 'package:code2ticket/features/converter/converter_screen.dart';
import 'package:code2ticket/features/discover/discover_controller.dart';
import 'package:code2ticket/features/discover/discover_screen.dart';
import 'package:code2ticket/features/feedback/feedback_screen.dart';
import 'package:code2ticket/features/giveaways/giveaway_detail_screen.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart';
import 'package:code2ticket/features/giveaways/home_screen.dart';
import 'package:code2ticket/features/notifications/notifications_controller.dart';
import 'package:code2ticket/features/organizer/organizer_contact.dart';
import 'package:code2ticket/features/organizer/organizer_screen.dart';
import 'package:code2ticket/features/notifications/notifications_screen.dart';
import 'package:code2ticket/features/profile/profile_screen.dart';
import 'package:code2ticket/features/profile/settings_screen.dart';
import 'package:code2ticket/features/tickets/input_code_screen.dart';
import 'package:code2ticket/features/tickets/tickets_controller.dart';
import 'package:code2ticket/features/tickets/tickets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../input_code_test.dart' show FakeApi, FakeAuth;
import '../support/display.dart';
import '../support/fake_location.dart';
import '../support/memory_cache.dart';
import '../support/memory_chat_store.dart';
import '../support/ui.dart';

/// Tata letak tanpa overflow (DESIGN.md daftar periksa 9): 360 dp, 428 dp, font sistem 1,3x, terang dan gelap.
/// Setiap layar digulir sampai habis supaya semua item (termasuk yang dibangun malas) ikut diperiksa.

Map<String, dynamic> sampleGiveaway(String id, String category, {String? title, int? ticketCount}) {
  final now = DateTime.now().toUtc();
  String iso(Duration d) => now.add(d).toIso8601String();
  return {
    'id': id,
    'title': title ?? 'Giveaway $id',
    'description': 'Deskripsi giveaway yang cukup panjang untuk menguji pembungkusan baris pada layar sempit dan font besar.',
    'organizer': 'Penyelenggara dengan Nama yang Sangat Panjang Sekali',
    'category': category,
    'prize_name': 'Hadiah utama berupa paket lengkap berukuran besar',
    'prize_value_idr': 20000000,
    'how_to_participate': 'Ikuti akun penyelenggara lalu cari kode di unggahan terbaru.\nKode juga dibagikan di stan saat acara berlangsung, jadi datang lebih awal supaya tidak kehabisan.',
    'organizer_url': 'https://www.penyelenggara-contoh.co.id/giveaway/halaman-yang-cukup-panjang',
    'latitude': -6.2,
    'longitude': 106.8,
    'address': 'Jalan Panjang Sekali Nomor 123, Kecamatan Contoh, Kota Contoh, Indonesia',
    'radius_km': 5,
    'start_at': iso(const Duration(hours: -1)),
    'end_at': iso(const Duration(hours: 2)),
    'draw_at': iso(const Duration(hours: 3, minutes: 7, seconds: 9)),
    'winner_count': 3,
    'ticket_count': ticketCount ?? 12,
    'status': 'active',
    'distance_km': 2.3,
  };
}

final sampleLongTitle = 'Giveaway dengan judul yang sangat panjang sekali sehingga harus dibungkus ke beberapa baris di layar sempit';

List<Map<String, dynamic>> sampleGiveaways() => [
      sampleGiveaway('g1', 'gaming', title: sampleLongTitle),
      sampleGiveaway('g2', 'travel'),
      sampleGiveaway('g3', 'tech'),
      sampleGiveaway('g4', 'food'),
      sampleGiveaway('g5', 'lifestyle'),
    ];

List<Map<String, dynamic>> sampleTickets() {
  final now = DateTime.now().toUtc();
  Map<String, dynamic> t(int n, String result, String gid) => {
        'id': 'tk$n',
        'ticket_number': n,
        'giveaway_id': gid,
        'giveaway_title': n == 1 ? sampleLongTitle : 'Giveaway $gid',
        'prize_name': 'Hadiah utama berupa paket lengkap berukuran besar',
        'category': n.isEven ? 'travel' : 'gaming',
        'end_at': now.add(const Duration(hours: 2)).toIso8601String(),
        'draw_at': now.add(const Duration(hours: 3)).toIso8601String(),
        'giveaway_status': 'active',
        'created_at': now.toIso8601String(),
        'result': result,
        'code_masked': '****-****-AB12',
      };
  return [t(1, 'eligible', 'g1'), t(123456, 'waiting_for_draw', 'g1'), t(3, 'winner', 'g2'), t(4, 'not_selected', 'g3')];
}

List<Map<String, dynamic>> sampleNotifications() {
  final now = DateTime.now().toUtc().toIso8601String();
  Map<String, dynamic> n(int id, String type, String title, {bool read = false, String? gid = 'g1'}) => {
        'id': id, 'type': type, 'title': title, 'is_read': read, 'giveaway_id': gid, 'created_at': now,
        'body': 'Tiket #000012 memenangkan Hadiah utama berupa paket lengkap berukuran besar pada undian $sampleLongTitle.',
      };
  return [
    n(5, 'winner', 'Selamat, kamu menang!'),
    n(4, 'draw_result', 'Hasil undian sudah keluar', read: true),
    n(3, 'ticket_created', 'Tiket berhasil dibuat', gid: null),
    n(2, 'reminder', 'Draw sebentar lagi'),
    n(1, 'jenis_baru_tak_dikenal', 'Info umum', read: true, gid: null),
  ];
}

AppUser sampleUser({String role = 'user'}) => AppUser(
      id: 'u1',
      username: 'pengguna_dengan_username_panjang',
      email: 'alamat.email.yang.sangat.panjang@contoh-domain-panjang.co.id',
      fullName: 'Nama Lengkap Pengguna yang Sangat Panjang Sekali',
      role: role,
      xp: 1234,
      level: 3,
      badges: ['first_ticket', 'early_bird'],
    );

/// Auth palsu tanpa akses biometric/SQLite perangkat.
class SampleAuth extends FakeAuth {
  SampleAuth(super.api);
  @override
  Future<bool> isBiometricAvailable() async => false;
  @override
  Future<bool> isBiometricEnabled({String? userId}) async => false;
}

class SampleEnv {
  SampleEnv() {
    api = FakeApi((m, p, b) async {
      await beforeResponse?.call(p);
      if (p.startsWith('/app-config/organizer')) return {...organizer};
      if (p.startsWith('/me/affinity')) return {...affinity};
      if (p.startsWith('/game/leaderboard')) {
        return {
          'ok': true,
          'data': [
            {'rank': 1, 'username': 'ab***', 'level': 4, 'total_score': 12000},
            {'rank': 2, 'username': 'pengguna_dengan_username_panjang', 'level': 3, 'total_score': 9800},
            {'rank': 3, 'username': 'cd***', 'level': 1, 'total_score': 700},
            {'rank': 4, 'username': 'ef***', 'level': 1, 'total_score': 300},
          ],
        };
      }
      if (p == '/game/scores') {
        return {'ok': true, 'score': 700, 'xp_earned': 70, 'daily_xp_total': 70, 'daily_cap_reached': false, 'user': {'id': 'u1', 'username': 'pengguna_dengan_username_panjang', 'email': 'a@b.co', 'full_name': 'Nama', 'role': 'user', 'xp': 100, 'level': 1, 'badges': <String>[]}};
      }
      if (p.endsWith('/winners')) return {'ok': true, 'drawn': true, 'winners': [for (var i = 0; i < drawWinners.length; i++) {'rank': i + 1, 'ticket_number': drawWinners[i], 'name': 'pe***${i + 1}'}]};
      if (p.endsWith('/verification')) return {'ok': true, ...drawVerification};
      if (p.startsWith('/giveaways/')) return {...sampleGiveaways().first, 'status': giveawayStatus, ...giveawayExtra};
      if (p.startsWith('/giveaways')) return {'ok': true, 'data': sampleGiveaways()};
      if (p.startsWith('/tickets')) return {'ok': true, 'data': List.of(tickets)};
      if (p.startsWith('/admin/giveaways/')) {
        if (m == 'GET') {
          return {
            'ok': true,
            'data': [
              {'code': 'ABCD-EFGH-JKLM', 'is_used': false, 'used_at': null, 'geo_radius_km': null},
              {'code': 'NPQR-STUV-WXYZ', 'is_used': true, 'used_at': DateTime.now().toUtc().toIso8601String(), 'geo_radius_km': '5.00'},
            ],
          };
        }
        return {'ok': true, 'codes': ['ABCD-EFGH-JKLM', 'NPQR-STUV-WXYZ', 'A2B3-C4D5-E6F7']};
      }
      if (p.startsWith('/notifications/read')) return {'ok': true, 'updated': 1};
      if (p.startsWith('/notifications')) return {'ok': true, 'data': sampleNotifications()};
      if (p.startsWith('/feedback')) {
        return {
          'ok': true,
          'data': [
            {'id': 1, 'suggestion': 'Saran yang cukup panjang ' * 6, 'impression': 'Kesan yang cukup panjang ' * 6, 'created_at': DateTime.now().toUtc().toIso8601String()},
          ],
        };
      }
      return {'ok': true};
    });
    auth = SampleAuth(api)..user = sampleUser();
    authed = AuthedApi(api, auth);
  }
  /// Isi GET /app-config/organizer; tes boleh mengubahnya sebelum layar dibuka.
  Map<String, dynamic> organizer = {'ok': true, 'email': 'admin@example.test', 'note': null};

  /// Dipanggil sebelum tiap jawaban API (tes boleh menahan atau melempar galat untuk jalur tertentu).
  Future<void> Function(String path)? beforeResponse;

  /// Isi GET /me/affinity ({kategori: skor}); kosong = tanpa "Untuk kamu".
  Map<String, dynamic> affinity = {};

  /// Field tambahan/penimpa untuk jawaban GET /giveaways/:id (mis. cara ikut kosong).
  Map<String, dynamic> giveawayExtra = {};

  /// Status giveaway yang dijawab GET /giveaways/:id (tes boleh mengubahnya sebelum layar dibuka).
  String giveawayStatus = 'active';

  /// Penanda "hasil sudah dilihat" dan data hasil draw (diambil dari vektor acuan Python).
  final settings = MemorySettings();
  late final Map<String, dynamic> drawVerification = jsonDecode(jsonEncode((jsonDecode(File('test/fixtures/m1_vectors.json').readAsStringSync())['scenarios'] as List).first['data'])) as Map<String, dynamic>;
  late final List<int> drawWinners = verifyData(VerificationData.tryParse(drawVerification)!).winningTickets;

  late final FakeApi api;
  late final SampleAuth auth;
  late final AuthedApi authed;

  /// Isi GET /tickets; tes boleh mengubahnya sebelum layar dibuka.
  final tickets = sampleTickets();

  Widget app(Widget home) => wrap(themedApp(home));

  /// Membungkus [child] dengan semua provider yang dipakai layar.
  Widget wrap(Widget child) => MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<AuthedApi>.value(value: authed),
          Provider<SettingsStore>.value(value: settings),
          Provider<LocationService>.value(value: LocationService(FakeGateway())),
          ...displayProviders(),
          ChangeNotifierProvider(create: (_) => OrganizerContactController(authed, settings)),
          ChangeNotifierProvider(create: (_) => GiveawaysController(authed, auth, MemoryCacheStore(), retryInterval: null)),
          ChangeNotifierProvider(create: (_) => TicketsController(authed, auth, MemoryCacheStore(), retryInterval: null)),
          ChangeNotifierProvider(create: (_) => NotificationsController(authed, auth)),
          ChangeNotifierProvider(create: (_) => AdminController(authed, auth)),
          ChangeNotifierProvider(create: (_) => GameController(authed, auth)),
          ChangeNotifierProvider(create: (_) => AffinityController(authed, auth)),
          ChangeNotifierProvider(create: (_) => AssistantController(authed, auth, MemoryChatStore())),
          ChangeNotifierProvider(
              create: (_) => DiscoverController(authed, auth, MemoryCacheStore(), LocationService(FakeGateway()), retryInterval: null)),
        ],
        child: child,
      );
}

Future<VerificationReport?> _syncVerify(({Map<String, dynamic> raw, List<int>? announced}) a) async => verifyRaw(a);

/// Menggulir layar pertama sampai habis dan memastikan tidak ada galat tata letak.
Future<void> _scrollThrough(WidgetTester tester) async {
  final scrollable = find.byType(Scrollable);
  if (scrollable.evaluate().isEmpty) return;
  for (var i = 0; i < 14; i++) {
    await tester.drag(scrollable.first, const Offset(0, -420), warnIfMissed: false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull, reason: 'setelah menggulir ke-${i + 1}');
  }
}

void main() {
  // Tiap layar: pembangun + teks yang harus tampil (membuktikan layar benar-benar terisi, bukan masih kerangka).
  final screens = <String, (Widget Function(), String)>{
    'Home': (() => const HomeScreen(), 'Menu fitur'),
    'Detail Giveaway': (() => GiveawayDetailScreen(giveawayId: 'g1', initial: Giveaway.tryParse(sampleGiveaways().first)), 'Input Code'),
    'My Tickets': (() => const TicketsScreen(), '#123456'),
    'Notifikasi': (() => const NotificationsScreen(), 'Hasil draw sudah keluar'),
    'Admin': (() => const AdminGiveawaysScreen(), 'Buat giveaway'),
    'Buat Giveaway': (() => const CreateGiveawayScreen(), 'Informasi'),
    'Kelola Giveaway': (() => AdminGiveawayScreen(giveawayId: 'g1', initial: Giveaway.tryParse(sampleGiveaways().first)), 'Generate Code'),
    'Generate Code': (() => const GenerateCodesScreen(giveawayId: 'g1'), 'Buat kode'),
    'Daftar Kode': (() => const CodesListScreen(giveawayId: 'g1'), 'ABCD-EFGH-JKLM'),
    'Asisten': (() => const AssistantScreen(), 'Ada giveaway gaming apa?'),
    'Pilih game': (() => const GameChooserScreen(), 'Rakit Rantai'),
    'Code Hunt (hub)': (() => const GameHubScreen(), 'Pilih tingkat'),
    'Papan Peringkat': (() => const LeaderboardScreen(), 'Skor total 7 hari terakhir'),
    'Rakit Rantai (level)': (() => const ChainLevelsScreen(), 'Pilih level'),
    'Rakit Rantai (susun)': (() => const ChainPlayScreen(levelNumber: 3), 'Langkah: 0'),
    'Rakit Rantai (periksa)': (() => const ChainPlayScreen(levelNumber: 5), 'Percobaan: 0'),
    'Maze (siap)': (() => MazePlayScreen(levelIndex: 2, seed: 1, tilt: () => const Stream.empty()), 'Siap?'),
    'Cek Keaslian': (() => DrawVerifyScreen(giveawayId: 'g1', runner: _syncVerify), 'Seed dikunci sebelum tiket terbit'),
    'Profil': (() => const ProfileScreen(), 'Level 3'),
    'Login': (() => const LoginScreen(), 'Belum punya akun? Daftar'),
    'Daftar': (() => const RegisterScreen(), 'Sudah punya akun? Masuk'),
    'Kunci biometric': (() => const BiometricLockScreen(), 'Aplikasi Terkunci'),
    'Konverter': (() => const ConverterScreen(), 'Mata Uang'),
    'Pengaturan': (() => const SettingsScreen(), 'Mata uang default'),
    'Untuk Penyelenggara': (() => const OrganizerScreen(), 'Cara kerjanya'),
    'Saran & Kesan': (() => const FeedbackScreen(), 'Riwayat kirimanmu'),
    'Discover': (() => const DiscoverScreen(), 'Discover'),
    'Input Code': (() => const InputCodeScreen(), 'Tukar kode'),
  };

  testWidgets('pendeteksi overflow bekerja: widget yang meluap memang dilaporkan', (tester) async {
    await setViewport(tester);
    await tester.pumpWidget(themedApp(const Scaffold(body: Row(children: [SizedBox(width: 500, height: 10)]))));
    expect(tester.takeException(), isNotNull);
  });

  for (final v in layoutVariants) {
    group('tata letak: ${v.name}', () {
      for (final e in screens.entries) {
        testWidgets(e.key, (tester) async {
          await setViewport(tester, width: v.width, textScale: v.scale, brightness: v.brightness);
          final env = SampleEnv();
          await tester.pumpWidget(env.app(e.value.$1()));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: '${e.key} ${v.name}');
          expect(find.text(e.value.$2), findsWidgets, reason: '${e.key} harus terisi');
          await _scrollThrough(tester);
          await tester.pumpWidget(const SizedBox()); // hentikan timer (hitung mundur)
        });
      }

      // Layar goyang beranimasi tanpa henti, jadi tidak memakai pumpAndSettle.
      Future<void> frames(WidgetTester tester) async {
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      testWidgets('Hasil Draw: layar goyang', (tester) async {
        await setViewport(tester, width: v.width, textScale: v.scale, brightness: v.brightness);
        final env = SampleEnv();
        await tester.pumpWidget(env.app(DrawResultScreen(giveawayId: 'g1', runner: _syncVerify, shakes: () => const Stream<void>.empty())));
        await frames(tester);
        expect(find.text('Goyangkan untuk melihat hasil'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _scrollThrough(tester);
        await tester.tap(find.byKey(const Key('reveal_button')));
        await frames(tester);
        expect(find.text('Daftar pemenang'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _scrollThrough(tester);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Hasil Draw: hasil (sudah dilihat)', (tester) async {
        await setViewport(tester, width: v.width, textScale: v.scale, brightness: v.brightness);
        final env = SampleEnv();
        env.settings.values['u1|draw_seen:g1'] = '1';
        await tester.pumpWidget(env.app(DrawResultScreen(giveawayId: 'g1', runner: _syncVerify, shakes: () => const Stream<void>.empty())));
        await frames(tester);
        expect(find.text('Daftar pemenang'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _scrollThrough(tester);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Maze: hasil waktu habis di tingkat sulit', (tester) async {
        await setViewport(tester, width: v.width, textScale: v.scale, brightness: v.brightness);
        final env = SampleEnv();
        await tester.pumpWidget(env.app(MazePlayScreen(levelIndex: 2, seed: 1, tilt: () => const Stream.empty())));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('maze_start')));
        await tester.pump();
        for (var i = 0; i < 20 * 55; i++) {
          await tester.pump(const Duration(milliseconds: 50));
        }
        await tester.pumpAndSettle();
        expect(find.text('Waktu habis'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _scrollThrough(tester);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Maze: Tiket Latihan setelah selesai di tingkat sulit (12 segmen)', (tester) async {
        await setViewport(tester, width: v.width, textScale: v.scale, brightness: v.brightness);
        final env = SampleEnv();
        await tester.pumpWidget(env.app(MazePlayScreen(levelIndex: 2, seed: 1, tilt: () => const Stream.empty())));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('maze_start')));
        await tester.pump();
        final path = Maze.generate(10, 10, Random(1), stars: 12).solve()!;
        for (var i = 1; i < path.length; i++) {
          final d = Dir.values.firstWhere((d) => path[i - 1].$1 + d.dx == path[i].$1 && path[i - 1].$2 + d.dy == path[i].$2);
          await tester.tap(find.byKey(Key('dpad_${d.name}')));
          await tester.pump();
        }
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('practice_ticket')), findsOneWidget);
        expect(find.text('Tiket latihan: tidak memengaruhi peluang menang'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _scrollThrough(tester);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Home: bagian "Untuk kamu"', (tester) async {
        await setViewport(tester, width: v.width, textScale: v.scale, brightness: v.brightness);
        final env = SampleEnv()..affinity = {'travel': 5, 'gaming': 2};
        await tester.pumpWidget(env.app(const HomeScreen()));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Untuk kamu'), 200, scrollable: find.byType(Scrollable).first);
        expect(find.text('Untuk kamu'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _scrollThrough(tester);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Generate Code: hasil (peringatan, kode, salin)', (tester) async {
        await setViewport(tester, width: v.width, textScale: v.scale, brightness: v.brightness);
        final env = SampleEnv();
        await tester.pumpWidget(env.app(const GenerateCodesScreen(giveawayId: 'g1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('generate_codes')));
        await tester.pumpAndSettle();
        expect(find.text('ABCD-EFGH-JKLM'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _scrollThrough(tester);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Kelola Giveaway: dialog konfirmasi draw', (tester) async {
        await setViewport(tester, width: v.width, textScale: v.scale, brightness: v.brightness);
        final env = SampleEnv();
        await tester.pumpWidget(env.app(AdminGiveawayScreen(giveawayId: 'g1', initial: Giveaway.tryParse(sampleGiveaways().first))));
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.byKey(const Key('run_draw')), 200, scrollable: find.byType(Scrollable).first);
        await tester.tap(find.byKey(const Key('run_draw')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('draw_confirm')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('Input Code: hasil sukses (TicketCard + nomor besar)', (tester) async {
        await setViewport(tester, width: v.width, textScale: v.scale, brightness: v.brightness);
        final env = SampleEnv();
        final api = FakeApi((m, p, b) async => {
              'ok': true,
              'ticket': {
                'id': 't1',
                'ticket_number': 123456,
                'giveaway_id': 'g1',
                'giveaway_title': sampleLongTitle,
                'prize_name': 'Hadiah utama berupa paket lengkap berukuran besar',
                'draw_at': DateTime.now().add(const Duration(hours: 3)).toUtc().toIso8601String(),
                'result': 'eligible',
              },
            });
        final auth = FakeAuth(api);
        await tester.pumpWidget(MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthController>.value(value: auth),
            Provider<LocationService>.value(value: LocationService(FakeGateway())),
            ...displayProviders(),
            ChangeNotifierProvider(create: (_) => TicketsController(AuthedApi(api, auth), auth, MemoryCacheStore(), retryInterval: null)),
          ],
          child: themedApp(const InputCodeScreen()),
        ));
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(const Key('code_field')), 'ABCDEFGHJKLM');
        await tester.tap(find.byKey(const Key('submit_code')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('ticket_number')), findsOneWidget);
        expect(tester.takeException(), isNull);
        await _scrollThrough(tester);
        await tester.pumpWidget(const SizedBox());
        expect(env.api.calls, isEmpty);
      });
    });
  }
}
