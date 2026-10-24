// Membuat ikon peluncur, ikon adaptif, logo splash, dan ikon kecil notifikasi dari satu bentuk tiket.
// Jalankan di app\: dart run tool/make_icons.dart
// Hasil: assets\branding\*.png (master 1024 px) dan android\app\src\main\res\{mipmap,drawable}-*\.
import 'dart:io';
import 'dart:math' as math;

import 'package:image/image.dart' as img;

const indigo = (0x4F, 0x46, 0xE5), amber = (0xF5, 0x9E, 0x0B);

enum Mode { full, foreground, splash, mono }

/// Tiket putih berukuran [scale] x lebar kanvas; takik amber di tepi kiri/kanan dan garis sobekan putus-putus amber.
/// Mode mono: siluet putih, takik dan sobekan transparan (ikon notifikasi harus monokrom).
img.Image render(int size, Mode mode, {int ss = 3}) {
  final out = img.Image(width: size, height: size, numChannels: 4);
  final scale = switch (mode) { Mode.full => 0.58, Mode.foreground => 0.40, Mode.splash => 0.60, Mode.mono => 0.84 };
  final tw = scale * size, th = tw * 0.64, r = th * 0.14;
  final cx = size / 2, cy = size / 2, left = cx - tw / 2, right = cx + tw / 2, top = cy - th / 2, bottom = cy + th / 2;
  final notchR = th * 0.13, perfX = left + tw * 0.70, dash = th * 0.09, gap = th * 0.06, perfW = tw * 0.012;

  // (0 = di luar, 1 = putih, 2 = takik/sobekan)
  int at(double x, double y) {
    final dx = math.max(math.max(left + r - x, x - (right - r)), 0.0), dy = math.max(math.max(top + r - y, y - (bottom - r)), 0.0);
    if (x < left || x > right || y < top || y > bottom || dx * dx + dy * dy > r * r) return 0;
    for (final nx in [left, right]) {
      if ((x - nx) * (x - nx) + (y - cy) * (y - cy) <= notchR * notchR) return 2;
    }
    if ((x - perfX).abs() <= perfW && y > top + th * 0.12 && y < bottom - th * 0.12) {
      if (((y - top - th * 0.12) % (dash + gap)) < dash) return 2;
    }
    return 1;
  }

  for (var py = 0; py < size; py++) {
    for (var px = 0; px < size; px++) {
      var white = 0.0, notch = 0.0;
      for (var sy = 0; sy < ss; sy++) {
        for (var sx = 0; sx < ss; sx++) {
          final v = at(px + (sx + 0.5) / ss, py + (sy + 0.5) / ss);
          if (v == 1) white++;
          if (v == 2 && mode != Mode.mono) notch++;
        }
      }
      final n = ss * ss.toDouble();
      final bg = mode == Mode.full ? 1.0 : 0.0;
      if (mode == Mode.mono) {
        out.setPixelRgba(px, py, 255, 255, 255, (255 * white / n).round());
        continue;
      }
      // komposit: latar (indigo atau transparan) < putih < takik amber
      final wa = white / n, na = notch / n;
      final alpha = math.min(1.0, bg + wa + na);
      double ch(int bgc, int wc, int nc) =>
          alpha == 0 ? 0 : (bgc * bg * (1 - wa - na).clamp(0, 1) + wc * wa + nc * na) / math.max(bg * (1 - wa - na).clamp(0, 1) + wa + na, 1e-9);
      out.setPixelRgba(px, py, ch(indigo.$1, 255, amber.$1).round(), ch(indigo.$2, 255, amber.$2).round(), ch(indigo.$3, 255, amber.$3).round(),
          (255 * alpha).round());
    }
  }
  return out;
}

void save(String path, img.Image image) {
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(img.encodePng(image));
}

void main() {
  const res = 'android/app/src/main/res';
  save('assets/branding/icon.png', render(1024, Mode.full));
  save('assets/branding/icon_foreground.png', render(1024, Mode.foreground));
  save('assets/branding/notification.png', render(256, Mode.mono));
  const dens = {'mdpi': 1.0, 'hdpi': 1.5, 'xhdpi': 2.0, 'xxhdpi': 3.0, 'xxxhdpi': 4.0};
  dens.forEach((d, f) {
    save('$res/mipmap-$d/ic_launcher.png', render((48 * f).round(), Mode.full));
    save('$res/drawable-$d/ic_launcher_foreground.png', render((108 * f).round(), Mode.foreground));
    save('$res/drawable-$d/splash_logo.png', render((160 * f).round(), Mode.splash));
    save('$res/drawable-$d/ic_stat_notify.png', render((24 * f).round(), Mode.mono));
  });
  stdout.writeln('Ikon dibuat.');
}
