import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/db/rate_cache.dart' show SettingsStore;
import '../../core/json.dart';
import '../../core/notifications/draw_spoiler.dart';
import '../../core/verify/chain_verifier.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;

/// Satu pemenang dari GET /giveaways/:id/winners. Nama sudah disamarkan server; tidak ada data pribadi lain.
class DrawWinner {
  const DrawWinner({required this.rank, required this.ticketNumber, required this.name});
  final int rank, ticketNumber;
  final String name;

  static DrawWinner? tryParse(dynamic raw) {
    final j = asMap(raw);
    if (j == null || j['ticket_number'] == null) return null;
    return DrawWinner(rank: asInt(j['rank']), ticketNumber: asInt(j['ticket_number']), name: asString(j['name']) ?? '');
  }
}

/// Menjalankan verifikasi (di isolate pada app, langsung di tes).
typedef VerifyRunner = Future<VerificationReport?> Function(({Map<String, dynamic> raw, List<int>? announced}) args);

Future<VerificationReport?> isolateRunner(({Map<String, dynamic> raw, List<int>? announced}) args) => compute(verifyRaw, args);

String drawErrorMessage(String? code) => switch (code) {
      'not_found' => 'Giveaway tidak ditemukan.',
      'too_many_requests' => 'Terlalu banyak permintaan. Tunggu sebentar lalu coba lagi.',
      _ => 'Gagal memuat hasil ($code).',
    };

/// Hasil draw + verifikasi satu giveaway: GET /giveaways/:id/winners dan /verification (keduanya GET, boleh diulang
/// otomatis). Perhitungan hash dilakukan di perangkat dari data mentah server; tidak ada seed/token yang dicatat di log.
class DrawController extends ChangeNotifier {
  DrawController(this._api, this.giveawayId, {VerifyRunner? runner}) : _runner = runner ?? isolateRunner;

  final AuthedApi _api;
  final String giveawayId;
  final VerifyRunner _runner;

  LoadState state = LoadState.idle;
  String? error;

  /// false = belum diundi.
  bool drawn = false;
  List<DrawWinner> winners = const [];
  VerificationReport? report;
  Future<void>? _inflight;

  Future<void> load() => _inflight ??= _load().whenComplete(() => _inflight = null);

  Future<void> _load() async {
    state = LoadState.loading;
    error = null;
    notifyListeners();
    try {
      final w = await _api.get('/giveaways/$giveawayId/winners');
      if (w['ok'] == false) throw NetworkException(drawErrorMessage(asString(w['error'])));
      final v = await _api.get('/giveaways/$giveawayId/verification');
      if (v['ok'] == false) throw NetworkException(drawErrorMessage(asString(v['error'])));
      drawn = w['drawn'] == true;
      winners = parseList(w['winners'], DrawWinner.tryParse);
      final rep = await _runner((raw: v, announced: [for (final x in winners) x.ticketNumber]));
      if (rep == null) throw NetworkException('Data verifikasi dari server tidak lengkap, jadi tidak bisa diperiksa.');
      report = rep;
      state = LoadState.loaded;
    } on InvalidSessionException {
      return; // AuthedApi sudah logout; router pindah ke Login
    } on NetworkException catch (e) {
      error = e.message;
      state = LoadState.error;
    } on ForbiddenException {
      error = 'Akses ditolak.';
      state = LoadState.error;
    }
    notifyListeners();
  }
}

/// Penanda "hasil draw giveaway ini sudah pernah dibuka" (tabel app_settings, per pengguna). Tidak berisi data sensitif.
class DrawSeenStore {
  const DrawSeenStore(this._store, this._userId);
  final SettingsStore? _store;
  final String _userId;

  String _key(String giveawayId) => drawSeenKey(giveawayId);

  Future<bool> isSeen(String giveawayId) async {
    try {
      return await _store?.getSetting(_key(giveawayId), userId: _userId) == '1';
    } catch (_) {
      return false; // gagal membaca: anggap baru (paling buruk, diminta goyang sekali lagi)
    }
  }

  Future<void> markSeen(String giveawayId) async {
    try {
      await _store?.setSetting(_key(giveawayId), '1', userId: _userId);
    } catch (_) {/* penanda hanya kenyamanan */}
  }
}
