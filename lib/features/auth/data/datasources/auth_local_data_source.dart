import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AuthLocalDataSource {
  final FlutterSecureStorage _storage;

  static const String _keySessionToken = 'c2t_session_token';
  static const String _keyBiometricEnabled = 'c2t_biometric_enabled';
  static const String _keyLastIdentifier = 'c2t_last_identifier';

  const AuthLocalDataSource({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  Future<void> saveSessionToken(String token) async {
    await _storage.write(key: _keySessionToken, value: token);
  }

  Future<String?> getSessionToken() async {
    return await _storage.read(key: _keySessionToken);
  }

  Future<void> clearSessionToken() async {
    await _storage.delete(key: _keySessionToken);
  }

  Future<void> setBiometricEnabled(bool enabled) async {
    await _storage.write(
      key: _keyBiometricEnabled,
      value: enabled ? 'true' : 'false',
    );
  }

  Future<bool> isBiometricEnabled() async {
    final value = await _storage.read(key: _keyBiometricEnabled);
    return value == 'true';
  }

  Future<void> saveLastIdentifier(String identifier) async {
    await _storage.write(key: _keyLastIdentifier, value: identifier);
  }

  Future<String?> getLastIdentifier() async {
    return await _storage.read(key: _keyLastIdentifier);
  }
}
