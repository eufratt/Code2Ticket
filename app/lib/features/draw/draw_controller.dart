import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/db/cache_store.dart';
import '../../core/db/rate_cache.dart' show SettingsStore;
import '../../core/json.dart';
import '../../core/offline.dart';
import '../../core/notifications/draw_spoiler.dart';
import '../../core/verify/chain_verifier.dart';
import '../auth/auth_controller.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'draw_models.dart';

export 'draw_models.dart';

const verifyOfflineMessage = 'Butuh koneksi internet untuk memeriksa keaslian.';

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
/// Layar Hasil Draw (default) memakai cache: online -> simpan hasil final; jaringan gagal -> tampilkan cache, atau
/// [notCached] bila belum ada. [verifyOnly] (Cek Keaslian) tidak memakai cache: offline hanya memberi [verifyOfflineMessage].
class DrawController extends ChangeNotifier {
  DrawController(this._api, this.giveawayId, {VerifyRunner? runner, this.cache, this.auth, this.verifyOnly = false})
      : _runner = runner ?? isolateRunner;

  final AuthedApi _api;
  final String giveawayId;
  final VerifyRunner _runner;
  final CacheStore? cache;
  final AuthController? auth;
  final bool verifyOnly;

  LoadState state = LoadState.idle;
  String? error;

  /// false = belum diundi.
  bool drawn = false;
  List<DrawWinner> winners = const [];
  VerificationReport? report;

  /// Ringkasan untuk layar hasil: dari server (online) atau dari cache (offline).
  int? drawnAtMs, totalTickets;

  /// true bila hasil berasal dari cache; [cachedAt] = kapan disimpan.
  bool offline = false;
  DateTime? cachedAt;

  /// Jaringan gagal dan belum ada hasil tersimpan untuk giveaway ini.
  bool notCached = false;
  Future<void>? _inflight;

  Future<void> load() => _inflight ??= _load().whenComplete(() => _inflight = null);

  Future<void> _load() async {
    state = LoadState.loading;
    error = null;
    offline = false;
    notCached = false;
    notifyListeners();
    final uid = auth?.user?.id;
    try {
      final w = await _api.get('/giveaways/$giveawayId/winners');
      if (w['ok'] == false) throw ServerFaultException(drawErrorMessage(asString(w['error'])));
      final v = await _api.get('/giveaways/$giveawayId/verification');
      if (v['ok'] == false) throw ServerFaultException(drawErrorMessage(asString(v['error'])));
      drawn = w['drawn'] == true;
      winners = parseList(w['winners'], DrawWinner.tryParse);
      final rep = await _runner((raw: v, announced: [for (final x in winners) x.ticketNumber]));
      if (rep == null) throw ServerFaultException('Data verifikasi dari server tidak lengkap, jadi tidak bisa diperiksa.');
      report = rep;
      drawnAtMs = rep.drawnAtMs;
      totalTickets = rep.totalTickets;
      state = LoadState.loaded;
      // Hanya hasil final yang disimpan; "Belum diundi" tidak pernah masuk cache.
      final store = cache;
      if (!verifyOnly && drawn && store != null && uid != null && auth?.status != AuthStatus.signedOut) {
        await bestEffort(() => store.saveDrawResult(uid, CachedDrawResult(giveawayId: giveawayId, winners: winners, drawnAtMs: drawnAtMs, totalTickets: totalTickets)));
      }
    } on InvalidSessionException {
      return; // AuthedApi sudah logout; router pindah ke Login
    } on NetworkException catch (e) {
      if (!showsOffline(e, offlineSession: auth?.offlineSession ?? false)) {
        error = e.message; // server menjawab tapi rusak: tetap "Coba lagi"
        state = LoadState.error;
      } else if (verifyOnly) {
        error = verifyOfflineMessage;
        state = LoadState.error;
      } else {
        final store = cache;
        final cached = uid == null || store == null ? null : await bestEffort(() => store.loadDrawResult(uid, giveawayId));
        if (cached == null) {
          notCached = true;
        } else {
          drawn = true;
          winners = cached.winners;
          drawnAtMs = cached.drawnAtMs;
          totalTickets = cached.totalTickets;
          offline = true;
          cachedAt = cached.cachedAt;
        }
        state = LoadState.loaded;
      }
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
