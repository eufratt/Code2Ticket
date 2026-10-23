import 'dart:convert';
import 'dart:io';

import 'package:code2ticket/core/verify/anchor_checker.dart';
import 'package:code2ticket/core/verify/chain_verifier.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// RPC publik tiruan (tanpa jaringan). [txs]: hash -> input; [mined]: hash yang sudah punya receipt sukses.
class FakeRpc {
  final txs = <String, String>{};
  final mined = <String>{};
  final hosts = <String>[];
  bool offline = false;

  late final client = MockClient((req) async {
    if (offline) throw const SocketException('Failed host lookup');
    hosts.add(req.url.host);
    final j = jsonDecode(req.body) as Map<String, dynamic>;
    final hash = (j['params'] as List).first as String;
    final Object? result = switch (j['method']) {
      'eth_getTransactionByHash' => txs.containsKey(hash) ? {'hash': hash, 'input': txs[hash]} : null,
      'eth_getTransactionReceipt' => mined.contains(hash) ? {'transactionHash': hash, 'status': '0x1'} : null,
      _ => null,
    };
    return http.Response(jsonEncode({'jsonrpc': '2.0', 'id': j['id'], 'result': result}), 200);
  });
}

late final Map<String, dynamic> vectors;

VerificationData scen(String name) => VerificationData.tryParse(
    jsonDecode(jsonEncode((vectors['scenarios'] as List).firstWhere((s) => s['name'] == name)['data'])) as Map<String, dynamic>)!;

String txOf(int i) => '0x${i.toRadixString(16).padLeft(64, '0')}';

/// Daftar jangkar seperti GET /giveaways/:id/anchors untuk blok Commit/Hasil [d].
Map<String, dynamic> anchorsJson(VerificationData d, {String status = 'confirmed', bool withTx = true}) => {
      'ok': true,
      'anchors': [
        for (final (i, b) in [d.commit, d.result].nonNulls.indexed)
          {
            'block_index': b.blockIndex,
            'block_type': b.blockType,
            'block_hash': b.blockHash,
            'tx_hash': withTx ? txOf(i + 1) : null,
            'chain_id': 11155111,
            'status': status,
            'explorer_url': withTx ? 'https://sepolia.etherscan.io/tx/${txOf(i + 1)}' : null,
            'rpc_url': 'https://ethereum-sepolia-rpc.publicnode.com',
          },
      ],
    };

/// RPC berisi transaksi yang benar untuk tiap blok [d].
FakeRpc honestRpc(VerificationData d, {bool mine = true}) {
  final rpc = FakeRpc();
  for (final (i, b) in [d.commit, d.result].nonNulls.indexed) {
    rpc.txs[txOf(i + 1)] = anchorDataHex(b.computeHash());
    if (mine) rpc.mined.add(txOf(i + 1));
  }
  return rpc;
}

void main() {
  setUpAll(() => vectors = jsonDecode(File('test/fixtures/m1_vectors.json').readAsStringSync()) as Map<String, dynamic>);

  test('data jangkar = hex UTF-8 "C2T:" + hash (sama dengan toHex viem di backend)', () {
    expect(anchorDataHex('0' * 64), '0x4332543a${'30' * 64}');
    expect(anchorDataHex('ab'), '0x4332543a6162');
  });

  test('cocok: Commit dan Hasil ditambang dengan data benar -> Lulus, tautan explorer https', () async {
    final d = scen('valid');
    final rpc = honestRpc(d);
    final step = await checkAnchors(d, AnchorInfo.parseResponse(anchorsJson(d)), rpc.client);
    expect(step.id, VerifyStepId.anchor);
    expect(step.status, StepStatus.pass);
    expect(step.anchors.map((a) => (a.blockType, a.state)), [('commit', AnchorState.anchored), ('result', AnchorState.anchored)]);
    expect(step.anchors.first.explorer.toString(), 'https://sepolia.etherscan.io/tx/${txOf(1)}');
    expect(rpc.hosts.toSet(), {'ethereum-sepolia-rpc.publicnode.com'});
  });

  test('tidak cocok: data transaksi berbeda dari hash lokal -> Gagal', () async {
    final d = scen('valid');
    final rpc = honestRpc(d)..txs[txOf(2)] = anchorDataHex('f' * 64);
    final step = await checkAnchors(d, AnchorInfo.parseResponse(anchorsJson(d)), rpc.client);
    expect(step.status, StepStatus.fail);
    expect(step.anchors.last.state, AnchorState.mismatch);
    expect(step.detail, contains('TIDAK cocok'));
  });

  test('hash blok dari server dipalsukan tetapi tx berisi hash asli: dibandingkan dengan hash hitungan lokal', () async {
    final d = scen('valid');
    final rpc = honestRpc(d);
    final json = anchorsJson(d);
    ((json['anchors'] as List).first as Map)['block_hash'] = 'f' * 64; // tidak dipakai untuk membandingkan
    final step = await checkAnchors(d, AnchorInfo.parseResponse(json), rpc.client);
    expect(step.status, StepStatus.pass);
  });

  test('menunggu: belum ada tx, tx belum dikenal node, atau belum ada receipt -> peringatan, bukan gagal', () async {
    final d = scen('valid');
    final noTx = await checkAnchors(d, AnchorInfo.parseResponse(anchorsJson(d, status: 'pending', withTx: false)), FakeRpc().client);
    expect(noTx.status, StepStatus.warning);
    expect(dominantAnchorState(noTx.anchors), AnchorState.pending);
    expect(noTx.anchors.every((a) => a.explorer == null), isTrue);

    final unknown = await checkAnchors(d, AnchorInfo.parseResponse(anchorsJson(d, status: 'pending')), FakeRpc().client);
    expect(unknown.status, StepStatus.warning);
    expect(unknown.anchors.every((a) => a.state == AnchorState.pending), isTrue);

    final unmined = await checkAnchors(d, AnchorInfo.parseResponse(anchorsJson(d, status: 'pending')), honestRpc(d, mine: false).client);
    expect(unmined.status, StepStatus.warning);
    expect(unmined.detail, startsWith('Menunggu penjangkaran'));
  });

  test('offline: RPC tidak terjangkau atau daftar jangkar gagal diambil -> peringatan dengan pesan jelas', () async {
    final d = scen('valid');
    final rpc = honestRpc(d)..offline = true;
    final step = await checkAnchors(d, AnchorInfo.parseResponse(anchorsJson(d)), rpc.client);
    expect(step.status, StepStatus.warning);
    expect(dominantAnchorState(step.anchors), AnchorState.unreachable);
    expect(step.detail, contains('Periksa koneksi internet'));

    final noList = await checkAnchors(d, null, FakeRpc().client, offline: true);
    expect(noList.status, StepStatus.warning);
    expect(noList.anchors.every((a) => a.state == AnchorState.unreachable), isTrue);

    final rpcError = MockClient((_) async => http.Response('{"jsonrpc":"2.0","id":1,"error":{"code":-32005,"message":"limit"}}', 200));
    expect((await checkAnchors(d, AnchorInfo.parseResponse(anchorsJson(d)), rpcError)).status, StepStatus.warning);
  });

  test('giveaway lama tanpa jangkar (status none / backend lama) -> "Belum dijangkarkan", tanpa panggilan RPC', () async {
    final d = scen('valid');
    final rpc = FakeRpc();
    final none = await checkAnchors(d, AnchorInfo.parseResponse(anchorsJson(d, status: 'none', withTx: false)), rpc.client);
    expect(none.status, StepStatus.warning);
    expect(none.anchors.every((a) => a.state == AnchorState.notAnchored), isTrue);
    expect(none.detail, startsWith('Belum dijangkarkan'));
    expect(AnchorInfo.parseResponse({'ok': false, 'error': 'not_found'}), isNull);
    final oldBackend = await checkAnchors(d, null, rpc.client);
    expect(dominantAnchorState(oldBackend.anchors), AnchorState.notAnchored);
    expect(rpc.hosts, isEmpty);
  });

  test('belum diundi: hanya blok Commit yang diperiksa', () async {
    final d = scen('belum diundi');
    final step = await checkAnchors(d, AnchorInfo.parseResponse(anchorsJson(d)), honestRpc(d).client);
    expect(step.anchors.map((a) => a.blockType), ['commit']);
    expect(step.status, StepStatus.pass);
  });

  test('peringatan jangkar tidak membatalkan Terverifikasi; gagal jangkar membatalkannya', () {
    final base = verifyData(scen('valid'));
    expect(base.verified, isTrue);
    final warn = base.withStep(anchorStep(const [BlockAnchor(blockType: 'commit', state: AnchorState.pending)]));
    expect((warn.verified, warn.hasWarning, warn.mismatch), (true, true, false));
    final bad = base.withStep(anchorStep(const [BlockAnchor(blockType: 'commit', state: AnchorState.mismatch)]));
    expect((bad.verified, bad.mismatch), (false, true));
    expect(bad.steps.length, 5);
  });

  test('tautan explorer/RPC dari server hanya https; RPC bawaan dipakai untuk chain yang dikenal', () async {
    final d = scen('belum diundi');
    final json = anchorsJson(d);
    final a = (json['anchors'] as List).first as Map<String, dynamic>;
    a['explorer_url'] = 'javascript:alert(1)';
    a['rpc_url'] = 'https://evil.example.test';
    final rpc = honestRpc(d);
    final step = await checkAnchors(d, AnchorInfo.parseResponse(json), rpc.client);
    expect(step.anchors.single.explorer, isNull);
    expect(rpc.hosts.toSet(), {'ethereum-sepolia-rpc.publicnode.com'});

    a['chain_id'] = 1234; // chain tak dikenal: rpc_url server dipakai bila https
    rpc.hosts.clear();
    await checkAnchors(d, AnchorInfo.parseResponse(json), rpc.client);
    expect(rpc.hosts.toSet(), {'evil.example.test'});
    a['rpc_url'] = 'http://plain.example.test';
    final insecure = await checkAnchors(d, AnchorInfo.parseResponse(json), rpc.client);
    expect(insecure.anchors.single.state, AnchorState.unreachable);
  });
}
