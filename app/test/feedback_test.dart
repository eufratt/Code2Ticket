import 'dart:async';

import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/widgets/widgets.dart' show PrimaryButton;
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/feedback/feedback_controller.dart';
import 'package:code2ticket/features/feedback/feedback_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'input_code_test.dart' show FakeApi, FakeAuth;
import 'support/display.dart';

// Bentuk asli GET /feedback (backend/src/services/features.js): larik {id, suggestion, impression, created_at}.
const _row = {'id': 7, 'suggestion': 'Tambah materi sensor', 'impression': 'Seru sekali', 'created_at': '2026-10-19T04:00:00.000Z'};

void main() {
  group('FeedbackEntry', () {
    test('mengurai baris asli; baris rusak dilewati', () {
      final e = FeedbackEntry.tryParse(_row)!;
      expect([e.id, e.suggestion, e.impression], [7, 'Tambah materi sensor', 'Seru sekali']);
      expect(e.createdAt!.toUtc(), DateTime.utc(2026, 10, 19, 4));
      expect(FeedbackEntry.tryParse({'id': 1, 'suggestion': 'x'}), isNull);
      expect(FeedbackEntry.tryParse('rusak'), isNull);
    });
  });

  group('FeedbackScreen', () {
    late FakeApi api;
    late FakeAuth auth;
    final history = <Map<String, dynamic>>[];

    Future<void> pump(WidgetTester tester, Future<Map<String, dynamic>> Function(String m, String p, dynamic b) post) async {
      tester.view.physicalSize = const Size(400 * 3, 1000 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      api = FakeApi((m, p, b) async => m == 'GET' ? {'ok': true, 'data': List.of(history)} : post(m, p, b));
      auth = FakeAuth(api);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<AuthedApi>.value(value: AuthedApi(api, auth)),
          ...displayProviders(),
        ],
        child: const MaterialApp(home: FeedbackScreen()),
      ));
      await tester.pumpAndSettle();
    }

    Future<void> fill(WidgetTester tester, String s, String i) async {
      await tester.enterText(find.byKey(const Key('suggestion_field')), s);
      await tester.enterText(find.byKey(const Key('impression_field')), i);
    }

    Future<void> send(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('send_feedback')));
      await tester.pumpAndSettle();
    }

    setUp(() => history.clear());

    testWidgets('kirim: POST /feedback (teks terpangkas), kolom dikosongkan, pesan sukses, riwayat dimuat ulang', (tester) async {
      await pump(tester, (m, p, b) async {
        history.insert(0, {..._row, 'suggestion': (b as Map)['suggestion'], 'impression': b['impression']});
        return {'ok': true};
      });
      expect(find.byKey(const Key('history_empty')), findsOneWidget);
      await fill(tester, '  Tambah materi sensor  ', ' Seru sekali ');
      await send(tester);
      final post = api.calls.where((c) => c.method == 'POST').single;
      expect([post.path, post.body, post.retry], ['/feedback', {'suggestion': 'Tambah materi sensor', 'impression': 'Seru sekali'}, false]);
      expect(find.byKey(const Key('feedback_success')), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('suggestion_field'))).controller!.text, isEmpty);
      expect(find.byKey(const Key('feedback_7')), findsOneWidget);
      expect(find.text('Tambah materi sensor'), findsOneWidget);
      expect(find.byKey(const Key('history_empty')), findsNothing);
    });

    testWidgets('kolom kosong ditolak di klien tanpa permintaan (saran dulu, lalu kesan)', (tester) async {
      await pump(tester, (m, p, b) async => fail('tidak boleh dipanggil'));
      await fill(tester, '   ', 'kesan');
      await send(tester);
      expect(find.text('Saran wajib diisi.'), findsOneWidget);
      await fill(tester, 'saran', '');
      await send(tester);
      expect(find.text('Kesan wajib diisi.'), findsOneWidget);
      expect(api.calls.where((c) => c.method == 'POST'), isEmpty);
    });

    testWidgets('lebih dari 1000 karakter: field membatasi input, controller juga menolak', (tester) async {
      await pump(tester, (m, p, b) async => fail('tidak boleh dipanggil'));
      final c = FeedbackController(AuthedApi(api, auth));
      expect(await c.submit('x' * 1001, 'ok'), contains('maksimal 1000'));
      expect(await c.submit('ok', 'y' * 1001), contains('maksimal 1000'));
      expect(await c.submit('x' * 1000, ''), 'Kesan wajib diisi.');
      c.dispose();
    });

    testWidgets('galat dari server (invalid_input) ditampilkan jelas; isi tidak hilang', (tester) async {
      await pump(tester, (m, p, b) async => {'ok': false, 'error': 'invalid_input', 'field': 'impression'});
      await fill(tester, 'saran', 'kesan');
      await send(tester);
      expect(find.byKey(const Key('feedback_error')), findsOneWidget);
      expect(find.textContaining('Kesan tidak valid'), findsOneWidget);
      expect(tester.widget<TextField>(find.byKey(const Key('suggestion_field'))).controller!.text, 'saran');
    });

    testWidgets('jaringan putus saat kirim: pesan galat, isi tetap, bisa dikirim lagi', (tester) async {
      var fail = true;
      await pump(tester, (m, p, b) async {
        if (fail) throw NetworkException('Tidak ada koneksi internet.');
        return {'ok': true};
      });
      await fill(tester, 'saran', 'kesan');
      await send(tester);
      expect(find.text('Tidak ada koneksi internet.'), findsOneWidget);
      fail = false;
      await send(tester);
      expect(find.byKey(const Key('feedback_success')), findsOneWidget);
      expect(find.text('Tidak ada koneksi internet.'), findsNothing);
    });

    testWidgets('tombol ditekan berulang saat mengirim: hanya satu permintaan', (tester) async {
      final gate = Completer<Map<String, dynamic>>();
      await pump(tester, (m, p, b) => gate.future);
      await fill(tester, 'saran', 'kesan');
      await tester.tap(find.byKey(const Key('send_feedback')));
      await tester.pump();
      expect(tester.widget<PrimaryButton>(find.byKey(const Key('send_feedback'))).onPressed, isNull);
      await tester.tap(find.byKey(const Key('send_feedback')), warnIfMissed: false);
      await tester.pump();
      gate.complete({'ok': true});
      await tester.pumpAndSettle();
      expect(api.calls.where((c) => c.method == 'POST'), hasLength(1));
    });

    testWidgets('riwayat milik pengguna ditampilkan, terbaru di atas', (tester) async {
      history.addAll([
        {..._row, 'id': 9, 'suggestion': 'Saran terbaru', 'impression': 'Kesan terbaru'},
        {..._row, 'id': 7},
      ]);
      await pump(tester, (m, p, b) async => {'ok': true});
      expect(find.byKey(const Key('feedback_9')), findsOneWidget);
      expect(find.byKey(const Key('feedback_7')), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('feedback_9'))).dy, lessThan(tester.getTopLeft(find.byKey(const Key('feedback_7'))).dy));
      expect(find.text('19 Okt 2026, 11.00 WIB'), findsNWidgets(2)); // waktu dalam zona pilihan
    });

    testWidgets('riwayat gagal dimuat: pesan + Coba lagi', (tester) async {
      var fail = true;
      api = FakeApi((m, p, b) async {
        if (fail) throw NetworkException('Tidak ada koneksi internet.');
        return {'ok': true, 'data': [_row]};
      });
      auth = FakeAuth(api);
      await tester.pumpWidget(MultiProvider(
        providers: [
          ChangeNotifierProvider<AuthController>.value(value: auth),
          Provider<AuthedApi>.value(value: AuthedApi(api, auth)),
          ...displayProviders(),
        ],
        child: const MaterialApp(home: FeedbackScreen()),
      ));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('history_error')), findsOneWidget);
      fail = false;
      await tester.scrollUntilVisible(find.text('Coba lagi'), 200, scrollable: find.byType(Scrollable).first);
      await tester.ensureVisible(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Coba lagi'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.byKey(const Key('feedback_7')), 200, scrollable: find.byType(Scrollable).first);
      expect(find.byKey(const Key('feedback_7')), findsOneWidget);
    });

    testWidgets('sesi berakhir (401) saat kirim: logout otomatis tanpa pesan galat', (tester) async {
      await pump(tester, (m, p, b) async => throw InvalidSessionException());
      await fill(tester, 'saran', 'kesan');
      await send(tester);
      expect(auth.invalidated, 1);
      expect(find.byKey(const Key('feedback_error')), findsNothing);
    });
  });
}
