import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

/// Kemiringan ponsel sebagai percepatan layar (m/s^2): x positif = ke kanan, y positif = ke bawah.
/// Accelerometer (dengan gravitasi): memiringkan sisi kanan ke bawah membuat x sensor NEGATIF, dan memiringkan sisi atas
/// ke bawah membuat y sensor NEGATIF; bola harus menggelinding ke arah sisi yang turun, maka x dibalik, y tetap.
/// Sensor tidak ada / ditolak -> aliran kosong (D-pad di layar tetap tersedia).
Stream<({double x, double y})> deviceTilt() {
  return accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
      .map((e) => (x: -e.x, y: e.y))
      .handleError((_) {});
}
