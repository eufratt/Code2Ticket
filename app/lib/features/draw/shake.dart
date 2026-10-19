import 'dart:async';
import 'dart:math';

import 'package:sensors_plus/sensors_plus.dart';

/// Mendeteksi goyangan dari besar percepatan (m/s², tanpa gravitasi): [spikes] lonjakan di atas [threshold],
/// masing-masing berjarak minimal [minGap], semuanya dalam [window]. Murni (tanpa sensor) supaya mudah diuji.
class ShakeDetector {
  ShakeDetector({this.threshold = 14, this.spikes = 3, this.window = const Duration(milliseconds: 1200), this.minGap = const Duration(milliseconds: 120)});

  final double threshold;
  final int spikes;
  final Duration window, minGap;
  final List<Duration> _hits = [];

  /// true bila sampel ini melengkapi sebuah goyangan (hitungan lalu diulang dari nol).
  bool add(double magnitude, Duration at) {
    if (magnitude < threshold) return false;
    if (_hits.isNotEmpty && at - _hits.last < minGap) return false;
    _hits.add(at);
    _hits.removeWhere((t) => at - t > window);
    if (_hits.length >= spikes) {
      _hits.clear();
      return true;
    }
    return false;
  }
}

/// Aliran kejadian goyang dari sensor percepatan perangkat. Sensor tidak ada / ditolak -> aliran tanpa kejadian
/// (tombol alternatif tetap tersedia di layar).
Stream<void> deviceShakes() {
  final sw = Stopwatch()..start();
  final detector = ShakeDetector();
  return userAccelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
      .map((e) => sqrt(e.x * e.x + e.y * e.y + e.z * e.z))
      .where((m) => detector.add(m, sw.elapsed))
      .map<void>((_) {})
      .handleError((_) {});
}
