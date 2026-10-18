/// Konfigurasi aplikasi dari --dart-define saat build/run:
/// flutter run --dart-define=API_BASE_URL=https://code2ticket.onrender.com
class AppConfig {
  static const apiBaseUrl = String.fromEnvironment('API_BASE_URL');

  static bool get isConfigured => apiBaseUrl.isNotEmpty;
}
