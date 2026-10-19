import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Kartu dasar: surface, radius 16, bayangan kartu, garis tipis. Dapat diketuk bila [onTap] diisi.
class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(Spacing.s16),
    this.raised = false,
    this.color,
    this.semanticLabel,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  /// Bayangan "terangkat" (DESIGN.md 3.5) untuk kartu yang ingin menonjol.
  final bool raised;
  final Color? color;

  /// Bila diisi, kartu dibaca sebagai satu tombol dengan label ini.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    Widget body = Padding(padding: padding, child: child);
    if (onTap != null) body = InkWell(onTap: onTap, child: body);
    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? c.surface,
        borderRadius: Radii.cardAll,
        border: Border.all(color: c.outline),
        boxShadow: raised ? AppShadows.raised(c) : AppShadows.card(c),
      ),
      child: Material(
        type: MaterialType.transparency,
        borderRadius: Radii.cardAll,
        clipBehavior: Clip.antiAlias,
        child: body,
      ),
    );
    if (semanticLabel != null) {
      card = Semantics(container: true, button: onTap != null, label: semanticLabel, excludeSemantics: true, onTap: onTap, child: card);
    }
    return card;
  }
}
