import 'package:flutter/material.dart';

import '../../core/display.dart';
import '../../core/format.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/theme/category_style.dart';
import '../../core/widgets/widgets.dart';
import '../discover/discover_filters.dart' show categoryLabel;
import 'giveaway_models.dart';

/// Status giveaway untuk chip (tabel DESIGN.md bagian 4).
AppStatus statusOfPhase(GiveawayPhase p) => switch (p) {
      GiveawayPhase.upcoming => AppStatus.giveawayUpcoming,
      GiveawayPhase.active => AppStatus.giveawayActive,
      GiveawayPhase.waitingDraw => AppStatus.giveawayWaitingDraw,
      GiveawayPhase.drawn => AppStatus.giveawayFinished,
    };

/// list = kartu penuh di daftar; carousel = lebar ditentukan induk (kartu horizontal Home); compact = ringkas (Peta).
enum GiveawayCardVariant { list, carousel, compact }

class GiveawayCard extends StatelessWidget {
  const GiveawayCard({
    super.key,
    required this.giveaway,
    required this.onTap,
    this.variant = GiveawayCardVariant.list,
    this.reasons,
  });
  final Giveaway giveaway;
  final VoidCallback onTap;
  final GiveawayCardVariant variant;
  final List<String>? reasons;

  @override
  Widget build(BuildContext context) {
    final g = giveaway;
    final status = statusOfPhase(g.phaseAt(DateTime.now()));
    return variant == GiveawayCardVariant.compact
        ? _Compact(g: g, status: status, onTap: onTap)
        : _Full(
            g: g,
            status: status,
            onTap: onTap,
            carousel: variant == GiveawayCardVariant.carousel,
            reasons: reasons,
          );
  }
}

/// Penanda kategori di atas banner: latar surface bersolid sehingga terbaca di atas gambar maupun gradien.
class CategoryTag extends StatelessWidget {
  const CategoryTag(this.category, {super.key});
  final String category;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final style = CategoryStyle.of(category);
    return DecoratedBox(
      decoration: ShapeDecoration(color: c.surface, shape: const StadiumBorder()),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.s8 + 2, vertical: Spacing.s4 + 1),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(style.icon, size: 14, color: c.onBackground),
          const SizedBox(width: Spacing.s4),
          Flexible(
            child: Text(categoryLabel(category), maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: c.onBackground)),
          ),
        ]),
      ),
    );
  }
}

class _Full extends StatelessWidget {
  const _Full({
    required this.g,
    required this.status,
    required this.onTap,
    required this.carousel,
    this.reasons,
  });
  final Giveaway g;
  final AppStatus status;
  final VoidCallback onTap;
  final bool carousel;
  final List<String>? reasons;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return SurfaceCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(children: [
            CategoryBanner(category: g.category, borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.card))),
            Positioned(top: Spacing.s8, left: Spacing.s8, child: CategoryTag(g.category)),
            Positioned(top: Spacing.s8, right: Spacing.s8, child: StatusChip(status)),
          ]),
          Padding(
            padding: const EdgeInsets.all(Spacing.s16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (reasons != null && reasons!.isNotEmpty) ...[
                  for (final r in reasons!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.s4),
                      child: _ReasonBadge(reason: r),
                    ),
                  const SizedBox(height: Spacing.s4),
                ],
                Text(g.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                if (g.organizer.isNotEmpty)
                  Text('oleh ${g.organizer}', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
                const SizedBox(height: Spacing.s8),
                _Prize(g: g),
                const SizedBox(height: Spacing.s8),
                _Line(
                  icon: Icons.event_outlined,
                  text: g.drawAt == null ? 'Jadwal draw belum ada' : 'Draw: ${context.when(g.drawAt!)}',
                ),
                if (!carousel) _Line(icon: Icons.confirmation_number_outlined, text: '${g.ticketCount} tiket terbit · ${g.winnerCount} pemenang'),
                if (g.distanceKm != null) _Line(icon: Icons.near_me, text: formatKm(g.distanceKm!), textKey: const Key('distance'), iconColor: c.primary),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip/baris kecil alasan rekomendasi (PRD FR-AI-01 AC4): ikon + teks, kontras token, dengan Semantics.
class _ReasonBadge extends StatelessWidget {
  const _ReasonBadge({required this.reason});
  final String reason;

  IconData _icon() {
    if (reason.startsWith('Karena') || reason.startsWith('Sesuai')) {
      return Icons.auto_awesome;
    }
    if (reason.contains('Draw') || reason.contains('segera')) {
      return Icons.timer_outlined;
    }
    if (reason.contains('km')) {
      return Icons.near_me;
    }
    return Icons.auto_awesome;
  }

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final theme = Theme.of(context);
    return Semantics(
      container: true,
      label: 'Alasan rekomendasi: $reason',
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: Spacing.s8, vertical: Spacing.s4),
        decoration: BoxDecoration(
          color: c.primaryContainer,
          borderRadius: Radii.inputAll,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(_icon(), size: 14, color: c.onPrimaryContainer),
            ),
            const SizedBox(width: Spacing.s4),
            Flexible(
              child: Text(
                reason,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: c.onPrimaryContainer,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Nilai hadiah menonjol (teks amber gelap, kontras 5,0 di atas putih) diikuti nama hadiah.
class _Prize extends StatelessWidget {
  const _Prize({required this.g});
  final Giveaway g;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: Spacing.s8,
      children: [
        Text(context.money(g.prizeValueIdr), style: theme.textTheme.titleMedium?.copyWith(color: c.accentText, fontWeight: FontWeight.w700)),
        if (g.prizeName.isNotEmpty) Text(g.prizeName, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _Line extends StatelessWidget {
  const _Line({required this.icon, required this.text, this.textKey, this.iconColor});
  final IconData icon;
  final String text;
  final Key? textKey;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Padding(
      padding: const EdgeInsets.only(top: Spacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 2), child: Icon(icon, size: 16, color: iconColor ?? c.muted)),
          const SizedBox(width: Spacing.s8),
          Expanded(child: Text(text, key: textKey, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.muted))),
        ],
      ),
    );
  }
}

class _Compact extends StatelessWidget {
  const _Compact({required this.g, required this.status, required this.onTap});
  final Giveaway g;
  final AppStatus status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return SurfaceCard(
      raised: true,
      padding: const EdgeInsets.all(Spacing.s12),
      onTap: onTap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 84,
            child: CategoryBanner(category: g.category, aspectRatio: 1, borderRadius: Radii.buttonAll),
          ),
          const SizedBox(width: Spacing.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleSmall),
                const SizedBox(height: Spacing.s4),
                Text(context.money(g.prizeValueIdr), style: theme.textTheme.titleSmall?.copyWith(color: c.accentText, fontWeight: FontWeight.w700)),
                const SizedBox(height: Spacing.s4),
                Wrap(spacing: Spacing.s8, runSpacing: Spacing.s4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  StatusChip(status),
                  if (g.distanceKm != null)
                    Text(formatKm(g.distanceKm!), key: const Key('distance'), style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
