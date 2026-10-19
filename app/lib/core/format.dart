// Format uang dan waktu ada di core/currency/currency.dart dan core/time/zones.dart
// (mengikuti mata uang dan zona pilihan pengguna).

/// Nomor tiket 6 digit: #000012.
String formatTicketNumber(int n) => '#${n.toString().padLeft(6, '0')}';

/// Jarak dalam km dengan koma desimal: "2,3 km"; di bawah 100 m: "<0,1 km".
String formatKm(double km) => km < 0.1 ? '<0,1 km' : '${km.toStringAsFixed(1).replaceAll('.', ',')} km';
