import '../models/user_model.dart';

abstract class AuthRepository {
  /// Registers a new user with format validation and password hashing.
  Future<UserModel> register({
    required String username,
    required String email,
    required String password,
  });

  /// Logs in a user, verifies password against BCrypt hash, and issues a 7-day session token.
  Future<({UserModel user, String sessionToken})> login({
    required String identifier,
    required String password,
  });

  /// Validates the locally stored session token against the remote database.
  Future<UserModel?> validateStoredSession();

  /// Revokes the current session remotely and clears local storage.
  Future<void> logout();

  /// Gets the raw session token stored in secure storage.
  Future<String?> getStoredSessionToken();

  /// Checks if biometric unlock is enabled by the user.
  Future<bool> isBiometricEnabled();

  /// Updates the biometric unlock preference.
  Future<void> setBiometricEnabled(bool enabled);
}
