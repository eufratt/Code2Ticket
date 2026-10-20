import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Batas foto profil yang diterima backend.
const maxPhotoBytes = 150 * 1024;
const maxPhotoSide = 512;

/// Mengecilkan foto ke sisi terpanjang <= [maxSide] px dan menyandikan ulang sebagai JPEG <= [maxBytes]
/// (kualitas diturunkan bertahap; bila masih besar, ukuran dikecilkan lagi). Orientasi EXIF diterapkan, lalu semua metadata (EXIF/GPS) dibuang.
/// Melempar [FormatException] bila bukan gambar yang dapat dibaca. Operasi berat: jalankan di isolate (compute).
Uint8List compressProfilePhoto(Uint8List input, {int maxSide = maxPhotoSide, int maxBytes = maxPhotoBytes}) {
  final decoded = img.decodeImage(input);
  if (decoded == null) throw const FormatException('Berkas bukan gambar yang dapat dibaca.');
  // Gambar baru dari piksel: EXIF (termasuk GPS) dan profil ICC bawaan berkas tidak ikut terbawa.
  final oriented = img.bakeOrientation(decoded);
  var image = img.Image(width: oriented.width, height: oriented.height);
  img.compositeImage(image, oriented);
  var side = maxSide;
  while (true) {
    final longest = image.width > image.height ? image.width : image.height;
    if (longest > side) {
      image = image.width >= image.height
          ? img.copyResize(image, width: side, interpolation: img.Interpolation.average)
          : img.copyResize(image, height: side, interpolation: img.Interpolation.average);
    }
    for (var quality = 85; quality >= 30; quality -= 10) {
      final bytes = Uint8List.fromList(img.encodeJpg(image, quality: quality));
      if (bytes.length <= maxBytes) return bytes;
    }
    side = (side * 0.8).floor();
    if (side < 64) {
      throw const FormatException('Foto terlalu rumit untuk dikecilkan ke batas ukuran.');
    }
  }
}
