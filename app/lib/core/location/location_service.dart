import 'package:geolocator/geolocator.dart';

/// Hasil upaya mendapatkan posisi. Posisi hanya dikembalikan ke pemanggil (memori); tidak disimpan di mana pun.
enum LocationStatus { granted, denied, deniedForever, serviceOff, unavailable }

class LocationFix {
  const LocationFix(this.status, {this.lat, this.lng});
  final LocationStatus status;
  final double? lat, lng;
  bool get ok => status == LocationStatus.granted && lat != null && lng != null;
}

enum GatewayPermission { denied, deniedForever, granted }

/// Lapisan tipis ke platform (geolocator) supaya logika izin dapat diuji dengan layanan lokasi palsu.
abstract class LocationGateway {
  Future<bool> serviceEnabled();
  Future<GatewayPermission> checkPermission();
  Future<GatewayPermission> requestPermission();

  /// Posisi saat ini; melempar bila gagal/timeout.
  Future<({double lat, double lng})> position();
  Future<bool> openAppSettings();
  Future<bool> openLocationSettings();
}

/// Izin lokasi hanya saat aplikasi dipakai (foreground), akurasi sedang cukup untuk jarak antar kota.
class GeolocatorGateway implements LocationGateway {
  GeolocatorGateway({this.timeout = const Duration(seconds: 8)});
  final Duration timeout;

  static GatewayPermission _map(LocationPermission p) => switch (p) {
        LocationPermission.always || LocationPermission.whileInUse => GatewayPermission.granted,
        LocationPermission.deniedForever => GatewayPermission.deniedForever,
        _ => GatewayPermission.denied,
      };

  @override
  Future<bool> serviceEnabled() => Geolocator.isLocationServiceEnabled();

  @override
  Future<GatewayPermission> checkPermission() async => _map(await Geolocator.checkPermission());

  @override
  Future<GatewayPermission> requestPermission() async => _map(await Geolocator.requestPermission());

  @override
  Future<({double lat, double lng})> position() async {
    final p = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(accuracy: LocationAccuracy.medium, timeLimit: timeout),
    );
    return (lat: p.latitude, lng: p.longitude);
  }

  @override
  Future<bool> openAppSettings() => Geolocator.openAppSettings();

  @override
  Future<bool> openLocationSettings() => Geolocator.openLocationSettings();
}

/// Logika izin lokasi: layanan lokasi mati, belum diminta, ditolak, ditolak permanen.
class LocationService {
  LocationService(this._gateway);
  final LocationGateway _gateway;

  /// [prompt] true: boleh memunculkan dialog izin sistem (aksi pengguna, mis. "Terdekat").
  /// false: hanya memakai izin yang sudah ada, tanpa mengganggu (mis. saat Input Code).
  Future<LocationFix> locate({bool prompt = true}) async {
    try {
      if (!await _gateway.serviceEnabled()) return const LocationFix(LocationStatus.serviceOff);
      var perm = await _gateway.checkPermission();
      if (perm == GatewayPermission.denied && prompt) perm = await _gateway.requestPermission();
      if (perm == GatewayPermission.deniedForever) return const LocationFix(LocationStatus.deniedForever);
      if (perm == GatewayPermission.denied) return const LocationFix(LocationStatus.denied);
      final p = await _gateway.position();
      return LocationFix(LocationStatus.granted, lat: p.lat, lng: p.lng);
    } catch (_) {
      return const LocationFix(LocationStatus.unavailable);
    }
  }

  /// Membuka pengaturan yang relevan untuk status [s] (izin permanen -> pengaturan aplikasi,
  /// layanan mati -> pengaturan lokasi). Mengembalikan false bila tidak ada yang dibuka.
  Future<bool> openSettingsFor(LocationStatus s) async {
    try {
      return switch (s) {
        LocationStatus.deniedForever => await _gateway.openAppSettings(),
        LocationStatus.serviceOff => await _gateway.openLocationSettings(),
        _ => false,
      };
    } catch (_) {
      return false;
    }
  }
}

/// Pesan siap tampil untuk status yang bukan `granted`.
String locationStatusMessage(LocationStatus s) => switch (s) {
      LocationStatus.granted => '',
      LocationStatus.denied => 'Izin lokasi ditolak. Fitur Terdekat membutuhkan lokasimu.',
      LocationStatus.deniedForever =>
        'Izin lokasi ditolak permanen. Buka pengaturan aplikasi untuk mengizinkan lokasi.',
      LocationStatus.serviceOff => 'Layanan lokasi di perangkat mati. Aktifkan lokasi lalu coba lagi.',
      LocationStatus.unavailable => 'Posisi belum bisa ditentukan. Coba lagi di tempat yang sinyalnya lebih baik.',
    };

/// Label tombol aksi untuk status [s].
String locationActionLabel(LocationStatus s) => switch (s) {
      LocationStatus.deniedForever => 'Buka pengaturan',
      LocationStatus.serviceOff => 'Buka pengaturan lokasi',
      LocationStatus.denied => 'Izinkan lokasi',
      _ => 'Coba lagi',
    };
