import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Session tidak ada / kedaluwarsa (HTTP 401) -> aplikasi harus logout.
class InvalidSessionException implements Exception {
  @override
  String toString() => 'invalid_session';
}

/// Bukan admin / akses ditolak (HTTP 403).
class ForbiddenException implements Exception {
  @override
  String toString() => 'forbidden';
}

/// Jaringan mati, timeout, atau respons tak terduga.
class NetworkException implements Exception {
  NetworkException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Aksi tulis ditolak lebih dulu karena sesi sedang offline (permintaan tidak dikirim).
class OfflineRequiredException extends NetworkException {
  OfflineRequiredException() : super('Butuh koneksi internet.');
}

typedef SlowRequestCallback = void Function(bool isSlow);

/// Klien HTTP untuk API Express Code2Ticket.
/// Base URL dibaca dari AppConfig.apiBaseUrl (--dart-define=API_BASE_URL).
class ApiClient {
  ApiClient({
    http.Client? client,
    this.baseUrl,
    this.onSlowRequest,
    List<Duration>? retryDelays,
    Duration? timeout,
  })  : _http = client ?? http.Client(),
        _retryDelays = retryDelays ??
            const [Duration(seconds: 3), Duration(seconds: 6)],
        _timeout = timeout ?? const Duration(seconds: 45);

  final http.Client _http;
  final String? baseUrl;
  final List<Duration> _retryDelays;
  final Duration _timeout;
  SlowRequestCallback? onSlowRequest;

  Uri _buildUri(String path) {
    final base =
        (baseUrl ?? AppConfig.apiBaseUrl).replaceAll(RegExp(r'/+$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p');
  }

  Future<Map<String, dynamic>> get(
    String path, {
    dynamic body,
    String? token,
  }) =>
      _send('GET', path, body: body, token: token);

  /// GET yang cepat gagal saat koneksi putus (tanpa jeda 3 dtk + 6 dtk); timeout dan 502/503 Render tetap diulang.
  /// Untuk cek sesi: pengguna offline tidak boleh menunggu di Splash.
  Future<Map<String, dynamic>> getOnce(String path, {String? token}) =>
      _send('GET', path, token: token, retry: false);

  /// [retry] false: jangan ulangi otomatis saat koneksi putus (mis. input kode,
  /// agar satu ketukan tidak bisa membuat dua tiket; atau cek sesi yang harus cepat gagal saat offline).
  Future<Map<String, dynamic>> post(
    String path, {
    dynamic body,
    String? token,
    bool retry = true,
  }) =>
      _send('POST', path, body: body, token: token, retry: retry);

  /// Unggah biner (mis. foto profil JPEG). Tidak pernah diulang otomatis.
  Future<Map<String, dynamic>> putBytes(
    String path,
    List<int> bytes, {
    required String contentType,
    String? token,
  }) =>
      _send('PUT', path, bytes: bytes, contentType: contentType, token: token, retry: false);

  Future<Map<String, dynamic>> patch(
    String path, {
    dynamic body,
    String? token,
  }) =>
      _send('PATCH', path, body: body, token: token);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    dynamic body,
    String? token,
    bool retry = true,
    List<int>? bytes,
    String? contentType,
  }) async {
    final uri = _buildUri(path);
    final isGet = method == 'GET';

    Timer? slowTimer;
    if (onSlowRequest != null) {
      slowTimer = Timer(const Duration(seconds: 5), () {
        onSlowRequest?.call(true);
      });
    }

    try {
      int attempt = 0;
      while (true) {
        try {
          final req = http.Request(method, uri);
          if (token != null && token.isNotEmpty) {
            req.headers['Authorization'] = 'Bearer $token';
          }
          if (bytes != null) {
            req.headers['Content-Type'] = contentType ?? 'application/octet-stream';
            req.bodyBytes = bytes;
          } else if (body != null) {
            req.headers['Content-Type'] = 'application/json';
            req.body = jsonEncode(body);
          }

          final streamed = await _http.send(req).timeout(_timeout);
          final res = await http.Response.fromStream(streamed);

          if (isGet && _isEdgeError(res) && attempt < _retryDelays.length) {
            await Future.delayed(_retryDelays[attempt]);
            attempt++;
            continue;
          }

          return _handleResponse(res);
        } on TimeoutException {
          // Hanya GET yang diulangi saat timeout
          if (isGet && attempt < _retryDelays.length) {
            await Future.delayed(_retryDelays[attempt]);
            attempt++;
            continue;
          }
          throw NetworkException('Koneksi terlalu lama. Coba lagi.');
        } on SocketException {
          // Gagal koneksi sebelum respons: boleh ulangi GET dan POST
          if (retry && attempt < _retryDelays.length) {
            await Future.delayed(_retryDelays[attempt]);
            attempt++;
            continue;
          }
          throw NetworkException('Tidak ada koneksi internet.');
        } on http.ClientException {
          // Gagal koneksi sebelum respons: boleh ulangi GET dan POST
          if (retry && attempt < _retryDelays.length) {
            await Future.delayed(_retryDelays[attempt]);
            attempt++;
            continue;
          }
          throw NetworkException('Tidak ada koneksi internet.');
        }
      }
    } finally {
      slowTimer?.cancel();
      onSlowRequest?.call(false);
    }
  }

  bool _isEdgeError(http.Response res) {
    if (res.statusCode == 502 || res.statusCode == 503) return true;
    if (res.statusCode == 404) {
      for (final entry in res.headers.entries) {
        if (entry.key.toLowerCase() == 'x-render-routing' &&
            entry.value.toLowerCase().contains('no-server')) {
          return true;
        }
      }
    }
    return false;
  }

  Map<String, dynamic> _handleResponse(http.Response res) {
    if (res.statusCode == 401) throw InvalidSessionException();
    if (res.statusCode == 403) throw ForbiddenException();

    dynamic decoded;
    try {
      decoded = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw NetworkException('Respons server tidak valid (${res.statusCode}).');
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is List) return {'ok': true, 'data': decoded};
      throw NetworkException('Respons server tidak valid.');
    }

    if (decoded is Map<String, dynamic> && decoded.containsKey('ok')) {
      return decoded;
    }

    throw NetworkException('Server menolak permintaan (${res.statusCode}).');
  }
}
