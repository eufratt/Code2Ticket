import 'dart:math';

/// Parameter kontrol kemiringan (semua sudut dalam radian). Disetel untuk ponsel dipegang dengan satu tangan;
/// ubah di sini, bukan di layar.
///
/// - [tiltTau]: konstanta waktu filter komplementer (detik). Per sampel gyroscope, a = tau / (tau + dt); pada 50 Hz
///   (dt = 20 ms) a ≈ 0,972. Gyroscope menentukan gerak jangka pendek, accelerometer menarik sudut kembali ke arah
///   gravitasi sehingga drift gyroscope hilang dalam kira-kira [tiltTau] detik.
/// - [tiltDeadZone]: sudut di bawah ini (≈ 2,9°) dianggap datar, supaya ponsel yang diam di tangan tidak menggeser bola.
///   Bagian di atasnya dihitung mulai dari nol (tanpa lompatan di tepi zona mati).
/// - [tiltMax]: sudut maksimum yang dihitung (≈ 34°); lebih miring tidak menambah percepatan.
/// - [tiltGain]: percepatan bola (sel/detik^2) per radian di atas zona mati; percepatan maksimum = (max - zona mati) * gain ≈ 8,8.
/// - [accelTrustBand]: accelerometer hanya dipercaya bila besar percepatannya dalam g ± band ini (m/s^2); saat ponsel
///   diguncang atau dihentak, koreksi dilewati dan sudut hanya mengikuti gyroscope.
/// - [gyroMaxDt]: batas langkah integrasi (detik); celah lebih besar (aplikasi dijeda, sensor tersendat) dipotong.
/// - [gyroTimeout]: tanpa sampel gyroscope selama ini = dianggap tidak ada, kembali ke accelerometer saja.
const double tiltTau = 0.7, tiltDeadZone = 0.05, tiltMax = 0.6, tiltGain = 16, accelTrustBand = 2.5, gyroMaxDt = 0.1;
const Duration gyroTimeout = Duration(seconds: 1);
const double standardGravity = 9.80665;

/// Masukan sensor untuk [TiltFilter]; dipisah dari plugin supaya filter dan layar bisa diuji dengan data sintetis.
sealed class TiltInput {
  const TiltInput();
}

/// Accelerometer (dengan gravitasi), m/s^2, sumbu perangkat.
class AccelInput extends TiltInput {
  const AccelInput(this.x, this.y, this.z);
  final double x, y, z;
}

/// Gyroscope: kecepatan sudut (rad/s) pada sumbu perangkat x dan y, selama [dt] detik sejak sampel sebelumnya.
class GyroInput extends TiltInput {
  const GyroInput(this.x, this.y, this.dt);
  final double x, y, dt;
}

/// Gyroscope tidak tersedia (aliran galat atau tidak ada data sampai [gyroTimeout]).
class GyroLost extends TiltInput {
  const GyroLost();
}

/// Kemiringan ponsel dari penggabungan sensor: sudut = a * (sudut + gyro * dt) + (1 - a) * sudut_accelerometer.
/// Murni logika (tanpa Flutter dan tanpa plugin).
///
/// Sumbu sudut mengikuti layar: x positif = sisi kanan turun (bola ke kanan), y positif = sisi bawah turun (bola ke bawah).
/// Dengan u = arah "atas" dunia dalam sumbu perangkat (= accelerometer): x = atan2(-ax, hypot(ay, az)),
/// y = atan2(ay, hypot(ax, az)); laju perubahan sudut kecil = gyro y (untuk x) dan gyro x (untuk y), kaidah tangan kanan
/// seperti Android/sensors_plus. Pendekatan sudut kecil: cukup untuk kemiringan permainan (< 35°).
///
/// Tanpa gyroscope ([gyroActive] false) sudut langsung = sudut accelerometer.
class TiltFilter {
  double _rx = 0, _ry = 0; // sudut mentah (rad)
  double _ox = 0, _oy = 0; // kalibrasi: sudut mentah yang dianggap datar
  double? _ax, _ay; // sudut dari accelerometer terakhir
  bool _accelOk = false; // sampel accelerometer terakhir dipercaya (tidak sedang diguncang)
  bool _gyro = false;

  bool get gyroActive => _gyro;

  /// Sudut relatif terhadap posisi kalibrasi (rad).
  double get angleX => _rx - _ox;
  double get angleY => _ry - _oy;

  /// Percepatan bola (sel/detik^2, arah layar) dari kemiringan, sudah melewati zona mati dan batas maksimum.
  ({double x, double y}) get ballAccel => (x: _shape(angleX), y: _shape(angleY));

  static double _shape(double a) {
    final m = min(a.abs(), tiltMax) - tiltDeadZone;
    return m <= 0 ? 0 : a.sign * m * tiltGain;
  }

  /// Posisi ponsel saat ini dianggap datar (dipanggil saat Mulai dan tombol "Kalibrasi ulang").
  void calibrate() {
    _ox = _rx;
    _oy = _ry;
  }

  void add(TiltInput e) {
    switch (e) {
      case AccelInput():
        _onAccel(e);
      case GyroInput():
        _onGyro(e);
      case GyroLost():
        _gyro = false;
    }
  }

  void _onAccel(AccelInput e) {
    final g = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
    _accelOk = (g - standardGravity).abs() <= accelTrustBand;
    if (!_accelOk) return;
    final ax = atan2(-e.x, sqrt(e.y * e.y + e.z * e.z)), ay = atan2(e.y, sqrt(e.x * e.x + e.z * e.z));
    final first = _ax == null;
    _ax = ax;
    _ay = ay;
    // Sampel pertama menentukan awal; tanpa gyroscope setiap sampel langsung dipakai.
    if (first || !_gyro) {
      _rx = ax;
      _ry = ay;
    }
  }

  void _onGyro(GyroInput e) {
    _gyro = true;
    final dt = e.dt.clamp(0.0, gyroMaxDt);
    final a = tiltTau / (tiltTau + dt);
    final ax = _ax, ay = _ay;
    _rx += e.y * dt;
    _ry += e.x * dt;
    if (_accelOk && ax != null && ay != null) {
      _rx = a * _rx + (1 - a) * ax;
      _ry = a * _ry + (1 - a) * ay;
    }
  }
}
