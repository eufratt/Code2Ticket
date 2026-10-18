import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Basis data lokal SQLite (sqflite) untuk cache dan pengaturan aplikasi.
/// Skema sesuai dengan Code2Ticket_ERD.md bagian SQLite schema.
class LocalDb {
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

  Future<void> close() async {
    if (_db != null && _db!.isOpen) {
      await _db!.close();
      _db = null;
    }
  }
}
