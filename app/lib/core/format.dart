const _bulan = [
  'Jan', 'Feb', 'Mar', 'Apr', 'Mei', 'Jun', 'Jul', 'Agu', 'Sep', 'Okt', 'Nov', 'Des',
];

/// Waktu dalam WIB (UTC+7) terlepas dari zona perangkat. Konversi 4 zona lengkap menyusul di M5.
String formatWib(DateTime t) {
  final w = t.toUtc().add(const Duration(hours: 7));
  String two(int n) => n.toString().padLeft(2, '0');
  return '${w.day} ${_bulan[w.month - 1]} ${w.year}, ${two(w.hour)}.${two(w.minute)} WIB';
}

/// Nomor tiket 6 digit: #000012.
String formatTicketNumber(int n) => '#${n.toString().padLeft(6, '0')}';

/// Nilai hadiah dalam USD (konversi mata uang menyusul di M5).
String formatUsd(double? v) {
  if (v == null) return '-';
  final fixed = v.toStringAsFixed(v == v.roundToDouble() ? 0 : 2);
  final parts = fixed.split('.');
  final grouped = parts[0].replaceAllMapped(RegExp(r'\B(?=(\d{3})+(?!\d))'), (_) => ',');
  return 'USD ${parts.length > 1 ? '$grouped.${parts[1]}' : grouped}';
}
