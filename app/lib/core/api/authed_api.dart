import 'dart:async';

import '../../features/auth/auth_controller.dart';
import 'api_client.dart';

/// Permintaan bertoken. Token diambil dari AuthController; bila server menjawab 401
/// (InvalidSessionException) pengguna otomatis di-logout (router mengarah ke Login) dan
/// pengecualian diteruskan supaya pemanggil berhenti tanpa menampilkan galat.
class AuthedApi {
  AuthedApi(this._api, this._auth);
  final ApiClient _api;
  final AuthController _auth;

  Future<Map<String, dynamic>> get(String path) => _run((t) => _api.get(path, token: t, retry: !_auth.offlineSession)); // sesi offline: gagal cepat, tanpa jeda ulang 3+6 dtk

  Future<Map<String, dynamic>> post(String path, {dynamic body, bool retry = true}) =>
      _write((t) => _api.post(path, body: body, token: t, retry: retry));

  Future<Map<String, dynamic>> putBytes(String path, List<int> bytes, {required String contentType}) =>
      _write((t) => _api.putBytes(path, bytes, contentType: contentType, token: t));

  Future<Map<String, dynamic>> patch(String path, {dynamic body}) =>
      _write((t) => _api.patch(path, body: body, token: t));

  /// Aksi tulis di sesi offline: validasi ulang dulu; masih offline -> ditolak tanpa mengirim permintaan.
  Future<Map<String, dynamic>> _write(Future<Map<String, dynamic>> Function(String token) call) async {
    if (_auth.offlineSession) {
      await _auth.revalidate();
      if (_auth.offlineSession) throw OfflineRequiredException();
    }
    return _run(call);
  }

  Future<Map<String, dynamic>> _run(Future<Map<String, dynamic>> Function(String token) call) async {
    final token = _auth.token;
    if (token == null) throw InvalidSessionException();
    try {
      final r = await call(token);
      if (_auth.offlineSession) unawaited(_auth.revalidate()); // server menjawab: sesi kembali online
      return r;
    } on InvalidSessionException {
      await _auth.handleInvalidSession();
      rethrow;
    }
  }
}
