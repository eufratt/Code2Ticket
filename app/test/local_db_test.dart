import 'package:code2ticket/core/db/local_db.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late LocalDb localDb;

  setUp(() async {
    db = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
      options: OpenDatabaseOptions(
        version: LocalDb.dbVersion,
        onCreate: LocalDb.createTables,
      ),
    );
    localDb = LocalDb.withDatabase(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('5 tabel SQLite terbentuk persis sesuai skema ERD', () async {
    final tables = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'table' AND name NOT LIKE 'sqlite_%'",
    );
    final names = tables.map((t) => t['name'] as String).toSet();

    expect(
      names,
      containsAll([
        'cached_giveaways',
        'cached_tickets',
        'search_history',
        'exchange_rate_cache',
        'app_settings',
      ]),
    );

    // Verifikasi index
    final indexes = await db.query(
      'sqlite_master',
      columns: ['name'],
      where: "type = 'index' AND name NOT LIKE 'sqlite_%'",
    );
    final indexNames = indexes.map((i) => i['name'] as String).toSet();
    expect(
      indexNames,
      containsAll([
        'idx_cg_category',
        'idx_cg_end',
        'idx_ct_user',
      ]),
    );
  });

  test('setSetting dan getSetting menyimpan, memperbarui, dan menghapus', () async {
    // Nilai tidak ada -> null
    expect(await localDb.getSetting('non_existent'), isNull);

    // Simpan nilai
    await localDb.setSetting('display_currency', 'IDR');
    expect(await localDb.getSetting('display_currency'), equals('IDR'));

    // Perbarui nilai
    await localDb.setSetting('display_currency', 'USD');
    expect(await localDb.getSetting('display_currency'), equals('USD'));

    // Set null -> nilai terhapus
    await localDb.setSetting('display_currency', null);
    expect(await localDb.getSetting('display_currency'), isNull);
  });

  test('pengaturan per user_id terisolasi dengan benar', () async {
    await localDb.setSetting('biometric_enabled', '1', userId: 'user_a');
    await localDb.setSetting('biometric_enabled', '0', userId: 'user_b');

    expect(await localDb.getSetting('biometric_enabled', userId: 'user_a'), equals('1'));
    expect(await localDb.getSetting('biometric_enabled', userId: 'user_b'), equals('0'));
    expect(await localDb.getSetting('biometric_enabled', userId: 'user_c'), isNull);
    expect(await localDb.getSetting('biometric_enabled', userId: ''), isNull);
  });
}
