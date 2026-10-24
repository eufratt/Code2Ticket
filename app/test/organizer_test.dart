import 'dart:async';
import 'dart:convert';

import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/open_link.dart';
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/features/giveaways/giveaway_card.dart';
import 'package:code2ticket/features/giveaways/home_screen.dart';
import 'package:code2ticket/features/organizer/organizer_contact.dart';
import 'package:code2ticket/features/organizer/organizer_screen.dart';
import 'package:code2ticket/features/profile/profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'layout/screens_layout_test.dart' show SampleEnv;
import 'support/ui.dart';

// Layar "Untuk Penyelenggara": panduan, kontak email dari server, mailto, offline, dan dua pintu masuk (Profil, Home).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final opened = <Uri>[];
  late bool openResult;
  final original = openExternal;
  setUp(() {
    opened.clear();
    openResult = true;
    openExternal = (u) async {
      opened.add(u);
      return openResult;
    };
  });
  tearDown(() => openExternal = original);

  Future<SampleEnv> pumpScreen(
    WidgetTester tester, {
    Map<String, dynamic>? organizer,
    SampleEnv? env,
    Brightness b = Brightness.light,
    double scale = 1.0,
  }) async {
    await setViewport(tester, height: 3200, brightness: b, textScale: scale);
    env ??= SampleEnv();
    if (organizer != null) env.organizer = organizer;
    await tester.pumpWidget(env.app(const OrganizerScreen()));
    await tester.pumpAndSettle();
    return env;
  }

  group('panduan', () {
    for (final b in Brightness.values) {
      testWidgets('isi panduan tampil, tombol >= 48 dp, tanpa overflow (${b.name}, font 1,3x)', (tester) async {
        await pumpScreen(tester, b: b, scale: 1.3);
        expect(find.text('Untuk Penyelenggara'), findsOneWidget); // judul AppBar
        expect(find.text('Punya giveaway? Jalankan drawnya di Code2Ticket.'), findsOneWidget);
        expect(find.text('Cara kerjanya'), findsOneWidget);
        expect(find.text('Hubungi admin lewat email dan kirim data giveaway.'), findsOneWidget);
        expect(find.text('Admin membuat giveaway dan kode untukmu.'), findsOneWidget);
        expect(find.textContaining('kamu yang menentukan cara peserta mendapatkannya'), findsOneWidget);
        expect(find.text('Draw berjalan otomatis pada jadwal dan pemenang tampil di aplikasi.'), findsOneWidget);
        expect(find.text('Data yang perlu kamu siapkan'), findsOneWidget);
        for (final t in ['Nama dan deskripsi giveaway', 'Kategori', 'Nama hadiah dan nilainya (Rp)', 'Periode (mulai, berakhir)', 'Jadwal draw', 'Jumlah pemenang', 'Batas tiket per peserta', 'Jumlah kode yang dibutuhkan', 'Cara mendapatkan kode dan tautan penyelenggara (opsional)', 'Lokasi dan radius bila tukar kode dibatasi area']) {
          expect(find.text(t), findsOneWidget, reason: t);
        }
        expect(find.text('Hasil draw tercatat di rantai hash yang dapat diperiksa siapa pun.'), findsOneWidget);
        await tester.scrollUntilVisible(find.byKey(const Key('contact_admin_email')), 200);
        expect(tester.getSize(find.byKey(const Key('contact_admin_email'))).height, greaterThanOrEqualTo(48));
        expect(tester.takeException(), isNull);
      });
    }
  });

  group('kontak email', () {
    testWidgets('tombol hanya bila email ada; catatan tampil di dekat tombol', (tester) async {
      await pumpScreen(tester, organizer: {'ok': true, 'email': 'admin@example.test', 'note': 'Dibalas 2 hari kerja.'});
      expect(find.byKey(const Key('contact_admin_email')), findsOneWidget);
      expect(find.text('Hubungi admin lewat email'), findsOneWidget);
      expect(find.text('Dibalas 2 hari kerja.'), findsOneWidget);
      expect(find.byKey(const Key('contact_unavailable')), findsNothing);
    });

    for (final r in <String, Map<String, dynamic>>{
      'kosong': {'ok': true, 'email': null, 'note': null},
      'email kosong tapi catatan ada': {'ok': true, 'email': '', 'note': 'Catatan'},
      'email tidak valid': {'ok': true, 'email': 'bukan-email', 'note': null},
      'ok:false': {'ok': false, 'error': 'not_found'},
    }.entries) {
      testWidgets('kontak ${r.key} -> pesan, tanpa tombol, panduan tetap tampil', (tester) async {
        await pumpScreen(tester, organizer: r.value);
        expect(find.text('Kontak admin belum tersedia. Coba lagi nanti.'), findsOneWidget);
        expect(find.byKey(const Key('contact_admin_email')), findsNothing);
        expect(find.byKey(const Key('contact_note')), findsNothing);
        expect(find.text('Cara kerjanya'), findsOneWidget);
      });
    }

    testWidgets('dialog konfirmasi: Batal tidak membuka; Buka membuka mailto dengan subjek dan isi ter-encode', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('contact_admin_email')));
      await tester.pumpAndSettle();
      expect(find.text('Tujuan: admin@example.test'), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);

      await tester.tap(find.byKey(const Key('contact_admin_email')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_open_mail')));
      await tester.pumpAndSettle();
      final uri = opened.single;
      expect(uri.scheme, 'mailto');
      expect(uri.path, 'admin@example.test');
      final raw = uri.toString();
      expect(raw, startsWith('mailto:admin@example.test?subject=Permintaan%20membuat%20giveaway%20di%20Code2Ticket&body='));
      expect(raw, isNot(contains(' ')));
      expect(raw, isNot(contains('\n')));
      expect(raw, isNot(contains('+')));
      expect(raw, contains('%0D%0A'));
      final q = Uri.splitQueryString(raw.substring(raw.indexOf('?') + 1), encoding: utf8);
      expect(q['subject'], 'Permintaan membuat giveaway di Code2Ticket');
      expect(q['body'], organizerMailBody());
      for (final f in ['Nama giveaway', 'Nilai hadiah (Rp)', 'Jadwal draw', 'Jumlah kode yang dibutuhkan', 'Tautan penyelenggara (opsional)']) {
        expect(q['body'], contains('$f:'));
      }
    });

    testWidgets('gagal membuka -> snackbar', (tester) async {
      openResult = false;
      await pumpScreen(tester);
      await tester.tap(find.byKey(const Key('contact_admin_email')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_open_mail')));
      await tester.pumpAndSettle();
      expect(find.text('Tidak bisa membuka aplikasi email.'), findsOneWidget);
    });
  });

  group('offline', () {
    testWidgets('tanpa simpanan: panduan tetap tampil, pesan kontak tidak tersedia, tanpa tombol', (tester) async {
      final env = SampleEnv()..beforeResponse = (p) async => p.startsWith('/app-config') ? throw NetworkException('Tidak ada koneksi internet.') : null;
      await pumpScreen(tester, env: env);
      expect(find.text('Cara kerjanya'), findsOneWidget);
      expect(find.text('Hasil draw tercatat di rantai hash yang dapat diperiksa siapa pun.'), findsOneWidget);
      expect(find.text('Kontak admin belum tersedia. Coba lagi nanti.'), findsOneWidget);
      expect(find.byKey(const Key('contact_admin_email')), findsNothing);
    });

    testWidgets('online menyimpan kontak; kemudian offline memakai simpanan terakhir', (tester) async {
      final env = await pumpScreen(tester, organizer: {'ok': true, 'email': 'admin@example.test', 'note': 'Catatan'});
      expect(env.settings.values['|${OrganizerContactController.cacheKey}'], contains('admin@example.test'));
      await tester.pumpWidget(const SizedBox());

      env.beforeResponse = (p) async => p.startsWith('/app-config') ? throw NetworkException('Tidak ada koneksi internet.') : null;
      await tester.pumpWidget(env.app(const OrganizerScreen()));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('contact_admin_email')), findsOneWidget);
      expect(find.text('Catatan'), findsOneWidget);
    });

    testWidgets('server menjawab kosong menghapus simpanan lama', (tester) async {
      final env = await pumpScreen(tester);
      expect(env.settings.values, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
      env.organizer = {'ok': true, 'email': null, 'note': null};
      await tester.pumpWidget(env.app(const OrganizerScreen()));
      await tester.pumpAndSettle();
      expect(env.settings.values['|${OrganizerContactController.cacheKey}'], isNull);
      expect(find.byKey(const Key('contact_admin_email')), findsNothing);
    });

    testWidgets('simpanan rusak atau penyimpanan gagal tidak membuat crash', (tester) async {
      final env = SampleEnv()
        ..settings.values['|${OrganizerContactController.cacheKey}'] = '{bukan json'
        ..beforeResponse = (p) async => p.startsWith('/app-config') ? throw NetworkException('x') : null;
      await pumpScreen(tester, env: env);
      expect(find.text('Kontak admin belum tersedia. Coba lagi nanti.'), findsOneWidget);
      env.settings.failing = true;
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(env.app(const OrganizerScreen()));
      await tester.pumpAndSettle();
      expect(find.text('Kontak admin belum tersedia. Coba lagi nanti.'), findsOneWidget);
    });
  });

  test('OrganizerContact.tryParse memeriksa ulang email dan catatan', () {
    expect(OrganizerContact.tryParse({'email': ' a@b.co ', 'note': ' hai '})!.email, 'a@b.co');
    expect(OrganizerContact.tryParse({'email': 'a@b.co', 'note': ' hai '})!.note, 'hai');
    expect(OrganizerContact.tryParse({'email': 'a@b.co', 'note': 'x' * 301})!.note, isNull);
    for (final bad in [null, 'a@b', 'a b@c.co', '@b.co', 'a\nb@c.co', '${'a' * 250}@b.co', 5]) {
      expect(OrganizerContact.tryParse({'email': bad}), isNull, reason: '$bad');
    }
    expect(OrganizerContact.tryParse(null), isNull);
  });

  group('pintu masuk', () {
    Future<void> pumpRouted(WidgetTester tester, SampleEnv env, String start) async {
      final router = GoRouter(initialLocation: start, routes: [
        GoRoute(path: '/home', builder: (_, _) => const HomeScreen()),
        GoRoute(path: '/profile', builder: (_, _) => const ProfileScreen()),
        GoRoute(path: '/organizer', builder: (_, _) => const OrganizerScreen()),
        GoRoute(path: '/settings', builder: (_, _) => const Scaffold(body: Text('PENGATURAN'))),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(env.wrap(MaterialApp.router(theme: AppTheme.light(), darkTheme: AppTheme.dark(), routerConfig: router)));
      await tester.pumpAndSettle();
    }

    testWidgets('Profil: item "Untuk Penyelenggara" membuka layar', (tester) async {
      await setViewport(tester, height: 1800);
      await pumpRouted(tester, SampleEnv(), '/profile');
      final item = find.byKey(const Key('open_organizer'));
      await tester.scrollUntilVisible(item, 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Untuk Penyelenggara'), findsOneWidget);
      expect(tester.getSize(item).height, greaterThanOrEqualTo(48));
      await tester.tap(item);
      await tester.pumpAndSettle();
      expect(find.text('Cara kerjanya'), findsOneWidget);
    });

    testWidgets('Home: kartu di bawah daftar, "Pelajari" membuka layar', (tester) async {
      await setViewport(tester, height: 2400);
      await pumpRouted(tester, SampleEnv(), '/home');
      final card = find.byKey(const Key('home_organizer_card'));
      await tester.scrollUntilVisible(card, 300, scrollable: find.byType(Scrollable).first);
      expect(find.text('Punya giveaway? Jalankan drawnya di Code2Ticket.'), findsOneWidget);
      expect(tester.getTopLeft(card).dy, greaterThan(tester.getBottomLeft(find.byType(GiveawayCard).last).dy));
      expect(tester.getSize(find.byKey(const Key('home_organizer_learn'))).height, greaterThanOrEqualTo(48));
      await tester.tap(find.byKey(const Key('home_organizer_learn')));
      await tester.pumpAndSettle();
      expect(find.text('Cara kerjanya'), findsOneWidget);
    });

    testWidgets('Home: kartu tidak tampil saat memuat', (tester) async {
      await setViewport(tester, height: 1800);
      final gate = Completer<void>();
      final env = SampleEnv()..beforeResponse = (p) => p.startsWith('/giveaways') ? gate.future : Future.value();
      await pumpRouted0(tester, env);
      expect(find.byKey(const Key('home_organizer_card')), findsNothing);
      expect(find.text('Menu fitur'), findsNothing);
      gate.complete();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('Home: kartu tidak tampil saat galat (ErrorState)', (tester) async {
      await setViewport(tester, height: 1800);
      final env = SampleEnv()..beforeResponse = (p) async => p.startsWith('/giveaways') ? throw ServerFaultException('Server rusak.') : null;
      await pumpRouted0(tester, env, settle: true);
      expect(find.text('Coba lagi'), findsOneWidget);
      expect(find.byKey(const Key('home_organizer_card')), findsNothing);
    });
  });
}

/// Home langsung (tanpa router): kartu dicek saat memuat dan galat; navigasi dicek di grup "pintu masuk".
Future<void> pumpRouted0(WidgetTester tester, SampleEnv env, {bool settle = false}) async {
  await tester.pumpWidget(env.app(const HomeScreen()));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

