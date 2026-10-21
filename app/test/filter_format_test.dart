import 'package:code2ticket/core/currency/currency.dart';
import 'package:code2ticket/core/currency/rates_controller.dart';
import 'package:code2ticket/core/rupiah_input.dart';
import 'package:code2ticket/core/settings/settings_controller.dart';
import 'package:code2ticket/features/discover/discover_filters.dart';
import 'package:code2ticket/features/discover/discover_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/display.dart';

// Pemisah ribuan di filter Nilai hadiah (Discover) dan formatter tanpa desimal.
const rates = RateSet(perUsd: {'IDR': 18000.0, 'EUR': 0.9, 'JPY': 150.0});

void main() {
  group('DecimalInputFormatter(decimals: 0)', () {
    TextEditingValue type(String t, [int? c]) =>
        const DecimalInputFormatter(decimals: 0).formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: t, selection: TextSelection.collapsed(offset: c ?? t.length)));

    test('bilangan bulat: koma ditolak, ribuan otomatis, kursor terjaga', () {
      expect(type('5000000').text, '5.000.000');
      expect(type('1,5').text, '15');
      expect(type('1.234,56').text, '123.456');
      final r = type('19.234', 2);
      expect([r.text, r.selection.baseOffset], ['19.234', 2]);
    });
  });

  Future<void> open(WidgetTester tester, void Function(DiscoverFilters?) onResult,
      {String currency = 'IDR', RateSet rateSet = rates, DiscoverFilters initial = const DiscoverFilters()}) async {
    final settings = SettingsController(MemorySettings())..currency = currency;
    final rc = RatesController(MemoryRates(), client: offlineClient(), retryDelays: const [])..rates = rateSet;
    await tester.pumpWidget(MultiProvider(
      providers: displayProviders(settings: settings, rates: rc),
      child: MaterialApp(
        home: Builder(
          builder: (c) => TextButton(
            key: const Key('open'),
            onPressed: () async => onResult(await showModalBottomSheet<DiscoverFilters>(
              context: c,
              isScrollControlled: true,
              builder: (_) => FilterSheet(initial: initial),
            )),
            child: const Text('buka'),
          ),
        ),
      ),
    ));
    await tester.tap(find.byKey(const Key('open')));
    await tester.pumpAndSettle();
  }

  String text(WidgetTester tester, String key) => tester.widget<TextField>(find.byKey(Key(key))).controller!.text;

  testWidgets('IDR: 5000000 -> 5.000.000 di min dan maks; koma tidak diterima; filter memakai nilai berformat', (tester) async {
    DiscoverFilters? got;
    await open(tester, (f) => got = f);
    await tester.enterText(find.byKey(const Key('min_value')), '5000000');
    await tester.enterText(find.byKey(const Key('max_value')), '9000000,5');
    expect(text(tester, 'min_value'), '5.000.000');
    expect(text(tester, 'max_value'), '90.000.005');
    await tester.enterText(find.byKey(const Key('max_value')), '15000000');
    await tester.tap(find.byKey(const Key('apply_filter')));
    await tester.pumpAndSettle();
    expect([got!.minValueIdr, got!.maxValueIdr], [5000000, 15000000]);
    expect(got!.activeFilterCount, 1);
  });

  testWidgets('min lebih besar dari maks tetap ditolak dengan pesan lama', (tester) async {
    await open(tester, (_) {});
    await tester.enterText(find.byKey(const Key('min_value')), '9000000');
    await tester.enterText(find.byKey(const Key('max_value')), '1000000');
    await tester.tap(find.byKey(const Key('apply_filter')));
    await tester.pumpAndSettle();
    expect(find.text('Nilai minimum tidak boleh lebih besar dari maksimum.'), findsOneWidget);
  });

  testWidgets('USD: koma dan maks. 2 desimal; dikonversi ke rupiah (min turun, maks naik)', (tester) async {
    DiscoverFilters? got;
    await open(tester, (f) => got = f, currency: 'USD');
    await tester.enterText(find.byKey(const Key('min_value')), '1234,567');
    expect(text(tester, 'min_value'), '1.234,56');
    await tester.enterText(find.byKey(const Key('min_value')), '1000');
    await tester.enterText(find.byKey(const Key('max_value')), '2500,5');
    expect(text(tester, 'max_value'), '2.500,5');
    await tester.tap(find.byKey(const Key('apply_filter')));
    await tester.pumpAndSettle();
    expect([got!.minValueIdr, got!.maxValueIdr], [18000000, 45009000]);
  });

  testWidgets('JPY: bilangan bulat', (tester) async {
    await open(tester, (_) {}, currency: 'JPY');
    await tester.enterText(find.byKey(const Key('min_value')), '150000,5');
    expect(text(tester, 'min_value'), '1.500.005');
  });

  testWidgets('membuka ulang sheet dengan filter aktif: nilai sudah berformat ribuan', (tester) async {
    await open(tester, (_) {}, initial: const DiscoverFilters(minValueIdr: 5000000, maxValueIdr: 25000000));
    expect(text(tester, 'min_value'), '5.000.000');
    expect(text(tester, 'max_value'), '25.000.000');
  });

  testWidgets('Atur ulang mengosongkan rentang nilai', (tester) async {
    DiscoverFilters? got;
    await open(tester, (f) => got = f, initial: const DiscoverFilters(minValueIdr: 5000000));
    await tester.tap(find.byKey(const Key('reset_filter')));
    await tester.pumpAndSettle();
    expect([got!.minValueIdr, got!.maxValueIdr, got!.activeFilterCount], [null, null, 0]);
  });
}
