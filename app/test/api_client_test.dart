import 'dart:async';

import 'package:code2ticket/core/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const testBase = 'https://api.test';

  test('HTTP 401 melempar InvalidSessionException', () async {
    final mock = MockClient((req) async {
      return http.Response(
        '{"ok":false,"error":"invalid_session"}',
        401,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = ApiClient(client: mock, baseUrl: testBase);
    expect(
      () => client.get('/auth/me', token: 'bad-token'),
      throwsA(isA<InvalidSessionException>()),
    );
  });

  test('HTTP 403 melempar ForbiddenException', () async {
    final mock = MockClient((req) async {
      return http.Response(
        '{"ok":false,"error":"forbidden"}',
        403,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = ApiClient(client: mock, baseUrl: testBase);
    expect(
      () => client.get('/admin/giveaways', token: 'user-token'),
      throwsA(isA<ForbiddenException>()),
    );
  });

  test('HTTP 200 ok:false dikembalikan apa adanya (gagal bisnis)', () async {
    final mock = MockClient((req) async {
      return http.Response(
        '{"ok":false,"error":"invalid_credentials","attempts_left":4}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = ApiClient(client: mock, baseUrl: testBase);
    final res = await client.post('/auth/login', body: {
      'identifier': 'user',
      'password_hash': 'dummy',
    });

    expect(res['ok'], isFalse);
    expect(res['error'], equals('invalid_credentials'));
    expect(res['attempts_left'], equals(4));
  });

  test('retry GET pada 404 edge (x-render-routing: no-server) lalu sukses',
      () async {
    int calls = 0;
    final mock = MockClient((req) async {
      calls++;
      if (calls == 1) {
        return http.Response(
          'Not Found',
          404,
          headers: {'x-render-routing': 'no-server'},
        );
      }
      return http.Response(
        '{"ok":true,"user":{"id":"u1","username":"test"}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = ApiClient(
      client: mock,
      baseUrl: testBase,
      retryDelays: [Duration.zero, Duration.zero],
    );

    final res = await client.get('/auth/me', token: 'tok');
    expect(calls, equals(2));
    expect(res['ok'], isTrue);
    expect((res['user'] as Map)['username'], equals('test'));
  });

  test('POST tidak retry setelah timeout menunggu respons', () async {
    int calls = 0;
    final mock = MockClient((req) async {
      calls++;
      throw TimeoutException('Request timeout');
    });

    final client = ApiClient(
      client: mock,
      baseUrl: testBase,
      retryDelays: [Duration.zero, Duration.zero],
    );

    await expectLater(
      () => client.post('/auth/register', body: {'username': 'test'}),
      throwsA(isA<NetworkException>()),
    );
    expect(calls, equals(1));
  });

  test('GET timeout diulangi hingga retryDelays habis', () async {
    int calls = 0;
    final mock = MockClient((req) async {
      calls++;
      throw TimeoutException('Request timeout');
    });

    final client = ApiClient(
      client: mock,
      baseUrl: testBase,
      retryDelays: [Duration.zero, Duration.zero],
    );

    await expectLater(
      () => client.get('/auth/me'),
      throwsA(isA<NetworkException>()),
    );
    expect(calls, equals(3)); // 1 initial + 2 retries
  });

  test('PATCH mengirim header dan body dengan benar', () async {
    final mock = MockClient((req) async {
      expect(req.method, equals('PATCH'));
      expect(req.headers['authorization'], equals('Bearer tok123'));
      expect(req.headers['content-type'], contains('application/json'));
      return http.Response(
        '{"ok":true,"user":{"full_name":"New Name"}}',
        200,
        headers: {'content-type': 'application/json'},
      );
    });

    final client = ApiClient(client: mock, baseUrl: testBase);
    final res = await client.patch('/me', body: {'full_name': 'New Name'}, token: 'tok123');
    expect(res['ok'], isTrue);
  });
}
