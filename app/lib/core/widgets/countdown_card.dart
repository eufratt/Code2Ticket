import 'package:flutter/material.dart';

import '../display.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';
import '../theme/app_typography.dart';
import 'surface_card.dart';

/// Kartu hitung mundur: hari/jam/menit/detik dengan angka display (tabular). Pembaruan hanya saat layar terlihat
/// (logika timer ada di [Countdown]).
class CountdownCard extends StatelessWidget {
  const CountdownCard({super.key, required this.target, this.now, this.title = 'Draw dalam'});
  final DateTime target;
  final String title;

  /// Hanya untuk tes: sumber waktu.
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    return SurfaceCard(
      color: c.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.timer_outlined, size: 20, color: c.onPrimaryContainer),
            const SizedBox(width: Spacing.s8),
            Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(color: c.onPrimaryContainer))),
          ]),
          const SizedBox(height: Spacing.s12),
          Countdown(
            target: target,
            now: now,
            style: theme.textTheme.titleMedium?.copyWith(color: c.onPrimaryContainer),
            builder: (context, left) => _Units(left: left),
          ),
        ],
      ),
    );
  }
}

class _Units extends StatelessWidget {
  const _Units({required this.left});
  final Duration left;

  @override
  Widget build(BuildContext context) {
    final d = left.inDays, h = left.inHours % 24, m = left.inMinutes % 60, s = left.inSeconds % 60;
    return Semantics(
      key: const Key('countdown'),
      label: '$d hari $h jam $m menit $s detik lagi',
      excludeSemantics: true,
      child: Row(children: [
        for (final (i, (value, label)) in [(d, 'hari'), (h, 'jam'), (m, 'menit'), (s, 'detik')].indexed) ...[
          if (i > 0) const SizedBox(width: Spacing.s8),
          Expanded(child: _Unit(value: value, label: label)),
        ],
      ]),
    );
  }
}

class _Unit extends StatelessWidget {
  const _Unit({required this.value, required this.label});
  final int value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.surface, borderRadius: Radii.buttonAll),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: Spacing.s8, horizontal: Spacing.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value.toString().padLeft(2, '0'),
                style: AppTypography.tabular(Theme.of(context).textTheme.displaySmall!.copyWith(color: c.onBackground)),
              ),
            ),
            Text(label, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.muted), maxLines: 1),
          ],
        ),
      ),
    );
  }
}
