import 'package:code2ticket/core/display.dart';
import 'package:code2ticket/core/settings/settings_controller.dart';
import 'package:code2ticket/core/time/zones.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/display.dart';

void main() {
  setUpAll(initTimeZones);

  group('formatInZone: keempat zona', () {
    final oct = DateTime.utc(2026, 10, 19, 20, 29); // London masih BST sampai 25 Okt 2026
    test('WIB, WITA, WIT, London pada 19 Okt 2026 20.29 UTC', () {
      expect(formatInZone(oct, AppZone.wib), '20 Okt 2026, 03.29 WIB');
      expect(formatInZone(oct, AppZone.wita), '20 Okt 2026, 04.29 WITA');
      expect(formatInZone(oct, AppZone.wit), '20 Okt 2026, 05.29 WIT');
      expect(formatInZone(oct, AppZone.london), '19 Okt 2026, 21.29 BST');
    });

    test('London musim dingin = GMT (UTC+0), musim panas = BST (UTC+1)', () {
      final winter = DateTime.utc(2026, 1, 15, 12);
      final summer = DateTime.utc(2026, 7, 15, 12);
      expect(formatInZone(winter, AppZone.london), '15 Jan 2026, 12.00 GMT');
      expect(formatInZone(summer, AppZone.london), '15 Jul 2026, 13.00 BST');
      expect(formatOffset(winter, AppZone.london), 'UTC+0');
      expect(formatOffset(summer, AppZone.london), 'UTC+1');
      expect(zoneAbbreviation(winter, AppZone.london), 'GMT');
      expect(zoneAbbreviation(summer, AppZone.london), 'BST');
    });

    test('zona Indonesia tidak mengenal musim panas: offset tetap sepanjang tahun', () {
      for (final m in [1, 7]) {
        final t = DateTime.utc(2026, m, 15, 0);
        expect(formatOffset(t, AppZone.wib), 'UTC+7');
        expect(formatOffset(t, AppZone.wita), 'UTC+8');
        expect(formatOffset(t, AppZone.wit), 'UTC+9');
      }
    });

    test('pergantian waktu London: 29 Mar 2026 01.00 UTC (maju) dan 25 Okt 2026 01.00 UTC (mundur)', () {
      expect(formatInZone(DateTime.utc(2026, 3, 29, 0, 59), AppZone.london), '29 Mar 2026, 00.59 GMT');
      expect(formatInZone(DateTime.utc(2026, 3, 29, 1, 0), AppZone.london), '29 Mar 2026, 02.00 BST');
      expect(formatInZone(DateTime.utc(2026, 10, 25, 0, 59), AppZone.london), '25 Okt 2026, 01.59 BST');
      expect(formatInZone(DateTime.utc(2026, 10, 25, 1, 0), AppZone.london), '25 Okt 2026, 01.00 GMT');
    });

    test('tidak bergantung zona perangkat: DateTime lokal dan UTC menghasilkan teks yang sama', () {
      final utc = DateTime.utc(2026, 10, 19, 20, 29);
      expect(formatInZone(utc.toLocal(), AppZone.wib), formatInZone(utc, AppZone.wib));
    });

    test('draw 20.00 WIB = 21.00 WITA = 22.00 WIT (TC-36)', () {
      final draw = instantFromWallClock(AppZone.wib, 2026, 10, 20, 20, 0);
      expect(draw, DateTime.utc(2026, 10, 20, 13));
      expect(formatInZone(draw, AppZone.wita), contains('21.00 WITA'));
      expect(formatInZone(draw, AppZone.wit), contains('22.00 WIT'));
    });
  });

  group('instantFromWallClock (Konverter waktu)', () {
    test('jam dinding di setiap zona -> instan UTC yang benar', () {
      expect(instantFromWallClock(AppZone.wib, 2026, 10, 19, 10, 0), DateTime.utc(2026, 10, 19, 3));
      expect(instantFromWallClock(AppZone.wit, 2026, 10, 19, 10, 0), DateTime.utc(2026, 10, 19, 1));
      expect(instantFromWallClock(AppZone.london, 2026, 7, 15, 12, 0), DateTime.utc(2026, 7, 15, 11)); // BST
      expect(instantFromWallClock(AppZone.london, 2026, 1, 15, 12, 0), DateTime.utc(2026, 1, 15, 12)); // GMT
    });

    test('12.00 London (musim panas) ditampilkan 18.00 WIB; di musim dingin 19.00 WIB', () {
      expect(formatInZone(instantFromWallClock(AppZone.london, 2026, 7, 15, 12, 0), AppZone.wib), '15 Jul 2026, 18.00 WIB');
      expect(formatInZone(instantFromWallClock(AppZone.london, 2026, 1, 15, 12, 0), AppZone.wib), '15 Jan 2026, 19.00 WIB');
    });

    test('AppZone.fromName: nilai tak dikenal -> WIB', () {
      expect(AppZone.fromName('london'), AppZone.london);
      expect(AppZone.fromName('mars'), AppZone.wib);
      expect(AppZone.fromName(null), AppZone.wib);
    });
  });

  group('formatCountdown', () {
    test('format per rentang', () {
      expect(formatCountdown(const Duration(hours: 2, minutes: 10, seconds: 5)), '2j 10m 05d');
      expect(formatCountdown(const Duration(minutes: 3, seconds: 9)), '3m 09d');
      expect(formatCountdown(const Duration(seconds: 42)), '42d');
      expect(formatCountdown(const Duration(days: 1, hours: 2, minutes: 3, seconds: 59)), '1h 2j 3m');
      expect(formatCountdown(Duration.zero), '0d');
      expect(formatCountdown(const Duration(seconds: -5)), '0d');
    });
  });

  group('Countdown widget', () {
    final target = DateTime(2026, 10, 19, 12, 0, 0);
    late DateTime now;

    Widget app(Widget child) => MaterialApp(home: Scaffold(body: child));

    testWidgets('berkurang tiap detik', (tester) async {
      now = target.subtract(const Duration(hours: 2, minutes: 10, seconds: 5));
      await tester.pumpWidget(app(Countdown(target: target, now: () => now)));
      expect(find.text('Draw dalam 2j 10m 05d'), findsOneWidget);
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Draw dalam 2j 10m 04d'), findsOneWidget);
      now = now.add(const Duration(seconds: 4));
      await tester.pump(const Duration(seconds: 4));
      expect(find.text('Draw dalam 2j 10m 00d'), findsOneWidget);
      // dispose: tester gagal bila masih ada timer tertunda -> membuktikan timer dihentikan saat layar ditutup
      await tester.pumpWidget(app(const SizedBox()));
    });

    testWidgets('berhenti sendiri saat target tercapai ("Waktu draw sudah tiba")', (tester) async {
      now = target.subtract(const Duration(seconds: 2));
      await tester.pumpWidget(app(Countdown(target: target, now: () => now)));
      now = target;
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Waktu draw sudah tiba'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3)); // tidak ada timer lagi yang berjalan
    });

    testWidgets('target sudah lewat: langsung "sudah tiba", tanpa timer', (tester) async {
      now = target.add(const Duration(hours: 1));
      await tester.pumpWidget(app(Countdown(target: target, now: () => now)));
      expect(find.text('Waktu draw sudah tiba'), findsOneWidget);
    });

    testWidgets('tersembunyi (TickerMode mati, mis. tab tidak aktif): tidak ada timer', (tester) async {
      now = target.subtract(const Duration(hours: 1));
      await tester.pumpWidget(app(TickerMode(enabled: false, child: Countdown(target: target, now: () => now))));
      now = now.add(const Duration(seconds: 10));
      await tester.pump(const Duration(seconds: 10));
      expect(find.text('Draw dalam 1j 00m 00d'), findsOneWidget); // beku, tidak diperbarui
      // tampil lagi -> timer menyala dan teks ikut jalan
      await tester.pumpWidget(app(TickerMode(enabled: true, child: Countdown(target: target, now: () => now))));
      now = now.add(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Draw dalam 59m 49d'), findsOneWidget);
      await tester.pumpWidget(app(const SizedBox()));
    });

    testWidgets('aplikasi ke latar belakang: timer dihentikan; kembali: berjalan lagi', (tester) async {
      now = target.subtract(const Duration(hours: 1));
      await tester.pumpWidget(app(Countdown(target: target, now: () => now)));
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      now = now.add(const Duration(minutes: 5));
      await tester.pump(const Duration(seconds: 30)); // tidak ada timer -> teks tidak berubah
      expect(find.text('Draw dalam 1j 00m 00d'), findsOneWidget);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(find.text('Draw dalam 55m 00d'), findsOneWidget); // langsung menyesuaikan saat kembali
      await tester.pumpWidget(app(const SizedBox()));
    });
  });

  group('preferensi tampilan', () {
    testWidgets('zona default berubah -> teks waktu di layar berubah; mata uang berubah -> nilai berubah', (tester) async {
      final settings = SettingsController(MemorySettings());
      final instant = DateTime.utc(2026, 7, 15, 12);
      await tester.pumpWidget(MultiProvider(
        providers: displayProviders(settings: settings),
        child: MaterialApp(
          home: Builder(builder: (c) => Column(children: [Text(c.when(instant), key: const Key('t')), Text(c.money(1200), key: const Key('m'))])),
        ),
      ));
      String text(String k) => tester.widget<Text>(find.byKey(Key(k))).data!;
      expect(text('t'), '15 Jul 2026, 19.00 WIB');
      await settings.setZone(AppZone.london);
      await tester.pump();
      expect(text('t'), '15 Jul 2026, 13.00 BST');
      expect(text('m'), 'US\$1.200,00'); // kurs belum ada -> USD
    });
  });
}
