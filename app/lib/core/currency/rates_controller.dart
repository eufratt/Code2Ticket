import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../db/rate_cache.dart';
import 'currency.dart';

/// Kurs dari Frankfurter (API publik, tanpa kunci), dipanggil LANGSUNG dari aplikasi, bukan lewat backend.
/// Kurs bersifat harian, jadi diambil paling sering sekali per jam; selebihnya dari cache SQLite.
/// Bila gagal/offline, cache dipakai dan ditandai [offline] ("Kurs per [tanggal]" + label offline).
class RatesController extends ChangeNotifier {
  RatesController(
    this._cache, {
    http.Client? client,
    this.ttl = const Duration(hours: 1),
    this.retryGap = const Duration(minutes: 1),
    DateTime Function()? clock,
  })  : _http = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  static final url = Uri.parse('https://api.frankfurter.dev/v2/rates?base=USD&quotes=IDR,EUR,JPY');

  final RateCache _cache;
  final http.Client _http;
  final Duration ttl, retryGap;
  final DateTime Function() _clock;

  RateSet rates = const RateSet(perUsd: {});

  /// Kapan kurs terakhir diambil dari server (null bila belum pernah).
  DateTime? fetchedAt;

  /// true bila kurs yang dipakai berasal dari cache karena pengambilan terbaru gagal.
  bool offline = false;
  bool loading = false;
  DateTime? _lastAttempt;
  Future<void>? _inflight;

  bool get hasRates => rates.perUsd.isNotEmpty;

  /// Memuat cache lalu menyegarkan dari server bila sudah lewat [ttl]. Tidak pernah melempar.
  Future<void> ensureFresh() => _inflight ??= _ensureFresh().whenComplete(() => _inflight = null);

  Future<void> _ensureFresh() async {
    if (!hasRates) await _loadCache();
    final now = _clock();
    final fresh = fetchedAt != null && now.difference(fetchedAt!) < ttl;
    if (fresh) return;
    // Gagal sebelumnya: jangan menghantam server tiap layar dibuka.
    if (_lastAttempt != null && now.difference(_lastAttempt!) < retryGap) return;
    _lastAttempt = now;
    loading = true;
    notifyListeners();
    try {
      final res = await _http.get(url).timeout(const Duration(seconds: 15));
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final parsed = parseFrankfurter(utf8.decode(res.bodyBytes));
      if (parsed.isEmpty) throw Exception('format kurs tidak dikenal');
      final stamp = _clock();
      final rows = [for (final p in parsed) CachedRate(target: p.target, rate: p.rate, rateDate: p.date, fetchedAt: stamp)];
      _apply(rows);
      offline = false;
      try {
        await _cache.saveRates('USD', rows);
      } catch (_) {}
    } catch (_) {
      offline = hasRates; // ada cache -> tampilkan dengan label offline; tidak ada -> USD saja
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> _loadCache() async {
    try {
      final rows = await _cache.loadRates('USD');
      if (rows.isNotEmpty) {
        _apply(rows);
        notifyListeners();
      }
    } catch (_) {}
  }

  void _apply(List<CachedRate> rows) {
    final dates = [for (final r in rows) ?parseRateDate(r.rateDate)]..sort();
    rates = RateSet(
      perUsd: {for (final r in rows) r.target: r.rate},
      rateDate: dates.isEmpty ? null : dates.last,
    );
    fetchedAt = rows.map((r) => r.fetchedAt).reduce((a, b) => a.isAfter(b) ? a : b);
  }
}
