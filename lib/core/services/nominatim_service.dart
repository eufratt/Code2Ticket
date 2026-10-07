import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

class NominatimPlace {
  final String displayName;
  final double latitude;
  final double longitude;
  final String? type;
  final String? road;
  final String? city;
  final String? suburb;

  const NominatimPlace({
    required this.displayName,
    required this.latitude,
    required this.longitude,
    this.type,
    this.road,
    this.city,
    this.suburb,
  });

  String get shortTitle {
    if (road != null && road!.isNotEmpty) {
      if (suburb != null && suburb!.isNotEmpty) return '$road, $suburb';
      return road!;
    }
    if (suburb != null && suburb!.isNotEmpty) return suburb!;
    if (city != null && city!.isNotEmpty) return city!;
    final parts = displayName.split(',');
    if (parts.isNotEmpty) return parts.first.trim();
    return displayName;
  }

  factory NominatimPlace.fromJson(Map<String, dynamic> json) {
    final lat = double.tryParse(json['lat']?.toString() ?? '0') ?? 0.0;
    final lon = double.tryParse(json['lon']?.toString() ?? '0') ?? 0.0;
    final address = json['address'] as Map<String, dynamic>? ?? {};

    return NominatimPlace(
      displayName: json['display_name'] as String? ?? 'Lokasi',
      latitude: lat,
      longitude: lon,
      type: json['type'] as String?,
      road: address['road'] as String? ?? address['pedestrian'] as String?,
      city: address['city'] as String? ??
          address['town'] as String? ??
          address['municipality'] as String? ??
          address['county'] as String?,
      suburb: address['suburb'] as String? ??
          address['village'] as String? ??
          address['neighbourhood'] as String?,
    );
  }
}

class NominatimService {
  final http.Client _client;
  static const String _baseUrl = 'https://nominatim.openstreetmap.org';
  static const String _userAgent = 'Code2Ticket/1.0 (contact: mobile@code2ticket.app)';

  // In-memory caches to respect OSM usage policy and minimize traffic
  final Map<String, List<NominatimPlace>> _searchCache = {};
  final Map<String, String> _reverseGeocodeCache = {};

  // Rate-limiting timestamp: Ensure >= 1000ms between network calls
  DateTime? _lastRequestTime;

  NominatimService({http.Client? client}) : _client = client ?? http.Client();

  /// Throttling helper to ensure maximum 1 request per second as per Nominatim TOS
  Future<void> _throttle() async {
    if (_lastRequestTime != null) {
      final elapsed = DateTime.now().difference(_lastRequestTime!);
      const minInterval = Duration(milliseconds: 1050);
      if (elapsed < minInterval) {
        final waitDuration = minInterval - elapsed;
        await Future<void>.delayed(waitDuration);
      }
    }
    _lastRequestTime = DateTime.now();
  }

  /// Forward Geocoding: Search address or landmark
  Future<List<NominatimPlace>> searchLocation(
    String query, {
    int limit = 5,
    String countryCode = 'id',
  }) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];

    final cacheKey = '${cleanQuery.toLowerCase()}_${limit}_$countryCode';
    if (_searchCache.containsKey(cacheKey)) {
      return _searchCache[cacheKey]!;
    }

    await _throttle();

    try {
      final uri = Uri.parse('$_baseUrl/search').replace(
        queryParameters: {
          'q': cleanQuery,
          'format': 'json',
          'addressdetails': '1',
          'limit': limit.toString(),
          if (countryCode.isNotEmpty) 'countrycodes': countryCode,
        },
      );

      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
          'Accept-Language': 'id-ID,id;q=0.9,en;q=0.8',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as List<dynamic>;
        final places = data
            .map((item) => NominatimPlace.fromJson(item as Map<String, dynamic>))
            .toList();

        _searchCache[cacheKey] = places;
        return places;
      } else {
        debugPrint('Nominatim API error: HTTP ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error searching location via Nominatim: $e');
    }

    return [];
  }

  /// Reverse Geocoding: Convert GPS coordinates to human-readable address
  Future<String> reverseGeocode(double latitude, double longitude) async {
    // Round to 4 decimal places (~11 meters) for cache key
    final cacheKey = '${latitude.toStringAsFixed(4)}_${longitude.toStringAsFixed(4)}';
    if (_reverseGeocodeCache.containsKey(cacheKey)) {
      return _reverseGeocodeCache[cacheKey]!;
    }

    await _throttle();

    try {
      final uri = Uri.parse('$_baseUrl/reverse').replace(
        queryParameters: {
          'lat': latitude.toString(),
          'lon': longitude.toString(),
          'format': 'json',
          'addressdetails': '1',
          'zoom': '16',
        },
      );

      final response = await _client.get(
        uri,
        headers: {
          'User-Agent': _userAgent,
          'Accept': 'application/json',
          'Accept-Language': 'id-ID,id;q=0.9,en;q=0.8',
        },
      ).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final place = NominatimPlace.fromJson(data);
        final result = place.shortTitle;
        _reverseGeocodeCache[cacheKey] = result;
        return result;
      }
    } catch (e) {
      debugPrint('Error reverse geocoding via Nominatim: $e');
    }

    return 'Lokasi (${latitude.toStringAsFixed(3)}, ${longitude.toStringAsFixed(3)})';
  }
}

// -----------------------------------------------------------------------------
// RIVERPOD PROVIDER
// -----------------------------------------------------------------------------

final nominatimServiceProvider = Provider<NominatimService>((ref) {
  return NominatimService();
});
