import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

enum LocationPermissionStatus {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
  unknown;

  bool get isGranted => this == LocationPermissionStatus.granted;
}

class UserLocation {
  final double latitude;
  final double longitude;
  final LocationPermissionStatus status;
  final String? errorMessage;
  final bool isFallback;

  const UserLocation({
    required this.latitude,
    required this.longitude,
    required this.status,
    this.errorMessage,
    this.isFallback = false,
  });

  /// Default fallback location in Yogyakarta (Tugu Jogja area)
  static const UserLocation yogyakartaDefault = UserLocation(
    latitude: -7.782884,
    longitude: 110.367069,
    status: LocationPermissionStatus.denied,
    isFallback: true,
  );

  UserLocation copyWith({
    double? latitude,
    double? longitude,
    LocationPermissionStatus? status,
    String? errorMessage,
    bool? isFallback,
  }) {
    return UserLocation(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
      isFallback: isFallback ?? this.isFallback,
    );
  }
}

class LocationService {
  /// Calculate Haversine distance in kilometers between two GPS coordinates
  static double calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const p = 0.017453292519943295; // Math.PI / 180
    final a = 0.5 -
        math.cos((lat2 - lat1) * p) / 2 +
        math.cos(lat1 * p) *
            math.cos(lat2 * p) *
            (1 - math.cos((lon2 - lon1) * p)) /
            2;
    return 12742 * math.asin(math.sqrt(a)); // 2 * R (R = 6371 km)
  }

  /// Check whether coordinates are within a specified radius
  static bool isWithinRadius(
    double userLat,
    double userLon,
    double targetLat,
    double targetLon,
    double radiusKm,
  ) {
    final distance = calculateDistanceKm(userLat, userLon, targetLat, targetLon);
    return distance <= radiusKm;
  }

  /// Check current permission status without requesting
  Future<LocationPermissionStatus> checkPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationPermissionStatus.serviceDisabled;
      }

      final permission = await Geolocator.checkPermission();
      switch (permission) {
        case LocationPermission.always:
        case LocationPermission.whileInUse:
          return LocationPermissionStatus.granted;
        case LocationPermission.denied:
          return LocationPermissionStatus.denied;
        case LocationPermission.deniedForever:
          return LocationPermissionStatus.deniedForever;
        case LocationPermission.unableToDetermine:
          return LocationPermissionStatus.unknown;
      }
    } catch (e) {
      debugPrint('Error checking location permission: $e');
      return LocationPermissionStatus.unknown;
    }
  }

  /// Request permission explicitly from the user
  Future<LocationPermissionStatus> requestPermission() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return LocationPermissionStatus.serviceDisabled;
      }

      final permission = await Geolocator.requestPermission();
      switch (permission) {
        case LocationPermission.always:
        case LocationPermission.whileInUse:
          return LocationPermissionStatus.granted;
        case LocationPermission.denied:
          return LocationPermissionStatus.denied;
        case LocationPermission.deniedForever:
          return LocationPermissionStatus.deniedForever;
        case LocationPermission.unableToDetermine:
          return LocationPermissionStatus.unknown;
      }
    } catch (e) {
      debugPrint('Error requesting location permission: $e');
      return LocationPermissionStatus.unknown;
    }
  }

  /// Fetch the current user location with permission checks and error handling
  Future<UserLocation> getCurrentLocation({bool requestIfDenied = true}) async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return UserLocation.yogyakartaDefault.copyWith(
          status: LocationPermissionStatus.serviceDisabled,
          errorMessage: 'Layanan lokasi (GPS) pada perangkat sedang dinonaktifkan.',
        );
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied && requestIfDenied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        return UserLocation.yogyakartaDefault.copyWith(
          status: LocationPermissionStatus.deniedForever,
          errorMessage:
              'Izin lokasi ditolak secara permanen. Silakan aktifkan izin lokasi di Pengaturan Aplikasi.',
        );
      }

      if (permission == LocationPermission.denied) {
        return UserLocation.yogyakartaDefault.copyWith(
          status: LocationPermissionStatus.denied,
          errorMessage: 'Izin lokasi belum diberikan.',
        );
      }

      // Permission granted, get real coordinates
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );

      return UserLocation(
        latitude: position.latitude,
        longitude: position.longitude,
        status: LocationPermissionStatus.granted,
        isFallback: false,
      );
    } catch (e) {
      debugPrint('Error getting current location: $e');
      return UserLocation.yogyakartaDefault.copyWith(
        status: LocationPermissionStatus.unknown,
        errorMessage: 'Gagal mendeteksi lokasi saat ini: $e',
      );
    }
  }

  /// Open app settings page for permission management
  Future<bool> openAppSettings() async {
    return Geolocator.openAppSettings();
  }

  /// Open device location settings page
  Future<bool> openLocationSettings() async {
    return Geolocator.openLocationSettings();
  }
}

// -----------------------------------------------------------------------------
// RIVERPOD PROVIDERS
// -----------------------------------------------------------------------------

final locationServiceProvider = Provider<LocationService>((ref) {
  return LocationService();
});

class UserLocationNotifier extends Notifier<UserLocation?> {
  @override
  UserLocation? build() {
    return null;
  }

  Future<UserLocation> fetchLocation({bool requestIfDenied = true}) async {
    final service = ref.read(locationServiceProvider);
    final location = await service.getCurrentLocation(
      requestIfDenied: requestIfDenied,
    );
    state = location;
    return location;
  }

  void setCustomLocation(double lat, double lng) {
    state = UserLocation(
      latitude: lat,
      longitude: lng,
      status: LocationPermissionStatus.granted,
      isFallback: false,
    );
  }
}

final userLocationProvider =
    NotifierProvider<UserLocationNotifier, UserLocation?>(UserLocationNotifier.new);
