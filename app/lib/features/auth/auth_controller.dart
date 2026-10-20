import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/crypto/password_hasher.dart';
import '../../core/db/local_db.dart';
import '../../core/offline.dart';
import '../../core/security/biometric_service.dart';
import '../../core/session/session_store.dart';
import 'auth_models.dart';

enum AuthStatus { unknown, signedOut, biometricRequired, signedIn }

/// Sumber kebenaran status login. Dipakai router (route guard) dan layar auth.
class AuthController extends ChangeNotifier {
  AuthController(
    this._api,
    this._store, {
    LocalDb? db,
    BiometricService? biometric,
  })  : _db = db ?? LocalDb.instance,
        _biometric = biometric ?? BiometricService() {
    _api.onSlowRequest = setWakingUp;
  }

  final ApiClient _api;
  final SessionStore _store;
  final LocalDb _db;
  final BiometricService _biometric;

  AuthStatus status = AuthStatus.unknown;
  AppUser? user;
  String? _token;
  String? get token => _token;

  /// Kunci app_settings (user_id kosong) untuk profil terakhir yang valid; tanpa token atau password.
  static const profileKey = 'last_profile';

  /// true: sesi dibuka dari token + profil lokal karena server tak terjangkau (status tetap signedIn).
  /// Data berasal dari cache; aksi tulis butuh koneksi. Keluar hanya lewat 401 atau logout.
  bool offlineSession = false;
  Future<void>? _revalidating;

  /// Dipanggil sekali saat sesi offline kembali online: controller berdata cache menyegarkan diri.
  final List<VoidCallback> backOnline = [];

  bool _isWakingUp = false;
  bool get isWakingUp => _isWakingUp;

  void setWakingUp(bool value) {
    if (_isWakingUp != value) {
      _isWakingUp = value;
      notifyListeners();
    }
  }

  Future<bool> isBiometricAvailable() => _biometric.isAvailable();

  Future<bool> isBiometricEnabled({String? userId}) async {
    final uid = userId ?? user?.id ?? '';
    final val = await _db.getSetting('biometric_enabled', userId: uid);
    if (val != null) return val == '1' || val == 'true';
    if (uid.isNotEmpty) {
      final global = await _db.getSetting('biometric_enabled', userId: '');
      return global == '1' || global == 'true';
    }
    return false;
  }

  Future<bool> setBiometricEnabled(bool enable) async {
    if (enable) {
      final available = await _biometric.isAvailable();
      if (!available) return false;
      final ok = await _biometric.authenticate(
        'Konfirmasi identitas Anda untuk mengaktifkan kunci biometric',
      );
      if (!ok) return false;
    }
    await _db.setSetting(
      'biometric_enabled',
      enable ? '1' : '0',
      userId: user?.id ?? '',
    );
    notifyListeners();
    return true;
  }

  Future<bool> unlockWithBiometric() async {
    final ok = await _biometric.authenticate(
      'Konfirmasi identitas Anda untuk membuka Code2Ticket',
    );
    if (ok) {
      status = AuthStatus.signedIn;
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Dipanggil saat aplikasi dibuka: validasi token tersimpan ke server. HANYA penolakan server (401)
  /// yang mengeluarkan pengguna; jaringan mati, timeout, atau 5xx dengan profil tersimpan -> sesi offline.
  Future<void> restore() async {
    final t = await _store.readToken();
    if (t == null) return _setSignedOut();
    AppUser? me;
    try {
      me = await _fetchMe(t);
    } on InvalidSessionException {
      return _clear();
    } catch (_) {/* galat jaringan: lihat di bawah */}
    if (me != null) {
      user = me;
      offlineSession = false;
      await _remember(me);
    } else {
      final saved = AppUserProfile.tryParseProfile(await bestEffort(() => _db.getSetting(profileKey)));
      if (saved == null) return _setSignedOut(); // tidak ada profil: minta login ulang, token tidak dihapus
      user = saved;
      offlineSession = true;
    }
    _token = t;
    await _unlock();
  }

  Future<AppUser?> _fetchMe(String token) async {
    final r = await _api.getOnce('/auth/me', token: token);
    return r['ok'] == true ? AppUser.fromJson(r['user'] as Map<String, dynamic>) : null;
  }

  /// Menerapkan kunci biometric (bila aktif) sebelum konten tampil, juga pada sesi offline.
  Future<void> _unlock() async {
    final locked = await isBiometricEnabled(userId: user!.id) &&
        !await _biometric.authenticate('Konfirmasi identitas Anda untuk membuka Code2Ticket');
    status = locked ? AuthStatus.biometricRequired : AuthStatus.signedIn;
    notifyListeners();
  }

  /// Sesi offline -> validasi ulang /auth/me (aplikasi di-resume, tarik untuk menyegarkan, koneksi kembali).
  /// 200 -> online dan data disegarkan; 401 -> keluar dengan pembersihan; galat jaringan -> tetap offline.
  Future<void> revalidate() {
    if (!offlineSession || _token == null) return Future.value();
    return _revalidating ??= _revalidate().whenComplete(() => _revalidating = null);
  }

  Future<void> _revalidate() async {
    final t = _token;
    try {
      final me = await _fetchMe(t!);
      if (me == null || _token != t) return;
      user = me;
      offlineSession = false;
      await _remember(me);
      notifyListeners();
      for (final f in [...backOnline]) {
        f();
      }
    } on InvalidSessionException {
      if (_token == t) await _clear();
    } catch (_) {/* masih offline */}
  }

  Future<void> _remember(AppUser u) => bestEffort(() => _db.setSetting(profileKey, u.toProfileJson()));

  Future<AuthResult> register({
    required String username,
    required String email,
    required String fullName,
    required String password,
  }) async {
    try {
      final salt = PasswordHasher.generateSalt();
      final hash = PasswordHasher.hash(password, salt);
      final r = await _api.post('/auth/register', body: {
        'username': username.trim(),
        'email': email.trim(),
        'full_name': fullName.trim(),
        'salt': salt,
        'password_hash': hash,
      });
      if (r['ok'] != true) return AuthResult.fail(authErrorMessage(r));
      return login(identifier: username, password: password);
    } on NetworkException catch (e) {
      return AuthResult.fail(e.message);
    }
  }

  Future<AuthResult> login(
      {required String identifier, required String password}) async {
    try {
      final s = await _api.post('/auth/salt', body: {
        'identifier': identifier.trim(),
      });
      if (s['ok'] != true || s['salt'] == null) {
        return AuthResult.fail(authErrorMessage(s));
      }
      final hash = PasswordHasher.hash(password, s['salt'] as String);
      final r = await _api.post('/auth/login', body: {
        'identifier': identifier.trim(),
        'password_hash': hash,
      });
      if (r['ok'] != true) return AuthResult.fail(authErrorMessage(r));
      _token = r['token'] as String;
      await _store.saveToken(_token!);
      user = AppUser.fromJson(r['user'] as Map<String, dynamic>);
      offlineSession = false;
      await _remember(user!);
      status = AuthStatus.signedIn;
      notifyListeners();
      return const AuthResult.ok();
    } on NetworkException catch (e) {
      return AuthResult.fail(e.message);
    }
  }

  Future<void> logout() async {
    final t = _token;
    if (t != null && !offlineSession) {
      try {
        await _api.post('/auth/logout', token: t);
      } catch (_) {/* tetap logout lokal */}
    }
    await _clear();
  }

  /// Memperbarui data pengguna yang sedang login (mis. setelah ubah nama / ganti foto).
  void updateUser(AppUser u) {
    user = u;
    unawaited(_remember(u));
    notifyListeners();
  }

  /// Dipanggil bila request bertoken melempar InvalidSessionException.
  Future<void> handleInvalidSession() => _clear();

  Future<void> _clear() async {
    // Cache giveaway/tiket, riwayat pencarian dan chat ikut dihapus; sesi kedaluwarsa saat cold start (user belum
    // terisi) memakai id profil tersimpan, atau menghapus semua baris bila id tidak diketahui. Gagal menghapus tidak menahan logout.
    final uid = user?.id ?? AppUserProfile.tryParseProfile(await bestEffort(() => _db.getSetting(profileKey)))?.id;
    await bestEffort(() => _db.clearUserData(userId: uid));
    await bestEffort(() => _db.setSetting(profileKey, null));
    await bestEffort(_store.clear);
    _setSignedOut();
  }

  void _setSignedOut() {
    _token = null;
    user = null;
    offlineSession = false;
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}
