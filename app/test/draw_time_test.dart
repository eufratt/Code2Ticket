import 'dart:io' show HttpDate;

import 'package:code2ticket/core/display.dart';
import 'package:code2ticket/core/settings/settings_controller.dart';
import 'package:code2ticket/core/time/server_clock.dart';
import 'package:code2ticket/core/time/zones.dart';
import 'package:code2ticket/features/giveaways/giveaway_detail_screen.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'layout/screens_layout_test.dart' show SampleEnv, sampleGiveaways;
import 'support/display.dart';
import 'support/ui.dart';

// Waktu draw mengikuti zona pilihan pengguna (satu jalur: context.when -> formatInZone) dan hitung mundur memakai jam server.
void main() {
  setUpAll(initTimeZones);
  tearDown(() => serverClockOffset = Duration.zero);

  group('context.when: zona pilihan', () {
    testWidgets('batas pergantian hari: 17.30 UTC = besok 00.30 WIB, hari yang sama di London', (tester) async {
      final settings = SettingsController(MemorySettings());
      final draw = DateTime.utc(2026, 10, 19, 17, 30);
      await tester.pumpWidget(MultiProvider(
        providers: displayProviders(settings: settings),
        child: MaterialApp(home: Builder(builder: (c) => Text(c.when(draw), key: const Key('t')))),
      ));
      String text() => tester.widget<Text>(find.byKey(const Key('t'))).data!;
      final expected = {
        AppZone.wib: '20 Okt 2026, 00.30 WIB',
        AppZone.wita: '20 Okt 2026, 01.30 WITA',
        AppZone.wit: '20 Okt 2026, 02.30 WIT',
        AppZone.london: '19 Okt 2026, 18.30 BST',
      };
      for (final MapEntry(key: zone, value: label) in expected.entries) {
        await settings.setZone(zone);
        await tester.pump();
        expect(text(), label, reason: zone.name);
      }
    });

    test('format 24 jam: tengah malam 00.00, siang 12.00, malam 23.59', () {
      expect(formatInZone(DateTime.utc(2026, 1, 14, 17), AppZone.wib), '15 Jan 2026, 00.00 WIB');
      expect(formatInZone(DateTime.utc(2026, 1, 15, 5), AppZone.wib), '15 Jan 2026, 12.00 WIB');
      expect(formatInZone(DateTime.utc(2026, 1, 15, 16, 59), AppZone.wib), '15 Jan 2026, 23.59 WIB');
      // Pergantian tahun di WIT terjadi saat UTC masih tahun lama.
      expect(formatInZone(DateTime.utc(2026, 12, 31, 15), AppZone.wit), '1 Jan 2027, 00.00 WIT');
    });
  });

  group('Detail Giveaway: label Draw di Informasi', () {
    testWidgets('memakai zona pilihan dan berubah langsung saat Pengaturan diganti', (tester) async {
      await setViewport(tester, height: 2600);
      final draw = DateTime.utc(2027, 1, 15, 13);
      final extra = {'draw_at': draw.toIso8601String()};
      final env = SampleEnv()..giveawayExtra = extra;
      final settings = SettingsController(MemorySettings());
      await tester.pumpWidget(env.wrap(ChangeNotifierProvider<SettingsController>.value(
        value: settings,
        child: themedApp(GiveawayDetailScreen(giveawayId: 'g1', initial: Giveaway.tryParse({...sampleGiveaways().first, ...extra}))),
      )));
      await tester.pumpAndSettle();
      Finder row(String text) => find.descendant(of: find.byKey(const Key('info_draw')), matching: find.text(text));
      expect(row('15 Jan 2027, 20.00 WIB'), findsOneWidget);
      await settings.setZone(AppZone.london);
      await tester.pumpAndSettle();
      expect(row('15 Jan 2027, 13.00 GMT'), findsOneWidget);
      await settings.setZone(AppZone.wit);
      await tester.pumpAndSettle();
      expect(row('15 Jan 2027, 22.00 WIT'), findsOneWidget);
      await tester.pumpWidget(const SizedBox()); // hentikan timer hitung mundur
    });
  });

  group('jam server', () {
    test('header Date 1 jam di depan -> offset ~1 jam', () {
      final sent = DateTime.now();
      recordServerDate(HttpDate.format(sent.add(const Duration(hours: 1))), sent, sent.add(const Duration(milliseconds: 200)));
      expect((serverClockOffset - const Duration(hours: 1)).inMilliseconds.abs(), lessThan(1500));
    });

    test('selisih < 2 dtk dianggap nol (resolusi header 1 dtk)', () {
      serverClockOffset = const Duration(minutes: 5);
      final sent = DateTime.now();
      recordServerDate(HttpDate.format(sent), sent, sent.add(const Duration(milliseconds: 100)));
      expect(serverClockOffset, Duration.zero);
    });

    test('header kosong/rusak atau bolak-balik terlalu lama -> offset tidak berubah', () {
      serverClockOffset = const Duration(minutes: 5);
      final sent = DateTime.now();
      final far = HttpDate.format(sent.add(const Duration(hours: 2)));
      recordServerDate(null, sent, sent);
      recordServerDate('bukan tanggal', sent, sent);
      recordServerDate(far, sent, sent.add(const Duration(seconds: 10)));
      expect(serverClockOffset, const Duration(minutes: 5));
    });

    testWidgets('Countdown memakai jam server, bukan jam perangkat', (tester) async {
      serverClockOffset = const Duration(hours: 1); // jam perangkat 1 jam terlambat
      final target = DateTime.now().add(const Duration(hours: 2, seconds: 30));
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: Countdown(target: target))));
      expect(tester.widget<Text>(find.byKey(const Key('countdown'))).data, startsWith('Draw dalam 1j 00m'));
      await tester.pumpWidget(const SizedBox());
    });
  });
}
