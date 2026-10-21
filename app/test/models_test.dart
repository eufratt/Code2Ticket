import 'dart:convert';

import 'package:code2ticket/core/format.dart';
import 'package:code2ticket/core/json.dart';
import 'package:code2ticket/features/giveaways/giveaway_models.dart';
import 'package:code2ticket/features/tickets/redeem_messages.dart';
import 'package:code2ticket/features/tickets/ticket_models.dart';
import 'package:flutter_test/flutter_test.dart';

// Contoh respons asli dari backend/src (GET /giveaways, POST /codes/redeem, GET /tickets).
const giveawayJson = '''
{"id":"5deb977d-ff30-4e4e-849d-ff389fe51e6a","title":"Demo: Laptop Gaming Giveaway","description":"Giveaway demo tanpa batas lokasi.","organizer":"Code2Ticket Demo","category":"gaming","prize_name":"Laptop Gaming 15\\"","prize_value_idr":20000000,"latitude":null,"longitude":null,"address":null,"radius_km":null,"start_at":"2026-10-18T16:23:20.789Z","end_at":"2026-10-18T19:29:20.790Z","draw_at":"2026-10-18T20:29:20.790Z","winner_count":3,"ticket_count":0,"status":"active","distance_km":null}''';
const redeemOk = '''
{"ok":true,"ticket":{"id":"1d1c22a6-2381-41ec-9baf-1b1c174fc622","ticket_number":1,"giveaway_id":"5deb977d-ff30-4e4e-849d-ff389fe51e6a","giveaway_title":"Demo: Laptop Gaming Giveaway","prize_name":"Laptop Gaming 15\\"","draw_at":"2026-10-18T20:29:20.790Z","result":"eligible"}}''';
const ticketJson = '''
{"id":"1d1c22a6-2381-41ec-9baf-1b1c174fc622","ticket_number":1,"giveaway_id":"5deb977d-ff30-4e4e-849d-ff389fe51e6a","giveaway_title":"Demo: Laptop Gaming Giveaway","prize_name":"Laptop Gaming 15\\"","category":"gaming","end_at":"2026-10-18T19:29:20.790Z","draw_at":"2026-10-18T20:29:20.790Z","giveaway_status":"active","created_at":"2026-10-18T16:29:31.551Z","result":"eligible","code_masked":"****-****-7FES"}''';

void main() {
  group('Giveaway', () {
    test('mengurai respons asli', () {
      final g = Giveaway.tryParse(jsonDecode(giveawayJson))!;
      expect(g.id, '5deb977d-ff30-4e4e-849d-ff389fe51e6a');
      expect(g.title, 'Demo: Laptop Gaming Giveaway');
      expect(g.prizeName, 'Laptop Gaming 15"');
      expect(g.prizeValueIdr, 20000000);
      expect(g.winnerCount, 3);
      expect(g.ticketCount, 0);
      expect(g.latitude, isNull);
      expect(g.address, isNull);
      expect(g.drawAt!.toUtc(), DateTime.utc(2026, 10, 18, 20, 29, 20, 790));
      expect(g.drawAt!.isUtc, isFalse); // zona lokal perangkat
    });

    test('field hilang atau bertipe salah tidak melempar', () {
      final g = Giveaway.tryParse({
        'id': 'x',
        'title': 'T',
        'prize_value_idr': '5000000', // numeric dalam bentuk string
        'winner_count': 'tiga',
        'end_at': 'bukan tanggal',
        'ticket_count': null,
      })!;
      expect(g.prizeValueIdr, 5000000);
      expect(g.winnerCount, 1);
      expect(g.endAt, isNull);
      expect(g.ticketCount, 0);
      expect(g.category, 'other');
    });

    test('elemen tanpa id/judul atau bukan objek dilewati', () {
      final list = parseList(
        [jsonDecode(giveawayJson), {'title': 'tanpa id'}, 'sampah', null, {'id': 'a', 'title': 'B'}],
        Giveaway.tryParse,
      );
      expect(list.map((g) => g.id), ['5deb977d-ff30-4e4e-849d-ff389fe51e6a', 'a']);
      expect(parseList({'bukan': 'list'}, Giveaway.tryParse), isEmpty);
    });

    test('fase dihitung dari waktu, bukan dari kolom status yang bisa tertinggal', () {
      final g = Giveaway(
        id: 'a',
        title: 'T',
        status: 'upcoming', // basi: scheduler belum jalan
        startAt: DateTime.utc(2026, 1, 1),
        endAt: DateTime.utc(2026, 1, 2),
      );
      expect(g.phaseAt(DateTime.utc(2025, 12, 31)), GiveawayPhase.upcoming);
      expect(g.phaseAt(DateTime.utc(2026, 1, 1, 12)), GiveawayPhase.active);
      expect(g.phaseAt(DateTime.utc(2026, 1, 3)), GiveawayPhase.waitingDraw);
      expect(Giveaway(id: 'a', title: 'T', status: 'drawn').phaseAt(DateTime.utc(2026)), GiveawayPhase.drawn);
    });
  });

  group('Ticket', () {
    test('mengurai respons asli', () {
      final t = Ticket.tryParse(jsonDecode(ticketJson))!;
      expect(t.ticketNumber, 1);
      expect(t.giveawayTitle, 'Demo: Laptop Gaming Giveaway');
      expect(t.result, TicketResult.eligible);
      expect(t.codeMasked, '****-****-7FES');
      expect(t.createdAt!.toUtc(), DateTime.utc(2026, 10, 18, 16, 29, 31, 551));
    });

    test('semua nilai result dipetakan; nilai tak dikenal netral', () {
      TicketResult of(String r) => Ticket.tryParse({'id': 'a', 'giveaway_id': 'g', 'result': r})!.result;
      expect(of('winner'), TicketResult.winner);
      expect(of('not_selected'), TicketResult.notSelected);
      expect(of('waiting_for_draw'), TicketResult.waitingForDraw);
      expect(of('eligible'), TicketResult.eligible);
      expect(of('sesuatu_baru'), TicketResult.eligible);
    });

    test('tanpa id atau giveaway_id -> null', () {
      expect(Ticket.tryParse({'id': 'a'}), isNull);
      expect(Ticket.tryParse([]), isNull);
    });
  });

  group('RedeemOutcome', () {
    test('sukses', () {
      final o = RedeemOutcome.fromJson(jsonDecode(redeemOk));
      expect(o.isSuccess, isTrue);
      expect(o.ticket!.ticketNumber, 1);
      expect(o.ticket!.giveawayTitle, 'Demo: Laptop Gaming Giveaway');
    });

    test('gagal bisnis: kode dibawa apa adanya', () {
      final o = RedeemOutcome.fromJson({'ok': false, 'error': 'code_used'});
      expect(o.isSuccess, isFalse);
      expect(o.error, 'code_used');
    });

    test('rate_limited membawa jeda', () {
      final o = RedeemOutcome.fromJson({'ok': false, 'error': 'rate_limited', 'retry_after_seconds': 421});
      expect(o.retryAfterSeconds, 421);
      expect(redeemErrorMessage(o.error!, retryAfterSeconds: o.retryAfterSeconds), contains('8 menit'));
    });

    test('ok:true tanpa tiket yang valid dianggap galat, bukan sukses', () {
      expect(RedeemOutcome.fromJson({'ok': true}).isSuccess, isFalse);
      expect(RedeemOutcome.fromJson({'ok': true, 'ticket': 5}).error, 'bad_response');
    });

    test('setiap kode redeem backend punya pesan khusus', () {
      const codes = [
        'invalid_format', 'code_not_found', 'code_used', 'giveaway_not_started', 'giveaway_ended',
        'giveaway_not_ready', 'ticket_limit', 'location_required', 'out_of_area', 'rate_limited',
        'too_many_requests', 'invalid_input',
      ];
      for (final c in codes) {
        expect(redeemErrorMessage(c), isNot(startsWith('Terjadi kesalahan')), reason: c);
      }
      expect(redeemErrorMessage('code_used'), 'Kode ini sudah digunakan.');
      expect(redeemErrorMessage('aneh'), contains('aneh'));
    });
  });

  group('format', () {
    test('nomor tiket 6 digit', () => expect(formatTicketNumber(12), '#000012'));
  });
}
