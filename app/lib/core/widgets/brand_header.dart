import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/category_style.dart';

/// Teks merek di atas layar masuk/daftar/kunci: tile gradien + nama + satu kalimat tagline.
class BrandHeader extends StatelessWidget {
  const BrandHeader({super.key, this.tagline = 'Undian digital yang adil dan bisa diverifikasi'});
  final String tagline;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ExcludeSemantics(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: CategoryStyle.gaming.gradient,
              borderRadius: const BorderRadius.all(Radius.circular(20)),
              boxShadow: AppShadows.fab(context.colors),
            ),
            child: const SizedBox(width: 72, height: 72, child: Icon(Icons.confirmation_number, color: Colors.white, size: 36)),
          ),
        ),
        const SizedBox(height: Spacing.s16),
        Semantics(header: true, child: Text('Code2Ticket', textAlign: TextAlign.center, style: theme.textTheme.displaySmall)),
        const SizedBox(height: Spacing.s4),
        Text(tagline, textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: context.colors.muted)),
      ],
    );
  }
}
