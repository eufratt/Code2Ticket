import 'package:code2ticket/core/currency/currency.dart';
import 'package:code2ticket/core/currency/rates_controller.dart';
import 'package:code2ticket/core/db/local_db.dart';
import 'package:code2ticket/core/db/rate_cache.dart';
import 'package:code2ticket/core/settings/settings_controller.dart';
import 'package:code2ticket/core/time/zones.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'support/display.dart';

/// Respons ASLI Frankfurter v2 (curl.exe, 2026-10-19). Perhatikan: tanggal bisa berbeda per mata uang.
const realBody =
    '[{"date":"2026-10-19","base":"USD","quote":"EUR","rate":0.89012},{"date":"2026-10-18","base":"USD","quote":"IDR","rate":17989},{"date":"2026-10-19","base":"USD","quote":"JPY","rate":158.06}]';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('parseFrankfurter', () {
    test('respons v2 asli', () {
      final r = parseFrankfurter(realBody);
      expect(r.map((e) => e.target), ['EUR', 'IDR', 'JPY']);
      expect(r.firstWhere((e) => e.target == 'IDR').rate, 17989);
      expect(r.firstWhere((e) => e.target == 'IDR').date, '2026-10-18');
      expect(r.firstWhere((e) => e.target == 'JPY').rate, 158.06);
    });

    test('bentuk v1 lama {"rates":{...}} tetap diterima', () {
      final r = parseFrankfurter('{"base":"USD","date":"2026-10-19","rates":{"EUR":0.89,"IDR":17989}}');
      expect(r.map((e) => e.target), ['EUR', 'IDR']);
      expect(r.first.date, '2026-10-19');
    });

    test('defensif: sampah, elemen rusak, kurs tidak valid, base lain, USD ke USD', () {
      expect(parseFrankfurter('bukan json'), isEmpty);
      expect(parseFrankfurter('{"message":"not found"}'), isEmpty);
      expect(parseFrankfurter('[]'), isEmpty);
      final r = parseFrankfurter('['
          '{"base":"USD","quote":"EUR","rate":0.9},'
          '{"base":"USD","quote":"IDR","rate":"17000"},' // string numerik
          '{"base":"USD","quote":"JPY","rate":0},' // nol dibuang
          '{"base":"USD","quote":"GBP","rate":-1},'
          '{"base":"USD","quote":"CHF"},' // tanpa kurs
          '{"base":"EUR","quote":"IDR","rate":19000},' // base lain
          '{"base":"USD","quote":"USD","rate":1},'
          '"rusak", null, 5]');
      expect(r.map((e) => e.target), ['EUR', 'IDR']);
      expect(r[1].rate, 17000);
    });
  });

  group('formatMoney (pemisah lokal Indonesia)', () {
    test('IDR dan JPY tanpa desimal', () {
      expect(formatMoney(21587000, 'IDR'), 'Rp 21.587.000');
      expect(formatMoney(21587000.6, 'IDR'), 'Rp 21.587.001');
      expect(formatMoney(189672.4, 'JPY'), '¥189.672');
      expect(formatMoney(0, 'IDR'), 'Rp 0');
    });
    test('USD dan EUR dua desimal', () {
      expect(formatMoney(1200, 'USD'), 'US\$1.200,00');
      expect(formatMoney(1234567.5, 'USD'), 'US\$1.234.567,50');
      expect(formatMoney(1068.139, 'EUR'), '€1.068,14');
      expect(formatMoney(0.5, 'EUR'), '€0,50');
      expect(formatMoney(999.999, 'USD'), 'US\$1.000,00');
    });
    test('negatif dan kode lain', () {
      expect(formatMoney(-1500, 'IDR'), '-Rp 1.500');
      expect(formatMoney(-0.001, 'USD'), 'US\$0,00'); // tidak ada "-0,00"
      expect(formatMoney(5, 'GBP'), 'GBP 5,00');
    });
    test('4 mata uang wajib didukung', () => expect(supportedCurrencies, containsAll(['IDR', 'USD', 'EUR', 'JPY'])));
  });

  group('RateSet.convert', () {
    final r = RateSet(perUsd: {'IDR': 17989, 'EUR': 0.89012, 'JPY': 158.06});
    test('dari USD', () {
      expect(r.convert(1200, 'USD', 'IDR'), closeTo(21586800, 0.01));
      expect(r.convert(1200, 'USD', 'EUR'), closeTo(1068.144, 0.001));
    });
    test('antar mata uang non-USD lewat USD, dan kebalikannya', () {
      final jpy = r.convert(1000000, 'IDR', 'JPY')!;
      expect(jpy, closeTo(1000000 / 17989 * 158.06, 0.001));
      expect(r.convert(jpy, 'JPY', 'IDR')!, closeTo(1000000, 0.001));
    });
    test('mata uang sama tidak perlu kurs; kurs hilang -> null', () {
      expect(const RateSet(perUsd: {}).convert(5, 'IDR', 'IDR'), 5);
      expect(const RateSet(perUsd: {}).convert(5, 'USD', 'IDR'), isNull);
      expect(r.convert(5, 'USD', 'GBP'), isNull);
    });
  });

  group('RatesController: online simpan, offline pakai cache, kedaluwarsa', () {
    late MemoryRates cache;
    late DateTime now;
    var calls = 0;
    var status = 200;
    var body = realBody;

    RatesController make({
      Duration ttl = const Duration(hours: 1),
      Duration retryGap = const Duration(minutes: 1),
      List<Duration> retryDelays = const [Duration.zero, Duration.zero],
    }) {
      cache = MemoryRates();
      return RatesController(
        cache,
        client: MockClient((req) async {
          calls++;
          expect(req.url.toString(), 'https://api.frankfurter.dev/v2/rates?base=USD&quotes=IDR,EUR,JPY');
          if (status == 0) throw http.ClientException('putus');
          return http.Response(body, status);
        }),
        ttl: ttl,
        retryGap: retryGap,
        retryDelays: retryDelays,
        clock: () => now,
      );
    }

    setUp(() {
      calls = 0;
      status = 200;
      body = realBody;
      now = DateTime(2026, 10, 19, 12);
    });

    test('online: kurs dipakai, tanggal terbaru, tersimpan ke cache, tidak offline', () async {
      final c = make();
      await c.ensureFresh();
      expect(c.hasRates, isTrue);
      expect(c.offline, isFalse);
      expect(c.rates.perUsd['IDR'], 17989);
      expect(c.rates.rateDate, DateTime.parse('2026-10-19'));
      expect(c.fetchedAt, now);
      expect(cache.rows.map((r) => r.target).toSet(), {'EUR', 'IDR', 'JPY'});
    });

    test('paling sering sekali per jam: dalam 1 jam tidak memanggil server lagi', () async {
      final c = make();
      await c.ensureFresh();
      now = now.add(const Duration(minutes: 59));
      await c.ensureFresh();
      expect(calls, 1);
      now = now.add(const Duration(minutes: 2)); // lewat 1 jam -> kedaluwarsa
      await c.ensureFresh();
      expect(calls, 2);
    });

    test('permintaan bersamaan memakai satu panggilan', () async {
      final c = make();
      await Future.wait([c.ensureFresh(), c.ensureFresh(), c.ensureFresh()]);
      expect(calls, 1);
    });

    test('aplikasi dibuka lagi dengan cache segar: kurs dari cache tanpa panggilan jaringan', () async {
      final first = make();
      await first.ensureFresh();
      final second = RatesController(cache, client: MockClient((_) async {
        calls++;
        return http.Response(realBody, 200);
      }), clock: () => now.add(const Duration(minutes: 10)));
      await second.ensureFresh();
      expect(calls, 1);
      expect(second.rates.perUsd['EUR'], 0.89012);
      expect(second.offline, isFalse);
    });

    test('offline dengan cache kedaluwarsa: kurs cache dipakai dan ditandai offline', () async {
      final c = make();
      await c.ensureFresh();
      final stale = RatesController(cache, client: MockClient((_) async => throw http.ClientException('putus')),
          clock: () => now.add(const Duration(hours: 5)));
      await stale.ensureFresh();
      expect(stale.hasRates, isTrue);
      expect(stale.offline, isTrue);
      expect(stale.rates.perUsd['IDR'], 17989);
      expect(stale.fetchedAt, now); // label memakai waktu ambil lama
    });

    test('offline tanpa cache: tidak ada kurs, tidak melempar', () async {
      status = 0;
      final c = make();
      await c.ensureFresh();
      expect(c.hasRates, isFalse);
      expect(c.offline, isFalse);
    });

    test('HTTP 500, 429, atau format tak dikenal -> cache dipakai (offline)', () async {
      for (final (st, b) in [(500, 'err'), (429, '{}'), (200, '{"x":1}'), (200, 'bukan json')]) {
        final c = make();
        await c.ensureFresh();
        status = st;
        body = b;
        now = now.add(const Duration(hours: 2));
        await c.ensureFresh();
        expect(c.offline, isTrue, reason: '$st $b');
        expect(c.rates.perUsd['IDR'], 17989);
        status = 200;
        body = realBody;
        now = DateTime(2026, 10, 19, 12);
      }
    });

    test('(a) gagal pertama lalu berhasil pada retry -> kurs tersimpan ke cache', () async {
      final localCache = MemoryRates();
      var callCount = 0;
      final c = RatesController(
        localCache,
        client: MockClient((_) async {
          callCount++;
          if (callCount == 1) throw http.ClientException('koneksi awal gagal');
          return http.Response(realBody, 200);
        }),
        retryDelays: const [Duration.zero, Duration.zero],
        clock: () => now,
      );
      await c.ensureFresh();
      expect(callCount, 2);
      expect(c.hasRates, isTrue);
      expect(c.offline, isFalse);
      expect(c.rates.perUsd['IDR'], 17989);
      expect(c.lastError, isNull);
      expect(localCache.rows.map((r) => r.target).toSet(), {'EUR', 'IDR', 'JPY'});
    });

    test('(b) tanpa kurs, panggilan kedua dalam <60 dtk tetap mencoba', () async {
      status = 0;
      final c = make(retryDelays: const []);
      await c.ensureFresh();
      expect(calls, 1);
      expect(c.hasRates, isFalse);

      // Panggilan kedua hanya berselang 10 detik (< 60 dtk): tetap mencoba memanggil server
      now = now.add(const Duration(seconds: 10));
      await c.ensureFresh();
      expect(calls, 2);
    });

    test('(c) dengan kurs, throttle tetap berlaku (kecuali force)', () async {
      final c = make(retryDelays: const []);
      await c.ensureFresh(); // berhasil, hasRates == true
      expect(calls, 1);
      expect(c.hasRates, isTrue);

      status = 0; // bila terpanggil lagi, gagal
      now = now.add(const Duration(seconds: 10)); // < 60 detik
      await c.ensureFresh(); // throttle berlaku karena hasRates == true
      expect(calls, 1); // tidak ada panggilan baru
      expect(c.hasRates, isTrue);

      // Bila force: true, throttle diabaikan
      await c.ensureFresh(force: true);
      expect(calls, 2); // dipanggil karena force: true
    });

    test('(d) tidak ada permintaan ganda bersamaan (termasuk saat force)', () async {
      final c = make(retryDelays: const []);
      await Future.wait([c.ensureFresh(), c.ensureFresh(), c.ensureFresh()]);
      expect(calls, 1);

      now = now.add(const Duration(hours: 2));
      await Future.wait([c.ensureFresh(force: true), c.ensureFresh(force: true)]);
      expect(calls, 2);
    });

    test('(e) lastError terisi saat gagal dan hilang saat sukses', () async {
      status = 0;
      final c = make(retryDelays: const []);
      await c.ensureFresh();
      expect(c.hasRates, isFalse);
      expect(c.lastError, isNotNull);
      expect(c.lastError, contains('putus'));

      status = 200;
      await c.ensureFresh(force: true);
      expect(c.hasRates, isTrue);
      expect(c.lastError, isNull);
    });

    test('lifecycle resumed memuat ulang kurs bila belum ada kurs atau cache kedaluwarsa', () async {
      status = 0;
      final c = make(retryDelays: const []);
      await c.ensureFresh();
      expect(calls, 1);
      expect(c.hasRates, isFalse);

      // Server kembali online, aplikasi resumed -> memuat ulang karena belum ada kurs
      status = 200;
      c.handleAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(calls, 2);
      expect(c.hasRates, isTrue);

      // Masih fresh -> resumed tidak memanggil server
      c.handleAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(calls, 2);

      // Kedaluwarsa (> 1 jam) -> resumed memanggil server
      now = now.add(const Duration(hours: 2));
      c.handleAppLifecycleState(AppLifecycleState.resumed);
      await pumpEventQueue();
      expect(calls, 3);
    });

    test('online kembali setelah offline: kurs diperbarui dan label offline hilang', () async {
      final c = make();
      await c.ensureFresh();
      status = 0;
      now = now.add(const Duration(hours: 2));
      await c.ensureFresh();
      expect(c.offline, isTrue);
      status = 200;
      body = '[{"date":"2026-10-20","base":"USD","quote":"IDR","rate":18100}]';
      now = now.add(const Duration(minutes: 5));
      await c.ensureFresh();
      expect(c.offline, isFalse);
      expect(c.rates.perUsd['IDR'], 18100);
    });

    test('cache SQLite rusak tidak mengganggu pengambilan kurs', () async {
      final c = make();
      cache.failing = true;
      await c.ensureFresh();
      expect(c.hasRates, isTrue);
    });
  });

  group('LocalDb: exchange_rate_cache dan app_settings', () {
    late Database db;
    late LocalDb local;
    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(version: LocalDb.dbVersion, onCreate: LocalDb.createTables));
      local = LocalDb.withDatabase(db);
    });
    tearDown(() => db.close());

    test('kurs: simpan lalu baca, ganti kurs lama, waktu ambil tersimpan', () async {
      final at = DateTime.utc(2026, 10, 19, 5);
      await local.saveRates('USD', [CachedRate(target: 'IDR', rate: 17989, rateDate: '2026-10-18', fetchedAt: at)]);
      await local.saveRates('USD', [
        CachedRate(target: 'IDR', rate: 18000, rateDate: '2026-10-19', fetchedAt: at),
        CachedRate(target: 'EUR', rate: 0.89, rateDate: '2026-10-19', fetchedAt: at),
      ]);
      final rows = await local.loadRates('USD');
      expect(rows, hasLength(2));
      final idr = rows.firstWhere((r) => r.target == 'IDR');
      expect([idr.rate, idr.rateDate], [18000, '2026-10-19']);
      expect(idr.fetchedAt.toUtc(), at);
      expect(await local.loadRates('EUR'), isEmpty);
    });

    test('pengaturan tampilan tersimpan per perangkat dan dimuat ulang', () async {
      final s = SettingsController(local);
      await s.load();
      expect([s.currency, s.zone], ['IDR', AppZone.wib]); // bawaan
      await s.setCurrency('EUR');
      await s.setZone(AppZone.london);
      final again = SettingsController(local);
      await again.load();
      expect([again.currency, again.zone], ['EUR', AppZone.london]);
      expect(await local.getSetting('display_currency'), 'EUR');
      expect(await local.getSetting('display_timezone', userId: 'u1'), isNull); // bukan milik pengguna tertentu
    });

    test('nilai tersimpan yang tidak dikenal diabaikan; mata uang tak didukung ditolak', () async {
      await local.setSetting('display_currency', 'XXX');
      await local.setSetting('display_timezone', 'mars');
      final s = SettingsController(local);
      await s.load();
      expect([s.currency, s.zone], ['IDR', AppZone.wib]);
      await s.setCurrency('GBP');
      expect(s.currency, 'IDR');
    });
  });
}
