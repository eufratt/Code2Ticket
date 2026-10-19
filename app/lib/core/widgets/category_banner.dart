import 'package:flutter/material.dart';

import '../theme/category_style.dart';
import '../theme/app_tokens.dart';

/// Banner giveaway: gambar bila ada URL, selain itu gradien kategori + ikon (DESIGN.md 3.3). Tidak pernah kotak kosong:
/// gambar yang gagal dimuat juga jatuh ke gradien. Rasio 16:9 (kartu) atau [height] tetap (Detail: 180).
/// Dekoratif, jadi tidak dibaca pembaca layar; teks di atas gambar selalu memakai chip bersolid sendiri.
class CategoryBanner extends StatelessWidget {
  const CategoryBanner({
    super.key,
    required this.category,
    this.imageUrl,
    this.aspectRatio = 16 / 9,
    this.height,
    this.borderRadius = Radii.cardAll,
  });
  final String? category;
  final String? imageUrl;
  final double aspectRatio;
  final double? height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final style = CategoryStyle.of(category);
    final url = imageUrl?.trim();
    final hasImage = url != null && url.isNotEmpty;
    final gradient = _Gradient(style: style);
    final content = hasImage
        ? Stack(fit: StackFit.expand, children: [
            Image.network(
              url,
              key: const Key('banner_image'),
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => gradient,
              loadingBuilder: (_, child, progress) => progress == null ? child : gradient,
            ),
            // Lapisan gelap tipis di bawah supaya apa pun yang ditaruh di atas gambar tetap terbaca.
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0x00000000), Color(0x66000000)],
                ),
              ),
            ),
          ])
        : gradient;
    return ExcludeSemantics(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: height != null
            ? SizedBox(height: height, width: double.infinity, child: content)
            : AspectRatio(aspectRatio: aspectRatio, child: content),
      ),
    );
  }
}

class _Gradient extends StatelessWidget {
  const _Gradient({required this.style});
  final CategoryStyle style;

  // Tanpa LayoutBuilder: banner berada di dalam IntrinsicHeight (carousel Home) yang tidak mendukungnya.
  @override
  Widget build(BuildContext context) {
    return Stack(
      key: Key('banner_gradient_${style.key}'),
      fit: StackFit.expand,
      children: [
        DecoratedBox(decoration: BoxDecoration(gradient: style.gradient)),
        // Lapisan gelap 20% supaya ikon putih terbaca di atas warna terang (mis. biru muda travel).
        const DecoratedBox(decoration: BoxDecoration(color: Color(0x33000000))),
        const CustomPaint(painter: _BubblePainter()),
        Center(
          child: FractionallySizedBox(
            heightFactor: 0.42,
            child: FittedBox(child: Icon(style.icon, size: 96, color: Colors.white)),
          ),
        ),
      ],
    );
  }
}

/// Lingkaran dekoratif samar di pojok kanan atas.
class _BubblePainter extends CustomPainter {
  const _BubblePainter();
  @override
  void paint(Canvas canvas, Size size) {
    final r = size.height * 0.45;
    canvas.drawCircle(Offset(size.width - r * 0.6, r * 0.2), r, Paint()..color = const Color(0x1FFFFFFF));
  }

  @override
  bool shouldRepaint(_BubblePainter old) => false;
}
