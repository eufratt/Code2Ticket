import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import 'status_chip.dart';

/// Pesan di dalam layar (bukan snackbar): galat di atas tombol, atau konfirmasi sukses.
/// Dibaca pembaca layar begitu muncul (liveRegion). Selalu teks + ikon, tidak hanya warna.
class InlineMessage extends StatelessWidget {
  const InlineMessage(this.message, {super.key, this.tone = StatusTone.error});
  final String message;
  final StatusTone tone;

  @override
  Widget build(BuildContext context) {
    final sc = StatusChip.colorsOf(context.colors, tone);
    final icon = switch (tone) {
      StatusTone.success => Icons.check_circle_outline,
      StatusTone.warning => Icons.warning_amber_rounded,
      StatusTone.info => Icons.info_outline,
      _ => Icons.error_outline,
    };
    return Semantics(
      liveRegion: true,
      child: DecoratedBox(
        decoration: BoxDecoration(color: sc.bg, borderRadius: Radii.buttonAll),
        child: Padding(
          padding: const EdgeInsets.all(Spacing.s12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: sc.fg),
              const SizedBox(width: Spacing.s8),
              Expanded(child: Text(message, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: sc.fg))),
            ],
          ),
        ),
      ),
    );
  }
}
