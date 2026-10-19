import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/location/location_service.dart';
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
    'prize_value_usd': 1200,
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

AppUser sampleUser() => AppUser(
      id: 'u1',
      username: 'pengguna_dengan_username_panjang',
      email: 'alamat.email.yang.sangat.panjang@contoh-domain-panjang.co.id',
      fullName: 'Nama Lengkap Pengguna yang Sangat Panjang Sekali',
      role: 'user',
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
      if (p.startsWith('/giveaways/')) return sampleGiveaways().first;
      if (p.startsWith('/giveaways')) return {'ok': true, 'data': sampleGiveaways()};
      if (p.startsWith('/tickets')) return {'ok': true, 'data': List.of(tickets)};
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
          Provider<LocationService>.value(value: LocationService(FakeGateway())),
          ...displayProviders(),
          ChangeNotifierProvider(create: (_) => GiveawaysController(authed, auth, MemoryCacheStore(), retryInterval: null)),
          ChangeNotifierProvider(create: (_) => TicketsController(authed, auth, MemoryCacheStore(), retryInterval: null)),
          ChangeNotifierProvider(
              create: (_) => DiscoverController(authed, auth, MemoryCacheStore(), LocationService(FakeGateway()), retryInterval: null)),
        ],
        child: child,
      );
}

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
    'Home': (() => const HomeScreen(), 'Segera draw'),
    'Detail Giveaway': (() => GiveawayDetailScreen(giveawayId: 'g1', initial: Giveaway.tryParse(sampleGiveaways().first)), 'Input Code'),
    'My Tickets': (() => const TicketsScreen(), '#123456'),
    'Profil': (() => const ProfileScreen(), 'Level 3'),
    'Login': (() => const LoginScreen(), 'Belum punya akun? Daftar'),
    'Daftar': (() => const RegisterScreen(), 'Sudah punya akun? Masuk'),
    'Kunci biometric': (() => const BiometricLockScreen(), 'Aplikasi Terkunci'),
    'Konverter': (() => const ConverterScreen(), 'Mata Uang'),
    'Pengaturan': (() => const SettingsScreen(), 'Mata uang default'),
    'Saran & Kesan': (() => const FeedbackScreen(), 'Riwayat kirimanmu'),
    'Discover': (() => const DiscoverScreen(), 'Terdekat'),
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
