import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/json.dart';
import '../auth/auth_controller.dart';
import '../giveaways/giveaway_models.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'admin_models.dart';

/// Hasil operasi admin: [data] bila berhasil, atau [error] (pesan Indonesia siap tampil).
class AdminResult<T> {
  const AdminResult.ok(this.data) : error = null;
  const AdminResult.fail(this.error) : data = null;
  final T? data;
  final String? error;
  bool get isOk => error == null;
}

/// Operasi admin: GET|POST /admin/giveaways, POST|GET /admin/giveaways/:id/codes,
/// POST /admin/giveaways/:id/draw. Semua POST: tanpa retry otomatis, satu per satu ([busy]). Server tetap penentu
/// hak akses (403 -> "Akses ditolak"). Kode yang dibuat hanya dikembalikan ke pemanggil: tidak disimpan di sini,
/// di SQLite, maupun di log.
class AdminController extends ChangeNotifier {
  AdminController(this._api, this._auth) {
    _auth.addListener(_onAuth);
  }

  final AuthedApi _api;
  final AuthController _auth;

  List<Giveaway> giveaways = const [];
  LoadState state = LoadState.idle;
  String? error;

  /// true selama satu operasi tulis berjalan (mencegah kirim ganda).
  bool busy = false;
  Future<void>? _inflight;

  /// Daftar giveaway untuk admin: GET /admin/giveaways (semua status; GET /giveaways publik hanya yang aktif).
  Future<void> loadGiveaways() => _inflight ??= _loadGiveaways().whenComplete(() => _inflight = null);

  Future<void> _loadGiveaways() async {
    state = LoadState.loading;
    error = null;
    notifyListeners();
    try {
      final r = await _api.get('/admin/giveaways?limit=50');
      if (r['ok'] == false) throw NetworkException('Gagal memuat giveaway (${r['error']}).');
      giveaways = parseList(r['data'], Giveaway.tryParse);
      state = LoadState.loaded;
    } on InvalidSessionException {
      return;
    } on NetworkException catch (e) {
      error = e.message;
      state = LoadState.error;
    } on ForbiddenException {
      error = adminErrorMessage('forbidden');
      state = LoadState.error;
    }
    notifyListeners();
  }

  /// Mengembalikan id giveaway baru. null = sedang sibuk atau sesi berakhir.
  Future<AdminResult<String>?> createGiveaway(GiveawayDraft draft) async {
    final r = await _write(() => _api.post('/admin/giveaways', body: draft.toJson(), retry: false), (j) => asString(j['giveaway_id']) ?? '');
    if (r != null && r.isOk) await loadGiveaways();
    return r;
  }

  /// Membuat [count] kode. Daftar kode hanya ada di hasil ini.
  Future<AdminResult<List<String>>?> generateCodes(String giveawayId, int count) => _write(
        () => _api.post('/admin/giveaways/$giveawayId/codes', body: {'count': count}, retry: false),
        (j) => [for (final c in (j['codes'] is List ? j['codes'] as List : const [])) if (c is String) c],
      );

  /// Draw manual (mode demo server). Tidak bisa dibatalkan.
  Future<AdminResult<DrawOutcome>?> runDraw(String giveawayId) async {
    final r = await _write(() => _api.post('/admin/giveaways/$giveawayId/draw', body: <String, dynamic>{}, retry: false), DrawOutcome.fromJson);
    if (r != null && r.isOk) await loadGiveaways();
    return r;
  }

  /// GET daftar kode (boleh diulang otomatis oleh ApiClient). Tidak mengubah [busy].
  Future<AdminResult<List<AdminCode>>?> listCodes(String giveawayId) async {
    try {
      final r = await _api.get('/admin/giveaways/$giveawayId/codes');
      if (r['ok'] == false) return AdminResult.fail(adminErrorMessage(asString(r['error']), field: asString(r['field'])));
      return AdminResult.ok(parseList(r['data'], AdminCode.tryParse));
    } on InvalidSessionException {
      return null;
    } on ForbiddenException {
      return AdminResult.fail(adminErrorMessage('forbidden'));
    } on NetworkException catch (e) {
      return AdminResult.fail(e.message);
    }
  }

  Future<AdminResult<T>?> _write<T>(Future<Map<String, dynamic>> Function() call, T Function(Map<String, dynamic>) parse) async {
    if (busy) return null;
    busy = true;
    notifyListeners();
    try {
      final r = await call();
      if (r['ok'] == false) return AdminResult.fail(adminErrorMessage(asString(r['error']), field: asString(r['field'])));
      return AdminResult.ok(parse(r));
    } on InvalidSessionException {
      return null; // AuthedApi sudah logout; router pindah ke Login
    } on ForbiddenException {
      return AdminResult.fail(adminErrorMessage('forbidden'));
    } on NetworkException catch (e) {
      return AdminResult.fail(e.message);
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  void _onAuth() {
    if (_auth.status == AuthStatus.signedOut && (giveaways.isNotEmpty || state != LoadState.idle)) {
      giveaways = const [];
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
