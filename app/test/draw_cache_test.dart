import 'package:code2ticket/core/db/local_db.dart';
import 'package:code2ticket/features/draw/draw_models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

CachedDrawResult sample(String gid, {int total = 12}) => CachedDrawResult(
      giveawayId: gid,
      drawnAtMs: 1760000000000,
      totalTickets: total,
      winners: const [
        DrawWinner(rank: 1, ticketNumber: 7, name: 'bu***'),
        DrawWinner(rank: 2, ticketNumber: 3, name: 'an***'),
      ],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late LocalDb store;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(version: LocalDb.dbVersion, onCreate: LocalDb.createTables, singleInstance: false),
    );
    store = LocalDb.withDatabase(db);
  });
  tearDown(() => db.close());

  group('cached_draw_results', () {
    test('simpan lalu baca: ringkasan dan pemenang utuh', () async {
      await store.saveDrawResult('u1', sample('g1'));
      final r = (await store.loadDrawResult('u1', 'g1'))!;
      expect(r.status, 'drawn');
      expect(r.totalTickets, 12);
      expect(r.drawnAtMs, 1760000000000);
      expect(r.winners.map((w) => (w.rank, w.ticketNumber, w.name)), [(1, 7, 'bu***'), (2, 3, 'an***')]);
      expect(r.cachedAt, isNotNull);
      expect(await store.loadDrawResult('u1', 'g2'), isNull);
    });

    test('simpan ulang memperbarui baris yang sama', () async {
      await store.saveDrawResult('u1', sample('g1'));
      await store.saveDrawResult('u1', sample('g1', total: 20));
      expect((await db.query('cached_draw_results')).length, 1);
      expect((await store.loadDrawResult('u1', 'g1'))!.totalTickets, 20);
    });

    test('tidak ada kolom seed/token: hanya data publik', () async {
      final cols = (await db.rawQuery('PRAGMA table_info(cached_draw_results)')).map((r) => r['name']).toSet();
      expect(cols, {'giveaway_id', 'user_id', 'status', 'drawn_at_ms', 'total_tickets', 'winner_count', 'winners_json', 'cached_at'});
    });

    test('maksimal 50 giveaway per pengguna: yang paling lama dibuang, pengguna lain tidak tersentuh', () async {
      await store.saveDrawResult('u2', sample('lain'));
      for (var i = 0; i < 52; i++) {
        await store.saveDrawResult('u1', sample('g$i'));
      }
      final rows = await db.query('cached_draw_results', where: 'user_id = ?', whereArgs: ['u1']);
      expect(rows.length, LocalDb.drawKeep);
      expect(await store.loadDrawResult('u1', 'g0'), isNull);
      expect(await store.loadDrawResult('u1', 'g1'), isNull);
      expect(await store.loadDrawResult('u1', 'g2'), isNotNull);
      expect(await store.loadDrawResult('u1', 'g51'), isNotNull);
      expect(await store.loadDrawResult('u2', 'lain'), isNotNull);
    });

    test('dipisah per pengguna', () async {
      await store.saveDrawResult('u1', sample('g1'));
      expect(await store.loadDrawResult('u2', 'g1'), isNull);
      await store.saveDrawResult('u2', sample('g1', total: 3));
      expect((await store.loadDrawResult('u1', 'g1'))!.totalTickets, 12);
      expect((await store.loadDrawResult('u2', 'g1'))!.totalTickets, 3);
    });

    test('dibersihkan saat logout', () async {
      await store.saveDrawResult('u1', sample('g1'));
      await store.saveDrawResult('u2', sample('g2'));
      await store.clearUserData(userId: 'u1');
      expect(await db.query('cached_draw_results'), isEmpty);
    });

    test('baris rusak dibaca sebagai tidak ada, tidak melempar', () async {
      await db.insert('cached_draw_results', {
        'giveaway_id': 'g1', 'user_id': 'u1', 'status': 'drawn', 'winner_count': 1, 'winners_json': '{bukan json', 'cached_at': 'rusak',
      });
      expect(await store.loadDrawResult('u1', 'g1'), isNull);
    });

    test('migrasi v5 -> v6 menambah tabel tanpa menghapus data yang ada', () async {
      final old = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(version: 5, singleInstance: false, onCreate: (d, _) async {
        await d.execute("CREATE TABLE app_settings (user_id TEXT NOT NULL DEFAULT '', key TEXT NOT NULL, value TEXT, PRIMARY KEY (user_id, key))");
        await d.execute('CREATE TABLE cached_tickets (id TEXT PRIMARY KEY, user_id TEXT NOT NULL, giveaway_id TEXT NOT NULL, ticket_number INTEGER NOT NULL, cached_at TEXT NOT NULL)');
      }));
      await old.insert('app_settings', {'user_id': 'u', 'key': 'k', 'value': 'v'});
      await old.insert('cached_tickets', {'id': 't1', 'user_id': 'u', 'giveaway_id': 'g1', 'ticket_number': 1, 'cached_at': '2026-10-19T00:00:00Z'});
      await LocalDb.upgradeTables(old, 5, 6);
      final s = LocalDb.withDatabase(old);
      await s.saveDrawResult('u', sample('g1'));
      expect((await s.loadDrawResult('u', 'g1'))!.winners.length, 2);
      expect(await s.getSetting('k', userId: 'u'), 'v');
      expect((await old.query('cached_tickets')).length, 1);
      await LocalDb.upgradeTables(old, 5, 6); // diulang: tidak crash (IF NOT EXISTS)
      await old.close();
    });
  });
}
