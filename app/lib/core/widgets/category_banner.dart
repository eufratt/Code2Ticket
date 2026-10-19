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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final h = box.hasBoundedHeight ? box.maxHeight : 120.0;
      return Stack(
        key: Key('banner_gradient_${style.key}'),
        fit: StackFit.expand,
        children: [
          DecoratedBox(decoration: BoxDecoration(gradient: style.gradient)),
          // Lapisan gelap 20% supaya ikon putih terbaca di atas warna terang (mis. biru muda travel).
          const DecoratedBox(decoration: BoxDecoration(color: Color(0x33000000))),
          Positioned(
            right: -h * 0.15,
            top: -h * 0.25,
            child: Container(
              width: h * 0.9,
              height: h * 0.9,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0x1FFFFFFF)),
            ),
          ),
          Center(child: Icon(style.icon, size: (h * 0.42).clamp(32.0, 96.0), color: Colors.white)),
        ],
      );
    });
  }
}
