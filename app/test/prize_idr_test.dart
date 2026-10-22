import 'package:code2ticket/core/currency/currency.dart';
import 'package:code2ticket/core/currency/rates_controller.dart';
import 'package:code2ticket/core/db/local_db.dart';
import 'package:code2ticket/core/display.dart';
import 'package:code2ticket/core/json.dart';
import 'package:code2ticket/core/rupiah_input.dart';
import 'package:code2ticket/core/settings/settings_controller.dart';
import 'package:code2ticket/features/discover/discover_filters.dart';
import 'package:code2ticket/features/discover/discover_screen.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/display.dart';

// Nilai hadiah berbasis rupiah: format, konversi dari IDR, default IDR, offline tanpa kurs, isian rupiah, migrasi cache lokal v3.
const rates = RateSet(perUsd: {'IDR': 18000.0, 'EUR': 0.9, 'JPY': 150.0});
const noRates = RateSet(perUsd: {});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('format rupiah dan konversi dari IDR', () {
    test('IDR tampil persis sama dengan nilai tersimpan, dengan atau tanpa kurs', () {
      expect(formatPrize(5000000, 'IDR', noRates), 'Rp 5.000.000');
      expect(formatPrize(5000000, 'IDR', rates), 'Rp 5.000.000');
      expect(formatPrize(1, 'IDR', rates), 'Rp 1');
      expect(formatPrize(100000000000, 'IDR', rates), 'Rp 100.000.000.000');
      expect(formatMoney(5000000, 'IDR'), 'Rp 5.000.000'); // tanpa desimal
    });

    test('IDR -> USD / EUR / JPY lewat kurs Frankfurter (pivot USD)', () {
      expect(formatPrize(18000000, 'USD', rates), 'US\$1.000,00');
      expect(formatPrize(18000000, 'EUR', rates), '€900,00');
      expect(formatPrize(18000000, 'JPY', rates), '¥150.000');
      expect(rates.convert(18000000, 'IDR', 'USD'), closeTo(1000, 1e-9));
    });

    test('kurs belum ada / mata uang tak punya kurs -> IDR (mata uang dasar), bukan USD', () {
      expect(prizeCurrency('USD', noRates), 'IDR');
      expect(formatPrize(5000000, 'USD', noRates), 'Rp 5.000.000');
      expect(formatPrize(5000000, 'EUR', const RateSet(perUsd: {'IDR': 18000.0})), 'Rp 5.000.000');
      expect(prizeCurrency('EUR', rates), 'EUR');
    });

    test('masukan filter -> rupiah: minimum ke bawah, maksimum ke atas, dijepit ke batas', () {
      expect(prizeToIdr(100, 'USD', rates, up: false), 1800000);
      expect(prizeToIdr(0.0001, 'USD', rates, up: false), 1);
      expect(prizeToIdr(0.0001, 'USD', rates, up: true), 2);
      expect(prizeToIdr(1.5, 'IDR', rates, up: false), 1);
      expect(prizeToIdr(1.5, 'IDR', rates, up: true), 2);
      expect(prizeToIdr(5000000, 'IDR', noRates, up: true), 5000000);
      expect(prizeToIdr(5, 'USD', noRates, up: true), isNull);
      expect(prizeToIdr(1e30, 'IDR', rates, up: true), maxPrizeIdr);
    });

    test('teks isian filter dari rupiah tersimpan', () {
      expect(prizeInputText(5000000, 'IDR', rates), '5.000.000');
      expect(prizeInputText(18000000, 'USD', rates), '1.000');
      expect(prizeInputText(18000900, 'USD', rates), '1.000,05'); // dua desimal
      expect(prizeInputText(18000000, 'JPY', rates), '150.000');
    });
  });

  group('default IDR dan pilihan pengguna', () {
    test('pengguna baru -> IDR; pilihan lama tetap', () async {
      final fresh = SettingsController(MemorySettings());
      expect(fresh.currency, 'IDR');
      await fresh.load();
      expect(fresh.currency, 'IDR');

      final store = MemorySettings()..values['|display_currency'] = 'EUR';
      final kept = SettingsController(store);
      await kept.load();
      expect(kept.currency, 'EUR');
    });
  });

  group('nilai hadiah di layar', () {
    Future<void> pumpValue(WidgetTester tester, {required String currency, RateSet rateSet = noRates, int? idr = 5000000}) async {
      final settings = SettingsController(MemorySettings())..currency = currency;
      final rc = RatesController(MemoryRates(), client: offlineClient(), retryDelays: const [])..rates = rateSet;
      await tester.pumpWidget(MultiProvider(
        providers: displayProviders(settings: settings, rates: rc),
        child: MaterialApp(
          home: Builder(builder: (c) => Column(children: [Text(c.money(idr), key: const Key('m')), const RateNote()])),
        ),
      ));
    }

    String money(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('m'))).data!;

    testWidgets('IDR: Rp 5.000.000 persis dan tanpa catatan kurs', (tester) async {
      await pumpValue(tester, currency: 'IDR', rateSet: rates);
      expect(money(tester), 'Rp 5.000.000');
      expect(find.byKey(const Key('rate_note')), findsNothing);
    });

    testWidgets('USD dengan kurs: dikonversi dari IDR', (tester) async {
      await pumpValue(tester, currency: 'USD', rateSet: rates, idr: 18000000);
      expect(money(tester), 'US\$1.000,00');
    });

    testWidgets('offline tanpa kurs cache: tampil IDR dengan catatan, bukan USD', (tester) async {
      await pumpValue(tester, currency: 'USD');
      expect(money(tester), 'Rp 5.000.000');
      expect(find.text('Kurs belum tersedia, nilai ditampilkan dalam IDR (mata uang dasar).'), findsOneWidget);
    });

    testWidgets('nilai tidak ada (mis. backend lama) -> "-" tanpa crash', (tester) async {
      await pumpValue(tester, currency: 'IDR', idr: null);
      expect(money(tester), '-');
    });
  });

  group('model dan JSON', () {
    test('asIntOrNull: angka, string, desimal dibulatkan, selain itu null', () {
      expect(asIntOrNull(5000000), 5000000);
      expect(asIntOrNull('5000000'), 5000000);
      expect(asIntOrNull(5000000.0), 5000000);
      expect(asIntOrNull('NaN'), isNull);
      expect(asIntOrNull(null), isNull);
      expect(asIntOrNull('abc'), isNull);
    });

    test('respons baru terbaca; respons lama (hanya prize_value_usd) -> null tanpa crash', () {
      expect(Giveaway.tryParse({'id': 'a', 'title': 'T', 'prize_value_idr': 5000000})!.prizeValueIdr, 5000000);
      final old = Giveaway.tryParse({'id': 'a', 'title': 'T', 'prize_value_usd': 1200})!;
      expect(old.prizeValueIdr, isNull);
      expect(old.toRow(DateTime.utc(2026)).containsKey('prize_value_usd'), isFalse);
    });

    test('simpan ke baris cache lalu baca lagi: Rp 5.000.000 tetap Rp 5.000.000', () {
      const g = Giveaway(id: 'a', title: 'T', prizeValueIdr: 5000000);
      final back = Giveaway.tryParse(g.toRow(DateTime.utc(2026)))!;
      expect(back.prizeValueIdr, 5000000);
      expect(formatPrize(back.prizeValueIdr!, 'IDR', noRates), 'Rp 5.000.000');
    });
  });

  group('isian rupiah (form Admin)', () {
    String typed(String input) =>
        const RupiahInputFormatter().formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: input)).text;

    test('pemisah ribuan otomatis, hanya angka, tanpa nol di depan, maks. 12 digit', () {
      expect(typed('5000000'), '5.000.000');
      expect(typed('5.000.000'), '5.000.000');
      expect(typed('1200,5'), '12.005'); // desimal tidak diterima: hanya angka yang tersisa
      expect(typed('-5'), '5');
      expect(typed('abc'), '');
      expect(typed('007'), '7');
      expect(typed('0'), '0');
      expect(typed('1234567890123'), '123.456.789.012');
    });

    test('parseRupiah', () {
      expect(parseRupiah('5.000.000'), 5000000);
      expect(parseRupiah('5000000'), 5000000);
      expect(parseRupiah(''), isNull);
      expect(parseRupiah('1,5'), isNull);
      expect(parseRupiah('-5'), isNull);
      expect(parseRupiah('1' * 16), isNull);
    });
  });

  group('filter Discover pada IDR', () {
    testWidgets('IDR: Rp 1.000.000 - Rp 5.000.000 dikirim apa adanya', (tester) async {
      DiscoverFilters? got;
      await tester.pumpWidget(MultiProvider(
        providers: displayProviders(),
        child: MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              key: const Key('open'),
              onPressed: () async => got = await showModalBottomSheet<DiscoverFilters>(
                context: c,
                isScrollControlled: true,
                builder: (_) => const FilterSheet(initial: DiscoverFilters()),
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(find.text('Nilai hadiah (Rp)'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('min_value')), '1.000.000');
      await tester.enterText(find.byKey(const Key('max_value')), '5000000');
      await tester.tap(find.byKey(const Key('apply_filter')));
      await tester.pumpAndSettle();
      expect([got!.minValueIdr, got!.maxValueIdr], [1000000, 5000000]);
      expect(got!.toQuery()['min_value'], '1000000');
      expect(got!.toQuery()['max_value'], '5000000');
    });

    testWidgets('USD: masukan dalam dolar dikonversi ke rupiah (min turun, maks naik); isian awal dari rupiah', (tester) async {
      DiscoverFilters? got;
      final settings = SettingsController(MemorySettings())..currency = 'USD';
      final rc = RatesController(MemoryRates(), client: offlineClient(), retryDelays: const [])..rates = rates;
      await tester.pumpWidget(MultiProvider(
        providers: displayProviders(settings: settings, rates: rc),
        child: MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              key: const Key('open'),
              onPressed: () async => got = await showModalBottomSheet<DiscoverFilters>(
                context: c,
                isScrollControlled: true,
                builder: (_) => const FilterSheet(initial: DiscoverFilters(minValueIdr: 18000000)),
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(find.text('Nilai hadiah (USD)'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('min_value'))).controller!.text, '1.000'); // Rp 18.000.000 = US$1.000
      await tester.enterText(find.byKey(const Key('min_value')), '100');
      await tester.enterText(find.byKey(const Key('max_value')), '250,5');
      await tester.tap(find.byKey(const Key('apply_filter')));
      await tester.pumpAndSettle();
      expect(got!.minValueIdr, 1800000);
      expect(got!.maxValueIdr, 4509000);
    });

    testWidgets('USD terpilih tetapi offline tanpa kurs: isian dalam rupiah', (tester) async {
      DiscoverFilters? got;
      final settings = SettingsController(MemorySettings())..currency = 'USD';
      await tester.pumpWidget(MultiProvider(
        providers: displayProviders(settings: settings),
        child: MaterialApp(
          home: Builder(
            builder: (c) => TextButton(
              key: const Key('open'),
              onPressed: () async => got = await showModalBottomSheet<DiscoverFilters>(
                context: c,
                isScrollControlled: true,
                builder: (_) => const FilterSheet(initial: DiscoverFilters()),
              ),
              child: const Text('buka'),
            ),
          ),
        ),
      ));
      await tester.tap(find.byKey(const Key('open')));
      await tester.pumpAndSettle();
      expect(find.text('Nilai hadiah (Rp)'), findsOneWidget);
      await tester.enterText(find.byKey(const Key('min_value')), '750000');
      await tester.tap(find.byKey(const Key('apply_filter')));
      await tester.pumpAndSettle();
      expect(got!.minValueIdr, 750000);
    });


    test('filter lokal dan sort pada IDR: tepi inklusif, nilai kosong tersaring bila ada batas', () {
      final now = DateTime.now();
      Giveaway g(String id, int? v) => Giveaway(
            id: id, title: id, category: 'tech', prizeValueIdr: v,
            startAt: now.subtract(const Duration(hours: 1)), endAt: now.add(const Duration(hours: 5)),
          );
      final all = [g('a', 1000000), g('b', 5000000), g('c', 90000000), g('x', null)];
      List<String> ids(DiscoverFilters f) => f.applyLocal(all, now: now).map((e) => e.id).toList();
      expect(ids(const DiscoverFilters(minValueIdr: 5000000)), ['b', 'c']);
      expect(ids(const DiscoverFilters(maxValueIdr: 5000000)), ['a', 'b']);
      expect(ids(const DiscoverFilters(minValueIdr: 1000000, maxValueIdr: 5000000)), ['a', 'b']);
      expect(ids(const DiscoverFilters(sort: GiveawaySort.value)), ['c', 'b', 'a', 'x']);
    });
  });

  group('migrasi SQLite lokal v3 dan v4', () {
    Future<Database> openV2() async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      // Skema v2 lama (APK sebelum nilai hadiah rupiah).
      await db.execute('''CREATE TABLE cached_giveaways (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT, organizer TEXT, category TEXT,
        prize_name TEXT, prize_value_usd REAL, latitude REAL, longitude REAL, address TEXT, radius_km REAL,
        start_at TEXT, end_at TEXT, draw_at TEXT, winner_count INTEGER, ticket_count INTEGER,
        status TEXT, seed_hash TEXT, cached_at TEXT NOT NULL)''');
      await db.execute('CREATE INDEX idx_cg_category ON cached_giveaways(category)');
      await db.execute('CREATE INDEX idx_cg_end ON cached_giveaways(end_at)');
      await db.execute('''CREATE TABLE chat_messages (
        id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL,
        related_json TEXT, created_at TEXT NOT NULL)''');
      await db.insert('cached_giveaways', {'id': 'g1', 'title': 'Lama', 'prize_value_usd': 1200.0, 'cached_at': '2026-10-19T00:00:00Z'});
      await db.insert('chat_messages', {'user_id': 'u1', 'role': 'assistant', 'content': 'Ada.', 'related_json': '[{"id":"g1","prize_value_usd":1200}]', 'created_at': '2026-10-19T00:00:00Z'});
      await db.insert('chat_messages', {'user_id': 'u1', 'role': 'user', 'content': 'halo', 'created_at': '2026-10-19T00:00:00Z'});
      return db;
    }

    test('v2 -> v4: cache giveaway dibuat ulang dengan prize_value_idr, percakapan tetap, kartu lama dikosongkan', () async {
      final db = await openV2();
      await LocalDb.upgradeTables(db, 2, 4);
      final cols = (await db.rawQuery('PRAGMA table_info(cached_giveaways)')).map((r) => r['name']).toList();
      expect(cols, contains('prize_value_idr'));
      expect(cols, isNot(contains('prize_value_usd')));
      expect(await db.query('cached_giveaways'), isEmpty);
      final idx = (await db.rawQuery("SELECT name FROM sqlite_master WHERE type='index' AND name LIKE 'idx_cg_%'")).map((r) => r['name']);
      expect(idx, containsAll(['idx_cg_category', 'idx_cg_end']));

      final chats = await db.query('chat_messages', orderBy: 'id');
      expect(chats.map((r) => r['content']), ['Ada.', 'halo']);
      expect(chats.map((r) => r['related_json']), [null, null]);

      // tabel baru langsung bisa dipakai LocalDb
      final local = LocalDb.withDatabase(db);
      await local.saveGiveaways([const Giveaway(id: 'g2', title: 'Baru', prizeValueIdr: 5000000)]);
      expect((await local.loadGiveaway('g2'))!.prizeValueIdr, 5000000);
      await db.close();
    });

    test('v1 -> v4 (APK paling lama) tidak crash: tabel chat dibuat dulu, lalu dibersihkan', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
      await db.execute('CREATE TABLE cached_giveaways (id TEXT PRIMARY KEY, title TEXT NOT NULL, prize_value_usd REAL, cached_at TEXT NOT NULL)');
      await LocalDb.upgradeTables(db, 1, 4);
      expect((await db.rawQuery('PRAGMA table_info(cached_giveaways)')).map((r) => r['name']), contains('prize_value_idr'));
      expect(await db.query('chat_messages'), isEmpty);
      await db.close();
    });

    test('pemasangan baru: dbVersion 6 dan kolom prize_value_idr', () async {
      expect(LocalDb.dbVersion, 6);
      final db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: LocalDb.dbVersion, onCreate: LocalDb.createTables),
      );
      expect((await db.rawQuery('PRAGMA table_info(cached_giveaways)')).map((r) => r['name']), contains('prize_value_idr'));
      await db.close();
    });
  });
}
