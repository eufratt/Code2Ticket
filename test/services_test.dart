import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:code2ticket/core/services/currency_service.dart';
import 'package:code2ticket/core/services/timezone_service.dart';

void main() {
  setUpAll(() async {
    await initializeDateFormatting('id_ID', null);
    await TimezoneService.initialize();
  });

  group('CurrencyService Tests', () {
    test('uses fallback rates when client throws network error', () async {
      final mockClient = MockClient((request) async {
        throw Exception('Network unreachable');
      });

      final service = CurrencyService(client: mockClient);
      final rates = await service.getRates();

      expect(rates.isOfflineFallback, isTrue);
      expect(rates.getRate('USD'), 1.0);
      expect(rates.getRate('IDR'), 16350.0);
      expect(rates.getRate('EUR'), 0.92);
      expect(rates.getRate('JPY'), 155.0);

      final convertedIdr = service.convert(100.0, 'IDR', rates);
      expect(convertedIdr, 1635000.0);

      final formattedIdr = service.format(100.0, SupportedCurrency.idr, rates);
      expect(formattedIdr.contains('Rp'), isTrue);
    });

    test('parses rates correctly from mock API response', () async {
      final mockClient = MockClient((request) async {
        final payload = {
          'amount': 1.0,
          'base': 'USD',
          'date': '2026-03-24',
          'rates': {
            'IDR': 16000.0,
            'EUR': 0.90,
            'JPY': 150.0,
          }
        };
        return http.Response(jsonEncode(payload), 200);
      });

      final service = CurrencyService(client: mockClient);
      final rates = await service.getRates();

      expect(rates.isOfflineFallback, isFalse);
      expect(rates.getRate('USD'), 1.0);
      expect(rates.getRate('IDR'), 16000.0);
      expect(rates.getRate('EUR'), 0.90);
      expect(rates.getRate('JPY'), 150.0);

      // Formatting test
      expect(service.format(10.0, SupportedCurrency.usd, rates), '\$10.00');
      expect(service.format(10.0, SupportedCurrency.idr, rates).contains('160'), isTrue);
      expect(service.format(10.0, SupportedCurrency.eur, rates).contains('9'), isTrue);
    });
  });

  group('TimezoneService Tests', () {
    final service = TimezoneService();
    final testDateUtc = DateTime.utc(2026, 3, 24, 13, 0, 0); // 13:00 UTC

    test('converts UTC to WIB (UTC+7)', () {
      final converted = service.convertToTimezone(testDateUtc, TargetTimezone.wib);
      expect(converted.hour, 20); // 13 + 7 = 20
    });

    test('converts UTC to JST (UTC+9)', () {
      final converted = service.convertToTimezone(testDateUtc, TargetTimezone.jst);
      expect(converted.hour, 22); // 13 + 9 = 22
    });

    test('formats time with timezone string correctly', () {
      final formattedWib = service.formatWithTimezone(testDateUtc, TargetTimezone.wib);
      expect(formattedWib.contains('WIB'), isTrue);
      expect(formattedWib.contains('20:00'), isTrue);

      final formattedJst = service.formatWithTimezone(testDateUtc, TargetTimezone.jst);
      expect(formattedJst.contains('JST'), isTrue);
      expect(formattedJst.contains('22:00'), isTrue);

      final formattedUtc = service.formatWithTimezone(testDateUtc, TargetTimezone.utc);
      expect(formattedUtc.contains('UTC'), isTrue);
      expect(formattedUtc.contains('13:00'), isTrue);
    });
  });
}
