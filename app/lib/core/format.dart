// Format uang dan waktu ada di core/currency/currency.dart dan core/time/zones.dart
// (mengikuti mata uang dan zona pilihan pengguna).

/// Nomor tiket 6 digit: #000012.
String formatTicketNumber(int n) => '#${n.toString().padLeft(6, '0')}';

/// Jarak dalam km dengan koma desimal: "2,3 km"; di bawah 100 m: "<0,1 km".
String formatKm(double km) => km < 0.1 ? '<0,1 km' : '${km.toStringAsFixed(1).replaceAll('.', ',')} km';

/// Angka masukan pengguna format Indonesia: titik ribuan, koma desimal ("1.000.000,50" = 1000000.5).
/// Titik tunggal tanpa koma = ribuan bila diikuti tepat 3 digit dan bagian depannya bukan "0" ("1.000"), selain itu desimal ("1.5").
/// null untuk kosong, non-angka, negatif, atau tidak finit.
double? parseIdNumber(String text) {
  final t = text.trim();
  if (!RegExp(r'^[0-9][0-9.,]*$').hasMatch(t)) return null;
  final commas = ','.allMatches(t).length;
  if (commas > 1) return null;
  var intPart = t, frac = '';
  if (commas == 1) {
    final i = t.indexOf(',');
    intPart = t.substring(0, i);
    frac = t.substring(i + 1);
    if (frac.contains('.') || frac.isEmpty) return null;
    if (intPart.contains('.') && !_thousands(intPart)) return null;
    intPart = intPart.replaceAll('.', '');
  } else if (t.contains('.')) {
    final parts = t.split('.');
    if (parts.length > 2 || (parts[1].length == 3 && parts[0] != '0')) {
      if (!_thousands(t)) return null;
      intPart = parts.join();
    } else {
      intPart = parts[0];
      frac = parts[1];
      if (frac.isEmpty) return null;
    }
  }
  final v = double.tryParse(frac.isEmpty ? intPart : '$intPart.$frac');
  return v != null && v.isFinite ? v : null;
}

bool _thousands(String s) => RegExp(r'^[0-9]{1,3}(\.[0-9]{3})+$').hasMatch(s);
