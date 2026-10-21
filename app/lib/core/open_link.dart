import 'package:url_launcher/url_launcher.dart';

/// Membuka tautan di browser eksternal. Variabel supaya tes bisa menggantinya tanpa platform channel.
Future<bool> Function(Uri uri) openExternal = (uri) => launchUrl(uri, mode: LaunchMode.externalApplication);

/// Uri bila [s] tautan https absolut yang aman dibuka (host ada, tanpa kredensial, tanpa spasi/karakter kontrol); selain itu null.
/// Server sudah memeriksa, tetapi data cache atau server lama tidak boleh dipercaya begitu saja.
Uri? parseHttpsUrl(String? s) {
  final t = s?.trim() ?? '';
  if (t.isEmpty || t.length > 500 || RegExp(r'[\s\x00-\x1f\x7f]').hasMatch(t)) return null;
  final u = Uri.tryParse(t);
  if (u == null || !u.isAbsolute || u.scheme != 'https' || u.host.isEmpty || u.userInfo.isNotEmpty) return null;
  return u;
}

bool isHttpsUrl(String s) => parseHttpsUrl(s) != null;
