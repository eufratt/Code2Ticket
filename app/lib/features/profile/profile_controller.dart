
import 'package:flutter/foundation.dart';

import '../../core/api/api_client.dart';
import '../../core/api/authed_api.dart';
import '../../core/images/photo_compress.dart';
import '../../core/json.dart';
import '../auth/auth_controller.dart';
import '../auth/auth_models.dart';

/// Ubah nama (PATCH /me) dan ganti foto profil (PUT /me/photo). Mengembalikan pesan galat siap tampil, atau null bila sukses.
class ProfileController extends ChangeNotifier {
  ProfileController(this._api, this._auth, {Future<Uint8List> Function(Uint8List)? compress})
      : _compress = compress ?? ((b) => compute(compressProfilePhoto, b));

  final AuthedApi _api;
  final AuthController _auth;
  final Future<Uint8List> Function(Uint8List) _compress;

  bool saving = false;

  Future<String?> updateName(String name) async {
    final n = name.trim();
    if (n.isEmpty || n.length > 100) return 'Nama lengkap wajib diisi (maks. 100 karakter).';
    return _run(() async {
      final r = await _api.patch('/me', body: {'full_name': n});
      return _applyUser(r);
    });
  }

  /// [raw] = berkas gambar dari kamera/galeri; dikompres di klien (maks. 512 px, JPEG <= 150 KB) lalu diunggah.
  Future<String?> uploadPhoto(Uint8List raw) async {
    final Uint8List jpeg;
    try {
      jpeg = await _compress(raw);
    } on FormatException catch (e) {
      return e.message;
    }
    if (jpeg.length > maxPhotoBytes) return 'Foto masih terlalu besar setelah dikecilkan.';
    return _run(() async {
      final r = await _api.putBytes('/me/photo', jpeg, contentType: 'image/jpeg');
      return _applyUser(r);
    });
  }

  String? _applyUser(Map<String, dynamic> r) {
    if (r['ok'] == true) {
      final u = asMap(r['user']);
      if (u != null) _auth.updateUser(AppUser.fromJson(u));
      return null;
    }
    return switch (r['error']) {
      'payload_too_large' => 'Foto terlalu besar (maks. 150 KB).',
      'too_many_requests' => 'Terlalu banyak percobaan. Coba lagi sebentar.',
      'invalid_input' when r['field'] == 'full_name' => 'Nama lengkap wajib diisi (maks. 100 karakter).',
      'invalid_input' => 'Data tidak valid.',
      _ => 'Gagal menyimpan (${r['error']}).',
    };
  }

  Future<String?> _run(Future<String?> Function() op) async {
    if (saving) return 'Sedang menyimpan, tunggu sebentar.';
    saving = true;
    notifyListeners();
    try {
      return await op();
    } on InvalidSessionException {
      return null; // AuthedApi sudah logout
    } on NetworkException catch (e) {
      return e.message;
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}
