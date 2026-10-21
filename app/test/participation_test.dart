import 'package:code2ticket/core/db/local_db.dart';
import 'package:code2ticket/core/open_link.dart';
import 'package:code2ticket/features/giveaways/giveaway_detail_screen.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/tickets/input_code_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'layout/screens_layout_test.dart' show SampleEnv, sampleGiveaways;
import 'support/ui.dart';

// Cara mendapatkan kode + tautan penyelenggara (Detail, Input Code, cache SQLite v4).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();

  final opened = <Uri>[];
  late bool openResult;
  final original = openExternal;
  setUp(() {
    opened.clear();
    openResult = true;
    openExternal = (u) async {
      opened.add(u);
      return openResult;
    };
  });
  tearDown(() => openExternal = original);

  Future<void> pumpDetail(WidgetTester tester, {Map<String, dynamic> extra = const {}, Brightness b = Brightness.light}) async {
    await setViewport(tester, height: 2600, brightness: b);
    final env = SampleEnv()..giveawayExtra = extra;
    await tester.pumpWidget(env.wrap(themedApp(GiveawayDetailScreen(giveawayId: 'g1', initial: Giveaway.tryParse({...sampleGiveaways().first, ...extra})))));
    await tester.pumpAndSettle();
  }

  group('Detail: cara mendapatkan kode', () {
    for (final b in Brightness.values) {
      testWidgets('teks tampil (baris baru terjaga, dapat dipilih), tombol >= 48 dp, ${b.name}', (tester) async {
        await pumpDetail(tester, b: b);
        expect(find.text('Cara mendapatkan kode'), findsOneWidget);
        final t = tester.widget<SelectableText>(find.byKey(const Key('how_to_text')));
        expect(t.data, contains('\n'));
        expect(t.data, startsWith('Ikuti akun penyelenggara'));
        expect(find.byKey(const Key('how_to_empty')), findsNothing);
        expect(tester.getSize(find.byKey(const Key('open_organizer_link'))).height, greaterThanOrEqualTo(48));
      });
    }

    testWidgets('giveaway lama (NULL): pesan pengganti, tanpa tombol tautan', (tester) async {
      await pumpDetail(tester, extra: {'how_to_participate': null, 'organizer_url': null});
      expect(find.text('Penyelenggara belum menambahkan cara mendapatkan kode.'), findsOneWidget);
      expect(find.byKey(const Key('how_to_text')), findsNothing);
      expect(find.byKey(const Key('open_organizer_link')), findsNothing);
    });

    testWidgets('tombol hanya bila ada URL', (tester) async {
      await pumpDetail(tester, extra: {'organizer_url': null});
      expect(find.byKey(const Key('how_to_text')), findsOneWidget);
      expect(find.byKey(const Key('open_organizer_link')), findsNothing);
    });

    testWidgets('dialog konfirmasi menampilkan domain; Batal tidak membuka; Buka membuka di browser eksternal', (tester) async {
      await pumpDetail(tester);
      await tester.tap(find.byKey(const Key('open_organizer_link')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Code2Ticket tidak mengelola giveaway di luar aplikasi.'), findsOneWidget);
      expect(find.text('Tujuan: www.penyelenggara-contoh.co.id'), findsOneWidget);
      await tester.tap(find.text('Batal'));
      await tester.pumpAndSettle();
      expect(opened, isEmpty);

      await tester.tap(find.byKey(const Key('open_organizer_link')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_open_link')));
      await tester.pumpAndSettle();
      expect(opened.single.toString(), 'https://www.penyelenggara-contoh.co.id/giveaway/halaman-yang-cukup-panjang');
      expect(find.text('Tidak bisa membuka tautan.'), findsNothing);
    });

    testWidgets('gagal membuka -> snackbar "Tidak bisa membuka tautan."', (tester) async {
      openResult = false;
      await pumpDetail(tester);
      await tester.tap(find.byKey(const Key('open_organizer_link')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('confirm_open_link')));
      await tester.pumpAndSettle();
      expect(find.text('Tidak bisa membuka tautan.'), findsOneWidget);
    });

    for (final bad in ['http://example.com', 'javascript:alert(1)', 'ftp://example.com/x', 'https://user:pw@example.com', 'https://exa mple.com']) {
      testWidgets('alamat tidak aman ($bad): tanpa dialog, tidak dibuka, snackbar "Tautan tidak valid."', (tester) async {
        await pumpDetail(tester, extra: {'organizer_url': bad});
        await tester.tap(find.byKey(const Key('open_organizer_link')));
        await tester.pumpAndSettle();
        expect(find.text('Tautan tidak valid.'), findsOneWidget);
        expect(find.byKey(const Key('confirm_open_link')), findsNothing);
        expect(opened, isEmpty);
      });
    }
  });

  test('parseHttpsUrl', () {
    expect(parseHttpsUrl('https://example.com/a?b=1')?.host, 'example.com');
    for (final s in [null, '', 'http://a.com', 'a.com', 'https://', 'https://u@a.com', 'data:text/plain,x', 'file:///x', 'https://a.com/\u0001']) {
      expect(parseHttpsUrl(s), isNull, reason: '$s');
    }
  });

  testWidgets('Input Code: teks bantu di bawah tombol, alur tukar kode tidak berubah', (tester) async {
    await setViewport(tester);
    await tester.pumpWidget(SampleEnv().app(const InputCodeScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Belum punya kode? Lihat cara mendapatkannya di detail giveaway.'), findsOneWidget);
    expect(find.byKey(const Key('submit_code')), findsOneWidget);
    expect(tester.getTopLeft(find.byKey(const Key('code_help'))).dy, greaterThan(tester.getBottomLeft(find.byKey(const Key('submit_code'))).dy));
  });

  group('cache SQLite v4', () {
    test('model <-> baris cache: cara ikut dan tautan tersimpan; giveaway lama tetap null', () {
      const g = Giveaway(id: 'a', title: 'T', howToParticipate: 'Ambil kode di stan.', organizerUrl: 'https://e.com/x');
      final back = Giveaway.tryParse(g.toRow(DateTime.utc(2026)))!;
      expect([back.howToParticipate, back.organizerUrl], ['Ambil kode di stan.', 'https://e.com/x']);
      final old = Giveaway.tryParse({'id': 'a', 'title': 'T', 'prize_value_idr': 1})!;
      expect([old.howToParticipate, old.organizerUrl], [null, null]);
    });

    test('v3 -> v4 dan v2 -> v4: kolom baru ada, cache dibuang, percakapan tetap, tanpa crash', () async {
      for (final from in [3, 2]) {
        final db = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
        await db.execute('CREATE TABLE cached_giveaways (id TEXT PRIMARY KEY, title TEXT NOT NULL, prize_value_idr INTEGER, cached_at TEXT NOT NULL)');
        await db.execute('CREATE TABLE chat_messages (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id TEXT NOT NULL, role TEXT NOT NULL, content TEXT NOT NULL, related_json TEXT, created_at TEXT NOT NULL)');
        await db.insert('cached_giveaways', {'id': 'g1', 'title': 'Lama', 'prize_value_idr': 5, 'cached_at': 'x'});
        await db.insert('chat_messages', {'user_id': 'u', 'role': 'user', 'content': 'halo', 'created_at': 'x'});
        await LocalDb.upgradeTables(db, from, 4);
        final cols = (await db.rawQuery('PRAGMA table_info(cached_giveaways)')).map((r) => r['name']);
        expect(cols, containsAll(['how_to_participate', 'organizer_url', 'prize_value_idr']), reason: 'dari v$from');
        expect(await db.query('cached_giveaways'), isEmpty);
        expect((await db.query('chat_messages')).single['content'], 'halo');
        final local = LocalDb.withDatabase(db);
        await local.saveGiveaways([const Giveaway(id: 'g2', title: 'Baru', howToParticipate: 'Cara dapat kode.', organizerUrl: 'https://e.com')]);
        expect((await local.loadGiveaway('g2'))!.howToParticipate, 'Cara dapat kode.');
        await db.close();
      }
    });
  });
}
