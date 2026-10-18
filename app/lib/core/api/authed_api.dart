import '../../features/auth/auth_controller.dart';
import 'api_client.dart';

/// Permintaan bertoken. Token diambil dari AuthController; bila server menjawab 401
/// (InvalidSessionException) pengguna otomatis di-logout (router mengarah ke Login) dan
/// pengecualian diteruskan supaya pemanggil berhenti tanpa menampilkan galat.
class AuthedApi {
  AuthedApi(this._api, this._auth);
  final ApiClient _api;
  final AuthController _auth;

  Future<Map<String, dynamic>> get(String path) => _run((t) => _api.get(path, token: t));

  Future<Map<String, dynamic>> post(String path, {dynamic body, bool retry = true}) =>
      _run((t) => _api.post(path, body: body, token: t, retry: retry));

  Future<Map<String, dynamic>> _run(Future<Map<String, dynamic>> Function(String token) call) async {
    final token = _auth.token;
    if (token == null) throw InvalidSessionException();
    try {
      return await call(token);
    } on InvalidSessionException {
      await _auth.handleInvalidSession();
      rethrow;
    }
  }
}
