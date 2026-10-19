import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

const _bulan = ['Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des'];

bool _initialized = false;

/// Memuat basis data zona waktu IANA (sekali). Panggil sebelum memakai [AppZone].
void initTimeZones() {
  if (_initialized) return;
  tzdata.initializeTimeZones();
  _initialized = true;
}

/// Empat zona yang wajib didukung. Offset dan musim panas London dihitung oleh data IANA, bukan manual.
enum AppZone {
  wib('Asia/Jakarta', 'WIB'),
  wita('Asia/Makassar', 'WITA'),
  wit('Asia/Jayapura', 'WIT'),
  london('Europe/London', 'London');

  const AppZone(this.ianaName, this.title);
  final String ianaName;
  final String title;

  tz.Location get location {
    initTimeZones();
    return tz.getLocation(ianaName);
  }

  static AppZone fromName(String? name) =>
      AppZone.values.where((z) => z.name == name).firstOrNull ?? AppZone.wib;
}

/// Waktu [instant] di zona [zone].
tz.TZDateTime inZone(DateTime instant, AppZone zone) => tz.TZDateTime.from(instant, zone.location);

/// Singkatan zona pada saat itu: WIB, WITA, WIT, GMT atau BST (London, tergantung tanggal).
String zoneAbbreviation(DateTime instant, AppZone zone) => inZone(instant, zone).timeZoneName;

String _two(int n) => n.toString().padLeft(2, '0');

/// "19 Okt 2026, 03.29 WIB" / "19 Jul 2026, 12.00 BST".
String formatInZone(DateTime instant, AppZone zone) {
  final t = inZone(instant, zone);
  return '${t.day} ${_bulan[t.month - 1]} ${t.year}, ${_two(t.hour)}.${_two(t.minute)} ${t.timeZoneName}';
}

/// Tanggal saja ("19 Okt 2026"), tanpa konversi zona (untuk tanggal kurs).
String formatDate(DateTime d) => '${d.day} ${_bulan[d.month - 1]} ${d.year}';

/// Offset terhadap UTC pada saat itu, mis. "UTC+7", "UTC+1".
String formatOffset(DateTime instant, AppZone zone) {
  final o = inZone(instant, zone).timeZoneOffset;
  final h = o.inHours, m = o.inMinutes.remainder(60).abs();
  return 'UTC${h >= 0 ? '+' : '-'}${h.abs()}${m == 0 ? '' : ':${_two(m)}'}';
}

/// Waktu dinding (tahun, bulan, ...) di [zone] -> instan UTC.
DateTime instantFromWallClock(AppZone zone, int y, int mo, int d, int h, int mi) =>
    tz.TZDateTime(zone.location, y, mo, d, h, mi).toUtc();

/// "2j 10m 05d" (hari "h", jam "j", menit "m", detik "d"); bagian nol di depan dihilangkan.
String formatCountdown(Duration remaining) {
  final s = remaining.inSeconds;
  if (s <= 0) return '0d';
  final days = s ~/ 86400, hours = s % 86400 ~/ 3600, mins = s % 3600 ~/ 60, secs = s % 60;
  if (days > 0) return '${days}h ${hours}j ${mins}m';
  if (hours > 0) return '${hours}j ${_two(mins)}m ${_two(secs)}d';
  if (mins > 0) return '${mins}m ${_two(secs)}d';
  return '${secs}d';
}
