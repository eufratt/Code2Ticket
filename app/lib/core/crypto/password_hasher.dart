import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Kontrak dengan server (db/README.md, bagian 1):
/// hex( PBKDF2-HMAC-SHA256(password UTF-8, salt UTF-8, 10.000 iterasi, 32 byte) ).
/// Salt dipakai SEBAGAI TEKS (32 karakter hex), bukan di-decode ke byte.
class PasswordHasher {
  PasswordHasher._();

  static const int iterations = 10000;
  static const int keyLength = 32;

  static String hash(String password, String salt) {
    final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
      ..init(Pbkdf2Parameters(
          Uint8List.fromList(utf8.encode(salt)), iterations, keyLength));
    return _hex(derivator.process(Uint8List.fromList(utf8.encode(password))));
  }

  /// Salt acak 16 byte -> 32 karakter hex (dipakai saat register).
  static String generateSalt([Random? random]) {
    final r = random ?? Random.secure();
    return _hex(Uint8List.fromList(List.generate(16, (_) => r.nextInt(256))));
  }

  static String _hex(Uint8List bytes) =>
      bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}
