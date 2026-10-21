import 'package:code2ticket/core/db/local_db.dart';
import 'package:code2ticket/features/giveaways/giveaway_detail_screen.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'layout/screens_layout_test.dart' show SampleEnv, sampleGiveaways;
import 'support/ui.dart';

// Batas lokasi tukar kode per giveaway: model, cache SQLite v5, keterangan di Detail.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  Future<void> pumpDetail(WidgetTester tester, Map<String, dynamic> extra, {Brightness b = Brightness.light}) async {
    await setViewport(tester, height: 2600, brightness: b);
    final env = SampleEnv()..giveawayExtra = extra;
    await tester.pumpWidget(env.wrap(themedApp(GiveawayDetailScreen(giveawayId: 'g1', initial: Giveaway.tryParse({...sampleGiveaways().first, ...extra})))));
    await tester.pumpAndSettle();
  }

  group('model', () {
    test('redeem_geo_restricted: bawaan false; true/1 -> true; round-trip baris cache', () {
      final base = sampleGiveaways().first;
      expect(Giveaway.tryParse(base)!.redeemGeoRestricted, isFalse);
      final on = Giveaway.tryParse({...base, 'redeem_geo_restricted': true})!;
      expect(on.redeemGeoRestricted, isTrue);
      expect(on.withDistance(1).redeemGeoRestricted, isTrue);
      final row = on.toRow(DateTime.utc(2026, 10, 22));
      expect(row['redeem_geo_restricted'], 1);
      expect(Giveaway.tryParse(row)!.redeemGeoRestricted, isTrue);
    });
  });

  group('Detail: keterangan area tukar kode', () {
    for (final b in Brightness.values) {
      testWidgets('terbatas: keterangan radius dan alamat tampil, ${b.name}', (tester) async {
        await pumpDetail(tester, {'redeem_geo_restricted': true, 'radius_km': 5, 'address': 'Jl. Contoh 1'}, b: b);
        expect(find.byKey(const Key('redeem_geo_notice')), findsOneWidget);
        expect(find.text('Kode hanya dapat ditukar di area giveaway (radius 5 km)'), findsOneWidget);
        expect(find.text('Jl. Contoh 1'), findsWidgets);
      });
    }

    testWidgets('tidak terbatas: tanpa keterangan', (tester) async {
      await pumpDetail(tester, {'redeem_geo_restricted': false});
      expect(find.byKey(const Key('redeem_geo_notice')), findsNothing);
    });
  });

  group('cache SQLite v5', () {
    test('v4 -> v5 dan v1 -> v5: kolom baru ada, cache dibuang, tanpa crash', () async {
      for (final from in [1, 4]) {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(singleInstance: false));
        await db.execute('CREATE TABLE cached_giveaways (id TEXT PRIMARY KEY, title TEXT NOT NULL, cached_at TEXT NOT NULL)');
        await db.insert('cached_giveaways', {'id': 'g1', 'title': 'Lama', 'cached_at': 'x'});
        await LocalDb.upgradeTables(db, from, 5);
        final cols = (await db.rawQuery('PRAGMA table_info(cached_giveaways)')).map((r) => r['name']);
        expect(cols, contains('redeem_geo_restricted'));
        expect(await db.query('cached_giveaways'), isEmpty);
        await db.close();
      }
    });

    test('simpan dan baca: redeemGeoRestricted terjaga', () async {
      final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath,
          options: OpenDatabaseOptions(version: LocalDb.dbVersion, onCreate: LocalDb.createTables, singleInstance: false));
      final store = LocalDb.withDatabase(db);
      final g = Giveaway.tryParse({...sampleGiveaways().first, 'redeem_geo_restricted': true})!;
      await store.saveGiveaways([g]);
      expect((await store.loadGiveaway(g.id))!.redeemGeoRestricted, isTrue);
      await db.close();
    });
  });
}
