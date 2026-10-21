import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/db/cache_store.dart';
import '../../core/geocoding/geocoder.dart';
import '../../core/json.dart';
import '../../core/location/location_service.dart';
import '../../core/offline.dart';
import '../auth/auth_controller.dart';
import '../giveaways/giveaway_models.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'discover_filters.dart';

/// Posisi pengguna yang sedang dipakai Discover. Hanya di memori: tidak pernah disimpan.
typedef UserPosition = ({double lat, double lng});

/// Pencarian/filter/urutan giveaway di server (debounce 400 ms); riwayat pencarian di SQLite per pengguna;
/// saat jaringan gagal menyaring cache lokal dengan aturan yang sama.
class DiscoverController extends ChangeNotifier with OfflineRetry {
  DiscoverController(
    this._api,
    this._auth,
    this._cache,
    this._location, {
    this.retryInterval = const Duration(seconds: 20),
    this.debounce = const Duration(milliseconds: 400),
    this.pageSize = 20,
  }) {
    _auth.addListener(_onAuth);
    _auth.backOnline.add(reloadSilently);
  }

  final AuthedApi _api;
  final AuthController _auth;
  final CacheStore _cache;
  final LocationService _location;
  @override
  final Duration? retryInterval;
  final Duration debounce;
  final int pageSize;

  DiscoverFilters filters = const DiscoverFilters();
  List<Giveaway> items = const [];
  LoadState state = LoadState.idle;
  String? error;
  bool offline = false;
  DateTime? cachedAt;
  bool hasMore = false;
  bool loadingMore = false;
  List<String> history = const [];
  UserPosition? position;

  /// Alasan mode Terdekat tidak bisa dipakai (izin/layanan lokasi); null bila baik-baik saja.
  LocationStatus? locationProblem;
  bool locating = false;

  /// Nama tempat bila posisi berasal dari pencarian manual (Nominatim), bukan GPS.
  String? manualLabel;

  Timer? _debounceTimer;
  int _seq = 0; // hanya jawaban permintaan terbaru yang dipakai

  String? get _uid => _auth.user?.id;

  /// Jarak/urutan/radius hanya dikirim bila posisinya ada.
  Map<String, String> _query({int offset = 0}) =>
      filters.toQuery(lat: position?.lat, lng: position?.lng, limit: pageSize, offset: offset);

  Future<void> ensureLoaded() async {
    if (state == LoadState.idle) await search();
    await loadHistory();
  }

  // ---------------------------------------------------------------- input pengguna

  /// Dipanggil tiap ketikan: server baru dipanggil setelah [debounce] tanpa ketikan baru.
  void onQueryChanged(String text) {
    if (text == filters.query) return;
    filters = filters.copyWith(query: text);
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, search);
    notifyListeners();
  }

  /// Tombol cari di keyboard: langsung mencari dan menyimpan kata ke riwayat.
  Future<void> submitQuery(String text) async {
    _debounceTimer?.cancel();
    filters = filters.copyWith(query: text);
    await commitQuery();
    await search();
  }

  /// Menyimpan kata kunci yang sedang dipakai ke riwayat (saat submit atau membuka hasil).
  Future<void> commitQuery() async {
    final uid = _uid;
    final q = filters.query.trim();
    if (uid == null || q.isEmpty) return;
    await bestEffort(() => _cache.addSearch(uid, q));
    await loadHistory();
  }

  Future<void> setFilters(DiscoverFilters f) {
    _debounceTimer?.cancel();
    filters = f;
    return search();
  }

  Future<void> setPosition(UserPosition? p) {
    position = p;
    // Mode terdekat tanpa posisi tidak bermakna: matikan dan jatuhkan urutan "terdekat".
    if (p == null && (filters.nearby || filters.sort == GiveawaySort.nearest)) {
      filters = filters.copyWith(
        nearbyRadiusKm: null,
        sort: filters.sort == GiveawaySort.nearest ? GiveawaySort.deadline : filters.sort,
      );
    }
    return search();
  }

  /// Mode Terdekat dengan GPS. Meminta izin lokasi (saat dipakai) bila perlu; bila gagal, mode tetap mati
  /// dan [locationProblem] berisi alasannya.
  Future<void> enableNearby({int radiusKm = 10}) async {
    locating = true;
    notifyListeners();
    final fix = await _location.locate();
    locating = false;
    if (!fix.ok) {
      locationProblem = fix.status;
      notifyListeners();
      return;
    }
    locationProblem = null;
    manualLabel = null;
    position = (lat: fix.lat!, lng: fix.lng!);
    await setFilters(filters.copyWith(nearbyRadiusKm: radiusKm, sort: GiveawaySort.nearest));
  }

  /// Mode Terdekat dari lokasi manual (hasil pencarian nama tempat).
  Future<void> useManualPlace(Place p, {int radiusKm = 10}) {
    locationProblem = null;
    manualLabel = p.name;
    position = (lat: p.lat, lng: p.lng);
    return setFilters(filters.copyWith(nearbyRadiusKm: filters.nearbyRadiusKm ?? radiusKm, sort: GiveawaySort.nearest));
  }

  Future<void> setNearbyRadius(int km) => setFilters(filters.copyWith(nearbyRadiusKm: km));

  Future<void> disableNearby() {
    locationProblem = null;
    manualLabel = null;
    position = null;
    return setFilters(filters.copyWith(
      nearbyRadiusKm: null,
      sort: filters.sort == GiveawaySort.nearest ? GiveawaySort.deadline : filters.sort,
    ));
  }

  /// Membuka pengaturan yang sesuai dengan [locationProblem].
  Future<bool> openLocationSettings() =>
      locationProblem == null ? Future.value(false) : _location.openSettingsFor(locationProblem!);

  // ---------------------------------------------------------------- pemuatan

  Future<void> search() => _run(silent: false);

  @override
  Future<void> reloadSilently() => _run(silent: true);

  Future<void> _run({required bool silent}) async {
    _debounceTimer?.cancel();
    final seq = ++_seq;
    if (!silent) {
      state = LoadState.loading;
      error = null;
      notifyListeners();
    }
    try {
      final r = await _api.get(_path(_query()));
      if (seq != _seq) return;
      if (r['ok'] == false) throw ServerFaultException('Gagal memuat giveaway (${r['error']}).');
      items = parseList(r['data'], Giveaway.tryParse);
      hasMore = items.length >= pageSize;
      state = LoadState.loaded;
      offline = false;
      cachedAt = null;
      cancelRetry();
      if (_auth.status != AuthStatus.signedOut) await bestEffort(() => _cache.saveGiveaways(items));
    } on InvalidSessionException {
      return;
    } on NetworkException catch (e) {
      if (seq != _seq) return;
      if (silent) return;
      final cached = (await bestEffort(_cache.loadGiveaways)) ?? const <Giveaway>[];
      if (cached.isEmpty && !showsOffline(e, offlineSession: _auth.offlineSession)) {
        error = e.message;
        state = LoadState.error;
      } else {
        items = filters.applyLocal(cached, lat: position?.lat, lng: position?.lng);
        hasMore = false;
        offline = true;
        cachedAt = await bestEffort(_cache.giveawaysUpdatedAt);
        state = LoadState.loaded;
        scheduleRetry();
      }
    }
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (!hasMore || loadingMore || offline || state != LoadState.loaded) return;
    loadingMore = true;
    notifyListeners();
    final seq = _seq;
    try {
      final r = await _api.get(_path(_query(offset: items.length)));
      if (seq != _seq) return;
      if (r['ok'] == false) throw ServerFaultException('Gagal memuat giveaway (${r['error']}).');
      final page = parseList(r['data'], Giveaway.tryParse);
      final seen = items.map((g) => g.id).toSet();
      items = [...items, ...page.where((g) => !seen.contains(g.id))];
      hasMore = page.length >= pageSize;
      if (_auth.status != AuthStatus.signedOut) await bestEffort(() => _cache.saveGiveaways(page));
    } on InvalidSessionException {
      return;
    } on NetworkException {
      hasMore = true; // coba lagi saat digulir ulang
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  static String _path(Map<String, String> q) => Uri(path: '/giveaways', queryParameters: q).toString();

  // ---------------------------------------------------------------- riwayat pencarian

  Future<void> loadHistory() async {
    final uid = _uid;
    history = uid == null ? const [] : ((await bestEffort(() => _cache.recentSearches(uid))) ?? const []);
    notifyListeners();
  }

  Future<void> deleteHistory(String q) async {
    final uid = _uid;
    if (uid != null) await bestEffort(() => _cache.deleteSearch(uid, q));
    await loadHistory();
  }

  Future<void> clearHistory() async {
    final uid = _uid;
    if (uid != null) await bestEffort(() => _cache.clearSearches(uid));
    await loadHistory();
  }

  void _onAuth() {
    if (_auth.status == AuthStatus.signedOut && (items.isNotEmpty || state != LoadState.idle || position != null)) {
      _debounceTimer?.cancel();
      _seq++;
      filters = const DiscoverFilters();
      items = const [];
      history = const [];
      position = null;
      manualLabel = null;
      locationProblem = null;
      locating = false;
      state = LoadState.idle;
      error = null;
      offline = false;
      cachedAt = null;
      hasMore = false;
      cancelRetry();
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _auth.removeListener(_onAuth);
    _auth.backOnline.remove(reloadSilently);
    super.dispose();
  }
}
