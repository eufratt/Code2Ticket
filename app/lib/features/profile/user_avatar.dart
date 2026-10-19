import 'package:flutter/material.dart';

import '../../core/config.dart';
import '../auth/auth_models.dart';

/// Alamat foto: relatif ("/users/{id}/photo?v=...") diawali alamat API; alamat absolut dipakai apa adanya.
String? resolvePhotoUrl(String? photoUrl, {String? base}) {
  if (photoUrl == null || photoUrl.isEmpty) return null;
  if (photoUrl.startsWith('http://') || photoUrl.startsWith('https://')) return photoUrl;
  final b = (base ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/+$'), '');
  return '$b${photoUrl.startsWith('/') ? '' : '/'}$photoUrl';
}

String initialsOf(String name) {
  final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
  if (parts.isEmpty) return '?';
  final first = String.fromCharCode(parts.first.runes.first).toUpperCase();
  if (parts.length == 1) return first;
  return first + String.fromCharCode(parts.last.runes.first).toUpperCase();
}

/// Foto profil bulat; placeholder inisial bila belum ada foto atau gagal dimuat.
/// Gambar hanya ditampilkan dari server (cache gambar bawaan Flutter), tidak disimpan di SQLite.
class UserAvatar extends StatelessWidget {
  const UserAvatar({super.key, required this.user, this.radius = 40});
  final AppUser? user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = Container(
      key: const Key('avatar_initials'),
      width: radius * 2,
      height: radius * 2,
      alignment: Alignment.center,
      color: scheme.primaryContainer,
      child: Text(initialsOf(user?.fullName ?? ''),
          style: TextStyle(fontSize: radius * 0.8, color: scheme.onPrimaryContainer, fontWeight: FontWeight.w600)),
    );
    final url = resolvePhotoUrl(user?.photoUrl);
    return ClipOval(
      child: SizedBox(
        width: radius * 2,
        height: radius * 2,
        child: url == null
            ? placeholder
            : Image.network(
                url,
                key: ValueKey(url), // alamat berganti (?v=) -> gambar dimuat ulang
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => placeholder,
                loadingBuilder: (_, child, progress) => progress == null ? child : placeholder,
              ),
      ),
    );
  }
}
