import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/db/local_db.dart';
import 'package:code2ticket/core/security/biometric_service.dart';
import 'package:code2ticket/core/session/session_store.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
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
}
