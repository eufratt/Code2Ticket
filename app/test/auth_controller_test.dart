import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/session/session_store.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStorage.setMockInitialValues({});
  });

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
    final auth = AuthController(api, store);

    await auth.restore();

    expect(auth.status, equals(AuthStatus.signedOut));
    expect(auth.token, isNull);
    expect(auth.user, isNull);
    expect(await store.readToken(), isNull);
  });

  test('restore() dengan token valid (200) menjadi signedIn', () async {
    FlutterSecureStorage.setMockInitialValues({'c2t_token': 'valid-token'});
    final store = SessionStore();

    final mock = MockClient((req) async {
      expect(req.url.path, equals('/auth/me'));
      return http.Response(
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
    });

    final api = ApiClient(client: mock, baseUrl: 'https://test.api');
    final auth = AuthController(api, store);

    await auth.restore();

    expect(auth.status, equals(AuthStatus.signedIn));
    expect(auth.token, equals('valid-token'));
    expect(auth.user?.username, equals('user1'));
    expect(auth.user?.level, equals(2));
  });
}
