import 'package:code2ticket/core/currency/rates_controller.dart';
import 'package:code2ticket/core/settings/settings_controller.dart';
import 'package:code2ticket/core/time/zones.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/converter/converter_screen.dart';
import 'package:code2ticket/features/profile/settings_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';

import 'currency_test.dart' show realBody;
import 'input_code_test.dart' show FakeApi, FakeAuth;
import 'support/display.dart';

class _Auth extends FakeAuth {
  _Auth(super.api);
  @override
  Future<bool> isBiometricAvailable() async => false;
  @override
  Future<bool> isBiometricEnabled({String? userId}) async => false;
}

void main() {
  setUpAll(initTimeZones);

  Future<RatesController> ratesWith({bool online = true}) async {
    final r = RatesController(
      MemoryRates(),
      client: MockClient((_) async => online ? http.Response(realBody, 200) : throw http.ClientException('offline')),
    );
    await r.ensureFresh();
    return r;
  }

  Future<void> pumpConverter(WidgetTester tester, RatesController rates, {Widget? home}) async {
    await tester.pumpWidget(MultiProvider(
      providers: displayProviders(rates: rates),
      child: MaterialApp(home: home ?? const ConverterScreen()),
    ));
    await tester.pumpAndSettle();
  }

  String result(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('currency_result'))).data!;

  group('Konverter: tab Mata Uang', () {
    testWidgets('USD -> IDR langsung terhitung dan berlabel kurs per tanggal', (tester) async {
      await pumpConverter(tester, await ratesWith());
      expect(result(tester), 'Rp 17.989'); // 1 USD
      await tester.enterText(find.byKey(const Key('amount_field')), '1200');
      await tester.pump();
      expect(result(tester), 'Rp 21.586.800');
      expect(find.textContaining('Kurs per 19 Okt 2026'), findsOneWidget);
      expect(find.textContaining('offline'), findsNothing);
    });

    testWidgets('pilih mata uang tujuan EUR dan JPY (format sesuai mata uang)', (tester) async {
      await pumpConverter(tester, await ratesWith());
      await tester.enterText(find.byKey(const Key('amount_field')), '1200');
      for (final (name, expected) in [('Euro (EUR)', '€1.068,14'), ('Yen Jepang (JPY)', '¥189.672')]) {
        await tester.tap(find.byKey(const Key('to_currency')));
        await tester.pumpAndSettle();
        await tester.tap(find.text(name).last);
        await tester.pumpAndSettle();
        expect(result(tester), expected);
      }
    });

    testWidgets('tombol tukar menukar asal dan tujuan', (tester) async {
      await pumpConverter(tester, await ratesWith());
      await tester.enterText(find.byKey(const Key('amount_field')), '17989');
      await tester.tap(find.byKey(const Key('swap_currency'))); // IDR -> USD
      await tester.pumpAndSettle();
      expect(result(tester), 'US\$1,00');
    });

    testWidgets('masukan tidak valid: pesan, tanpa hasil; koma desimal diterima', (tester) async {
      await pumpConverter(tester, await ratesWith());
      await tester.enterText(find.byKey(const Key('amount_field')), 'abc');
      await tester.pump();
      expect(find.text('Masukkan angka yang valid.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('amount_field')), '-5');
      await tester.pump();
      expect(find.text('Masukkan angka yang valid.'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('amount_field')), '0,5');
      await tester.pump();
      expect(result(tester), 'Rp 8.995'); // 0,5 USD (8994,5 dibulatkan)
    });

    testWidgets('offline dengan kurs tersimpan: tetap menghitung dan memberi label offline', (tester) async {
      final cache = MemoryRates();
      await RatesController(cache, client: MockClient((_) async => http.Response(realBody, 200))).ensureFresh();
      final offline = RatesController(cache,
          client: MockClient((_) async => throw http.ClientException('putus')),
          clock: () => DateTime.now().add(const Duration(days: 2)));
      await offline.ensureFresh();
      await pumpConverter(tester, offline);
      expect(result(tester), 'Rp 17.989');
      expect(find.textContaining('offline (kurs tersimpan)'), findsOneWidget);
    });

    testWidgets('offline tanpa kurs sama sekali: pesan jelas, tidak crash', (tester) async {
      await pumpConverter(tester, await ratesWith(online: false));
      expect(result(tester), contains('Kurs belum tersedia'));
    });
  });

  group('Konverter: tab Waktu', () {
    String line(WidgetTester tester, String zone) => tester.widget<Text>(find.byKey(Key('conv_$zone'))).data!;

    testWidgets('satu waktu tampil di keempat zona sekaligus (London musim panas)', (tester) async {
      await pumpConverter(tester, await ratesWith(),
          home: Scaffold(body: TimeConverter(initial: DateTime.utc(2026, 7, 15, 3))));
      expect(line(tester, 'wib'), '15 Jul 2026, 10.00 WIB');
      expect(line(tester, 'wita'), '15 Jul 2026, 11.00 WITA');
      expect(line(tester, 'wit'), '15 Jul 2026, 12.00 WIT');
      expect(line(tester, 'london'), '15 Jul 2026, 04.00 BST');
      expect(find.text('UTC+1'), findsOneWidget); // offset London musim panas
    });

    testWidgets('musim dingin: London GMT (UTC+0)', (tester) async {
      await pumpConverter(tester, await ratesWith(),
          home: Scaffold(body: TimeConverter(initial: DateTime.utc(2026, 1, 15, 3))));
      expect(line(tester, 'london'), '15 Jan 2026, 03.00 GMT');
      expect(find.text('UTC+0'), findsOneWidget);
    });

    testWidgets('mengganti zona asal mempertahankan saat yang sama (hasil 4 zona tidak berubah)', (tester) async {
      await pumpConverter(tester, await ratesWith(),
          home: Scaffold(body: TimeConverter(initial: DateTime.utc(2026, 10, 19, 20, 29))));
      final before = [for (final z in AppZone.values) line(tester, z.name)];
      await tester.tap(find.byKey(const Key('source_zone')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('London').last);
      await tester.pumpAndSettle();
      expect([for (final z in AppZone.values) line(tester, z.name)], before);
    });

    testWidgets('tab Waktu dapat dibuka dari layar Konverter', (tester) async {
      await pumpConverter(tester, await ratesWith());
      await tester.tap(find.text('Waktu'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('conv_london')), findsOneWidget);
      expect(find.text('Zona asal'), findsOneWidget);
    });
  });

  group('Pengaturan', () {
    testWidgets('mata uang dan zona default tersimpan; biometric tetap ada di sini', (tester) async {
      final store = MemorySettings();
      final settings = SettingsController(store);
      final api = FakeApi((m, p, b) async => {'ok': true});
      final auth = _Auth(api);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          ...displayProviders(settings: settings),
        ],
        child: const MaterialApp(home: SettingsScreen()),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('currency_EUR')));
      await tester.pumpAndSettle();
      expect(settings.currency, 'EUR');
      expect(store.values['|display_currency'], 'EUR');

      await tester.scrollUntilVisible(find.byKey(const Key('zone_london')), 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.byKey(const Key('zone_london')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('zone_london')));
      await tester.pumpAndSettle();
      expect(settings.zone, AppZone.london);
      expect(store.values['|display_timezone'], 'london');
      for (final c in ['IDR', 'USD', 'EUR', 'JPY']) {
        expect(find.byKey(Key('currency_$c')), findsOneWidget);
      }
      await tester.scrollUntilVisible(find.text('Kunci biometric'), 200, scrollable: find.byType(Scrollable).first);
      expect(find.text('Kunci biometric'), findsOneWidget);
      expect(find.text('Perangkat tidak mendukung biometric'), findsOneWidget);
    });
  });
}
