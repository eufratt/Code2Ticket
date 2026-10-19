import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../core/display.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import '../giveaways/giveaway_card.dart' show statusOfPhase;
import '../giveaways/giveaway_models.dart';
import '../giveaways/giveaways_controller.dart' show LoadState;
import 'admin_controller.dart';

/// Pintu Admin: daftar giveaway (GET /giveaways) menuju Generate Code, Daftar Kode, dan Draw manual; tombol Buat giveaway.
/// Hanya dibuka dari menu Profil untuk role admin (router juga menolak non-admin); server tetap penentu (403).
class AdminGiveawaysScreen extends StatefulWidget {
  const AdminGiveawaysScreen({super.key});
  @override
  State<AdminGiveawaysScreen> createState() => _AdminGiveawaysScreenState();
}

class _AdminGiveawaysScreenState extends State<AdminGiveawaysScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(context.read<AdminController>().loadGiveaways);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.watch<AdminController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Admin')),
      body: switch (c.state) {
        LoadState.idle || LoadState.loading when c.giveaways.isEmpty => const SkeletonLoader(shape: SkeletonShape.ticket, count: 3),
        LoadState.error when c.giveaways.isEmpty => ErrorState(message: c.error ?? 'Gagal memuat.', onRetry: c.loadGiveaways),
        _ => RefreshIndicator(
            onRefresh: c.loadGiveaways,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
              children: [
                PrimaryButton(key: const Key('admin_create'), label: 'Buat giveaway', icon: Icons.add, onPressed: () => context.push('/admin/create')),
                const SectionHeader('Giveaway', padding: EdgeInsets.only(top: Spacing.s8)),
                if (c.giveaways.isEmpty)
                  const EmptyState(icon: Icons.card_giftcard, title: 'Belum ada giveaway', message: 'Buat giveaway pertama lewat tombol di atas.', compact: true)
                else
                  for (final g in c.giveaways)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Spacing.cardGap),
                      child: _AdminGiveawayTile(giveaway: g),
                    ),
              ],
            ),
          ),
      },
    );
  }
}

class _AdminGiveawayTile extends StatelessWidget {
  const _AdminGiveawayTile({required this.giveaway});
  final Giveaway giveaway;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = giveaway;
    final phase = g.phaseAt(DateTime.now());
    return SurfaceCard(
      key: Key('admin_giveaway_${g.id}'),
      onTap: () => context.push('/admin/giveaway/${g.id}', extra: g),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(g.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleMedium),
                const SizedBox(height: Spacing.s8),
                Wrap(spacing: Spacing.s8, runSpacing: Spacing.s4, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  StatusChip(statusOfPhase(phase)),
                  Text('${g.ticketCount} tiket', style: theme.textTheme.bodySmall),
                ]),
                if (g.drawAt != null)
                  Padding(
                    padding: const EdgeInsets.only(top: Spacing.s4),
                    child: Text('Draw ${context.when(g.drawAt!)}', style: theme.textTheme.bodySmall?.copyWith(color: context.colors.muted)),
                  ),
              ],
            ),
          ),
          Icon(Icons.chevron_right, color: context.colors.muted),
        ],
      ),
    );
  }
}
