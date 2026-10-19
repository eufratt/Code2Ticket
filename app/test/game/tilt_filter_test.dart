import 'dart:math';

import 'package:code2ticket/features/game/tilt_filter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Data sintetis: ponsel dimiringkan dengan sudut sebenarnya (rx = sisi kanan turun, ry = sisi bawah turun, rad).
/// Accelerometer = arah "atas" dunia dalam sumbu perangkat; gyroscope = laju perubahan sudut.
AccelInput accelAt(double rx, double ry) {
  const g = standardGravity;
  return AccelInput(-g * sin(rx), g * sin(ry), g * cos(rx) * cos(ry));
}

const dt = 0.02; // 50 Hz

void main() {
  group('TiltFilter', () {
    test('rotasi konstan: sudut mengikuti sudut sebenarnya (gyro + accelerometer sepakat)', () {
      final f = TiltFilter()..add(accelAt(0, 0));
      const w = 0.5; // rad/s selama 1 detik = 0,5 rad
      for (var i = 1; i <= 50; i++) {
        f.add(GyroInput(0, w, dt)); // gyro y = sisi kanan turun
        f.add(accelAt(w * dt * i, 0));
      }
      expect(f.angleX, closeTo(0.5, 0.01));
      expect(f.angleY, closeTo(0, 0.005));
      expect(f.gyroActive, isTrue);
      // Sumbu lain: gyro x = sisi bawah turun.
      final g = TiltFilter()..add(accelAt(0, 0));
      for (var i = 1; i <= 50; i++) {
        g.add(GyroInput(w, 0, dt));
        g.add(accelAt(0, w * dt * i));
      }
      expect(g.angleY, closeTo(0.5, 0.01));
      expect(g.angleX, closeTo(0, 0.005));
    });

    test('gyroscope memimpin: accelerometer lambat (5 Hz, nilai basi) tetap terlacak, accelerometer saja tertinggal', () {
      final fused = TiltFilter()..add(accelAt(0, 0));
      final accOnly = TiltFilter()..add(accelAt(0, 0));
      const w = 1.0;
      for (var i = 1; i <= 29; i++) {
        final truth = w * dt * i;
        fused.add(GyroInput(0, w, dt));
        if (i % 10 == 0) {
          fused.add(accelAt(truth, 0));
          accOnly.add(accelAt(truth, 0));
        }
      }
      const truth = 0.58; // accelerometer terakhir (0,4) sudah basi 9 sampel
      final fusedErr = (fused.angleX - truth).abs(), accErr = (accOnly.angleX - truth).abs();
      expect(fusedErr, lessThan(0.07));
      expect(accErr, greaterThan(0.15));
      expect(fusedErr, lessThan(accErr / 2));
    });

    test('drift gyroscope dikoreksi accelerometer: bias 0,05 rad/s saat diam tidak menumpuk', () {
      final f = TiltFilter()..add(accelAt(0, 0));
      for (var i = 0; i < 50 * 60; i++) {
        f.add(const GyroInput(0, 0.05, dt));
        f.add(accelAt(0, 0));
      }
      // Integrasi murni akan mencapai 3 rad; kesalahan tetap ~ bias * tau = 0,035 rad.
      expect(f.angleX.abs(), lessThan(0.05));
    });

    test('tanpa gyroscope: sudut = sudut accelerometer; GyroLost mengembalikan mode accelerometer', () {
      final f = TiltFilter();
      expect(f.gyroActive, isFalse);
      f.add(accelAt(0.3, -0.2));
      expect(f.angleX, closeTo(0.3, 0.01));
      expect(f.angleY, closeTo(-0.2, 0.01));
      f.add(accelAt(-0.1, 0.4));
      expect(f.angleX, closeTo(-0.1, 0.01));
      expect(f.angleY, closeTo(0.4, 0.01));
      f.add(const GyroInput(0, 0.5, dt));
      expect(f.gyroActive, isTrue);
      f.add(const GyroLost());
      expect(f.gyroActive, isFalse);
      f.add(accelAt(0.2, 0.2));
      expect(f.angleX, closeTo(0.2, 0.02));
    });

    test('arah bola: sisi kanan turun -> x positif; sisi atas turun -> y negatif; sisi bawah turun -> y positif', () {
      var f = TiltFilter()..add(accelAt(0.3, 0));
      expect(f.ballAccel.x, greaterThan(0));
      expect(f.ballAccel.y, 0);
      f = TiltFilter()..add(accelAt(-0.3, 0));
      expect(f.ballAccel.x, lessThan(0));
      f = TiltFilter()..add(accelAt(0, 0.3));
      expect(f.ballAccel.y, greaterThan(0));
      f = TiltFilter()..add(accelAt(0, -0.3));
      expect(f.ballAccel.y, lessThan(0));
    });

    test('zona mati: ponsel diam (derau kecil) tidak menggeser bola; di luar zona mati naik mulus dan terbatas', () {
      final f = TiltFilter()..add(accelAt(0, 0));
      for (final a in [0.01, -0.03, 0.045, -0.049]) {
        f.add(accelAt(a, a));
        expect(f.ballAccel, (x: 0.0, y: 0.0), reason: 'sudut $a');
      }
      f.add(accelAt(tiltDeadZone + 0.1, 0));
      expect(f.ballAccel.x, closeTo(0.1 * tiltGain, 0.02));
      f.add(accelAt(1.2, 0)); // jauh di atas batas
      expect(f.ballAccel.x, closeTo((tiltMax - tiltDeadZone) * tiltGain, 1e-9));
    });

    test('kalibrasi: posisi saat dipanggil = nol; kemiringan berikutnya relatif terhadapnya', () {
      final f = TiltFilter()..add(accelAt(0.4, -0.3));
      expect(f.ballAccel.x, greaterThan(0));
      f.calibrate();
      expect(f.angleX, 0);
      expect(f.ballAccel, (x: 0.0, y: 0.0));
      f.add(accelAt(0.4 + 0.2, -0.3));
      expect(f.angleX, closeTo(0.2, 0.02));
      expect(f.ballAccel.x, greaterThan(0));
      expect(f.ballAccel.y, 0);
    });

    test('kalibrasi bertahan dengan gyroscope aktif (tidak ada loncatan)', () {
      final f = TiltFilter()..add(accelAt(0.3, 0));
      f.add(const GyroInput(0, 0, dt));
      f.calibrate();
      for (var i = 0; i < 100; i++) {
        f.add(const GyroInput(0, 0, dt));
        f.add(accelAt(0.3, 0));
      }
      expect(f.angleX.abs(), lessThan(1e-6));
    });

    test('guncangan (besar percepatan jauh dari gravitasi) diabaikan accelerometer; sudut hanya dari gyroscope', () {
      final f = TiltFilter()..add(accelAt(0, 0));
      f.add(const GyroInput(0, 0, dt));
      f.add(const AccelInput(25, 0, 0)); // hentakan
      f.add(const GyroInput(0, 0, dt));
      expect(f.angleX, closeTo(0, 1e-9));
      final accOnly = TiltFilter()..add(accelAt(0, 0));
      accOnly.add(const AccelInput(25, 0, 0));
      expect(accOnly.angleX, closeTo(0, 1e-9));
    });

    test('langkah waktu dibatasi: celah besar tidak melempar sudut', () {
      final f = TiltFilter()..add(accelAt(0, 0));
      f.add(const GyroInput(0, 1, 30)); // celah 30 detik
      expect(f.angleX.abs(), lessThan(gyroMaxDt * 1.0 + 1e-9));
    });
  });
}
