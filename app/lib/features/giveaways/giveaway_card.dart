import 'package:flutter/material.dart';

import '../../core/format.dart';
import 'giveaway_models.dart';

String phaseLabel(GiveawayPhase p) => switch (p) {
      GiveawayPhase.upcoming => 'Segera mulai',
      GiveawayPhase.active => 'Aktif',
      GiveawayPhase.waitingDraw => 'Menunggu draw',
      GiveawayPhase.drawn => 'Sudah diundi',
    };

class GiveawayCard extends StatelessWidget {
  const GiveawayCard({super.key, required this.giveaway, required this.onTap});
  final Giveaway giveaway;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = giveaway;
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(g.title, style: theme.textTheme.titleMedium)),
                  const SizedBox(width: 8),
                  Chip(
                    label: Text(g.category),
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              if (g.organizer.isNotEmpty) Text('oleh ${g.organizer}', style: theme.textTheme.bodySmall),
              const SizedBox(height: 8),
              Text('${g.prizeName} · ${formatUsd(g.prizeValueUsd)}'),
              const SizedBox(height: 4),
              Text(
                g.drawAt == null ? 'Jadwal draw belum ada' : 'Draw: ${formatWib(g.drawAt!)}',
                style: theme.textTheme.bodySmall,
              ),
              Text('${g.ticketCount} tiket terbit · ${g.winnerCount} pemenang',
                  style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
