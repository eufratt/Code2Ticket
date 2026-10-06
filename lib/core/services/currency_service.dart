import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';

enum SupportedCurrency {
  usd('USD', '\$', 'Dolar AS'),
  idr('IDR', 'Rp', 'Rupiah Indonesia'),
  eur('EUR', '€', 'Euro'),
  jpy('JPY', '¥', 'Yen Jepang');

  final String code;
  final String symbol;
  final String displayName;

  const SupportedCurrency(this.code, this.symbol, this.displayName);

  static SupportedCurrency fromCode(String code) {
    return SupportedCurrency.values.firstWhere(
      (c) => c.code.toUpperCase() == code.toUpperCase(),
      orElse: () => SupportedCurrency.idr,
    );
  }
}

class CurrencyRates {
  final Map<String, double> rates;
  final DateTime lastUpdated;
  final bool isFromCache;
  final bool isOfflineFallback;

  const CurrencyRates({
    required this.rates,
    required this.lastUpdated,
    this.isFromCache = false,
    this.isOfflineFallback = false,
  });

  double getRate(String targetCurrency) {
    if (targetCurrency.toUpperCase() == 'USD') return 1.0;
    return rates[targetCurrency.toUpperCase()] ?? 1.0;
  }
}

class CurrencyService {
  final http.Client _client;
  CurrencyRates? _cachedRates;
  DateTime? _lastFetchTime;

  static const Duration cacheTtl = Duration(hours: 1);

  static const Map<String, double> defaultFallbackRates = {
    'USD': 1.0,
    'IDR': 16350.0,
    'EUR': 0.92,
    'JPY': 155.0,
  };

  CurrencyService({http.Client? client}) : _client = client ?? http.Client();

  /// Fetch exchange rates with base USD to IDR, EUR, JPY using Frankfurter API.
  /// Falls back to in-memory cache or robust offline fallback rates.
  Future<CurrencyRates> getRates({bool forceRefresh = false}) async {
    final now = DateTime.now();

    // Return active memory cache if still valid and not forcing refresh
    if (!forceRefresh &&
        _cachedRates != null &&
        _lastFetchTime != null &&
        now.difference(_lastFetchTime!) < cacheTtl) {
      return _cachedRates!;
    }

    final baseUrl = (dotenv.isInitialized ? dotenv.env['FRANKFURTER_BASE_URL'] : null) ??
        'https://api.frankfurter.app';
    final uri = Uri.parse('$baseUrl/latest?from=USD&to=IDR,EUR,JPY');

    try {
      final response = await _client.get(uri).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final rawRates = data['rates'] as Map<String, dynamic>? ?? {};

        final Map<String, double> parsedRates = {
          'USD': 1.0,
          'IDR': (rawRates['IDR'] as num?)?.toDouble() ?? defaultFallbackRates['IDR']!,
          'EUR': (rawRates['EUR'] as num?)?.toDouble() ?? defaultFallbackRates['EUR']!,
          'JPY': (rawRates['JPY'] as num?)?.toDouble() ?? defaultFallbackRates['JPY']!,
        };

        _lastFetchTime = now;
        _cachedRates = CurrencyRates(
          rates: parsedRates,
          lastUpdated: now,
          isFromCache: false,
          isOfflineFallback: false,
        );
        return _cachedRates!;
      } else {
        debugPrint('Frankfurter API returned status code ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error fetching rates from Frankfurter API: $e');
    }

    // In case of error/offline/timeout:
    if (_cachedRates != null) {
      return CurrencyRates(
        rates: _cachedRates!.rates,
        lastUpdated: _cachedRates!.lastUpdated,
        isFromCache: true,
        isOfflineFallback: false,
      );
    }

    // Return hardcoded default fallback rates
    _cachedRates = CurrencyRates(
      rates: Map<String, double>.from(defaultFallbackRates),
      lastUpdated: now,
      isFromCache: false,
      isOfflineFallback: true,
    );
    return _cachedRates!;
  }

  /// Convert an amount in USD to target currency code
  double convert(double amountInUsd, String targetCurrency, [CurrencyRates? rates]) {
    final currentRates = rates ?? _cachedRates;
    if (currentRates == null) {
      final rate = defaultFallbackRates[targetCurrency.toUpperCase()] ?? 1.0;
      return amountInUsd * rate;
    }
    return amountInUsd * currentRates.getRate(targetCurrency);
  }

  /// Format an amount in USD into formatted string for the selected currency
  String format(double amountInUsd, SupportedCurrency currency, [CurrencyRates? rates]) {
    final convertedAmount = convert(amountInUsd, currency.code, rates);

    switch (currency) {
      case SupportedCurrency.idr:
        final formatter = NumberFormat.currency(
          locale: 'id_ID',
          symbol: 'Rp ',
          decimalDigits: 0,
        );
        return formatter.format(convertedAmount);
      case SupportedCurrency.usd:
        final formatter = NumberFormat.currency(
          locale: 'en_US',
          symbol: '\$',
          decimalDigits: 2,
        );
        return formatter.format(convertedAmount);
      case SupportedCurrency.eur:
        final formatter = NumberFormat.currency(
          locale: 'de_DE',
          symbol: '€',
          decimalDigits: 2,
        );
        return formatter.format(convertedAmount);
      case SupportedCurrency.jpy:
        final formatter = NumberFormat.currency(
          locale: 'ja_JP',
          symbol: '¥',
          decimalDigits: 0,
        );
        return formatter.format(convertedAmount);
    }
  }
}

// -----------------------------------------------------------------------------
// RIVERPOD PROVIDERS
// -----------------------------------------------------------------------------

final currencyServiceProvider = Provider<CurrencyService>((ref) {
  return CurrencyService();
});

final currencyRatesProvider = FutureProvider<CurrencyRates>((ref) async {
  final service = ref.watch(currencyServiceProvider);
  return service.getRates();
});

class SelectedCurrencyNotifier extends Notifier<SupportedCurrency> {
  @override
  SupportedCurrency build() => SupportedCurrency.idr;

  void setCurrency(SupportedCurrency currency) {
    state = currency;
  }
}

final selectedCurrencyProvider =
    NotifierProvider<SelectedCurrencyNotifier, SupportedCurrency>(
  SelectedCurrencyNotifier.new,
);
