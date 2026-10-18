import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/json.dart';
import '../auth/auth_controller.dart';
import 'giveaway_models.dart';

enum LoadState { idle, loading, loaded, error }

/// Daftar giveaway aktif (Home) dan pencarian satu giveaway untuk layar detail.
class GiveawaysController extends ChangeNotifier {
  GiveawaysController(this._api, this._auth) {
    _auth.addListener(_onAuth);
  }

  final AuthedApi _api;
  final AuthController _auth;

  List<Giveaway> items = const [];
  LoadState state = LoadState.idle;
  String? error;
  Future<void>? _inflight;

  Future<void> load() => _inflight ??= _load().whenComplete(() => _inflight = null);

  Future<void> _load() async {
    state = LoadState.loading;
    error = null;
    notifyListeners();
    try {
      final r = await _api.get('/giveaways?limit=50');
      if (r['ok'] == false) {
        throw NetworkException('Gagal memuat giveaway (${r['error']}).');
      }
      items = parseList(r['data'], Giveaway.tryParse);
      state = LoadState.loaded;
    } on InvalidSessionException {
      return;
    } on NetworkException catch (e) {
      error = e.message;
      state = LoadState.error;
    }
    notifyListeners();
  }

  /// Backend belum punya GET /giveaways/:id, jadi detail dicari di daftar. Daftar bawaan hanya
  /// memuat yang aktif; bila tidak ketemu, cari di semua status (maks. 50 teratas).
  Future<Giveaway?> find(String id) async {
    Giveaway? hit() => items.where((g) => g.id == id).firstOrNull;
    if (hit() != null) return hit();
    try {
      final r = await _api.get('/giveaways?status=all&limit=50');
      final all = parseList(r['data'], Giveaway.tryParse);
      return all.where((g) => g.id == id).firstOrNull;
    } on InvalidSessionException {
      return null;
    } on NetworkException {
      return null;
    }
  }

  void _onAuth() {
    if (_auth.status == AuthStatus.signedOut && (items.isNotEmpty || state != LoadState.idle)) {
      items = const [];
      state = LoadState.idle;
      error = null;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuth);
    super.dispose();
  }
}
