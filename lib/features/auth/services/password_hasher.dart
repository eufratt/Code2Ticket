import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:dbcrypt/dbcrypt.dart';

class PasswordHasher {
  final DBCrypt _dbcrypt = DBCrypt();

  /// Hashes a plain-text password using BCrypt with salt (10 rounds).
  String hashPassword(String plainPassword) {
    final salt = _dbcrypt.gensaltWithRounds(10);
    return _dbcrypt.hashpw(plainPassword, salt);
  }

  /// Verifies a plain-text password against a stored BCrypt hash.
  bool verifyPassword(String plainPassword, String hashedPassword) {
    try {
      return _dbcrypt.checkpw(plainPassword, hashedPassword);
    } catch (_) {
      return false;
    }
  }

  /// Generates a cryptographically secure random session token (32 bytes).
  String generateSessionToken() {
    final random = Random.secure();
    final values = List<int>.generate(32, (_) => random.nextInt(256));
    return base64UrlEncode(values).replaceAll('=', '');
  }

  /// Computes the SHA-256 hash of a session token for safe database storage.
  String hashSessionToken(String token) {
    final bytes = utf8.encode(token);
    return sha256.convert(bytes).toString();
  }

  /// Checks if a session has expired or is revoked.
  bool isSessionValid(DateTime expiresAt, bool isRevoked) {
    if (isRevoked) return false;
    return DateTime.now().toUtc().isBefore(expiresAt.toUtc());
  }
}
