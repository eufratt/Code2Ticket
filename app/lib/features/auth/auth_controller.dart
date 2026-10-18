import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/crypto/password_hasher.dart';
import '../../core/session/session_store.dart';
import 'auth_models.dart';

enum AuthStatus { unknown, signedOut, signedIn }

/// Sumber kebenaran status login. Dipakai router (route guard) dan layar auth.
class AuthController extends ChangeNotifier {
  AuthController(this._api, this._store) {
    _api.onSlowRequest = setWakingUp;
  }

  final ApiClient _api;
  final SessionStore _store;

  AuthStatus status = AuthStatus.unknown;
  AppUser? user;
  String? _token;
  String? get token => _token;

  bool _isWakingUp = false;
  bool get isWakingUp => _isWakingUp;

  void setWakingUp(bool value) {
    if (_isWakingUp != value) {
      _isWakingUp = value;
      notifyListeners();
    }
  }

  /// Dipanggil saat aplikasi dibuka: validasi token tersimpan ke server.
  Future<void> restore() async {
    final t = await _store.readToken();
    if (t == null) return _setSignedOut();
    try {
      final r = await _api.get('/auth/me', token: t);
      if (r['ok'] == true) {
        _token = t;
        user = AppUser.fromJson(r['user'] as Map<String, dynamic>);
        status = AuthStatus.signedIn;
        notifyListeners();
      } else {
        await _clear();
      }
    } on InvalidSessionException {
      await _clear();
    } on NetworkException {
      // Offline: token tidak dihapus. Minta login ulang tanpa menghapus token.
      _setSignedOut();
    }
  }

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
      status = AuthStatus.signedIn;
      notifyListeners();
      return const AuthResult.ok();
    } on NetworkException catch (e) {
      return AuthResult.fail(e.message);
    }
  }

  Future<void> logout() async {
    final t = _token;
    if (t != null) {
      try {
        await _api.post('/auth/logout', token: t);
      } catch (_) {/* tetap logout lokal */}
    }
    await _clear();
  }

  /// Dipanggil bila request bertoken melempar InvalidSessionException.
  Future<void> handleInvalidSession() => _clear();

  Future<void> _clear() async {
    await _store.clear();
    _setSignedOut();
  }

  void _setSignedOut() {
    _token = null;
    user = null;
    status = AuthStatus.signedOut;
    notifyListeners();
  }
}
