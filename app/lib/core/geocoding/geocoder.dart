import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../api/api_client.dart';
import '../json.dart';

class Place {
  const Place({required this.name, required this.lat, required this.lng});
  final String name;
  final double lat, lng;
}

/// Pencarian nama tempat -> koordinat lewat Nominatim (OpenStreetMap), untuk lokasi manual saat izin lokasi ditolak.
/// Kebijakan Nominatim: User-Agent yang jelas, maks. 1 permintaan/detik, tanpa autocomplete tiap ketikan
/// (dipanggil hanya dari tombol Cari), hasil di-cache. Tanpa kunci API. Hanya teks pencarian yang dikirim,
/// bukan posisi pengguna.
class Geocoder {
  Geocoder({
    http.Client? client,
    this.minGap = const Duration(milliseconds: 1100),
    Future<void> Function(Duration)? sleep,
    DateTime Function()? clock,
  })  : _http = client ?? http.Client(),
        _sleep = sleep ?? Future.delayed,
        _clock = clock ?? DateTime.now;

  static const userAgent = 'Code2Ticket/1.0 (+https://github.com/eufratt/Code2Ticket)';
  static const minQueryLength = 3;
  static const _maxCache = 30;

  final http.Client _http;
  final Duration minGap;
  final Future<void> Function(Duration) _sleep;
  final DateTime Function() _clock;

  final Map<String, List<Place>> _cache = {};
  Future<void> _queue = Future.value();
  DateTime? _lastRequestAt;

  static String _key(String q) => q.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  /// Mengembalikan daftar tempat (maks. 5). Melempar [NetworkException] bila layanan gagal / dibatasi.
  Future<List<Place>> search(String query) {
    final key = _key(query);
    if (key.length < minQueryLength) return Future.value(const []);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    // Antrean: permintaan berjalan satu per satu dengan jeda minimal.
    final result = _queue.then((_) => _fetch(key));
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<List<Place>> _fetch(String key) async {
    final cached = _cache[key];
    if (cached != null) return cached;
    final last = _lastRequestAt;
    if (last != null) {
      final wait = minGap - _clock().difference(last);
      if (wait > Duration.zero) await _sleep(wait);
    }
    _lastRequestAt = _clock();
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': key,
      'format': 'jsonv2',
      'limit': '5',
      'accept-language': 'id',
    });
    final http.Response res;
    try {
      res = await _http.get(uri, headers: {'User-Agent': userAgent}).timeout(const Duration(seconds: 15));
    } on TimeoutException {
      throw NetworkException('Pencarian tempat terlalu lama. Coba lagi.');
    } on http.ClientException {
      throw NetworkException('Tidak ada koneksi internet.');
    }
    if (res.statusCode == 429 || res.statusCode == 403) {
      throw NetworkException('Layanan pencarian tempat sedang dibatasi. Coba lagi beberapa saat.');
    }
    if (res.statusCode != 200) throw NetworkException('Pencarian tempat gagal (${res.statusCode}).');
    final places = _parse(utf8.decode(res.bodyBytes));
    if (_cache.length >= _maxCache) _cache.remove(_cache.keys.first);
    _cache[key] = places;
    return places;
  }

  static List<Place> _parse(String body) {
    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      throw NetworkException('Respons pencarian tempat tidak valid.');
    }
    return parseList(decoded, (e) {
      final m = asMap(e);
      final lat = asDouble(m?['lat']), lng = asDouble(m?['lon']);
      final name = asString(m?['display_name']);
      if (lat == null || lng == null || name == null) return null;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) return null;
      return Place(name: name, lat: lat, lng: lng);
    });
  }
}
