import 'dart:async';
import 'dart:convert';

import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/session/session_store.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/giveaways/giveaways_controller.dart';
import 'package:code2ticket/features/tickets/input_code_screen.dart';
import 'package:code2ticket/features/tickets/tickets_controller.dart';
import 'package:code2ticket/features/tickets/tickets_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'support/memory_cache.dart';
import 'models_test.dart' show redeemOk, ticketJson;

/// ApiClient palsu: mencatat panggilan dan menjawab lewat [handler]. Tanpa jaringan.
class FakeApi extends ApiClient {
  FakeApi(this.handler);
  final Future<Map<String, dynamic>> Function(String method, String path, dynamic body) handler;
  final List<({String method, String path, dynamic body, bool retry})> calls = [];

  int posts(String path) => calls.where((c) => c.method == 'POST' && c.path == path).length;

  @override
  Future<Map<String, dynamic>> get(String path, {dynamic body, String? token}) {
    calls.add((method: 'GET', path: path, body: body, retry: true));
    return handler('GET', path, body);
  }

  @override
  Future<Map<String, dynamic>> post(String path, {dynamic body, String? token, bool retry = true}) {
    calls.add((method: 'POST', path: path, body: body, retry: retry));
    return handler('POST', path, body);
  }
}

class FakeAuth extends AuthController {
  FakeAuth(ApiClient api) : super(api, SessionStore()) {
    status = AuthStatus.signedIn;
  }
  String? tok = 'token-uji';
  int invalidated = 0;

  @override
  String? get token => tok;

  @override
  Future<void> handleInvalidSession() async {
    invalidated++;
    tok = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}

Map<String, dynamic> json(String s) => jsonDecode(s) as Map<String, dynamic>;

void main() {
  late FakeApi api;
  late FakeAuth auth;
  late TicketsController tickets;

  Map<String, dynamic> ticketsList() => {
        'ok': true,
        'data': [json(ticketJson)],
      };

  Future<void> pumpScreen(WidgetTester tester) async {
    auth = FakeAuth(api);
    final authed = AuthedApi(api, auth);
    tickets = TicketsController(authed, auth, MemoryCacheStore(), retryInterval: null);
    await tester.pumpWidget(MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthController>.value(value: auth),
        Provider<AuthedApi>.value(value: authed),
        ChangeNotifierProvider<TicketsController>.value(value: tickets),
      ],
      child: const MaterialApp(home: InputCodeScreen()),
    ));
  }

  Future<void> submit(WidgetTester tester, String code) async {
    await tester.enterText(find.byKey(const Key('code_field')), code);
    await tester.tap(find.byKey(const Key('submit_code')));
    await tester.pump();
  }

  testWidgets('kode benar: tiket tampil, body tanpa lokasi, tanpa retry otomatis', (tester) async {
    api = FakeApi((m, p, b) async => p == '/codes/redeem' ? json(redeemOk) : ticketsList());
    await pumpScreen(tester);
    await submit(tester, 'aaaabbbbcccc'); // huruf kecil tanpa strip -> diformat otomatis
    await tester.pumpAndSettle();

    expect(find.text('Tiket berhasil dibuat'), findsOneWidget);
    expect(find.byKey(const Key('ticket_number')), findsOneWidget);
    expect(find.text('#000001'), findsOneWidget);
    expect(find.text('Demo: Laptop Gaming Giveaway'), findsOneWidget);
    final call = api.calls.firstWhere((c) => c.path == '/codes/redeem');
    expect(call.body, {'code': 'AAAA-BBBB-CCCC', 'lat': null, 'lng': null});
    expect(call.retry, isFalse);
    expect(tickets.items, hasLength(1)); // daftar tiket disegarkan setelah sukses
  });

  testWidgets('kode tidak ditemukan', (tester) async {
    api = FakeApi((m, p, b) async => {'ok': false, 'error': 'code_not_found'});
    await pumpScreen(tester);
    await submit(tester, 'AAAA-BBBB-CCCC');
    await tester.pumpAndSettle();
    expect(find.text('Kode tidak ditemukan.'), findsOneWidget);
    expect(find.byKey(const Key('ticket_number')), findsNothing);
  });

  testWidgets('kode sudah dipakai', (tester) async {
    api = FakeApi((m, p, b) async => {'ok': false, 'error': 'code_used'});
    await pumpScreen(tester);
    await submit(tester, 'AAAA-BBBB-CCCC');
    await tester.pumpAndSettle();
    expect(find.text('Kode ini sudah digunakan.'), findsOneWidget);
  });

  testWidgets('format salah ditolak di klien tanpa memanggil server', (tester) async {
    api = FakeApi((m, p, b) async => fail('tidak boleh dipanggil'));
    await pumpScreen(tester);
    await submit(tester, 'ABC');
    await tester.pumpAndSettle();
    expect(find.text('Format kode harus XXXX-XXXX-XXXX.'), findsOneWidget);
    expect(api.calls, isEmpty);
  });

  testWidgets('rate_limited menampilkan sisa menit', (tester) async {
    api = FakeApi((m, p, b) async => {'ok': false, 'error': 'rate_limited', 'retry_after_seconds': 540});
    await pumpScreen(tester);
    await submit(tester, 'AAAA-BBBB-CCCC');
    await tester.pumpAndSettle();
    expect(find.textContaining('9 menit'), findsOneWidget);
  });

  testWidgets('jaringan putus: pesan arahkan cek My Tickets, bukan sukses', (tester) async {
    api = FakeApi((m, p, b) async => throw NetworkException('Tidak ada koneksi internet.'));
    await pumpScreen(tester);
    await submit(tester, 'AAAA-BBBB-CCCC');
    await tester.pumpAndSettle();
    expect(find.textContaining('Cek menu My Tickets'), findsOneWidget);
    expect(api.posts('/codes/redeem'), 1);
  });

  testWidgets('tombol ditekan berulang saat menunggu: hanya satu permintaan terkirim', (tester) async {
    final gate = Completer<Map<String, dynamic>>();
    api = FakeApi((m, p, b) => p == '/codes/redeem' ? gate.future : Future.value(ticketsList()));
    await pumpScreen(tester);
    await submit(tester, 'AAAA-BBBB-CCCC');

    // Tombol nonaktif + indikator memuat selama menunggu.
    expect(tester.widget<FilledButton>(find.byKey(const Key('submit_code'))).onPressed, isNull);
    await tester.tap(find.byKey(const Key('submit_code')), warnIfMissed: false);
    await tester.tap(find.byKey(const Key('submit_code')), warnIfMissed: false);
    await tester.pump();
    // Penjaga di controller juga menolak panggilan langsung kedua.
    expect(await tickets.redeem('AAAA-BBBB-CCCC'), isNull);
    expect(api.posts('/codes/redeem'), 1);

    gate.complete(json(redeemOk));
    await tester.pumpAndSettle();
    expect(find.text('#000001'), findsOneWidget);
    expect(api.posts('/codes/redeem'), 1);
  });

  testWidgets('sesi berakhir (401): logout otomatis, tidak ada pesan galat', (tester) async {
    api = FakeApi((m, p, b) async => throw InvalidSessionException());
    await pumpScreen(tester);
    await submit(tester, 'AAAA-BBBB-CCCC');
    await tester.pumpAndSettle();
    expect(auth.invalidated, 1);
    expect(find.textContaining('Terjadi kesalahan'), findsNothing);
    expect(tickets.redeeming, isFalse);
  });

  test('CodeInputFormatter: huruf besar, strip tiap 4, maksimal 12 karakter', () {
    final f = CodeInputFormatter();
    String run(String s) => f.formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: s)).text;
    expect(run('abcd1234efgh9'), 'ABCD-1234-EFGH');
    expect(run('ab-cd 12'), 'ABCD-12');
    expect(run(''), '');
  });

  group('TicketsController', () {
    test('mengelompokkan per giveaway dan menghitung tiket per giveaway', () async {
      api = FakeApi((m, p, b) async => {
            'ok': true,
            'data': [
              json(ticketJson),
              {...json(ticketJson), 'id': 't2', 'ticket_number': 2},
              {...json(ticketJson), 'id': 't3', 'giveaway_id': 'g-lain', 'result': 'winner'},
              'sampah',
            ],
          });
      auth = FakeAuth(api);
      tickets = TicketsController(AuthedApi(api, auth), auth, MemoryCacheStore(), retryInterval: null);
      await tickets.load();
      expect(tickets.state, LoadState.loaded);
      expect(tickets.items, hasLength(3));
      expect(tickets.grouped.keys.length, 2);
      expect(tickets.countFor('5deb977d-ff30-4e4e-849d-ff389fe51e6a'), 2);
      expect(ticketResultLabel(tickets.items.last.result), 'Menang');
    });

    test('GET gagal -> state error; 401 -> logout dan data dikosongkan', () async {
      var fail401 = false;
      api = FakeApi((m, p, b) async {
        if (fail401) throw InvalidSessionException();
        throw NetworkException('Tidak ada koneksi internet.');
      });
      auth = FakeAuth(api);
      tickets = TicketsController(AuthedApi(api, auth), auth, MemoryCacheStore(), retryInterval: null);
      await tickets.load();
      expect(tickets.state, LoadState.error);
      expect(tickets.error, 'Tidak ada koneksi internet.');
      fail401 = true;
      await tickets.load();
      expect(auth.invalidated, 1);
      expect(tickets.items, isEmpty);
    });

    test('load bersamaan memakai satu permintaan', () async {
      api = FakeApi((m, p, b) async => {'ok': true, 'data': []});
      auth = FakeAuth(api);
      tickets = TicketsController(AuthedApi(api, auth), auth, MemoryCacheStore(), retryInterval: null);
      await Future.wait([tickets.load(), tickets.load(), tickets.load()]);
      expect(api.calls.where((c) => c.path == '/tickets'), hasLength(1));
    });
  });
}
