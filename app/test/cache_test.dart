import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/db/local_db.dart';
import 'package:code2ticket/core/session/session_store.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/auth/auth_models.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart';
import 'package:code2ticket/features/tickets/ticket_models.dart';
import 'package:code2ticket/features/tickets/tickets_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'input_code_test.dart' show FakeApi, FakeAuth, json;
import 'models_test.dart' show giveawayJson, ticketJson;
import 'support/memory_cache.dart';

Giveaway gw(String id, {String title = 'T', DateTime? start, DateTime? end, double? lat, double? lng, String status = 'active'}) {
  final now = DateTime.now();
  return Giveaway(
    id: id,
    title: title,
    category: 'tech',
    prizeName: 'Hadiah',
    prizeValueUsd: 250.5,
    latitude: lat,
    longitude: lng,
    startAt: start ?? now.subtract(const Duration(hours: 1)),
    endAt: end ?? now.add(const Duration(hours: 2)),
    drawAt: (end ?? now.add(const Duration(hours: 2))).add(const Duration(hours: 1)),
    winnerCount: 2,
    ticketCount: 3,
    status: status,
    distanceKm: 4.2, // tidak boleh ikut tersimpan
  );
}

/// Contoh respons asli, tetapi jadwalnya dibuat relatif terhadap sekarang (tanggal contoh sudah lewat).
Map<String, dynamic> liveGiveawayJson() {
  final now = DateTime.now().toUtc();
  String iso(Duration d) => now.add(d).toIso8601String();
  return {
    ...json(giveawayJson),
    'start_at': iso(const Duration(hours: -1)),
    'end_at': iso(const Duration(hours: 2)),
    'draw_at': iso(const Duration(hours: 3)),
  };
}

Ticket tk(String id, String gid, {int n = 1}) => Ticket(
      id: id,
      ticketNumber: n,
      giveawayId: gid,
      giveawayTitle: 'T',
      prizeName: 'P',
      result: TicketResult.winner,
      codeMasked: '****-****-ABCD',
      createdAt: DateTime.utc(2026, 10, 18, 10),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  group('LocalDb: cache giveaway/tiket dan riwayat pencarian', () {
    late Database db;
    late LocalDb local;

    setUp(() async {
      db = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
        options: OpenDatabaseOptions(version: LocalDb.dbVersion, onCreate: LocalDb.createTables),
      );
      local = LocalDb.withDatabase(db);
    });
    tearDown(() => db.close());

    test('giveaway: simpan lalu baca kembali (tanggal, angka, koordinat); jarak tidak disimpan', () async {
      final g = Giveaway.tryParse(json(giveawayJson))!;
      await local.saveGiveaways([g, gw('b', lat: -6.2, lng: 106.8)]);
      final back = (await local.loadGiveaway(g.id))!;
      expect(back.title, g.title);
      expect(back.prizeValueUsd, 1200);
      expect(back.drawAt!.toUtc(), g.drawAt!.toUtc());
      expect(back.winnerCount, 3);
      final b = (await local.loadGiveaway('b'))!;
      expect([b.latitude, b.longitude], [-6.2, 106.8]);
      expect(b.distanceKm, isNull);
      expect(await local.loadGiveaways(), hasLength(2));
      expect(await local.giveawaysUpdatedAt(), isNotNull);
    });

    test('giveaway: simpan ulang id yang sama menimpa, tidak menggandakan', () async {
      await local.saveGiveaways([gw('a', title: 'Lama')]);
      await local.saveGiveaways([gw('a', title: 'Baru')]);
      final all = await local.loadGiveaways();
      expect(all, hasLength(1));
      expect(all.single.title, 'Baru');
    });

    test('cache kosong: loadGiveaway null, updatedAt null', () async {
      expect(await local.loadGiveaway('x'), isNull);
      expect(await local.giveawaysUpdatedAt(), isNull);
    });

    test('tiket: terikat user_id, replace hanya menyentuh milik pengguna itu', () async {
      await local.replaceTickets('u1', [tk('t1', 'g1'), tk('t2', 'g1', n: 2)]);
      await local.replaceTickets('u2', [tk('t3', 'g2')]);
      await local.replaceTickets('u1', [tk('t4', 'g3')]);
      expect((await local.loadTickets('u1')).map((t) => t.id), ['t4']);
      expect((await local.loadTickets('u2')).map((t) => t.id), ['t3']);
      final t = (await local.loadTickets('u2')).single;
      expect(t.result, TicketResult.winner);
      expect(t.codeMasked, '****-****-ABCD');
      expect(await local.ticketsUpdatedAt('u1'), isNotNull);
      expect(await local.ticketsUpdatedAt('u3'), isNull);
    });

    test('riwayat pencarian: terbaru dulu, dedupe, maks. 10, hapus satu/semua, per pengguna', () async {
      await local.addSearch('u1', 'laptop');
      await local.addSearch('u1', 'tiket');
      await local.addSearch('u1', 'laptop'); // naik ke atas, tidak dobel
      await local.addSearch('u2', 'milik u2');
      await local.addSearch('u1', '   '); // kosong diabaikan
      expect(await local.recentSearches('u1'), ['laptop', 'tiket']);
      for (var i = 0; i < 12; i++) {
        await local.addSearch('u1', 'q$i');
      }
      final recent = await local.recentSearches('u1');
      expect(recent, hasLength(10));
      expect(recent.first, 'q11');
      await local.deleteSearch('u1', 'q11');
      expect((await local.recentSearches('u1')).first, 'q10');
      await local.clearSearches('u1');
      expect(await local.recentSearches('u1'), isEmpty);
      expect(await local.recentSearches('u2'), ['milik u2']);
    });

    test('clearUserData: cache giveaway + tiket dihapus, riwayat milik pengguna itu saja', () async {
      await local.saveGiveaways([gw('a')]);
      await local.replaceTickets('u1', [tk('t1', 'g')]);
      await local.addSearch('u1', 'x');
      await local.addSearch('u2', 'y');
      await local.clearUserData(userId: 'u1');
      expect(await local.loadGiveaways(), isEmpty);
      expect(await local.loadTickets('u1'), isEmpty);
      expect(await local.recentSearches('u1'), isEmpty);
      expect(await local.recentSearches('u2'), ['y']);
    });

    test('tidak ada kolom token/password/lokasi pengguna di tabel cache', () async {
      for (final table in ['cached_giveaways', 'cached_tickets', 'search_history']) {
        final cols = (await db.rawQuery('PRAGMA table_info($table)')).map((r) => r['name'] as String);
        expect(cols.where((c) => RegExp('token|password|user_lat|user_lng').hasMatch(c)), isEmpty, reason: table);
      }
    });

    test('logout (AuthController) membersihkan cache dan riwayat pengguna', () async {
      FlutterSecureStorage.setMockInitialValues({});
      final api = FakeApi((m, p, b) async {
        if (p == '/auth/salt') return {'ok': true, 'salt': 'a' * 32};
        if (p == '/auth/login') {
          return {
            'ok': true,
            'token': 't' * 64,
            'user': {'id': 'u1', 'username': 'user1', 'email': 'u@x.id', 'full_name': 'U', 'role': 'user', 'xp': 0, 'level': 1},
          };
        }
        return {'ok': true};
      });
      final auth = AuthController(api, SessionStore(), db: local);
      expect((await auth.login(identifier: 'user1', password: 'Passw0rd!1')).success, isTrue);
      await local.saveGiveaways([gw('a')]);
      await local.replaceTickets('u1', [tk('t1', 'g')]);
      await local.addSearch('u1', 'laptop');

      await auth.logout();

      expect(auth.status, AuthStatus.signedOut);
      expect(await local.loadGiveaways(), isEmpty);
      expect(await local.loadTickets('u1'), isEmpty);
      expect(await local.recentSearches('u1'), isEmpty);
    });
  });

  group('GiveawaysController: online simpan, offline baca cache', () {
    late FakeApi api;
    late FakeAuth auth;
    late MemoryCacheStore cache;
    var online = true;

    GiveawaysController make({Duration? retry}) {
      cache = MemoryCacheStore();
      auth = FakeAuth(api);
      return GiveawaysController(AuthedApi(api, auth), auth, cache, retryInterval: retry);
    }

    setUp(() {
      online = true;
      api = FakeApi((m, p, b) async {
        if (!online) throw NetworkException('Tidak ada koneksi internet.');
        if (p.startsWith('/giveaways/')) {
          return p.endsWith('/hilang') ? {'ok': false, 'error': 'not_found'} : liveGiveawayJson();
        }
        return {'ok': true, 'data': [liveGiveawayJson()]};
      });
    });

    test('online: tampil dan tersimpan ke cache', () async {
      final c = make();
      await c.load();
      expect(c.state, LoadState.loaded);
      expect(c.offline, isFalse);
      expect(c.items, hasLength(1));
      expect(cache.giveaways.keys, ['5deb977d-ff30-4e4e-849d-ff389fe51e6a']);
    });

    test('offline: baca cache, ditandai offline + waktu pembaruan', () async {
      final c = make();
      await c.load();
      online = false;
      c.items = const [];
      await c.load();
      expect(c.offline, isTrue);
      expect(c.state, LoadState.loaded);
      expect(c.items.single.title, 'Demo: Laptop Gaming Giveaway');
      expect(c.cachedAt, isNotNull);
    });

    test('offline: hanya giveaway yang masih aktif menurut waktu yang tampil di Home', () async {
      final c = make();
      cache.giveaways['lewat'] = gw('lewat', end: DateTime.now().subtract(const Duration(hours: 1)));
      cache.giveaways['drawn'] = gw('drawn', status: 'drawn');
      cache.giveaways['aktif'] = gw('aktif');
      online = false;
      await c.load();
      expect(c.items.map((g) => g.id), ['aktif']);
    });

    test('offline tanpa cache: state error dengan pesan, bukan daftar kosong', () async {
      final c = make();
      online = false;
      await c.load();
      expect(c.state, LoadState.error);
      expect(c.error, 'Tidak ada koneksi internet.');
      expect(c.offline, isFalse);
    });

    test('cache rusak tidak mengganggu pemuatan online', () async {
      final c = make();
      cache.failing = true;
      await c.load();
      expect(c.state, LoadState.loaded);
      expect(c.items, hasLength(1));
    });

    test('muat ulang otomatis saat online kembali, banner offline hilang', () async {
      final c = make(retry: const Duration(milliseconds: 30));
      await c.load();
      online = false;
      await c.load();
      expect(c.offline, isTrue);
      online = true;
      await Future.delayed(const Duration(milliseconds: 150));
      expect(c.offline, isFalse);
      expect(c.cachedAt, isNull);
      c.dispose();
    });

    test('masih offline: muat ulang berkala tidak mengubah tampilan cache', () async {
      final c = make(retry: const Duration(milliseconds: 30));
      await c.load();
      online = false;
      await c.load();
      final before = api.calls.length;
      await Future.delayed(const Duration(milliseconds: 120));
      expect(api.calls.length, greaterThan(before)); // sudah mencoba lagi
      expect(c.offline, isTrue);
      expect(c.items, hasLength(1));
      c.dispose();
    });

    test('logout mengosongkan daftar dan menghentikan muat ulang', () async {
      final c = make(retry: const Duration(milliseconds: 30));
      await c.load();
      online = false;
      await c.load();
      await auth.handleInvalidSession();
      expect(c.items, isEmpty);
      expect(c.offline, isFalse);
      final before = api.calls.length;
      await Future.delayed(const Duration(milliseconds: 120));
      expect(api.calls.length, before);
      c.dispose();
    });

    test('fetchOne: online simpan; 404 -> notFound; offline -> cache; tanpa cache -> error', () async {
      final c = make();
      final ok = await c.fetchOne('5deb977d-ff30-4e4e-849d-ff389fe51e6a');
      expect(ok.giveaway!.title, 'Demo: Laptop Gaming Giveaway');
      expect(ok.offline, isFalse);
      expect(cache.giveaways, hasLength(1));
      expect((await c.fetchOne('hilang')).notFound, isTrue);

      online = false;
      final off = await c.fetchOne('5deb977d-ff30-4e4e-849d-ff389fe51e6a');
      expect(off.offline, isTrue);
      expect(off.giveaway, isNotNull);
      expect(off.cachedAt, isNotNull);
      final none = await c.fetchOne('belum-pernah-dilihat');
      expect(none.giveaway, isNull);
      expect(none.error, 'Tidak ada koneksi internet.');
    });
  });

  group('TicketsController: cache per pengguna', () {
    late FakeApi api;
    late FakeAuth auth;
    late MemoryCacheStore cache;
    var online = true;

    TicketsController make({Duration? retry}) {
      cache = MemoryCacheStore();
      auth = FakeAuth(api);
      auth.user = AppUser(id: 'u1', username: 'a', email: 'a@x.id', fullName: 'A', role: 'user', xp: 0, level: 1);
      return TicketsController(AuthedApi(api, auth), auth, cache, retryInterval: retry);
    }

    setUp(() {
      online = true;
      api = FakeApi((m, p, b) async {
        if (!online) throw NetworkException('Tidak ada koneksi internet.');
        return {'ok': true, 'data': [json(ticketJson)]};
      });
    });

    test('online simpan, offline baca, online kembali memperbarui', () async {
      final c = make(retry: const Duration(milliseconds: 30));
      await c.load();
      expect(cache.tickets['u1'], hasLength(1));

      online = false;
      c.items = const [];
      await c.load();
      expect(c.offline, isTrue);
      expect(c.items.single.codeMasked, '****-****-7FES');
      expect(c.cachedAt, isNotNull);

      online = true;
      await Future.delayed(const Duration(milliseconds: 150));
      expect(c.offline, isFalse);
      c.dispose();
    });

    test('cache milik pengguna lain tidak ikut tampil', () async {
      final c = make();
      cache.tickets['u2'] = [tk('x', 'g')];
      online = false;
      await c.load();
      expect(c.state, LoadState.error);
      expect(c.items, isEmpty);
    });

    test('logout mengosongkan data di memori', () async {
      final c = make();
      await c.load();
      expect(c.items, isNotEmpty);
      await auth.handleInvalidSession();
      expect(c.items, isEmpty);
      expect(c.state, LoadState.idle);
    });
  });
}
