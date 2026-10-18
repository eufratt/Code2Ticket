import 'package:code2ticket/core/location/location_service.dart';

/// Layanan lokasi palsu: semua keadaan platform dapat diatur, panggilan dicatat.
class FakeGateway implements LocationGateway {
  FakeGateway({
    this.service = true,
    this.permission = GatewayPermission.denied,
    this.afterRequest = GatewayPermission.granted,
    this.lat = -6.2,
    this.lng = 106.8,
    this.positionError,
  });

  bool service;
  GatewayPermission permission;

  /// Izin setelah pengguna menjawab dialog sistem.
  GatewayPermission afterRequest;
  double lat, lng;
  Object? positionError;

  int requests = 0, positions = 0, appSettingsOpened = 0, locationSettingsOpened = 0;

  @override
  Future<bool> serviceEnabled() async => service;

  @override
  Future<GatewayPermission> checkPermission() async => permission;

  @override
  Future<GatewayPermission> requestPermission() async {
    requests++;
    permission = afterRequest;
    return permission;
  }

  @override
  Future<({double lat, double lng})> position() async {
    positions++;
    if (positionError != null) throw positionError!;
    return (lat: lat, lng: lng);
  }

  @override
  Future<bool> openAppSettings() async {
    appSettingsOpened++;
    return true;
  }

  @override
  Future<bool> openLocationSettings() async {
    locationSettingsOpened++;
    return true;
  }
}
