import 'package:code2ticket/core/crypto/password_hasher.dart';
import 'package:flutter_test/flutter_test.dart';

// Nilai acuan dihitung dengan Python hashlib.pbkdf2_hmac (sama dengan server/tests).
void main() {
  test('PBKDF2 cocok dengan Python (ASCII)', () {
    expect(
      PasswordHasher.hash('password123', '0123456789abcdef0123456789abcdef'),
      '335f0b0930c013dc714572cee1e07f6c245fab8c09e9a55a42704413c9edc200',
    );
  });

  test('PBKDF2 cocok dengan Python (Unicode)', () {
    expect(
      PasswordHasher.hash('Pässwörd ✓', 'ffffffffffffffffffffffffffffffff'),
      '6c0fb7a2d1c4def2bf02efe2432fbd9b7f3dbb938f2e7b1e16ea871e2a29f774',
    );
  });

  test('salt 32 karakter hex dan acak', () {
    final a = PasswordHasher.generateSalt();
    final b = PasswordHasher.generateSalt();
    expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(a, isNot(b));
  });
}
