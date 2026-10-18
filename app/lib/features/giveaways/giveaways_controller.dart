import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/db/cache_store.dart';
import '../../core/json.dart';
import '../../core/offline.dart';
import '../auth/auth_controller.dart';
import 'giveaway_models.dart';

enum LoadState { idle, loading, loaded, error }

/// Hasil GET /giveaways/:id (atau cache bila offline).
class GiveawayLookup {
  const GiveawayLookup({this.giveaway, this.offline = false, this.cachedAt, this.notFound = false, this.error});
  final Giveaway? giveaway;
  final bool offline, notFound;
  final DateTime? cachedAt;
  final String? error;
}

/// Daftar giveaway aktif (Home) dan satu giveaway untuk layar detail. Online -> simpan ke cache;
/// jaringan gagal -> tampilkan cache (offline) dan coba lagi berkala.
class GiveawaysController extends ChangeNotifier with OfflineRetry {
  GiveawaysController(this._api, this._auth, this._cache, {this.retryInterval = const Duration(seconds: 20)}) {
    _auth.addListener(_onAuth);
  }

  final AuthedApi _api;
  final AuthController _auth;
  final CacheStore _cache;
  @override
  final Duration? retryInterval;

  List<Giveaway> items = const [];
  LoadState state = LoadState.idle;
  String? error;

  /// true bila [items] berasal dari cache; [cachedAt] = kapan terakhir diperbarui dari server.
  bool offline = false;
  DateTime? cachedAt;
  Future<void>? _inflight;

  Future<void> load() => _inflight ??= _load(silent: false).whenComplete(() => _inflight = null);

  @override
  Future<void> reloadSilently() => _inflight ??= _load(silent: true).whenComplete(() => _inflight = null);

  Future<void> _load({required bool silent}) async {
    if (!silent) {
      state = LoadState.loading;
      error = null;
      notifyListeners();
    }
    try {
      final r = await _api.get('/giveaways?limit=50');
      if (r['ok'] == false) throw NetworkException('Gagal memuat giveaway (${r['error']}).');
      items = parseList(r['data'], Giveaway.tryParse);
      state = LoadState.loaded;
      offline = false;
      cachedAt = null;
      cancelRetry();
      if (_auth.status != AuthStatus.signedOut) await bestEffort(() => _cache.saveGiveaways(items));
    } on InvalidSessionException {
      return; // AuthedApi sudah logout; router pindah ke Login
    } on NetworkException catch (e) {
      if (silent) return; // masih offline: biarkan tampilan cache apa adanya
      final now = DateTime.now();
      final cached = ((await bestEffort(_cache.loadGiveaways)) ?? const <Giveaway>[])
          .where((g) => g.phaseAt(now) == GiveawayPhase.active)
          .toList();
      if (cached.isNotEmpty) {
        items = cached;
        offline = true;
        cachedAt = await bestEffort(_cache.giveawaysUpdatedAt);
        state = LoadState.loaded;
        scheduleRetry();
      } else {
        error = e.message;
        state = LoadState.error;
      }
    }
    notifyListeners();
  }

  /// Satu giveaway lewat GET /giveaways/:id; offline -> dari cache.
  Future<GiveawayLookup> fetchOne(String id) async {
    try {
      final r = await _api.get('/giveaways/$id');
      if (r['ok'] == false) {
        if (r['error'] == 'not_found') return const GiveawayLookup(notFound: true);
        throw NetworkException('Gagal memuat giveaway (${r['error']}).');
      }
      final g = Giveaway.tryParse(r);
      if (g == null) throw NetworkException('Respons server tidak valid.');
      await bestEffort(() => _cache.saveGiveaways([g]));
      return GiveawayLookup(giveaway: g);
    } on InvalidSessionException {
      return const GiveawayLookup();
    } on NetworkException catch (e) {
      final cached = await bestEffort(() => _cache.loadGiveaway(id));
      if (cached == null) return GiveawayLookup(error: e.message);
      return GiveawayLookup(giveaway: cached, offline: true, cachedAt: await bestEffort(_cache.giveawaysUpdatedAt));
    }
  }

  void _onAuth() {
    if (_auth.status == AuthStatus.signedOut && (items.isNotEmpty || state != LoadState.idle)) {
      items = const [];
      state = LoadState.idle;
      error = null;
      offline = false;
      cachedAt = null;
      cancelRetry();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
