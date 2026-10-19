class AppUser {
  AppUser({
    required this.id,
    required this.username,
    required this.email,
    required this.fullName,
    this.photoUrl,
    required this.role,
    required this.xp,
    required this.level,
    this.badges = const [],
  });

  final String id, username, email, fullName, role;
  final String? photoUrl;
  final int xp, level;
  final List<String> badges;
  bool get isAdmin => role == 'admin';

  factory AppUser.fromJson(Map<String, dynamic> j) => AppUser(
        id: j['id'] as String,
        username: j['username'] as String,
        email: j['email'] as String,
        fullName: j['full_name'] as String,
        photoUrl: j['photo_url'] as String?,
        role: j['role'] as String,
        xp: (j['xp'] as num?)?.toInt() ?? 0,
        level: (j['level'] as num?)?.toInt() ?? 1,
        badges: [for (final b in (j['badges'] is List ? j['badges'] as List : const [])) if (b is String) b],
      );
}

/// Hasil operasi auth: sukses, atau pesan error siap tampil.
class AuthResult {
  const AuthResult.ok() : error = null;
  const AuthResult.fail(this.error);
  final String? error;
  bool get success => error == null;
}

String authErrorMessage(Map<String, dynamic> r) {
  switch (r['error']) {
    case 'invalid_credentials':
      final left = r['attempts_left'];
      return left == null
          ? 'Username/email atau password salah.'
          : 'Username/email atau password salah. Sisa percobaan: $left.';
    case 'locked':
      final s = (r['retry_after_seconds'] as num?)?.toInt() ?? 900;
      return 'Akun dikunci sementara. Coba lagi dalam ${(s / 60).ceil()} menit.';
    case 'username_taken':
      return 'Username sudah dipakai.';
    case 'email_taken':
      return 'Email sudah terdaftar.';
    case 'invalid_input':
      switch (r['field']) {
        case 'username':
          return 'Username 4-20 karakter: huruf, angka, underscore.';
        case 'email':
          return 'Format email tidak valid.';
        case 'full_name':
          return 'Nama lengkap wajib diisi (maks. 100 karakter).';
        default:
          return 'Data tidak valid.';
      }
    default:
      return 'Terjadi kesalahan (${r['error']}).';
  }
}
