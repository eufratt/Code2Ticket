import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Menyimpan token session di penyimpanan aman (Keystore/Keychain).
class SessionStore {
  SessionStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _s;
  static const _kToken = 'c2t_token';

  /// Galat secure storage (mis. Keystore rusak) diperlakukan sebagai belum masuk.
  Future<String?> readToken() async {
    try {
      return await _s.read(key: _kToken);
    } catch (_) {
      return null;
    }
  }
  Future<void> saveToken(String token) => _s.write(key: _kToken, value: token);
  Future<void> clear() => _s.delete(key: _kToken);
}
