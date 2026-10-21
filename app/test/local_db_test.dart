import 'package:code2ticket/core/db/local_db.dart';
import 'package:code2ticket/features/assistant/assistant_models.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
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
        'chat_messages',
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

  group('riwayat chat Asisten', () {
    ChatMessage m(ChatRole r, String t, {List<Giveaway> related = const []}) =>
        ChatMessage(role: r, text: t, related: related, createdAt: DateTime.utc(2026, 10, 19, 3, 42));

    test('tersimpan berurutan per pengguna beserta kartu giveaway; pengguna lain terisolasi', () async {
      const g = Giveaway(id: 'g1', title: 'Laptop Gaming', category: 'gaming', prizeName: 'Laptop', prizeValueIdr: 20000000, winnerCount: 2);
      await localDb.appendChat('u1', [m(ChatRole.user, 'ada gaming?'), m(ChatRole.assistant, 'Ada.', related: [g])]);
      await localDb.appendChat('u2', [m(ChatRole.user, 'rahasia u2')]);
      final rows = await localDb.loadChat('u1');
      expect(rows.map((x) => (x.role, x.text)), [(ChatRole.user, 'ada gaming?'), (ChatRole.assistant, 'Ada.')]);
      expect(rows.last.related.single.title, 'Laptop Gaming');
      expect(rows.last.related.single.prizeValueIdr, 20000000);
      expect(rows.first.confirmed && !rows.first.isError, isTrue);
      expect((await localDb.loadChat('u2')).single.text, 'rahasia u2');
    });

    test('hanya 200 pesan terakhir yang disimpan', () async {
      await localDb.appendChat('u1', [for (var i = 0; i < 205; i++) m(ChatRole.user, 'p$i')]);
      final rows = await localDb.loadChat('u1');
      expect(rows.length, 200);
      expect(rows.first.text, 'p5');
      expect(rows.last.text, 'p204');
    });

    test('clearChat dan clearUserData (logout) hanya menghapus milik pengguna itu', () async {
      await localDb.appendChat('u1', [m(ChatRole.user, 'a')]);
      await localDb.appendChat('u2', [m(ChatRole.user, 'b')]);
      await localDb.clearChat('u1');
      expect(await localDb.loadChat('u1'), isEmpty);
      await localDb.appendChat('u1', [m(ChatRole.user, 'c')]);
      await localDb.clearUserData(userId: 'u1');
      expect(await localDb.loadChat('u1'), isEmpty);
      expect((await localDb.loadChat('u2')).length, 1);
    });

    test('baris rusak dilewati, tidak melempar', () async {
      await db.insert('chat_messages', {'user_id': 'u1', 'role': 'system', 'content': 'x', 'created_at': '2026-10-19T00:00:00Z'});
      await db.insert('chat_messages', {'user_id': 'u1', 'role': 'user', 'content': 'ok', 'related_json': '{bukan json', 'created_at': 'rusak'});
      expect((await localDb.loadChat('u1')).map((x) => x.text), ['ok']);
    });

    test('migrasi v1 -> v2 menambah tabel chat tanpa mengubah tabel lama', () async {
      final old = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath, options: OpenDatabaseOptions(version: 1, singleInstance: false, onCreate: (d, _) async {
        await d.execute("CREATE TABLE app_settings (user_id TEXT NOT NULL DEFAULT '', key TEXT NOT NULL, value TEXT, PRIMARY KEY (user_id, key))");
      }));
      await old.insert('app_settings', {'user_id': 'u', 'key': 'k', 'value': 'v'});
      await LocalDb.upgradeTables(old, 1, LocalDb.dbVersion);
      final store = LocalDb.withDatabase(old);
      await store.appendChat('u', [m(ChatRole.user, 'halo')]);
      expect((await store.loadChat('u')).single.text, 'halo');
      expect(await store.getSetting('k', userId: 'u'), 'v');
      await old.close();
    });
  });
}
