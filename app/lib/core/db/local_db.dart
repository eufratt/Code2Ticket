import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../features/giveaways/giveaway_models.dart';
import '../../features/tickets/ticket_models.dart';
import 'cache_store.dart';
import 'rate_cache.dart';

/// Basis data lokal SQLite (sqflite) untuk cache dan pengaturan aplikasi.
/// Skema sesuai dengan Code2Ticket_ERD.md bagian SQLite schema.
class LocalDb implements CacheStore, RateCache, SettingsStore {
  LocalDb._();
  static final LocalDb instance = LocalDb._();

  Database? _db;

  /// Memungkinkan injeksi database untuk unit test.
  LocalDb.withDatabase(Database db) : _db = db;

  Future<Database> get database async {
    if (_db != null && _db!.isOpen) return _db!;
    _db = await _initDb();
    return _db!;
  }

  static const String dbName = 'code2ticket.db';
  static const int dbVersion = 1;

  Future<Database> _initDb() async {
    final dbPath = await getDatabasesPath();
    final path = p.join(dbPath, dbName);
    return await openDatabase(
      path,
      version: dbVersion,
      onCreate: createTables,
    );
  }

  static Future<void> createTables(Database db, int version) async {
    await db.execute('''
      CREATE TABLE cached_giveaways (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, description TEXT, organizer TEXT, category TEXT,
        prize_name TEXT, prize_value_usd REAL, latitude REAL, longitude REAL, address TEXT, radius_km REAL,
        start_at TEXT, end_at TEXT, draw_at TEXT, winner_count INTEGER, ticket_count INTEGER,
        status TEXT, seed_hash TEXT, cached_at TEXT NOT NULL
      )
    ''');
    await db.execute(
        'CREATE INDEX idx_cg_category ON cached_giveaways(category)');
    await db.execute('CREATE INDEX idx_cg_end ON cached_giveaways(end_at)');

    await db.execute('''
      CREATE TABLE cached_tickets (
        id TEXT PRIMARY KEY, user_id TEXT NOT NULL, giveaway_id TEXT NOT NULL, giveaway_title TEXT,
        prize_name TEXT, ticket_number INTEGER NOT NULL, result TEXT, end_at TEXT, draw_at TEXT,
        code_masked TEXT, created_at TEXT, cached_at TEXT NOT NULL
      )
    ''');
    await db.execute('CREATE INDEX idx_ct_user ON cached_tickets(user_id)');

    await db.execute('''
      CREATE TABLE search_history (
        id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL, query TEXT NOT NULL, created_at TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE exchange_rate_cache (
        base TEXT NOT NULL, target TEXT NOT NULL, rate REAL NOT NULL, rate_date TEXT, fetched_at TEXT NOT NULL,
        PRIMARY KEY (base, target)
      )
    ''');

    await db.execute('''
      CREATE TABLE app_settings (
        user_id TEXT NOT NULL DEFAULT '', key TEXT NOT NULL, value TEXT,
        PRIMARY KEY (user_id, key)
      )
    ''');
  }

  @override
  Future<String?> getSetting(String key, {String userId = ''}) async {
    final db = await database;
    final maps = await db.query(
      'app_settings',
      columns: ['value'],
      where: 'user_id = ? AND key = ?',
      whereArgs: [userId, key],
      limit: 1,
    );
    if (maps.isEmpty) return null;
    return maps.first['value'] as String?;
  }

  @override
  Future<void> setSetting(String key, String? value,
      {String userId = ''}) async {
    final db = await database;
    if (value == null) {
      await db.delete(
        'app_settings',
        where: 'user_id = ? AND key = ?',
        whereArgs: [userId, key],
      );
    } else {
      await db.insert(
        'app_settings',
        {'user_id': userId, 'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
  }

  // ---------------------------------------------------------------- cache giveaway / tiket

  @override
  Future<void> saveGiveaways(List<Giveaway> items) async {
    final db = await database;
    final now = DateTime.now();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final g in items) {
        batch.insert('cached_giveaways', g.toRow(now), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<List<Giveaway>> loadGiveaways() async {
    final db = await database;
    final rows = await db.query('cached_giveaways', orderBy: 'end_at ASC');
    return [for (final r in rows) ?Giveaway.tryParse(r)];
  }

  @override
  Future<Giveaway?> loadGiveaway(String id) async {
    final db = await database;
    final rows = await db.query('cached_giveaways', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Giveaway.tryParse(rows.first);
  }

  @override
  Future<DateTime?> giveawaysUpdatedAt() async {
    final db = await database;
    final r = await db.rawQuery('SELECT MAX(cached_at) AS t FROM cached_giveaways');
    return DateTime.tryParse(r.first['t'] as String? ?? '')?.toLocal();
  }

  @override
  Future<void> replaceTickets(String userId, List<Ticket> items) async {
    final db = await database;
    final now = DateTime.now();
    await db.transaction((txn) async {
      await txn.delete('cached_tickets', where: 'user_id = ?', whereArgs: [userId]);
      final batch = txn.batch();
      for (final t in items) {
        batch.insert('cached_tickets', t.toRow(userId, now), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    });
  }

  @override
  Future<List<Ticket>> loadTickets(String userId) async {
    final db = await database;
    final rows = await db.query('cached_tickets',
        where: 'user_id = ?', whereArgs: [userId], orderBy: 'created_at DESC, ticket_number DESC');
    return [for (final r in rows) ?Ticket.tryParse(r)];
  }

  @override
  Future<DateTime?> ticketsUpdatedAt(String userId) async {
    final db = await database;
    final r = await db.rawQuery('SELECT MAX(cached_at) AS t FROM cached_tickets WHERE user_id = ?', [userId]);
    return DateTime.tryParse(r.first['t'] as String? ?? '')?.toLocal();
  }

  // ---------------------------------------------------------------- riwayat pencarian

  @override
  Future<List<String>> recentSearches(String userId, {int limit = 10}) async {
    final db = await database;
    final rows = await db.query('search_history',
        columns: ['query'], where: 'user_id = ?', whereArgs: [userId], orderBy: 'id DESC', limit: limit);
    return [for (final r in rows) r['query'] as String];
  }

  /// Kata yang sama dipindah ke paling atas; hanya 10 terakhir yang disimpan.
  @override
  Future<void> addSearch(String userId, String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('search_history', where: 'user_id = ? AND query = ?', whereArgs: [userId, q]);
      await txn.insert('search_history',
          {'user_id': userId, 'query': q, 'created_at': DateTime.now().toUtc().toIso8601String()});
      await txn.rawDelete(
        'DELETE FROM search_history WHERE user_id = ? AND id NOT IN '
        '(SELECT id FROM search_history WHERE user_id = ? ORDER BY id DESC LIMIT 10)',
        [userId, userId],
      );
    });
  }

  @override
  Future<void> deleteSearch(String userId, String query) async {
    final db = await database;
    await db.delete('search_history', where: 'user_id = ? AND query = ?', whereArgs: [userId, query]);
  }

  @override
  Future<void> clearSearches(String userId) async {
    final db = await database;
    await db.delete('search_history', where: 'user_id = ?', whereArgs: [userId]);
  }

  @override
  Future<void> clearUserData({String? userId}) async {
    final db = await database;
    await db.delete('cached_giveaways');
    await db.delete('cached_tickets');
    if (userId != null) await clearSearches(userId);
  }

  // ---------------------------------------------------------------- cache kurs (exchange_rate_cache)

  @override
  Future<void> saveRates(String base, List<CachedRate> rates) async {
    final db = await database;
    final batch = db.batch();
    for (final r in rates) {
      batch.insert(
        'exchange_rate_cache',
        {
          'base': base,
          'target': r.target,
          'rate': r.rate,
          'rate_date': r.rateDate,
          'fetched_at': r.fetchedAt.toUtc().toIso8601String(),
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
  }

  @override
  Future<List<CachedRate>> loadRates(String base) async {
    final db = await database;
    final rows = await db.query('exchange_rate_cache', where: 'base = ?', whereArgs: [base]);
    final out = <CachedRate>[];
    for (final r in rows) {
      final target = r['target'] as String?;
      final rate = (r['rate'] as num?)?.toDouble();
      final at = DateTime.tryParse(r['fetched_at'] as String? ?? '');
      if (target == null || rate == null || at == null) continue;
      out.add(CachedRate(target: target, rate: rate, rateDate: r['rate_date'] as String?, fetchedAt: at.toLocal()));
    }
    return out;
  }

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
