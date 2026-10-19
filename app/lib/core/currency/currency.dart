import 'dart:convert';

import '../json.dart';

/// Mata uang yang didukung (nilai dasar hadiah di backend selalu USD).
const supportedCurrencies = ['IDR', 'USD', 'EUR', 'JPY'];

String currencyName(String code) => switch (code) {
      'IDR' => 'Rupiah (IDR)',
      'USD' => 'Dolar AS (USD)',
      'EUR' => 'Euro (EUR)',
      'JPY' => 'Yen Jepang (JPY)',
      _ => code,
    };

String _group(String digits) => digits.replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => '.');

/// Format angka sesuai mata uang dengan pemisah lokal Indonesia (ribuan "." dan desimal ","):
/// IDR dan JPY tanpa desimal, USD dan EUR dua desimal. Contoh: Rp 21.587.000, US$1.200,00, €1.068,14, ¥189.672.
String formatMoney(double amount, String code) {
  final noDecimals = code == 'IDR' || code == 'JPY';
  final fixed = amount.abs().toStringAsFixed(noDecimals ? 0 : 2);
  final parts = fixed.split('.');
  final number = parts.length > 1 ? '${_group(parts[0])},${parts[1]}' : _group(parts[0]);
  final sign = amount < 0 && double.parse(fixed) != 0 ? '-' : '';
  return switch (code) {
    'IDR' => '${sign}Rp $number',
    'USD' => '${sign}US\$$number',
    'EUR' => '$sign€$number',
    'JPY' => '$sign¥$number',
    _ => '$sign$code $number',
  };
}

/// Kurs: berapa satuan mata uang X untuk 1 USD, plus tanggal kurs.
class RateSet {
  const RateSet({required this.perUsd, this.rateDate});
  final Map<String, double> perUsd;

  /// Tanggal kurs terbaru di antara mata uang (Frankfurter memberi tanggal per mata uang).
  final DateTime? rateDate;

  bool has(String code) => code == 'USD' || perUsd.containsKey(code);

  /// Konversi lewat USD; null bila salah satu kurs belum ada.
  double? convert(double amount, String from, String to) {
    if (from == to) return amount;
    final f = from == 'USD' ? 1.0 : perUsd[from];
    final t = to == 'USD' ? 1.0 : perUsd[to];
    if (f == null || t == null || f == 0) return null;
    return amount / f * t;
  }
}

/// Satu kutipan hasil parsing Frankfurter.
class ParsedRate {
  const ParsedRate(this.target, this.rate, this.date);
  final String target;
  final double rate;
  final String? date;
}

/// Parsing respons Frankfurter. Bentuk v2 (asli, dicek dengan curl):
/// `[{"date":"2026-10-19","base":"USD","quote":"EUR","rate":0.89012}, ...]`.
/// Bentuk v1 lama `{"base":"USD","date":"...","rates":{"EUR":0.89}}` juga diterima. Elemen rusak dilewati;
/// kurs nol/negatif dibuang. Mengembalikan daftar kosong bila bentuknya tak dikenal.
List<ParsedRate> parseFrankfurter(String body, {String base = 'USD'}) {
  dynamic decoded;
  try {
    decoded = jsonDecode(body);
  } catch (_) {
    return const [];
  }
  final out = <ParsedRate>[];
  void add(String? target, double? rate, String? date) {
    if (target == null || rate == null || !rate.isFinite || rate <= 0 || target == base) return;
    out.add(ParsedRate(target, rate, date));
  }

  if (decoded is List) {
    for (final e in decoded) {
      final m = asMap(e);
      if (m == null) continue;
      final b = asString(m['base']);
      if (b != null && b != base) continue;
      add(asString(m['quote']), asDouble(m['rate']), asString(m['date']));
    }
  } else if (decoded is Map<String, dynamic> && decoded['rates'] is Map) {
    final date = asString(decoded['date']);
    (decoded['rates'] as Map).forEach((k, v) => add(k is String ? k : null, asDouble(v), date));
  }
  return out;
}

DateTime? parseRateDate(String? s) => s == null ? null : DateTime.tryParse(s);
