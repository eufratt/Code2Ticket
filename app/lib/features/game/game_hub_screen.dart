import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import 'maze.dart';

/// Pintu Game Maze: pilih tingkat, cara main, dan papan peringkat. Layar penuh, tanpa tab/FAB (DESIGN.md, Game).
class GameHubScreen extends StatelessWidget {
  const GameHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Game Maze')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
        children: [
          SurfaceCard(
            color: c.primaryContainer,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Icon(Icons.explore_outlined, size: 40, color: c.onPrimaryContainer)),
                const SizedBox(width: Spacing.s12),
                Expanded(
                  child: Text(
                    'Miringkan ponsel untuk menggulirkan bola ke pintu keluar dan kumpulkan bintang sebelum waktu habis. '
                    'Tidak bisa memiringkan? Pakai tombol panah di layar.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: c.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
          const SectionHeader('Pilih tingkat', padding: EdgeInsets.only(top: Spacing.s16)),
          for (var i = 0; i < MazeLevel.all.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.cardGap),
              child: SurfaceCard(
                key: Key('level_$i'),
                onTap: () => context.push('/game/play', extra: i),
                semanticLabel: 'Tingkat ${MazeLevel.all[i].name}, ${MazeLevel.all[i].cols} kali ${MazeLevel.all[i].rows}, ${MazeLevel.all[i].stars} bintang, ${MazeLevel.all[i].seconds} detik',
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(MazeLevel.all[i].name, style: theme.textTheme.titleMedium),
                          const SizedBox(height: Spacing.s4),
                          Text(
                            '${MazeLevel.all[i].cols}×${MazeLevel.all[i].rows} · ${MazeLevel.all[i].stars} bintang · ${MazeLevel.all[i].seconds} detik',
                            style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right, color: c.muted),
                  ],
                ),
              ),
            ),
          const SizedBox(height: Spacing.s8),
          PrimaryButton(key: const Key('open_leaderboard'), label: 'Papan peringkat', icon: Icons.leaderboard_outlined, variant: ButtonVariant.secondary, onPressed: () => context.push('/leaderboard')),
        ],
      ),
    );
  }
}
