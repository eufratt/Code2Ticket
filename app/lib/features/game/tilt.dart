import 'dart:async';

import 'package:sensors_plus/sensors_plus.dart';

import 'tilt_filter.dart';

/// Masukan sensor perangkat untuk [TiltFilter]: accelerometer (dengan gravitasi) dan gyroscope (sensors_plus).
/// Gyroscope galat atau diam selama [gyroTimeout] -> [GyroLost] (filter jatuh ke accelerometer saja); sensor yang tidak
/// ada tidak melempar galat (D-pad di layar tetap tersedia).
Stream<TiltInput> deviceTilt() {
  late final StreamController<TiltInput> out;
  final subs = <StreamSubscription<Object?>>[];
  Timer? watchdog;
  out = StreamController<TiltInput>(
    onListen: () {
      subs.add(accelerometerEventStream(samplingPeriod: SensorInterval.gameInterval)
          .listen((e) => out.add(AccelInput(e.x, e.y, e.z)), onError: (_) {}));
      final clock = Stopwatch()..start();
      DateTime? prev;
      var lastGyro = Duration.zero;
      subs.add(gyroscopeEventStream(samplingPeriod: SensorInterval.gameInterval).listen((e) {
        lastGyro = clock.elapsed;
        final dt = prev == null ? 0.0 : e.timestamp.difference(prev!).inMicroseconds / 1e6;
        prev = e.timestamp;
        out.add(GyroInput(e.x, e.y, dt));
      }, onError: (_) {
        prev = null;
        out.add(const GyroLost());
      }));
      watchdog = Timer.periodic(gyroTimeout, (_) {
        if (clock.elapsed - lastGyro >= gyroTimeout) {
          prev = null;
          out.add(const GyroLost());
        }
      });
    },
    onCancel: () {
      watchdog?.cancel();
      for (final s in subs) {
        s.cancel();
      }
    },
  );
  return out.stream;
}
