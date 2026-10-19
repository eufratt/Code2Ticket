import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/json.dart';
import '../auth/auth_controller.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'notification_models.dart';

/// Pesan siap tampil untuk kode galat server.
String notificationsErrorMessage(Object e) => switch (e) {
      ForbiddenException() => 'Akses ditolak.',
      NetworkException(:final message) => message,
      _ => 'Terjadi kesalahan. Coba lagi.',
    };

/// Notifikasi pengguna: GET /notifications (boleh diulang otomatis oleh ApiClient) dan
/// POST /notifications/read (tidak pernah diulang). Hitungan belum dibaca diturunkan dari daftar;
/// tanpa polling: dimuat saat Home dibuka dan saat app kembali ke foreground. Tidak disimpan di SQLite.
class NotificationsController extends ChangeNotifier {
  NotificationsController(this._api, this._auth) {
    _auth.addListener(_onAuth);
  }

  final AuthedApi _api;
  final AuthController _auth;

  List<AppNotification> items = const [];
  LoadState state = LoadState.idle;
  String? error;
  bool markingAll = false;
  Future<void>? _inflight;

  int get unreadCount => items.where((n) => !n.isRead).length;

  Future<void> load() => _inflight ??= _load(silent: false).whenComplete(() => _inflight = null);

  /// Menyegarkan diam-diam (lonceng Home): galat tidak mengubah tampilan.
  Future<void> refreshUnread() => _inflight ??= _load(silent: true).whenComplete(() => _inflight = null);

  Future<void> _load({required bool silent}) async {
    if (!silent) {
      state = LoadState.loading;
      error = null;
      notifyListeners();
    }
    try {
      final r = await _api.get('/notifications?limit=50');
      if (r['ok'] == false) throw NetworkException('Gagal memuat notifikasi (${r['error']}).');
      items = parseList(r['data'], AppNotification.tryParse);
      state = LoadState.loaded;
      error = null;
    } on InvalidSessionException {
      return; // AuthedApi sudah logout; router pindah ke Login
    } on NetworkException catch (e) {
      if (silent) return;
      error = e.message;
      state = LoadState.error;
    } on ForbiddenException catch (e) {
      if (silent) return;
      error = notificationsErrorMessage(e);
      state = LoadState.error;
    }
    notifyListeners();
  }

  /// Menandai satu notifikasi dibaca. Mengembalikan pesan galat, atau null bila berhasil/sesi berakhir.
  Future<String?> markRead(int id) async {
    final n = items.where((x) => x.id == id).firstOrNull;
    if (n == null || n.isRead) return null;
    return _mark([id], () => items = [for (final x in items) x.id == id ? x.asRead() : x]);
  }

  /// Menandai semua dibaca (POST tanpa `ids` = semua milik pengguna).
  Future<String?> markAllRead() async {
    if (markingAll || unreadCount == 0) return null;
    markingAll = true;
    notifyListeners();
    try {
      return await _mark(null, () => items = [for (final x in items) x.asRead()]);
    } finally {
      markingAll = false;
      notifyListeners();
    }
  }

  Future<String?> _mark(List<int>? ids, VoidCallback applyLocally) async {
    try {
      final r = await _api.post('/notifications/read', body: {'ids': ids}, retry: false);
      if (r['ok'] == false) return 'Gagal menandai dibaca (${r['error']}).';
      applyLocally();
      notifyListeners();
      return null;
    } on InvalidSessionException {
      return null;
    } on NetworkException catch (e) {
      return e.message;
    } on ForbiddenException catch (e) {
      return notificationsErrorMessage(e);
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
