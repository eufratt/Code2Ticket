import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../json.dart';
import '../open_link.dart';
import 'chain_verifier.dart';

// Langkah 5 Cek Keaslian: hash blok Commit/Hasil dijangkarkan backend ke blockchain publik testnet sebagai transaksi
// dengan data = hex UTF-8 "C2T:" + block_hash (backend\src\services\anchor.js: anchorData). App mengambil transaksi
// LANGSUNG dari RPC publik lewat JSON-RPC biasa (tanpa paket kripto) dan membandingkannya dengan hash yang dihitung
// di perangkat. Belum ada / belum dikonfirmasi / tidak terhubung = peringatan, bukan gagal; hanya data beda = gagal.

const anchorPrefix = 'C2T:';

/// RPC publik bawaan per chain_id. Dipakai lebih dulu daripada rpc_url dari server, supaya pemeriksaan tidak
/// bergantung pada alamat yang diberikan server kita sendiri.
const knownPublicRpc = <int, String>{80002: 'https://rpc-amoy.polygon.technology'};

const _hex = '0123456789abcdef';

/// "0x" + hex huruf kecil dari UTF-8 "C2T:" + blockHash (sama dengan viem toHex di backend).
String anchorDataHex(String blockHash) {
  final b = StringBuffer('0x');
  for (final x in utf8.encode('$anchorPrefix$blockHash')) {
    b..write(_hex[x >> 4])..write(_hex[x & 15]);
  }
  return b.toString();
}

/// Satu entri GET /giveaways/:id/anchors. [status]: pending | confirmed | failed | none.
class AnchorInfo {
  const AnchorInfo({required this.blockIndex, required this.blockType, required this.status, this.blockHash, this.txHash, this.chainId, this.explorerUrl, this.rpcUrl});
  final int blockIndex;
  final String blockType, status;
  final String? blockHash, txHash, explorerUrl, rpcUrl;
  final int? chainId;

  static AnchorInfo? tryParse(dynamic raw) {
    final j = asMap(raw);
    if (j == null || j['block_index'] == null) return null;
    return AnchorInfo(
      blockIndex: asInt(j['block_index']),
      blockType: asString(j['block_type']) ?? '',
      status: asString(j['status']) ?? 'none',
      blockHash: asString(j['block_hash']),
      txHash: asString(j['tx_hash']),
      chainId: asIntOrNull(j['chain_id']),
      explorerUrl: asString(j['explorer_url']),
      rpcUrl: asString(j['rpc_url']),
    );
  }

  /// null bila respons bukan daftar jangkar (mis. backend lama tanpa endpoint ini).
  static List<AnchorInfo>? parseResponse(Map<String, dynamic> j) =>
      j['ok'] == true && j['anchors'] is List ? parseList(j['anchors'], tryParse) : null;
}

enum AnchorState { anchored, pending, notAnchored, mismatch, unreachable }

/// Hasil pemeriksaan satu blok. [explorer] hanya https yang lolos parseHttpsUrl.
class BlockAnchor {
  const BlockAnchor({required this.blockType, required this.state, this.txHash, this.explorer});
  final String blockType;
  final AnchorState state;
  final String? txHash;
  final Uri? explorer;
}

class _RpcError implements Exception {}

Future<Object?> _rpc(http.Client client, Uri url, String method, List<Object> params) async {
  final res = await client
      .post(url, headers: {'content-type': 'application/json'}, body: jsonEncode({'jsonrpc': '2.0', 'id': 1, 'method': method, 'params': params}))
      .timeout(const Duration(seconds: 10));
  if (res.statusCode != 200) throw _RpcError();
  final j = jsonDecode(utf8.decode(res.bodyBytes));
  if (j is! Map || j['error'] != null) throw _RpcError();
  return j['result'];
}

final _txHashRe = RegExp(r'^0x[0-9a-fA-F]{64}$');

/// Memeriksa satu blok lokal terhadap transaksi jangkarnya di RPC publik. Tidak pernah melempar.
Future<BlockAnchor> checkBlockAnchor(ChainBlock local, AnchorInfo? info, http.Client client) async {
  BlockAnchor out(AnchorState s) => BlockAnchor(blockType: local.blockType, state: s, txHash: info?.txHash, explorer: parseHttpsUrl(info?.explorerUrl));
  if (info == null || info.status == 'none') return out(AnchorState.notAnchored);
  final tx = info.txHash;
  if (tx == null || !_txHashRe.hasMatch(tx)) return out(AnchorState.pending);
  final known = knownPublicRpc[info.chainId];
  final url = known != null ? Uri.parse(known) : parseHttpsUrl(info.rpcUrl);
  if (url == null) return out(AnchorState.unreachable);
  try {
    final t = asMap(await _rpc(client, url, 'eth_getTransactionByHash', [tx]));
    if (t == null) return out(AnchorState.pending); // belum tersiar / belum dikenal node
    final data = (asString(t['input']) ?? asString(t['data']) ?? '').toLowerCase();
    if (data != anchorDataHex(local.computeHash())) return out(AnchorState.mismatch);
    final r = asMap(await _rpc(client, url, 'eth_getTransactionReceipt', [tx]));
    return out(r != null && r['status'] == '0x1' ? AnchorState.anchored : AnchorState.pending);
  } catch (_) {
    return out(AnchorState.unreachable); // tanpa internet, timeout, RPC sibuk: bukan tanda kecurangan
  }
}

/// Keadaan yang paling menentukan: tidak cocok > tidak terhubung > menunggu > belum dijangkarkan > cocok.
AnchorState dominantAnchorState(List<BlockAnchor> blocks) {
  for (final s in [AnchorState.mismatch, AnchorState.unreachable, AnchorState.pending, AnchorState.notAnchored]) {
    if (blocks.any((b) => b.state == s)) return s;
  }
  return blocks.isEmpty ? AnchorState.notAnchored : AnchorState.anchored;
}

/// Langkah 5 dari hasil per blok: gagal hanya bila data di blockchain berbeda.
VerifyStep anchorStep(List<BlockAnchor> blocks) {
  final s = dominantAnchorState(blocks);
  final (status, detail) = switch (s) {
    AnchorState.anchored => (StepStatus.pass, 'Hash blok tercatat di blockchain publik dan sama dengan hasil hitungan di ponselmu.'),
    AnchorState.mismatch => (StepStatus.fail, 'Data transaksi di blockchain TIDAK cocok dengan hash blok yang dihitung di ponselmu.'),
    AnchorState.unreachable =>
      (StepStatus.warning, 'Tidak bisa menghubungi jaringan blockchain. Periksa koneksi internet lalu coba lagi; ini bukan tanda hasil diubah.'),
    AnchorState.pending => (StepStatus.warning, 'Menunggu penjangkaran: transaksi belum ada atau belum dikonfirmasi. Coba periksa lagi nanti.'),
    AnchorState.notAnchored => (StepStatus.warning, 'Belum dijangkarkan: giveaway ini belum punya catatan di blockchain publik.'),
  };
  return VerifyStep(VerifyStepId.anchor, status, detail, anchors: blocks);
}

/// Seluruh langkah 5: blok Commit (dan Hasil bila sudah diundi) dari [data] dibandingkan dengan [infos].
/// [infos] null = server tidak memberi daftar jangkar (dianggap belum dijangkarkan); [offline] = gagal mengambil daftar.
Future<VerifyStep> checkAnchors(VerificationData? data, List<AnchorInfo>? infos, http.Client client, {bool offline = false}) async {
  final local = [data?.commit, data?.result].whereType<ChainBlock>().toList();
  if (offline) return anchorStep([for (final b in local) BlockAnchor(blockType: b.blockType, state: AnchorState.unreachable)]);
  final checks = [for (final b in local) checkBlockAnchor(b, infos?.where((i) => i.blockIndex == b.blockIndex).firstOrNull, client)];
  return anchorStep(await Future.wait(checks));
}
