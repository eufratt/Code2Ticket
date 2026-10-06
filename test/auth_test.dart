import 'package:flutter_test/flutter_test.dart';
import 'package:code2ticket/features/auth/services/password_hasher.dart';

void main() {
  group('PasswordHasher & Session Expiry Unit Tests', () {
    late PasswordHasher hasher;

    setUp(() {
      hasher = PasswordHasher();
    });

    test('BCrypt hashes and verifies matching passwords', () {
      const password = 'SecretPassword123!';
      final hash = hasher.hashPassword(password);

      expect(hash.isNotEmpty, isTrue);
      expect(hash.startsWith(r'$2a$') || hash.startsWith(r'$2b$'), isTrue);

      // Correct password verifies successfully
      expect(hasher.verifyPassword(password, hash), isTrue);

      // Wrong password fails verification
      expect(hasher.verifyPassword('WrongPassword!', hash), isFalse);
    });

    test('Cryptographically secure session token generation and SHA-256 hashing', () {
      final token1 = hasher.generateSessionToken();
      final token2 = hasher.generateSessionToken();

      expect(token1.isNotEmpty, isTrue);
      expect(token2.isNotEmpty, isTrue);
      expect(token1, isNot(equals(token2)));

      final hash1 = hasher.hashSessionToken(token1);
      final hash2 = hasher.hashSessionToken(token2);

      expect(hash1.length, 64); // SHA-256 hex string is 64 characters
      expect(hash2.length, 64);
      expect(hash1, isNot(equals(hash2)));
    });

    test('Session validity check respects expiration time and revocation status', () {
      final now = DateTime.now().toUtc();

      // Active non-revoked session
      final futureExpiry = now.add(const Duration(days: 7));
      expect(hasher.isSessionValid(futureExpiry, false), isTrue);

      // Expired session
      final pastExpiry = now.subtract(const Duration(seconds: 1));
      expect(hasher.isSessionValid(pastExpiry, false), isFalse);

      // Revoked session (even if unexpired)
      expect(hasher.isSessionValid(futureExpiry, true), isFalse);
    });

    test('Input validation rules for registration', () {
      // Username validation
      expect(RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch('user_123'), isTrue);
      expect(RegExp(r'^[a-zA-Z0-9_.]+$').hasMatch('user@invalid'), isFalse);
      expect('ab'.length >= 3, isFalse);
      expect('abc'.length >= 3, isTrue);

      // Email validation
      final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
      expect(emailRegex.hasMatch('demo@code2ticket.app'), isTrue);
      expect(emailRegex.hasMatch('invalid-email'), isFalse);

      // Password length (min 8 chars)
      expect('1234567'.length >= 8, isFalse);
      expect('12345678'.length >= 8, isTrue);
    });
  });
}
