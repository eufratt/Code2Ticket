import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config.dart';

/// Session tidak ada / kedaluwarsa (SQLSTATE 28000) -> aplikasi harus logout.
class InvalidSessionException implements Exception {
  @override
  String toString() => 'invalid_session';
}

/// Bukan admin (SQLSTATE 42501).
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

/// Memanggil Postgres RPC lewat PostgREST: POST {url}/rest/v1/rpc/{fn}.
/// Kegagalan bisnis TIDAK berupa exception: dikembalikan sebagai {"ok": false, "error": "..."}.
class RpcClient {
  RpcClient({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;
  static const _timeout = Duration(seconds: 20);

  Future<Map<String, dynamic>> call(String fn,
      [Map<String, dynamic> params = const {}]) async {
    final uri = Uri.parse('${AppConfig.supabaseUrl}/rest/v1/rpc/$fn');
    http.Response res;
    try {
      res = await _http
          .post(uri,
              headers: {
                'apikey': AppConfig.supabaseAnonKey,
                'Authorization': 'Bearer ${AppConfig.supabaseAnonKey}',
                'Content-Type': 'application/json',
              },
              body: jsonEncode(params))
          .timeout(_timeout);
    } on TimeoutException {
      throw NetworkException('Koneksi terlalu lama. Coba lagi.');
    } on SocketException {
      throw NetworkException('Tidak ada koneksi internet.');
    } on http.ClientException {
      throw NetworkException('Tidak ada koneksi internet.');
    }

    dynamic body;
    try {
      body = jsonDecode(utf8.decode(res.bodyBytes));
    } catch (_) {
      throw NetworkException('Respons server tidak valid (${res.statusCode}).');
    }

    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (body is Map<String, dynamic>) return body;
      throw NetworkException('Respons server tidak valid.');
    }

    // PostgREST: {"code":"28000","message":"invalid_session",...}
    if (body is Map) {
      final code = body['code']?.toString();
      final msg = body['message']?.toString();
      if (code == '28000' || msg == 'invalid_session') {
        throw InvalidSessionException();
      }
      if (code == '42501' || msg == 'forbidden') throw ForbiddenException();
    }
    throw NetworkException('Server menolak permintaan (${res.statusCode}).');
  }
}
