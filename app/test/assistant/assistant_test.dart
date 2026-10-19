import 'dart:async';

import 'package:code2ticket/core/api/api_client.dart';
import 'package:code2ticket/core/api/authed_api.dart';
import 'package:code2ticket/core/theme/app_theme.dart';
import 'package:code2ticket/features/assistant/assistant_controller.dart';
import 'package:code2ticket/features/assistant/assistant_models.dart';
import 'package:code2ticket/features/assistant/assistant_screen.dart';
import 'package:code2ticket/features/auth/auth_controller.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../input_code_test.dart' show FakeApi, FakeAuth;
import '../layout/screens_layout_test.dart' show sampleGiveaway, sampleLongTitle, sampleUser;
import '../support/display.dart';
import '../support/memory_chat_store.dart';
import '../support/ui.dart';

Map<String, dynamic> reply(String text, {List<Map<String, dynamic>> related = const []}) => {'ok': true, 'reply': text, 'related': related};
Map<String, dynamic> err(String code, {Map<String, dynamic> extra = const {}}) => {'ok': false, 'error': code, ...extra};

ChatMessage msg(ChatRole role, String text, {List<Giveaway> related = const []}) =>
    ChatMessage(role: role, text: text, related: related, createdAt: DateTime.now());

void main() {
  late FakeApi api;
  late FakeAuth auth;
  late MemoryChatStore store;
  late AssistantController c;
  Future<Map<String, dynamic>> Function(String, String, dynamic) handler = (m, p, b) async => reply('ok');

  Future<void> setUpController() async {
    c = AssistantController(AuthedApi(api, auth), auth, store);
    await c.load();
  }

  setUp(() {
    handler = (m, p, b) async => reply('Halo juga!');
    api = FakeApi((m, p, b) => handler(m, p, b));
    auth = FakeAuth(api)..user = sampleUser();
    store = MemoryChatStore();
  });

  group('AssistantController', () {
    setUp(setUpController);

    test('sukses: POST /chat tanpa retry, balasan + kartu related (maks. 3) tampil dan riwayat tersimpan', () async {
      handler = (m, p, b) async => reply('Ini giveaway gaming.', related: [for (var i = 1; i <= 4; i++) sampleGiveaway('g$i', 'gaming')]);
      await c.send('  ada giveaway gaming?  ');
      final post = api.calls.single;
      expect(post.path, '/chat');
      expect(post.retry, isFalse);
      expect(post.body, {'message': 'ada giveaway gaming?', 'history': <Map<String, String>>[]});
      expect(c.sending, isFalse);
      expect(c.messages.map((m) => (m.role, m.confirmed, m.isError)), [(ChatRole.user, true, false), (ChatRole.assistant, true, false)]);
      expect(c.messages.last.text, 'Ini giveaway gaming.');
      expect(c.messages.last.related.map((g) => g.id), ['g1', 'g2', 'g3']);
      expect(store.rows['u1']!.map((m) => m.text), ['ada giveaway gaming?', 'Ini giveaway gaming.']);
    });

    test('riwayat ke server: hanya 6 giliran terakhir yang terjawab, dipotong 1000 karakter, galat tidak ikut', () async {
      store.rows['u1'] = [
        for (var i = 0; i < 8; i++) msg(i.isEven ? ChatRole.user : ChatRole.assistant, i == 5 ? 'x' * 1500 : 'pesan $i'),
      ];
      c = AssistantController(AuthedApi(api, auth), auth, store);
      await c.load();
      handler = (m, p, b) async => err('ai_unavailable');
      await c.send('pesan gagal');
      expect(c.messages.last.isError, isTrue);
      handler = (m, p, b) async => reply('jawaban');
      await c.send('pertanyaan baru');
      final history = (api.calls.last.body as Map)['history'] as List;
      expect(history.length, 6);
      expect(history.first, {'role': 'user', 'content': 'pesan 2'});
      expect((history[3] as Map)['content'], 'x' * 1000);
      expect(history.map((h) => (h as Map)['content']), isNot(contains('pesan gagal')));
      expect(history.every((h) => (h as Map)['role'] == 'user' || h['role'] == 'assistant'), isTrue);
    });

    test('pesan kosong atau lebih dari 500 karakter tidak dikirim', () async {
      await c.send('   ');
      await c.send('a' * 501);
      expect(api.calls, isEmpty);
      expect(c.messages, isEmpty);
      await c.send('a' * 500);
      expect(api.posts('/chat'), 1);
    });

    test('panjang dihitung per code point seperti server (emoji = 1)', () async {
      await c.send('😀' * 500);
      expect(api.posts('/chat'), 1);
    });

    test('tidak double submit: ketukan kedua saat menunggu diabaikan', () async {
      final gate = Completer<Map<String, dynamic>>();
      handler = (m, p, b) => gate.future;
      final first = c.send('halo');
      expect(c.sending, isTrue);
      await c.send('halo lagi');
      expect(api.posts('/chat'), 1);
      gate.complete(reply('hai'));
      await first;
      expect(c.messages.length, 2);
      expect(c.sending, isFalse);
    });

    for (final e in {
      'ai_unavailable': 'tidak bisa menjawab',
      'rate_limited': 'Terlalu banyak pesan',
      'daily_limit': 'Batas pesan harian',
      'ai_not_configured': 'belum diaktifkan',
      'invalid_input': 'Pesan tidak valid',
      'kode_tak_dikenal': 'Terjadi kesalahan',
    }.entries) {
      test('galat ${e.key} -> pesan Indonesia tanpa kode mentah, tidak disimpan, tanpa retry otomatis', () async {
        handler = (m, p, b) async => err(e.key);
        await c.send('halo');
        expect(api.posts('/chat'), 1);
        final bubble = c.messages.last;
        expect(bubble.isError, isTrue);
        expect(bubble.text, contains(e.value));
        expect(bubble.text, isNot(contains(e.key)));
        expect(c.messages.first.confirmed, isFalse);
        expect(c.canRetry, isTrue);
        expect(store.rows, isEmpty);
      });
    }

    test('rate_limited menyebut sisa detik dari server', () async {
      handler = (m, p, b) async => err('rate_limited', extra: {'retry_after_seconds': 42});
      await c.send('halo');
      expect(c.messages.last.text, contains('42 detik'));
    });

    test('jaringan putus -> pesan jaringan, POST tidak diulang otomatis', () async {
      handler = (m, p, b) async => throw NetworkException('Tidak ada koneksi internet.');
      await c.send('halo');
      expect(api.posts('/chat'), 1);
      expect(c.messages.last.text, 'Tidak ada koneksi internet.');
      expect(c.canRetry, isTrue);
    });

    test('ok:true tanpa balasan diperlakukan sebagai ai_unavailable', () async {
      handler = (m, p, b) async => {'ok': true};
      await c.send('halo');
      expect(c.messages.last.isError, isTrue);
    });

    test('401 -> alur logout yang ada, tanpa pesan galat', () async {
      handler = (m, p, b) async => throw InvalidSessionException();
      await c.send('halo');
      expect(auth.invalidated, 1);
      expect(c.messages, isEmpty, reason: 'logout mengosongkan percakapan di memori');
      expect(c.sending, isFalse);
    });

    test('kirim ulang: pesan yang sama dikirim lagi sekali, tidak ada duplikat, galat hilang saat sukses', () async {
      handler = (m, p, b) async => err('ai_unavailable');
      await c.send('halo');
      expect(c.messages.length, 2);
      handler = (m, p, b) async => reply('hai!');
      await c.retry();
      expect(api.posts('/chat'), 2);
      expect((api.calls.last.body as Map)['message'], 'halo');
      expect(c.messages.map((m) => (m.role, m.text, m.confirmed)), [(ChatRole.user, 'halo', true), (ChatRole.assistant, 'hai!', true)]);
      expect(store.rows['u1']!.length, 2);
      expect(c.canRetry, isFalse);
    });

    test('kirim ulang saat masih gagal: tepat satu galat di akhir', () async {
      handler = (m, p, b) async => err('rate_limited');
      await c.send('halo');
      await c.retry();
      expect(c.messages.where((m) => m.isError).length, 1);
      expect(c.messages.length, 2);
    });

    test('kirim ulang tidak jalan bila tidak ada galat', () async {
      await c.send('halo');
      await c.retry();
      expect(api.posts('/chat'), 1);
    });

    test('hapus percakapan: memori dan SQLite kosong', () async {
      await c.send('halo');
      expect(store.rows['u1'], isNotEmpty);
      await c.clear();
      expect(c.messages, isEmpty);
      expect(store.rows['u1'], isNull);
    });

    test('riwayat dimuat per pengguna; penyimpanan rusak tidak menjatuhkan kirim', () async {
      store.rows['u1'] = [msg(ChatRole.user, 'lama'), msg(ChatRole.assistant, 'jawaban lama')];
      store.rows['u2'] = [msg(ChatRole.user, 'orang lain')];
      c = AssistantController(AuthedApi(api, auth), auth, store);
      await c.load();
      expect(c.messages.map((m) => m.text), ['lama', 'jawaban lama']);
      store.failing = true;
      await c.send('baru');
      expect(c.messages.last.text, 'Halo juga!');
      expect(c.messages.last.isError, isFalse);
    });

    test('logout mengosongkan percakapan di memori', () async {
      await c.send('halo');
      await auth.handleInvalidSession();
      expect(c.messages, isEmpty);
    });
  });

  group('AssistantScreen', () {
    Future<void> open(WidgetTester tester, {double width = 360, double scale = 1.0, Brightness brightness = Brightness.light}) async {
      await setViewport(tester, width: width, textScale: scale, brightness: brightness);
      c = AssistantController(AuthedApi(api, auth), auth, store);
      final router = GoRouter(routes: [
        GoRoute(path: '/', builder: (_, _) => const AssistantScreen()),
        GoRoute(path: '/giveaway/:id', builder: (_, s) => Scaffold(body: Text('Detail ${s.pathParameters['id']}'))),
      ]);
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<AuthController>.value(value: auth),
            ChangeNotifierProvider<AssistantController>.value(value: c),
            ...displayProviders(),
          ],
          child: MaterialApp.router(theme: AppTheme.light(), darkTheme: AppTheme.dark(), routerConfig: router),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder send() => find.byKey(const Key('send_chat'));
    bool sendEnabled(WidgetTester t) => t.widget<IconButton>(send()).onPressed != null;

    testWidgets('sambutan + 3 saran cepat; kolom input dan penghitung 0/500', (tester) async {
      await open(tester);
      expect(find.byKey(const Key('welcome')), findsOneWidget);
      expect(find.byType(ActionChip), findsNWidgets(3));
      expect(find.text('0/500'), findsOneWidget);
      expect(sendEnabled(tester), isFalse);
    });

    testWidgets('tombol kirim aktif hanya bila ada teks; di atas 500 nonaktif dengan penghitung galat', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('chat_field')), 'halo');
      await tester.pump();
      expect(find.text('4/500'), findsOneWidget);
      expect(sendEnabled(tester), isTrue);
      await tester.enterText(find.byKey(const Key('chat_field')), 'a' * 501);
      await tester.pump();
      expect(find.textContaining('501/500'), findsOneWidget);
      expect(sendEnabled(tester), isFalse);
      await tester.enterText(find.byKey(const Key('chat_field')), '   ');
      await tester.pump();
      expect(sendEnabled(tester), isFalse);
      expect(api.calls, isEmpty);
    });

    testWidgets('urutan: pengguna di kanan, asisten di kiri, saran cepat hilang setelah percakapan mulai', (tester) async {
      await open(tester);
      await tester.enterText(find.byKey(const Key('chat_field')), 'Apa kabar?');
      await tester.pump();
      await tester.tap(send());
      await tester.pumpAndSettle();
      final mine = tester.getCenter(find.text('Apa kabar?'));
      final bot = tester.getCenter(find.text('Halo juga!'));
      expect(mine.dx, greaterThan(bot.dx), reason: 'pesan pengguna di kanan');
      expect(mine.dy, lessThan(bot.dy), reason: 'pertanyaan di atas jawaban');
      expect(find.byType(ActionChip), findsNothing);
      expect(find.text('0/500'), findsOneWidget, reason: 'kolom dikosongkan setelah kirim');
    });

    testWidgets('mengirim: indikator mengetik muncul, tombol nonaktif, tidak bisa dobel; hilang setelah balasan', (tester) async {
      final gate = Completer<Map<String, dynamic>>();
      handler = (m, p, b) => gate.future;
      await open(tester);
      await tester.tap(find.byType(ActionChip).first);
      await tester.pump();
      expect(find.byKey(const Key('typing')), findsOneWidget);
      await tester.enterText(find.byKey(const Key('chat_field')), 'lagi');
      await tester.pump();
      expect(sendEnabled(tester), isFalse);
      expect(find.byType(ActionChip), findsNothing);
      expect(api.posts('/chat'), 1);
      gate.complete(reply('Selesai'));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const Key('typing')), findsNothing);
      expect(find.text('Selesai'), findsOneWidget);
      expect(sendEnabled(tester), isTrue);
    });

    testWidgets('saran cepat dikirim sebagai pesan', (tester) async {
      await open(tester);
      await tester.tap(find.byKey(const Key('quick_Ada giveaway gaming apa?')));
      await tester.pumpAndSettle();
      expect((api.calls.single.body as Map)['message'], 'Ada giveaway gaming apa?');
    });

    testWidgets('kartu related di bawah balasan; ketuk membuka Detail Giveaway', (tester) async {
      handler = (m, p, b) async => reply('Ini yang cocok.', related: [sampleGiveaway('g7', 'gaming', title: 'Turnamen Gaming')]);
      await open(tester);
      await tester.enterText(find.byKey(const Key('chat_field')), 'gaming');
      await tester.pump();
      await tester.tap(send());
      await tester.pumpAndSettle();
      expect(find.text('Turnamen Gaming'), findsOneWidget);
      expect(tester.getTopLeft(find.byKey(const Key('related_g7'))).dy, greaterThan(tester.getBottomLeft(find.text('Ini yang cocok.')).dy));
      await tester.tap(find.byKey(const Key('related_g7')));
      await tester.pumpAndSettle();
      expect(find.text('Detail g7'), findsOneWidget);
    });

    testWidgets('galat jadi gelembung dengan Kirim ulang; ketuk mengirim ulang sekali dan berhasil', (tester) async {
      handler = (m, p, b) async => err('daily_limit');
      await open(tester);
      await tester.enterText(find.byKey(const Key('chat_field')), 'halo');
      await tester.pump();
      await tester.tap(send());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('chat_error')), findsOneWidget);
      expect(find.textContaining('Batas pesan harian'), findsOneWidget);
      expect(find.textContaining('daily_limit'), findsNothing);
      expect(find.byKey(const Key('retry_chat')), findsOneWidget);
      handler = (m, p, b) async => reply('Berhasil');
      await tester.tap(find.byKey(const Key('retry_chat')));
      await tester.pumpAndSettle();
      expect(api.posts('/chat'), 2);
      expect(find.byKey(const Key('chat_error')), findsNothing);
      expect(find.byKey(const Key('retry_chat')), findsNothing);
      expect(find.text('Berhasil'), findsOneWidget);
      expect(find.text('halo'), findsOneWidget);
    });

    testWidgets('riwayat tersimpan dimuat saat layar dibuka; Hapus percakapan butuh konfirmasi', (tester) async {
      store.rows['u1'] = [msg(ChatRole.user, 'pertanyaan lama'), msg(ChatRole.assistant, 'jawaban lama')];
      await open(tester);
      expect(find.text('pertanyaan lama'), findsOneWidget);
      expect(find.text('jawaban lama'), findsOneWidget);
      await tester.tap(find.byKey(const Key('clear_chat')));
      await tester.pumpAndSettle();
      expect(find.text('Hapus percakapan?'), findsOneWidget);
      await tester.tap(find.byKey(const Key('clear_cancel')));
      await tester.pumpAndSettle();
      expect(find.text('pertanyaan lama'), findsOneWidget);
      await tester.tap(find.byKey(const Key('clear_chat')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('clear_confirm')));
      await tester.pumpAndSettle();
      expect(find.text('pertanyaan lama'), findsNothing);
      expect(store.rows['u1'], isNull);
      expect(find.byType(ActionChip), findsNWidgets(3));
      expect(tester.widget<IconButton>(find.byKey(const Key('clear_chat'))).onPressed, isNull);
    });

    // Tata letak (DESIGN.md daftar periksa 9): percakapan panjang + kartu related + galat, tanpa overflow.
    for (final v in layoutVariants) {
      testWidgets('tata letak ${v.name}: percakapan panjang, kartu related, galat', (tester) async {
        final related = [for (var i = 1; i <= 3; i++) Giveaway.tryParse(sampleGiveaway('g$i', ['gaming', 'travel', 'tech'][i - 1], title: sampleLongTitle))!];
        store.rows['u1'] = [
          msg(ChatRole.user, 'Pertanyaan yang sangat panjang sekali ${'dan seterusnya ' * 20}'),
          msg(ChatRole.assistant, 'Jawaban yang juga panjang ${'berisi penjelasan ' * 30}', related: related),
          msg(ChatRole.user, 'Pendek'),
        ];
        handler = (m, p, b) async => err('rate_limited', extra: {'retry_after_seconds': 30});
        await open(tester, width: v.width, scale: v.scale, brightness: v.brightness);
        expect(tester.takeException(), isNull);
        await tester.enterText(find.byKey(const Key('chat_field')), 'kirim ini ${'panjang ' * 40}');
        await tester.pump();
        await tester.tap(send());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull, reason: v.name);
        expect(find.byKey(const Key('retry_chat')), findsOneWidget);
        for (var i = 0; i < 6; i++) {
          await tester.drag(find.byKey(const Key('chat_list')), const Offset(0, 300), warnIfMissed: false);
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull, reason: '${v.name} gulir ${i + 1}');
        }
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('tata letak kosong dan mengetik pada font 1,3x gelap', (tester) async {
      final gate = Completer<Map<String, dynamic>>();
      handler = (m, p, b) => gate.future;
      await open(tester, scale: 1.3, brightness: Brightness.dark);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byType(ActionChip).last);
      await tester.pump();
      expect(find.byKey(const Key('typing')), findsOneWidget);
      expect(tester.takeException(), isNull);
      gate.complete(reply('ok'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  });
}
