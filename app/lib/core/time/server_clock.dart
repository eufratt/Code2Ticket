import 'dart:io' show HttpDate;

/// Selisih jam server terhadap jam perangkat, diukur dari header `Date` respons API (dicatat oleh ApiClient).
/// Nol sampai ada respons yang membawa header itu. Hitung mundur memakai [serverNow] supaya jam perangkat yang salah
/// tidak menggeser sisa waktu draw.
Duration serverClockOffset = Duration.zero;

/// Selisih di bawah ini dianggap nol: header `Date` hanya beresolusi 1 detik.
const _minSkew = Duration(seconds: 2);

/// Sampel dengan waktu bolak-balik lebih lama dari ini dibuang (titik tengahnya terlalu tidak pasti).
const _maxRoundTrip = Duration(seconds: 3);

/// Waktu sekarang menurut server (jam perangkat + [serverClockOffset]).
DateTime serverNow() => DateTime.now().add(serverClockOffset);

/// Memperbarui [serverClockOffset] dari header `Date` sebuah respons. [sent]/[received] = jam perangkat saat permintaan
/// dikirim dan respons diterima. Header kosong/rusak atau bolak-balik terlalu lama -> offset tidak berubah.
void recordServerDate(String? dateHeader, DateTime sent, DateTime received) {
  if (dateHeader == null) return;
  final rtt = received.difference(sent);
  if (rtt.isNegative || rtt > _maxRoundTrip) return;
  final DateTime server;
  try {
    server = HttpDate.parse(dateHeader);
  } catch (_) {
    return;
  }
  // Header dipotong ke detik penuh: waktu server sebenarnya rata-rata setengah detik lebih lambat.
  final mid = sent.add(rtt ~/ 2);
  final skew = server.add(const Duration(milliseconds: 500)).difference(mid);
  serverClockOffset = skew.abs() < _minSkew ? Duration.zero : skew;
}
