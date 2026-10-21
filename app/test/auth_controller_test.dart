import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/db/local_db.dart';
import 'package:code2ticket/core/security/biometric_service.dart';
import 'package:code2ticket/core/session/session_store.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class FakeBiometricService extends BiometricService {
  FakeBiometricService({this.available = true, this.authResult = true});

  bool available;
  bool authResult;
  int authCalls = 0;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<bool> authenticate([String reason = '']) async {
    authCalls++;
    return authResult;
  }
}

/// Secure storage yang selalu gagal membaca (mis. Keystore rusak).
class _BrokenStorage implements FlutterSecureStorage {
  @override
  dynamic noSuchMethod(Invocation invocation) => Future<String?>.error(PlatformException(code: 'keystore'));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  late Database db;
  late LocalDb localDb;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
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

  http.Response validUserResponse() => http.Response(
        '''
        {
          "ok": true,
          "user": {
            "id": "u1",
            "username": "user1",
            "email": "u1@example.com",
            "full_name": "User One",
            "role": "user",
            "xp": 100,
            "level": 2
          }
        }
        ''',
        200,
        headers: {'content-type': 'application/json'},
      );

  test('restore() dengan token tidak valid (401) menghapus token dan menjadi signedOut', () async {
    FlutterSecureStorage.setMockInitialValues({'c2t_token': 'expired-token'});
    final store = SessionStore();

    final mock = MockClient((req) async {
      expect(req.url.path, equals('/auth/me'));
      expect(req.headers['authorization'], equals('Bearer expired-token'));
      return http.Response(
        '{"ok":false,"error":"invalid_session"}',
        401,
        headers: {'content-type': 'application/json'},
      );
    });

    final api = ApiClient(client: mock, baseUrl: 'https://test.api');
    final auth = AuthController(api, store, db: localDb);

    await auth.restore();

    expect(auth.status, equals(AuthStatus.signedOut));
    expect(auth.token, isNull);
    expect(auth.user, isNull);
    expect(await store.readToken(), isNull);
  });

  test('biometric MATI -> restore() langsung masuk (signedIn)', () async {
    FlutterSecureStorage.setMockInitialValues({'c2t_token': 'valid-token'});
    final store = SessionStore();
    final fakeBio = FakeBiometricService(authResult: false);

    final mock = MockClient((req) async => validUserResponse());
    final api = ApiClient(client: mock, baseUrl: 'https://test.api');
    final auth = AuthController(api, store, db: localDb, biometric: fakeBio);

    await auth.restore();

    expect(auth.status, equals(AuthStatus.signedIn));
    expect(auth.token, equals('valid-token'));
    expect(auth.user?.username, equals('user1'));
    expect(fakeBio.authCalls, equals(0)); // Biometric tidak dipanggil karena mati
  });

  test('biometric MENYALA + authenticate GAGAL -> tetap terkunci (biometricRequired)', () async {
    FlutterSecureStorage.setMockInitialValues({'c2t_token': 'valid-token'});
    final store = SessionStore();
    // Nyalakan biometric di localDb untuk user u1
    await localDb.setSetting('biometric_enabled', '1', userId: 'u1');

    final fakeBio = FakeBiometricService(authResult: false);
    final mock = MockClient((req) async => validUserResponse());
    final api = ApiClient(client: mock, baseUrl: 'https://test.api');
    final auth = AuthController(api, store, db: localDb, biometric: fakeBio);

    await auth.restore();

    expect(auth.status, equals(AuthStatus.biometricRequired));
    expect(auth.token, equals('valid-token'));
    expect(fakeBio.authCalls, equals(1));

    // Coba lagi tapi masih gagal
    final tryAgainFailed = await auth.unlockWithBiometric();
    expect(tryAgainFailed, isFalse);
    expect(auth.status, equals(AuthStatus.biometricRequired));

    // Coba lagi dan berhasil
    fakeBio.authResult = true;
    final tryAgainSuccess = await auth.unlockWithBiometric();
    expect(tryAgainSuccess, isTrue);
    expect(auth.status, equals(AuthStatus.signedIn));
  });

  test('setBiometricEnabled hanya aktif jika verifikasi biometric berhasil', () async {
    final store = SessionStore();
    final fakeBio = FakeBiometricService(authResult: false);
    final mock = MockClient((req) async => validUserResponse());
    final api = ApiClient(client: mock, baseUrl: 'https://test.api');
    final auth = AuthController(api, store, db: localDb, biometric: fakeBio);

    // Gagal verifikasi -> switch gagal nyala
    final failResult = await auth.setBiometricEnabled(true);
    expect(failResult, isFalse);
    expect(await auth.isBiometricEnabled(), isFalse);

    // Berhasil verifikasi -> switch nyala
    fakeBio.authResult = true;
    final okResult = await auth.setBiometricEnabled(true);
    expect(okResult, isTrue);
    expect(await auth.isBiometricEnabled(), isTrue);

    // Matikan switch
    final turnOff = await auth.setBiometricEnabled(false);
    expect(turnOff, isTrue);
    expect(await auth.isBiometricEnabled(), isFalse);
  });

  // ------------------------------------------------------------------ sesi offline (cold start tanpa internet)

  ApiClient apiWith(Future<http.Response> Function(http.Request) h) =>
      ApiClient(client: MockClient(h), baseUrl: 'https://test.api', retryDelays: const []);

  Future<http.Response> down(http.Request _) async => throw http.ClientException('no internet');

  /// Cold start online sekali supaya profil terakhir tersimpan, lalu app "ditutup" (controller baru).
  Future<SessionStore> seedOnlineProfile() async {
    FlutterSecureStorage.setMockInitialValues({'c2t_token': 'valid-token'});
    final store = SessionStore();
    await AuthController(apiWith((_) async => validUserResponse()), store, db: localDb, biometric: FakeBiometricService()).restore();
    return store;
  }

  Future<void> seedUserData() async {
    await localDb.addSearch('u1', 'kopi');
    await localDb.addSearch('u2', 'teh');
    await db.insert('cached_giveaways', {'id': 'g1', 'title': 'G', 'cached_at': '2026-01-01T00:00:00Z'});
    await db.insert('chat_messages', {'user_id': 'u1', 'role': 'user', 'content': 'hai', 'created_at': '2026-01-01T00:00:00Z'});
    await db.insert('chat_messages', {'user_id': 'u2', 'role': 'user', 'content': 'halo', 'created_at': '2026-01-01T00:00:00Z'});
  }

  Future<int> rows(String table) async => (await db.query(table)).length;

  http.Response invalidSession() => http.Response('{"ok":false,"error":"invalid_session"}', 401);

  test('galat jaringan + profil tersimpan -> sesi offline, token dipertahankan, tanpa token di SQLite', () async {
    final store = await seedOnlineProfile();
    final auth = AuthController(apiWith(down), store, db: localDb, biometric: FakeBiometricService());

    await auth.restore();

    expect(auth.status, equals(AuthStatus.signedIn));
    expect(auth.offlineSession, isTrue);
    expect(auth.token, equals('valid-token'));
    expect(auth.user?.id, equals('u1'));
    expect(auth.user?.username, equals('user1'));
    expect(await store.readToken(), equals('valid-token'));
    final saved = await localDb.getSetting(AuthController.profileKey);
    expect(saved, isNot(contains('valid-token')));
    expect(saved, isNot(contains('u1@example.com')));
  });

  test('5xx / respons tak valid diperlakukan sebagai galat jaringan, bukan keluar', () async {
    final store = await seedOnlineProfile();
    for (final res in [http.Response('Bad Gateway', 502), http.Response('oops', 500), http.Response('{"ok":false,"error":"x"}', 500)]) {
      final auth = AuthController(apiWith((_) async => res), store, db: localDb, biometric: FakeBiometricService());
      await auth.restore();
      expect(auth.status, equals(AuthStatus.signedIn), reason: '${res.statusCode}');
      expect(auth.offlineSession, isTrue);
    }
  });

  test('galat jaringan tanpa profil tersimpan -> belum masuk, token tidak dihapus', () async {
    FlutterSecureStorage.setMockInitialValues({'c2t_token': 'valid-token'});
    final store = SessionStore();
    final auth = AuthController(apiWith(down), store, db: localDb);

    await auth.restore();

    expect(auth.status, equals(AuthStatus.signedOut));
    expect(auth.offlineSession, isFalse);
    expect(await store.readToken(), equals('valid-token'));
  });

  test('401 saat cold start -> keluar, token, profil, dan data pengguna dibersihkan', () async {
    final store = await seedOnlineProfile();
    await seedUserData();
    final auth = AuthController(apiWith((_) async => invalidSession()), store, db: localDb);

    await auth.restore();

    expect(auth.status, equals(AuthStatus.signedOut));
    expect(await store.readToken(), isNull);
    expect(await localDb.getSetting(AuthController.profileKey), isNull);
    expect(await rows('cached_giveaways'), 0);
    expect(await localDb.recentSearches('u1'), isEmpty);
    expect(await localDb.recentSearches('u2'), ['teh']); // id lama dikenal dari profil tersimpan: hanya u1 dihapus
    expect((await db.query('chat_messages')).map((r) => r['user_id']), ['u2']);
  });

  test('401 tanpa id pengguna yang diketahui -> semua riwayat pencarian dan chat dibersihkan', () async {
    FlutterSecureStorage.setMockInitialValues({'c2t_token': 'expired'});
    await seedUserData();
    final auth = AuthController(apiWith((_) async => invalidSession()), SessionStore(), db: localDb);

    await auth.restore();

    expect(auth.status, equals(AuthStatus.signedOut));
    expect(await rows('search_history'), 0);
    expect(await rows('chat_messages'), 0);
    expect(await rows('cached_giveaways'), 0);
  });

  test('LocalDb.clearUserData(userId: null) menghapus semua baris pengguna, userId tertentu hanya miliknya', () async {
    await seedUserData();
    await localDb.clearUserData(userId: 'u1');
    expect(await rows('search_history'), 1);
    expect(await rows('chat_messages'), 1);

    await localDb.clearUserData();
    expect(await rows('search_history'), 0);
    expect(await rows('chat_messages'), 0);
  });

  test('galat baca token (secure storage) -> belum masuk tanpa crash', () async {
    final auth = AuthController(apiWith((_) async => validUserResponse()), SessionStore(_BrokenStorage()), db: localDb);

    await auth.restore();

    expect(auth.status, equals(AuthStatus.signedOut));
    expect(auth.token, isNull);
  });

  test('biometric aktif tetap diminta di sesi offline sebelum konten tampil', () async {
    final store = await seedOnlineProfile();
    await localDb.setSetting('biometric_enabled', '1', userId: 'u1');
    final bio = FakeBiometricService(authResult: false);
    final auth = AuthController(apiWith(down), store, db: localDb, biometric: bio);

    await auth.restore();

    expect(bio.authCalls, equals(1));
    expect(auth.status, equals(AuthStatus.biometricRequired));
    expect(auth.offlineSession, isTrue);

    bio.authResult = true;
    expect(await auth.unlockWithBiometric(), isTrue);
    expect(auth.status, equals(AuthStatus.signedIn));
    expect(auth.offlineSession, isTrue);
  });

  test('offline -> online: revalidate() 200 mengakhiri sesi offline, menyegarkan profil dan data', () async {
    final store = await seedOnlineProfile();
    var online = false;
    final auth = AuthController(
      apiWith((_) async => online
          ? http.Response('{"ok":true,"user":{"id":"u1","username":"user1","email":"u1@example.com","full_name":"Nama Baru","role":"user"}}', 200)
          : throw http.ClientException('no internet')),
      store,
      db: localDb,
      biometric: FakeBiometricService(),
    );
    var refreshed = 0;
    auth.backOnline.add(() => refreshed++);
    await auth.restore();

    await auth.revalidate(); // masih offline
    expect(auth.offlineSession, isTrue);
    expect(auth.status, equals(AuthStatus.signedIn));
    expect(refreshed, 0);

    online = true;
    await auth.revalidate();
    expect(auth.offlineSession, isFalse);
    expect(auth.status, equals(AuthStatus.signedIn));
    expect(auth.user?.fullName, equals('Nama Baru'));
    expect(refreshed, 1);
    expect(await localDb.getSetting(AuthController.profileKey), contains('Nama Baru'));
  });

  test('offline -> 401: revalidate() mengeluarkan pengguna dan membersihkan data', () async {
    final store = await seedOnlineProfile();
    await seedUserData();
    var expired = false;
    final auth = AuthController(
      apiWith((_) async => expired ? invalidSession() : throw http.ClientException('x')),
      store,
      db: localDb,
      biometric: FakeBiometricService(),
    );
    await auth.restore();
    expect(auth.offlineSession, isTrue);

    expired = true;
    await auth.revalidate();

    expect(auth.status, equals(AuthStatus.signedOut));
    expect(auth.offlineSession, isFalse);
    expect(await store.readToken(), isNull);
    expect(await localDb.recentSearches('u1'), isEmpty);
  });

  test('aksi tulis di sesi offline ditolak "Butuh koneksi internet" tanpa mengirim permintaan; GET tetap jalan', () async {
    final store = await seedOnlineProfile();
    var sent = <String>[];
    final api = apiWith((r) async {
      sent.add('${r.method} ${r.url.path}');
      throw http.ClientException('no internet');
    });
    final auth = AuthController(api, store, db: localDb, biometric: FakeBiometricService());
    await auth.restore();
    sent = [];
    final authed = AuthedApi(api, auth);

    await expectLater(
      authed.post('/codes/redeem', body: {'code': 'X'}, retry: false),
      throwsA(isA<OfflineRequiredException>().having((e) => e.message, 'message', 'Butuh koneksi internet.')),
    );
    await expectLater(authed.patch('/me', body: {'full_name': 'N'}), throwsA(isA<OfflineRequiredException>()));
    expect(sent, everyElement('GET /auth/me')); // hanya upaya validasi ulang, tidak ada POST/PATCH

    await expectLater(authed.get('/tickets'), throwsA(isA<NetworkException>()));
    expect(auth.status, equals(AuthStatus.signedIn));
  });

  test('sesi online: GET gagal jaringan -> sesi offline (bukan logout); 5xx dan aksi tulis tidak; GET sukses -> online lagi', () async {
    FlutterSecureStorage.setMockInitialValues({'c2t_token': 'tok'});
    var mode = 'online';
    final api = apiWith((r) async {
      if (r.url.path == '/auth/me') return validUserResponse();
      return switch (mode) {
        'down' => throw http.ClientException('no internet'),
        '500' => http.Response('boom', 500),
        _ => http.Response('{"ok":true,"data":[]}', 200),
      };
    });
    final auth = AuthController(api, SessionStore(), db: localDb, biometric: FakeBiometricService());
    await auth.restore();
    expect(auth.offlineSession, isFalse);
    final authed = AuthedApi(api, auth);
    var reloaded = 0;
    auth.backOnline.add(() => reloaded++);

    mode = '500';
    await expectLater(authed.get('/tickets'), throwsA(isA<ServerFaultException>()));
    expect(auth.offlineSession, isFalse); // server menjawab: koneksi ada

    mode = 'down';
    await expectLater(authed.post('/codes/redeem', body: {'code': 'X'}, retry: false), throwsA(isA<NetworkException>()));
    expect(auth.offlineSession, isFalse); // gagal tulis tidak mengubah status sesi

    await expectLater(authed.get('/tickets'), throwsA(isA<NetworkException>()));
    expect(auth.offlineSession, isTrue);
    expect(auth.status, equals(AuthStatus.signedIn));
    expect(auth.token, 'tok');

    mode = 'online';
    await authed.get('/tickets'); // jawaban sukses memicu validasi ulang
    await auth.revalidate();
    expect(auth.offlineSession, isFalse);
    expect(reloaded, 1);
  });
}
