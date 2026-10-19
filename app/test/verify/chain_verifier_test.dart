import 'dart:convert';
import 'dart:io';

import 'package:code2ticket/core/verify/chain_verifier.dart';
import 'package:flutter_test/flutter_test.dart';

/// Vektor dihasilkan oleh implementasi ACUAN Python (backend\test\reference\test_m1.py: sha, block_hash, pick_winners,
/// verify) dengan skrip pembangkit sekali jalan; di sini Dart harus menghasilkan nilai yang sama persis.
late final Map<String, dynamic> vectors;

Map<String, dynamic> deepCopy(Map<String, dynamic> m) => jsonDecode(jsonEncode(m)) as Map<String, dynamic>;

Map<String, dynamic> scenario(String name) => deepCopy((vectors['scenarios'] as List).firstWhere((s) => s['name'] == name)['data'] as Map<String, dynamic>);

VerificationReport verifyJson(Map<String, dynamic> raw, {List<int>? announced}) {
  final d = VerificationData.tryParse(raw);
  expect(d, isNotNull, reason: 'data harus terbaca');
  return verifyData(d!, announced: announced);
}

void main() {
  setUpAll(() => vectors = jsonDecode(File('test/fixtures/m1_vectors.json').readAsStringSync()) as Map<String, dynamic>);

  group('hash identik dengan acuan Python', () {
    test('SHA-256 (termasuk teks non-ASCII)', () {
      expect(sha256Hex('abc'), 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad');
      for (final v in vectors['sha'] as List) {
        expect(sha256Hex(v['in'] as String), v['out'], reason: '"${v['in']}"');
      }
    });

    test('owner_key', () {
      for (final v in vectors['owner_key'] as List) {
        expect(ownerKey(v['user'] as String, v['gid'] as String), v['out']);
      }
    });

    test('hash blok commit dan result (40 blok, termasuk winning_tickets kosong)', () {
      final blocks = vectors['blocks'] as List;
      expect(blocks.length, 40);
      for (final e in blocks) {
        final b = ChainBlock.tryParse(<String, dynamic>{...e['block'] as Map<String, dynamic>, 'block_hash': e['hash']})!;
        expect(b.computeHash(), e['hash'], reason: 'blok ${b.blockIndex} ${b.blockType}');
      }
    });

    test('tickets_hash dan pemenang (pickWinners) untuk berbagai ukuran, termasuk 0 tiket', () {
      for (final p in vectors['picks'] as List) {
        final tickets = [for (final t in p['tickets'] as List) ((t[0] as num).toInt(), t[1] as String)];
        final r = pickWinners(p['seed'] as String, p['gid'] as String, tickets, p['k'] as int);
        expect(r.ticketsHash, p['out']['tickets_hash'], reason: '${tickets.length} tiket');
        expect(r.winners, (p['out']['winners'] as List).cast<int>(), reason: '${tickets.length} tiket, k=${p['k']}');
      }
    });

    test('vektor tetap: format blok C| dan R|', () {
      const c = ChainBlock(blockIndex: 1, blockType: 'commit', giveawayId: 'g', seedHash: 's', winnerCount: 2, tsMs: 3, previousHash: genesisHash, blockHash: '');
      expect(c.hashInput, 'C|1|g|s|2|3|$genesisHash');
      const r = ChainBlock(
          blockIndex: 2, blockType: 'result', giveawayId: 'g', drawId: 'd', seed: 'sd', totalTickets: 5, ticketsHash: 'th', winningTickets: '1,2', tsMs: 9, previousHash: 'p', blockHash: '');
      expect(r.hashInput, 'R|2|g|d|sd|5|th|1,2|9|p');
    });
  });

  group('verifikasi: sama dengan verify() acuan pada setiap skenario', () {
    // Langkah yang harus gagal pada skenario rusak (satu-satunya yang membedakan penyebab).
    for (final s in (jsonDecode(File('test/fixtures/m1_vectors.json').readAsStringSync())['scenarios'] as List)) {
      test('${s['name']}', () {
        final raw = deepCopy(s['data'] as Map<String, dynamic>);
        final report = verifyJson(raw);
        expect(report.verified || !report.drawn && !report.mismatch, s['ref_ok'], reason: 'acuan: ${s['ref_why']}');
        final failStep = s['fail_step'];
        if (failStep != null) {
          expect(report.step(VerifyStepId.values.byName(failStep as String)).status, StepStatus.fail);
          expect(report.mismatch, isTrue);
        } else {
          expect(report.mismatch, isFalse);
        }
      });
    }
  });

  group('verifikasi: langkah dan penyebab', () {
    test('rantai valid: keempat langkah lulus, pemenang hasil hitung ulang tersedia', () {
      final raw = scenario('valid');
      final r = verifyJson(raw);
      expect(r.drawn, isTrue);
      expect(r.verified, isTrue);
      expect(r.steps.map((s) => s.status), everyElement(StepStatus.pass));
      expect(r.winningTickets.join(','), (raw['chain'] as List)[2]['winning_tickets']);
      expect(r.totalTickets, 12);
      expect(r.drawnAtMs, 1760000900000);
    });

    test('satu karakter diubah pada blok: langkah rantai gagal dan menyebut nomor blok', () {
      final raw = scenario('valid');
      final commit = (raw['chain'] as List)[1] as Map<String, dynamic>;
      final h = commit['seed_hash'] as String;
      commit['seed_hash'] = '${h.substring(0, 10)}${h[10] == 'a' ? 'b' : 'a'}${h.substring(11)}';
      final r = verifyJson(raw);
      expect(r.step(VerifyStepId.chain).status, StepStatus.fail);
      expect(r.step(VerifyStepId.chain).detail, contains('2'));
      expect(r.verified, isFalse);
      expect(r.mismatch, isTrue);
    });

    test('seed tidak cocok dengan komitmen (rantai disesuaikan): hanya langkah seed gagal', () {
      final r = verifyJson(scenario('seed tidak cocok komitmen (rantai disesuaikan)'));
      expect(r.step(VerifyStepId.seed).status, StepStatus.fail);
      expect(r.step(VerifyStepId.chain).status, StepStatus.pass);
      expect(r.verified, isFalse);
    });

    test('pemenang dipalsukan walau hash blok disesuaikan: rantai lulus tetapi pemenang gagal', () {
      final r = verifyJson(scenario('pemenang dipalsukan, hash blok disesuaikan'));
      expect(r.step(VerifyStepId.chain).status, StepStatus.pass);
      expect(r.step(VerifyStepId.winners).status, StepStatus.fail);
    });

    test('belum diundi: rantai dan komitmen diperiksa, seed dan pemenang dilewati, bukan "Terverifikasi"', () {
      final r = verifyJson(scenario('belum diundi'));
      expect(r.drawn, isFalse);
      expect(r.step(VerifyStepId.commit).status, StepStatus.pass);
      expect(r.step(VerifyStepId.chain).status, StepStatus.pass);
      expect(r.step(VerifyStepId.seed).status, StepStatus.skipped);
      expect(r.step(VerifyStepId.winners).status, StepStatus.skipped);
      expect(r.verified, isFalse);
      expect(r.mismatch, isFalse);
    });

    test('daftar pemenang yang ditampilkan harus sama dengan hasil hitung ulang', () {
      final raw = scenario('valid');
      final win = verifyJson(raw).winningTickets;
      expect(verifyJson(raw, announced: win.reversed.toList()).verified, isTrue); // urutan tidak penting
      final fake = verifyJson(raw, announced: [...win.take(win.length - 1), 999]);
      expect(fake.step(VerifyStepId.winners).status, StepStatus.fail);
      expect(fake.verified, isFalse);
    });

    test('tickets null padahal sudah diundi: gagal (tidak dipercaya begitu saja)', () {
      final raw = scenario('valid')..['tickets'] = null;
      expect(verifyJson(raw).step(VerifyStepId.winners).status, StepStatus.fail);
    });

    test('data rusak (blok tanpa hash, tiket bentuk salah) ditolak oleh parser', () {
      final raw = scenario('valid');
      (raw['chain'] as List)[0] = {'block_type': 'commit'};
      expect(VerificationData.tryParse(raw), isNull);
      final raw2 = scenario('valid');
      raw2['tickets'] = [
        [1]
      ];
      expect(VerificationData.tryParse(raw2), isNull);
      expect(verifyRaw((raw: {'chain': 5}, announced: null)), isNull);
    });
  });
}
