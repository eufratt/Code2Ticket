import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
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
    this.retryDelays = const [Duration(seconds: 2), Duration(seconds: 5)],
    DateTime Function()? clock,
  })  : _http = client ?? http.Client(),
        _clock = clock ?? DateTime.now;

  static final url = Uri.parse('https://api.frankfurter.dev/v2/rates?base=USD&quotes=IDR,EUR,JPY');

  final RateCache _cache;
  final http.Client _http;
  final Duration ttl, retryGap;
  final List<Duration> retryDelays;
  final DateTime Function() _clock;

  RateSet rates = const RateSet(perUsd: {});

  /// Kapan kurs terakhir diambil dari server (null bila belum pernah).
  DateTime? fetchedAt;

  /// true bila kurs yang dipakai berasal dari cache karena pengambilan terbaru gagal.
  bool offline = false;
  bool loading = false;

  /// Pesan galat terakhir bila pengambilan gagal (null bila berhasil).
  String? lastError;

  DateTime? _lastAttempt;
  Future<void>? _inflight;
  bool _disposed = false;

  bool get hasRates => rates.perUsd.isNotEmpty;

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  /// Memuat cache lalu menyegarkan dari server bila sudah lewat [ttl] atau belum ada kurs.
  /// [force] mengabaikan throttle [retryGap] dan [ttl], tetapi tetap menjaga agar tidak ada dua permintaan bersamaan.
  Future<void> ensureFresh({bool force = false}) =>
      _inflight ??= _ensureFresh(force: force).whenComplete(() => _inflight = null);

  /// Menangani perubahan lifecycle aplikasi (muat ulang bila resumed).
  void handleAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ensureFresh();
    }
  }

  Future<void> _ensureFresh({bool force = false}) async {
    if (loading) return;
    if (!hasRates) await _loadCache();
    final now = _clock();
    if (!force) {
      final fresh = fetchedAt != null && now.difference(fetchedAt!) < ttl;
      if (fresh) return;
      // Gagal sebelumnya: hanya throttle bila SUDAH ada kurs di memori.
      if (hasRates && _lastAttempt != null && now.difference(_lastAttempt!) < retryGap) {
        return;
      }
    }
    _lastAttempt = now;
    loading = true;
    notifyListeners();

    try {
      int attempt = 0;
      while (true) {
        if (_disposed) return;
        try {
          final res = await _http.get(url).timeout(const Duration(seconds: 15));
          if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
          final parsed = parseFrankfurter(utf8.decode(res.bodyBytes));
          if (parsed.isEmpty) throw Exception('format kurs tidak dikenal');
          final stamp = _clock();
          final rows = [
            for (final p in parsed)
              CachedRate(target: p.target, rate: p.rate, rateDate: p.date, fetchedAt: stamp)
          ];
          _apply(rows);
          offline = false;
          lastError = null;
          try {
            await _cache.saveRates('USD', rows);
          } catch (e) {
            if (kDebugMode) debugPrint('RatesController cache save error: $e');
          }
          break;
        } catch (e) {
          lastError = e.toString();
          if (kDebugMode) debugPrint('RatesController fetch error (attempt $attempt): $e');
          if (!hasRates && attempt < retryDelays.length) {
            await Future.delayed(retryDelays[attempt]);
            attempt++;
            continue;
          }
          offline = hasRates; // ada cache -> tampilkan dengan label offline; tidak ada -> USD saja
          break;
        }
      }
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
    } catch (e) {
      if (kDebugMode) debugPrint('RatesController cache load error: $e');
    }
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
