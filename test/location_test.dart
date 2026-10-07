import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:code2ticket/core/services/location_service.dart';
import 'package:code2ticket/core/services/nominatim_service.dart';

void main() {
  group('LocationService Unit Tests', () {
    test('Haversine formula calculates known distance accurately', () {
      // Distance between Tugu Jogja (-7.782884, 110.367069)
      // and Malioboro Mall (-7.792823, 110.365842) is approximately 1.1 km
      final distance = LocationService.calculateDistanceKm(
        -7.782884,
        110.367069,
        -7.792823,
        110.365842,
      );

      expect(distance, greaterThan(1.0));
      expect(distance, lessThan(1.3));
    });

    test('isWithinRadius correctly checks boundary', () {
      const userLat = -7.782884;
      const userLng = 110.367069;

      // Point ~1.1 km away
      const targetLat = -7.792823;
      const targetLng = 110.365842;

      // Inside 2.0 km radius
      expect(
        LocationService.isWithinRadius(userLat, userLng, targetLat, targetLng, 2.0),
        isTrue,
      );

      // Outside 0.5 km radius
      expect(
        LocationService.isWithinRadius(userLat, userLng, targetLat, targetLng, 0.5),
        isFalse,
      );
    });

    test('UserLocation fallback object has default Yogyakarta coordinates', () {
      expect(UserLocation.yogyakartaDefault.latitude, closeTo(-7.782, 0.01));
      expect(UserLocation.yogyakartaDefault.longitude, closeTo(110.367, 0.01));
      expect(UserLocation.yogyakartaDefault.isFallback, isTrue);
    });
  });

  group('NominatimService Tests', () {
    test('NominatimPlace parses from JSON correctly', () {
      final json = {
        'display_name': 'Tugu Yogyakarta, Jetis, Kota Yogyakarta, Daerah Istimewa Yogyakarta',
        'lat': '-7.782884',
        'lon': '110.367069',
        'type': 'monument',
        'address': {
          'road': 'Jalan Margo Utomo',
          'city': 'Kota Yogyakarta',
          'suburb': 'Jetis',
        }
      };

      final place = NominatimPlace.fromJson(json);
      expect(place.latitude, -7.782884);
      expect(place.longitude, 110.367069);
      expect(place.shortTitle, 'Jalan Margo Utomo, Jetis');
    });

    test('searchLocation uses cache on subsequent identical requests', () async {
      int requestCount = 0;
      final mockClient = MockClient((request) async {
        requestCount++;
        final mockResults = [
          {
            'display_name': 'Malioboro, Yogyakarta',
            'lat': '-7.7928',
            'lon': '110.3658',
            'address': {'road': 'Malioboro'},
          }
        ];
        return http.Response(jsonEncode(mockResults), 200);
      });

      final service = NominatimService(client: mockClient);

      final results1 = await service.searchLocation('Malioboro');
      expect(results1.length, 1);
      expect(requestCount, 1);

      // Second call should return from cache without network hit
      final results2 = await service.searchLocation('Malioboro');
      expect(results2.length, 1);
      expect(requestCount, 1);
    });
  });
}
