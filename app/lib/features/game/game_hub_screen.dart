import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_colors.dart';
import '../../core/theme/app_tokens.dart';
import '../../core/widgets/widgets.dart';
import 'code_hunt_widgets.dart';
import 'maze.dart';

/// Pintu Code Hunt (labirin bertema kode -> tiket -> draw): pilih tingkat, cara main, dan papan peringkat. Layar penuh, tanpa tab/FAB (DESIGN.md, Game).
class GameHubScreen extends StatelessWidget {
  const GameHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.colors;
    return Scaffold(
      appBar: AppBar(title: const Text('Game')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Spacing.screen, Spacing.s4, Spacing.screen, Spacing.s24),
        children: [
          const SectionHeader('Code Hunt'),
          SurfaceCard(
            color: c.primaryContainer,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ExcludeSemantics(child: Icon(Icons.explore_outlined, size: 40, color: c.onPrimaryContainer)),
                const SizedBox(width: Spacing.s12),
                Expanded(
                  child: Text(
                    'Miringkan ponsel untuk menggulirkan chip kode, kumpulkan segmen kode, lalu antar ke Mesin Undian '
                    'sebelum waktu habis. Kode yang lengkap menjadi Tiket Latihan. Tidak bisa memiringkan? Pakai tombol panah di layar.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: c.onPrimaryContainer),
                  ),
                ),
              ],
            ),
          ),
          Padding(padding: const EdgeInsets.only(top: Spacing.s12), child: PracticeTargetLine(target: practiceTargetOf(context, listen: true))),
          const SectionHeader('Pilih tingkat', padding: EdgeInsets.only(top: Spacing.s16)),
          for (var i = 0; i < MazeLevel.all.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: Spacing.cardGap),
              child: SurfaceCard(
                key: Key('level_$i'),
                onTap: () => context.push('/game/play', extra: i),
                semanticLabel: 'Tingkat ${MazeLevel.all[i].name}, ${MazeLevel.all[i].cols} kali ${MazeLevel.all[i].rows}, ${MazeLevel.all[i].stars} segmen kode, ${MazeLevel.all[i].seconds} detik',
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(MazeLevel.all[i].name, style: theme.textTheme.titleMedium),
                          const SizedBox(height: Spacing.s4),
                          Text(
                            '${MazeLevel.all[i].cols}×${MazeLevel.all[i].rows} · ${MazeLevel.all[i].stars} segmen · ${MazeLevel.all[i].seconds} detik',
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
          const SectionHeader('Rakit Rantai', padding: EdgeInsets.only(top: Spacing.s8)),
          SurfaceCard(
            key: const Key('open_chain'),
            onTap: () => context.push('/game/chain'),
            semanticLabel: 'Rakit Rantai. Susun dan periksa block hash-chain seperti pada verifikasi undian asli.',
            child: Row(children: [
              ExcludeSemantics(child: Icon(Icons.link, size: 32, color: c.primary)),
              const SizedBox(width: Spacing.s12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Rakit Rantai', style: theme.textTheme.titleMedium),
                  const SizedBox(height: Spacing.s4),
                  Text('Susun dan periksa block hash-chain seperti pada verifikasi undian asli.', style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
                ]),
              ),
              Icon(Icons.chevron_right, color: c.muted),
            ]),
          ),
          const SizedBox(height: Spacing.s16),
          PrimaryButton(key: const Key('open_leaderboard'), label: 'Papan peringkat', icon: Icons.leaderboard_outlined, variant: ButtonVariant.secondary, onPressed: () => context.push('/leaderboard')),
        ],
      ),
    );
  }
}
